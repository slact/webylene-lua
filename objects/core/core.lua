require "lfs"
require "cgilua"

core = {
	init = function(self)

		webylene:loadlib("utils") -- we need all the random junk in here
		
		local ev = webylene.event
		--where oh where shall I put this?
		
		cgilua.GET = cgilua.QUERY
		cgilua.REQUEST = table.merge(cgilua.GET, cgilua.POST)
		
		ev:fire("start")
		ev:start("load")
			--load config
			ev:start("loadConfig")
				self:loadConfig("config", "lua")
				self:loadConfig("config", "yaml")
				ev:fire("configLoaded")
			ev:finish("loadConfig")
			
			--load core objects
			ev:start("loadCore")
				self:loadObjects("objects/core")
				--ev:fire("coreLoaded")
			ev:finish("loadCore")
			
			--load plugin objects
			ev:start("loadPlugins")
				self:loadObjects("objects/plugins")
				--webylene event fire("pluginsLoaded")
			ev:finish("loadPlugins")
		ev:finish("load")
	
		ev:start("ready")
			ev:fire("route")
			
			--this may be needed so that blank pages don't cause a 500. that is, at least output the header.
			print ""
			
		ev:finish("ready")
	end,
	
	--- load config files of type <extension> from path <relativePath>. if <relativePath> is a folder, load all files with extension <extension>
	loadConfig = function(self, relativePath, extension)
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
		
		assert(loadFile[extension], "Config loader doesn't know what to do with the  <." .. extension .. "> extension.")
		local absolutePath = webylene.path .. "/" .. relativePath
		for file in lfs.dir(absolutePath) do																				-- is this part right?...
			if file ~= "." and file ~= ".."  and lfs.attributes(absolutePath .. "/" .. file, "mode")=="file" and file:sub(-#extension) == extension then
				--print ("will load <" .. absolutePath .. "/" .. file .. ">\n")
				loadFile[extension](absolutePath .. "/" .. file)
			end
		end
		return self
	end,
	
	--- load all objects in lua files in relativePath
	loadObjects = function(self, relativePath)
		local absolutePath = webylene.path .. "/" .. relativePath
		local webylene = webylene -- so that we don't have to go metatable-hopping all the time
		local extension = "lua"
		local extension_cutoff = #extension+2 --the dot +1
		for file in lfs.dir(absolutePath) do																				-- is this part right?...
			if file ~= "." and file ~= ".." and lfs.attributes(absolutePath .. "/" .. file, "mode")=="file" and file:sub(-#extension) == extension then
				webylene:importFile(absolutePath .. "/" .. file, file:sub(1, -extension_cutoff))
			end
		end
		return self
	end
	
}