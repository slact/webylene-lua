--- the webylene object is responsible for passing on a WSAPI request in a transparent, predictable manner.

--we'll need this stuff right off the bat
local req = require "wsapi.request"
local resp = require "wsapi.response"
local wsapi = wsapi

local xpcall, pcall, error, assert, debug = xpcall, pcall, error, assert, debug
local ipairs, pairs, require = ipairs, pairs, require
local table, type, setfenv, loadfile, setmetatable, rawset = table, type, setfenv, loadfile, setmetatable, rawset
local _G = _G


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

local import_path, object_paths = "", {}
local disregard = {} --we don't want webylene to be loaded more than once. also, this table is used to keep track of stuff that's not part of webylene. (avoid infinite lookup loops)
--- (too) magic webylene importer. called whenever webylene.foo is nil, tries to load foo.lua from the folders listed below. 
local import = function(self, object_name)
	local exists = rawget(self, object_name)
	if exists ~= nil then
		return exists
	elseif disregard[object_name] then
		return nil
	end
	local result
	
	for i,dir in pairs(object_paths) do
		local mypath = import_path:format(dir, object_name)
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


module(..., function(self)
	setmetatable(self, {
		__index = import
	})
end)

config = {}

local core_request, erry = nil, function(err)
	if not config or (type(config)=="table" and config.show_backtrace~=false) then
		return err ..  "\r\n" .. debug.traceback("", 2)
	else
		return err
	end
end

--- connectors
do
	local connectors = {
		cgi = 'cgi',
		fastcgi = 'fastcgi',
		fcgi = 'fastcgi',
		http = 'xavante',
		proxy = 'xavante'
	}
	
	initialize_connector = function(connector_name, path, request_processing_function, arg)
		local connector_module_name = connectors[connector_name]
		local baseDir = path .. "/web"
		assert(connector_module_name, "unknown protocol " .. connector_name)
		local connector = require ("wsapi." .. connector_module_name)
		if(connector_module_name == 'xavante') then
		
			--Hello httpd magic.
			
			local xavante = require "xavante"
			require "xavante.filehandler"
			require "xavante.cgiluahandler"
			require "xavante.redirecthandler"
			
			require "utilities.debug"
			
			local filehandler = xavante.filehandler(baseDir)
			local webylenehandler = wsapi.xavante.makeHandler(request_processing_function, nil, baseDir)
			local make_response = xavante.httpd.make_response
			
			local host, port = arg.host, arg.port or 80
			if not host then
				_G.logger:info("HTTP Server hostname not given. assuming localhost.")
				host = "localhost"
			end
			local msg = ("Xavante HTTP server for Webylene on %s:%d."):format(host, port)
			_G.logger:info("Starting " .. msg)
			xavante.start_message(function() _G.print("Started " .. msg) end)
			
			
			local res, err = pcall(xavante.HTTP, {
				server = { host= host, port=port },
				defaultHost = {
					rules = { {
						match = "",
						with = function(req, res, ...)
							local fres = filehandler(req, make_response(req), ...)
							if fres.statusline ~= "HTTP/1.1 404 Not Found" and fres.statusline ~= "HTTP/1.1 301 Moved Permanently" then
								return fres;
							else
								return webylenehandler(req, res, ...)
							end
						end
					} }
				}
			})
			if not res then 
				local err = "Error starting Xavante HTTP server: " .. err:match(".*: (.+)")
				_G.io.stderr:write(err .. "\r\n")
				_G.logger:error(err)
				return function() return 1 end
			else
				return xavante.start
			end
		else
			return function() 
				return connector.run(request_processing_function)
			end
		end
	end
end

function add_object_path(self, path)
	table.insert(object_paths, path)
	return self
end

--- environmental bootstrapping. figure out where we are and whatnot
initialize = function(self, webylene_path, environment, slash)
	assert(webylene_path, "Webylene project path is a must!")
	--assert(environment, "Webylene environment is a must!") --environment is really quite optional
	slash = slash or "/"
	self.path, self.path_separator, self.env = webylene_path, slash, environment
	
	import_path =  path .. path_separator .. "%s" .. path_separator .. "%s.lua"  
	object_paths = { --paths to look for objects in, in order of preference
		"objects" .. path_separator .. "core", 
		"objects",
		"objects" .. path_separator .. "plugins"
	}
	
	local res, err = xpcall(function()
		import(self, "core")
		core_request=self.core.request
		self.core:initialize()
	end,
	function(err)
		return ("Initialization error: %s\r\n%s"):format(err, debug and debug.traceback("", 2) or "(backtrace unavailable because the debug library is inaccessible)")
	end)
	if not res then error(err,0) end
	return self
end

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
end

--- config retrieval function. kinda redundant, but used in other languages' versions of webylene. here for consistency.
-- usage: cf("foo", "bar", "baz") retrieves webylene.config.foo.bar.baz
cf = function(...)
	local conf = config
	for i,v in ipairs({...}) do
		conf = conf[v]
	end
	return conf
end


set_config = function(self, k, v)
	rawset(config, k, v)
	return self
end

import = import
