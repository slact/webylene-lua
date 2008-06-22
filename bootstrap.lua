--we'll need this stuff right off the bat
require "cgilua"
require "lfs"

webylene = {
	--- where the crap is webylene running? this function finds the absolute path of the webylene root, based on the assumption that it was started from web/index.lua
	locate = function(self, path)
		local path = cgilua.script_pdir --there's the web/index.lua assumption. also, assumes that the server properly identifies script_pdir
		local slash_byte = string.byte("/",1)
		for i=#path-1, 1, -1 do   --i=path-1 to ignore trailing slash.
			if path:byte(i) == slash_byte then
				self.locate = nil
				self.path = path:sub(1, i-1)
				return self.path
			end
		end
		return nil, "couldn't find webylene root!!. cgilua.script_pdir was <" .. tostring(cgilua.script_pdir) .. ">."
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
		
		--print ("IMPORTAGE OF " .. object_name .. "\n")
		local safe_env = setmetatable({}, {__index=_G})
		setfenv(file_chunk, safe_env)() -- run the file in a safe environment
		local result = rawget(safe_env, object_name)
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
		local object_name = object_name or extractFilename(file_path):sub(1, (-#".lua"-1))
		--print("OBJ:" .. object_name .. " PATH:" .. file_path .. "\n" )
		if rawget(self, object_name) ~= nil then
			return self[object_name]
		end
		local result = self:importChunk(assert(loadfile(file_path)), object_name)
		if result ~= nil then
			return result
		end
		return nil
	end,
	
	--- load a library (random heap o' functions) from webylene root/lib/[lib_name].lua
	loadlib = function(self, lib_name)
		assert(loadfile(webylene.path .. "/lib/" .. lib_name .. ".lua"))()
	end
}

do
	local notFound = {}
	
	--- magic webylene importer. called whenever webylene.foo is nil, tries to load foo.lua from the folders listed below. 
	--@see webylene.importFile
	webylene.import = function(self, object_name)
		if rawget(self, object_name) ~= nil then
			return self.object_name
		elseif notFound[object_name] then
			return nil
		end
		local dirs = {"objects/core", "objects", "objects/plugins"} --where shall we look?
		local f, path, result
		for i,dir in pairs(dirs) do

			path = self.path .. "/" .. dir .. "/" .. object_name .. ".lua"
			f = io.open(path, "r")
			if f then
				result = self:importChunk(assert(loadstring(f:read("*all"), dir .. "/" .. object_name .. ".lua")), object_name)
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

--where am i?
assert(webylene:locate())
-----
webylene:import("core")