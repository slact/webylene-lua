--- the core manages lowish-level bootstrappy stuff, and fires important events.

--- EVENTS:
--- as you'd expect, this fires some essential events:
--[[ fired during initialization:
	<initialize>
		<loadUtilities>
			load essential utilities from the libs dir
		</loadUtilities>
		<loadConfig>
			load lua, followed by yaml config files from the config/ directory
		</loadConfig>
		<loadCore>
			load all objects in objects/core. basic, essential stuff.
		</loadCore>
		<loadPlugins>
			load all objects in objects/plugins. non-recursive.
		</loadPlugins>
	</initialize>
]]
--[[ fired during a request (when the server receives a request to view a page) or somesuch:
	<request>
		<route />
	</request>
]]
--[[ on total webylene shutdown:
	<shutdown />
]]

require "lfs"

local webylene = webylene
--- webylene core. this does all sorts of bootstrappity things.
local load_config, load_objects, load_addons  --closured for fun and profit. mostly fun.
core = {
	--- initialize webylene
	initialize = function(self)
		local ev = webylene:import("event", cf('paths', 'core'))
		local logger = webylene:import("logger", cf('paths', 'core'))
		logger:info("Starting ".. (cf('name') or cf('appname') or "webylene application") .. 
		  (cf('environment')
		    and (" in " .. cf('environment') .. " environment") 
		    or " without an environment parameter") ..  " with path " .. cf('path'))
		
		ev:start("initialize")	
			ev:start("loadUtilities")
				require "utilities" -- we need all the random junk in here
			ev:finish("loadUtilities")
			
			--load config
			ev:start("loadConfig")
				load_config(self, "yaml")
				load_config(self, "lua")
			ev:finish("loadConfig")
			
			--load core objects
			ev:start("loadCore")
				load_objects(self, cf('paths', 'core'))
			ev:finish("loadCore")	
			
			ev:start("loadAddons")
				load_addons(self)
			ev:finish("loadAddons")
			
			--load plugin objects
			ev:start("loadPlugins")
				for i,where_do_i_look in pairs(cf('paths', 'plugins')) do
					load_objects(self, where_do_i_look)
				end
			ev:finish("loadPlugins")
		ev:finish("initialize")
	end,
	
	--- respond to a request
	request = function()
		local e = webylene.event
		e:start("request")
			e:fire("route")
		e:finish("request")
	end,
	
	shutdown = function()
		webylene.event:fire("shutdown")
		for i, addon in pairs(webylene.addons or {}) do
			addon.event:fire("shutdown")
		end
	end
}
	
--- load config files of type <extension> from config paths
--remember, this is local.
load_config = function(self, extension)
	local sep = cf('path_separator')
	extension = extension or "yaml"
	local loadFile = {
		yaml = function(path)
			require "yaml"
			local f, err = io.open(path, "r")
			if not f then return nil, err end
			local success, conf = pcall(yaml.load, f:read("*all"))
			f:close()
			if not success then 
				local err = ("Error loading yaml file <%s>: %s"):format(path, conf)
				logger:error(err)
				error(err, 0)
			end
			--address environment-specific settings
			if conf.env and conf.env[self.env] then	
				table.mergeRecursivelyWith(conf, conf.env[webylene.env])
				conf.env = nil
			end
			table.mergeRecursivelyWith(webylene.config, conf)
		end,
		lua	= function(path)
			dofile(path)
		end
	}
	
	assert(loadFile[extension], "Config loader doesn't know what to do with the  \"." .. extension .. "\" extension.")
	for i, absolute_path in pairs(cf("paths", "config")) do
		for file in lfs.dir(absolute_path) do																				-- is this part right?...
			if file ~= "." and file ~= ".."  and lfs.attributes(absolute_path .. sep .. file, "mode")=="file" and file:sub(-#extension) == extension then
				loadFile[extension](absolute_path .. sep .. file)
			end
		end
	end
	return true
end
	
--- load all objects in lua files in relativePath
--remember, this is local.
load_objects = function(self, from_where)
	local extension = "lua"
	local extension_cutoff = #extension+2 --the dot +1
	for file in lfs.dir(from_where) do																				-- is this part right?...
		if file ~= "." and file ~= ".." and lfs.attributes(from_where .. cf('path_separator') .. file, "mode")=="file" and file:sub(-#extension) == extension then
			local obj = self[file:sub(1, -extension_cutoff)]
		end
	end
	return true
end

load_addons = function(self)
	for i, from_where in pairs(webylene.cf("paths", "addons") or {}) do
		for addon in lfs.dir(from_where) do
			if addon ~="." and addon ~=".." and lfs.attributes(from_where  .. addon, "mode")=="directory" then
				local env = setmetatable({}, {__index=_G})
				webylene.addons = webylene.addons or {}
				local w = require("webylene").new(webylene)
				w:set_env(env)
				webylene.addons[addon]=w
				w:initialize{
					path=from_where .. addon .. cf("path_separator"),
					protocol="none"
				}
			end
		end
	end
	print(debug.dump(webylene.addons))
end
