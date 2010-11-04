--- the webylene object is responsible for passing on a WSAPI request in a transparent, predictable manner.

--we'll need this stuff right off the bat
local req = require "wsapi.request"
local resp = require "wsapi.response"
local wsapi = wsapi
require "utilities.debug"

local xpcall, pcall, error, assert, debug, io, rawget, rawset = xpcall, pcall, error, assert, debug, io, rawget, rawset
local ipairs, pairs, require = ipairs, pairs, require
local table, type, setfenv, loadfile, setmetatable, rawset = table, type, setfenv, loadfile, setmetatable, rawset
local _G = _G
local print = print
local stderr, tostring = io.stderr, tostring

--- import a lua chunk and load it as an index in the webylene table. 
-- @param file_chunk lua chunk, at least defining a table named object_name
-- @param object_name expected name of the imported object/table
-- upon successful chunk loading, [object_name]:init() is called.
local importChunk = function(self, file_chunk, object_name, env)
	if file_chunk == nil then return end 
	
	local relatively_safe_env = setmetatable({}, {__index=env or _G})
	local ret = setfenv(file_chunk, relatively_safe_env)() -- run the file in a (relatively) safe environment
	local result = rawget(relatively_safe_env, object_name) or ret
	if result ~= nil then --there it is!
		rawset(self, object_name, result)
		if (type(result)=="table") and (type(result.init) == "function") then --if it's a table and has an init, run it.
			self[object_name]:init()
		end
		return self[object_name]
	end
	return nil
end

local function inherit(tbl, inheritance)
	local meta = getmetatable(tbl)
	if not meta then
		meta = {}
		setmetatable(tbl, meta)
	end
	local __index = meta.__index
	if type(__index)=='table' then
		return setlowestmetatable(meta.__index)
	elseif type(__index)=="function" then
		meta.__index = function(t, k)
			return  __index(t,k) or inheritance[k]
		end
	elseif not __index then
		meta.__index = inheritance
	end
end

module(...)

--- connectors
local newrequest, newresponse = req.new, resp.new

function new(parent, path)
	local config = {
		paths = {
			import={},
			config={},
			plugins={},
			addons={}
		}
	}
	
	local chunk_env = _G

	local core_request, erry = nil, function(err)
		if not config or (type(config)=="table" and config.show_backtrace~=false) then
			return err ..  "\r\n" .. debug.traceback("", 2)
		else
			return err
		end
	end
	
	local disregard = {} --we don't want webylene to be loaded more than once. also, this table is used to keep track of stuff that's not part of webylene. (avoid infinite lookup loops)
	--- (too) magic webylene importer. called whenever webylene.foo is nil, tries to load foo.lua from the folders listed below. 
	local import_pathf
	local import = function(self, object_name, look_here)
		local exists = rawget(self, object_name)
		if exists ~= nil then
			return exists 
		elseif disregard[object_name] then
			return nil
		end
		local result
		
		for i,dir in pairs(look_here and {look_here} or self.cf('paths', 'import')) do
			local mypath = import_pathf:format(dir, object_name)
			-- this is wasteful, but I don't see a better way to differentiate between 
			-- file-not-found errors and parsing errors while having lua think it's 
			-- processing a file and not some string.
			-- if anyone has any suggestions, i'd be perfecly glad to get rid of this unsightly code.
			local f = io.open(mypath, "r")
			if f then
				f:close()
				local chunk, err = loadfile(mypath)
				if not chunk then error(err, 0) end
				result = importChunk(self, chunk, object_name, chunk_env)
				if result ~= nil then
					return result
				end
			end
		end		
		-- we tried, but failed. make a note of it, and move on... :'( 
		disregard[object_name] = true
		return nil
	end
	
	
	local connectors = {
		cgi = 'cgi',
		fastcgi = 'fastcgi',
		fcgi = 'fastcgi',
		http = 'xavante',
		proxy = 'xavante',
	}
	
	return setmetatable({
		config = config,
		
		--- environmental bootstrapping. figure out where we are and whatnot
		initialize = function(self, arg)
			--assert(environment, "Webylene environment is a must!") --environment is really quite optional
			
			--path setting logic
			arg.path_separator = arg.path_separator or '/'
			local slash = arg.path_separator
			if arg.path and arg.path:sub(-1)~=slash then
				arg.path = arg.path .. slash
			end
			config.paths.root=arg.path
			for k, v in pairs(arg) do 
				self:set_config(k,v)
			end
			if(parent) then
				config.paths.core=parent.cf("paths","core")
				setmetatable(config, {__index=parent.config})
				for _, path_type in pairs{"import", "config"} do
					local paths = config.paths[path_use]
					for i, v in pairs(parent.cf("paths",path_use)) do
						table.insert(paths, v)
					end
				end
			elseif not self.cf("paths", "core") then
				config.paths.core = self.cf "path" .. "objects" .. slash .. "core" .. slash
			end
			table.insert(config.paths.config, self.cf("paths", "root") .. "config" .. slash)
			import_pathf = "%s%s.lua"  
			
			--paths to look for objects in, in order of preference
			for i, relpath in pairs{"objects" .. slash, "objects" .. slash .. "plugins" .. slash} do
				self:add_object_import_path(relpath, i)
			end

			local res, err = xpcall(function()
				import(self, "core", self.cf("paths", "core"))
				core_request = self.core.request
				self.core:initialize()
			end,
			function(err)
				return ("Initialization error: %s\r\n%s"):format(err, debug and debug.traceback("", 2) or "(backtrace unavailable because the debug library is inaccessible)")
			end)
			if not res then error(err,0) end
			return self
			
		end,
		
		set_config = function(self, k, v)
			rawset(config, k, v)
			return self
		end,

		set_env = function(self, env)
			env.webylene=self
			env.w=self
			inherit(env, self)
			chunk_env = env
			return self
		end,
		
		--- config retrieval function. kinda redundant, but used in other languages' versions of webylene. here for consistency.
		-- usage: cf("foo", "bar", "baz") retrieves webylene.config.foo.bar.baz
		cf = function(...)
			local arg = {...}
			if type(arg[1])=='table' then --someone did webylene:cf("foo", "bar")
				table.remove(arg, 1)
			end
			local conf = config
			for i,v in ipairs({...}) do
				conf = conf[v]
			end
			return conf
		end,
		
		--- process a wsapi request
		wsapi_request = function(self, wsapi_env)
			local request = setmetatable(newrequest(wsapi_env), {__index=wsapi_env}) 
			request.env = wsapi_env
			self.response, self.request = newresponse(), request
			local succ, err = xpcall(core_request, erry) --make sure errors are not hidden -- the bootstrap does not generate stack traces on error
			if succ then
				return self.response:finish()
			else
				error(err, 0)
			end
		end,
		
		get_object_import_paths = function(self)
			return self.cf("paths", "import")
		end,
		
		add_object_import_path = function(self, path, n)
			table.insert(self.cf("paths", "import"), n or #table+1, self.cf("paths", "root") .. path)
			return self
		end,
		
		import = import,
		
		initialize_connector = function(self, connector_name, request_processing_function, arg)
			local logger = self.logger
			local connector_module_name = connectors[connector_name]
			local baseDir = self.cf('path') .. self.cf('path_separator') .. "web"
			assert(connector_module_name, "unknown protocol: " .. connector_name)
			local connector = require ("wsapi." .. connector_module_name)
			if(connector_module_name == 'xavante') then
			
				--Hello httpd magic.
				local xavante = require "xavante"
				require "xavante.filehandler"
				require "xavante.cgiluahandler"
				require "xavante.redirecthandler"
				
				local stdout, stderr = io.stdout, io.stderr
			
				local filehandler = xavante.filehandler(baseDir)
				local webylenehandler = wsapi.xavante.makeHandler(request_processing_function, nil, baseDir)
				local make_response = xavante.httpd.make_response
				
				local host, port = arg.host, arg.port or 80
				if not host then
					stderr:write("HTTP Server hostname not given. assuming localhost.\r\n")
					host = "localhost"
				end
				local msg = ("Xavante HTTP server for Webylene on %s:%d."):format(host, port)
				
				xavante.start_message(function() stdout:write("Started " .. msg .. "\r\n") end)
				
				local res, err = pcall(xavante.HTTP, {
					server = { host= host, port=port },
					defaultHost = {
						rules = { {
						match = ".*",
							with = connector_name=='proxy' and webylenehandler or function(req, res, ...)
								local fres, err = filehandler(req, make_response(req), ...)
								if not fres.statusline:match("^HTTP/%d+%.%d+%s+[34]%d%d") then
									return fres;
								else
									return webylenehandler(req, res, ...)
								end
							end
						} }
					}
				})
				if not res then 
					local err = ("Error starting Xavante HTTP server on %s:%d: %s"):format(host, port, err:match(".*: (.+)"))
					stderr:write(err .. "\r\n")
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
		
	}, {__index=import})
end
