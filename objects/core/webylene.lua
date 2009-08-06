--- the webylene object is responsible for passing on a WSAPI request in a transparent, predictable manner.

--we'll need this stuff right off the bat
local req = require "wsapi.request"
local resp = require "wsapi.response"

local core_request, erry = nil, function(err)
	if not webylene.config or (type(webylene.config)=="table" and webylene.config.show_backtrace) then
		return err ..  "\r\n" .. debug.traceback("", 2)
	else
		return err
	end
end

webylene = {
	--- environmental bootstrapping. figure out where we are and whatnot
	initialize = function(self, path, environment)
		assert(path, "Webylene project path is a must!")
		--assert(environment, "Webylene environment is a must!") --environment is really quite optional
		self.path = path
		self.env = environment
		local slash = PATH_SEPARATOR
		
		--let local requires work.
		package.path = self.path .. slash .. "share" .. slash .. "?.lua;" .. self.path .. slash .. "share" .. slash .. "?" .. slash .. "init.lua;" .. package.path
		
		local res, err = xpcall(function()
			self:import("core")
			core_request=self.core.request
			self.core:initialize()
		end,
		function(err)
			return ("Initialization error: %s\r\n%s"):format(err, debug and debug.traceback("", 2) or "(backtrace unavailable because I have no access to the debug library)")
		end)
		if not res then error(err,0) end
		return self
	end,
	
	--- process a wsapi request
	wsapi_request = function(self, wsapi_env)
		local request = setmetatable(req.new(wsapi_env), {__index=wsapi_env}) 
		request.env = wsapi_env
		self.response, self.request = resp.new(), request
		local succ, err = xpcall(core_request, erry) --make sure errors are not hidden -- the bootstrap does not generate stack traces on error
		if succ then
			return self.response:finish()
		else
			error(err, 0)
		end
	end,

	path_separator = PATH_SEPARATOR,
	
	path = "",
	config = {}
}

--- config retrieval function. kinda redundant, but used in other languages' versions of webylene. here for consistency.
-- usage: cf("foo", "bar", "baz") retrieves webylene.config.foo.bar.baz
webylene.cf = function(...)
	local config = webylene.config
	for i,v in ipairs({...}) do
		config = config[v]
	end
	return config
end

do
	--- import a lua chunk and load it as an index in the webylene table. 
	-- @param file_chunk lua chunk, at least defining a table named object_name
	-- @param object_name expected name of the imported object/table
	-- upon successful chunk loading, [object_name]:init() is called.
	local importChunk = function(self, file_chunk, object_name)
		if file_chunk == nil then return end 
		
		local relatively_safe_env = setmetatable({}, {__index=_G})
		setfenv(file_chunk, relatively_safe_env)() -- run the file in a (relatively) safe environment
		local result = rawget(relatively_safe_env, object_name)
		if result ~= nil then --there it is!
			rawset(self, object_name, result)
			if (type(result)=="table") and (type(result.init) == "function") then --if it's a table and has an init, run it.
				self[object_name]:init()
			end
			return self[object_name]
		end
		return nil
	end
	local disregard = {webylene=true} --we don't want webylene to be loaded more than once. also, this table is used to keep track of stuff that's not part of webylene. (avoid infinite lookup loops)
	local object_dirs = {"objects" .. PATH_SEPARATOR .. "core", "objects", "objects" .. PATH_SEPARATOR .. "plugins"} --where shall we look?
	
	--- (too) magic webylene importer. called whenever webylene.foo is nil, tries to load foo.lua from the folders listed below. 
	webylene.import = function(self, object_name)
		local exists = rawget(self, object_name)
		if exists ~= nil then
			return exists
		elseif disregard[object_name] then
			return nil
		end
		local result
		local path =  self.path .. PATH_SEPARATOR .. "%s" .. PATH_SEPARATOR .. object_name .. ".lua"
		for i,dir in pairs(object_dirs) do
			local mypath = path:format(dir)
			-- this is wasteful, but I don't see a better way to differentiate between 
			-- file-not-found errors and parsing errors while having lua think it's 
			-- processing a file and not some string.
			-- if anyone has any suggestions, i'd be perfecly glad to get rid of this unsightly code.
			local f = io.open(mypath, "r")
			if f then
				f:close()
				local chunk, err = loadfile(mypath)
				if not chunk then error(err, 0) end
				result = importChunk(self, chunk, object_name)
				if result ~= nil then
					return result
				end
			end
		end		
		-- we tried, but failed. make a note of it, and move on... :'(  
		disregard[object_name] = true
		return nil
	end
end

setmetatable(webylene, {
	__index = webylene.import
})