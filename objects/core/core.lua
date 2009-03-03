require "lfs"
local webylene = webylene
--- webylene core. this does all sorts of bootstrappity things.
local load_config, load_objects  --closured
core = {
	--- initialize webylene
	initialize = function(self)
		local ev = webylene.event
		local logger = webylene.logger
		logger:info("started webylene in environment " .. webylene.env .. " with path " .. webylene.path)
		
		ev:start("initialize")	
			ev:start("loadUtilities")
				require "utilities" -- we need all the random junk in here
			ev:finish("loadUtilities")
			
			--load config
			ev:start("loadConfig")
				load_config(self, "config", "lua")
				load_config(self, "config", "yaml")
			ev:finish("loadConfig")
		
			--load core objects
			ev:start("loadCore")
				load_objects(self, "objects/core")
			ev:finish("loadCore")
			
			--load plugin objects
			ev:start("loadPlugins")
				load_objects(self, "objects/plugins")
			ev:finish("loadPlugins")
		ev:finish("initialize")
	end,
	
	--- respond to a request
	request = function(self)
		local e = webylene.event
		e:start("request")
			e:fire("route")
		e:finish("request")
	end
}
	
	--- load config files of type <extension> from path <relative_path>. if <relative_path> is a folder, load all files with extension <extension>
load_config = function(self, relative_path, extension)
	extension = extension or "yaml"
	local loadFile = {
		yaml = function(path)
			require "yaml"
			local conf = yaml.load_file(path)
			if conf.env and conf.env[webylene.env] then	
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
	local absolute_path = webylene.path .. webylene.path_separator .. relative_path
	for file in lfs.dir(absolute_path) do																				-- is this part right?...
		if file ~= "." and file ~= ".."  and lfs.attributes(absolute_path .. webylene.path_separator .. file, "mode")=="file" and file:sub(-#extension) == extension then
			loadFile[extension](absolute_path .. webylene.path_separator .. file)
		end
	end
	return self
end
	
--- load all objects in lua files in relativePath
load_objects = function(self, relativePath)
	local absolutePath = webylene.path .. webylene.path_separator .. relativePath
	local webylene = webylene -- so that we don't have to go metatable-hopping all the time
	local extension = "lua"
	local extension_cutoff = #extension+2 --the dot +1
	for file in lfs.dir(absolutePath) do																				-- is this part right?...
		if file ~= "." and file ~= ".." and lfs.attributes(absolutePath .. webylene.path_separator .. file, "mode")=="file" and file:sub(-#extension) == extension then
			local obj = webylene[file:sub(1, -extension_cutoff)]
		end
	end
	return self
end
