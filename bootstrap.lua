local path_separator = "/"

--we'll need this stuff right off the bat
require "wsapi.request"
require "wsapi.response"
webylene = {
	initialize = function(self, optional_wsapi_env)
		assert(self:locate(optional_wsapi_env))
		local slash = path_separator
		package.path = self.path .. slash .. "share" .. slash .. "?.lua;" .. self.path .. slash .. "share" .. slash .. "?" .. slash .. "init.lua;" .. package.path
		self:import("core")
		self.core:initialize(optional_wsapi_env)
	end,
	
	wsapi_request = function(self, wsapi_env)
		self.request = setmetatable(wsapi.request.new(wsapi_env), {__index=wsapi_env})
		self.request.env = wsapi_env
		self.req = self.request
		self.response = wsapi.response.new()
		self.core:request()
		return self.response:finish()
	end,

	path_separator = path_separator,
	
	--- where the crap is webylene running? this function finds the absolute path of the webylene root, based on the assumption that it was started from web/index.lua
	locate = function(self, wsapi_env)
		local path = nil
		local level = string.format("%s[^%s]+", path_separator, path_separator)
		if wsapi_env then
			if wsapi_env.PATH_TRANSLATED and wsapi_env.PATH_TRANSLATED ~= "" then -- /foo/bar/baz/webylene/web/index.lua, probably
				path = wsapi_env.PATH_TRANSLATED:gsub(level:rep(2) .. "$", "", 1)
			elseif wsapi_env.DOCUMENT_ROOT and wsapi_env.PATH_TRANSLATED ~= "" then --/foo/bar/baz/webylene/web/
				path = wsapi_env.DOCUMENT_ROOT:gsub(level .. path_separator .. "?$", "", 1)
			end
		else
			--last-ditch attempt
			path = debug.getinfo(1, 'S').source
			if path:byte(1) == string.byte("@", 1) then -- @/foo/bar/baz/webylene/bootstrap.lua, probably
				path = string.gsub(string.sub(path, 2), level .. "$", "", 1)
			end
		end
		if path then
			self.path = path
			return path
		else
			return nil, "Tried really hard, but couldn't find webylene root."
		end
	end,
	
	path = "",
	config = {},
	
	--- import a lua chunk and load it as an index in the webylene table. 
	-- @param file_chunk lua chunk, at least defining a table named object_name
	-- @param object_name expected name of the imported object/table
	--
	-- upon successful chunk loading, [object_name]:init() is called.
	importChunk = function(self, file_chunk, object_name)
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
	end,
	
	--- import contents of a file as webylene[object_name]
	-- @see webylene.importChunk
	importFile = function(self, file_path, object_name)
		local object_name = object_name or (string.match(path_separator .. file_path, ".*[^\\]"..path_separator.."(.-)$")):sub(1, -5)
		if rawget(self, object_name) ~= nil then
			return self[object_name]
		end
		local result = self:importChunk(assert(loadfile(file_path)), object_name)
		if result ~= nil then
			return result
		end
		return nil
	end
}

do
	local libsLoaded = {}
	--- load a library (heap o' functions) from webylene root/lib/[lib_name].lua
	webylene.loadlib = function(self, lib_name)
		if not libsLoaded[lib_name] then
			assert(loadfile(self.path .. path_separator .. "lib" .. path_separator .. lib_name .. ".lua"), string.format("%s.lua not found in " .. self.path .. path_separator .. "lib" .. path_separator , lib_name))()
			libsLoaded[lib_name]=true
		end
		return self
	end

	local notFound = {}
	local object_dirs = {"objects" .. path_separator .. "core", "objects", "objects" .. path_separator .. "plugins"} --where shall we look?
	
	--- (too) magic webylene importer. called whenever webylene.foo is nil, tries to load foo.lua from the folders listed below. 
	--@see webylene.importFile
	webylene.import = function(self, object_name)
		if rawget(self, object_name) ~= nil then
			return self.object_name
		elseif notFound[object_name] then
			return nil
		end
		local f, path, result
		for i,dir in pairs(object_dirs) do

			path = self.path .. path_separator .. dir .. path_separator .. object_name .. ".lua"
			f = io.open(path, "r")
			if f then
				result = self:importChunk(assert(loadstring(f:read("*all"), dir .. path_separator .. object_name .. ".lua")), object_name)
				if result ~= nil then
					return result
				end
			end
		end		
		-- we tried, but failed. make a note of it, and move on... :'(  
		notFound[object_name] = true
		return nil
	end
end

setmetatable(webylene, {
	__index = function(tbl, key) --trigger the importer
		return tbl:import(key)
	end
})

setmetatable(_G, {__index = webylene}) -- so that people don't have to write webylene.this and webylene.that and so forth all the time.	