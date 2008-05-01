--require "cgilua"
print = cgilua.print
cgilua.contentheader("text","plain")
webylene = {
	path = "/home/leop/sandbox/webylene/lua/trunk", --this sucks
	
	notFound = {},
	
	import = function(self, object_name)
		if rawget(self, object_name) ~= nil then
			return self.object_name
		elseif self.notFound[object_name] then
			return nil
		end
		local dirs = {"objects/core", "objects", "objects/plugins"} --where shall we look?
		local result
		for i,dir in pairs(dirs) do
			result = self:importChunk(loadfile(self.path .. "/" .. dir .. "/" .. object_name .. ".lua"), object_name)
			if result ~= nil then
				return result
			end
		end		
		-- we tried, but failed. make a note of it, and move on... :'(  
		self.notFound[object_name] = true
		return nil
	end, 
	
	importChunk = function(self, file_chunk, object_name)
		if file_chunk == nil then return end
		
		print ("IMPORTAGE OF " .. object_name .. "\n")
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
	
	importFile = function(self, file_path, object_name)
		object_name = object_name or extractFilename(file_path):sub(1, (-#".lua"-1))
		print("OBJ:" .. object_name .. " PATH:" .. file_path .. "\n" )
		if rawget(self, object_name) ~= nil then
			return self.object_name
		end
		local result = self:importChunk(loadfile(file_path), object_name)
		if result ~= nil then
			return result
		end
		return nil
	end
}

setmetatable(webylene, {
	__index = function(tbl, key) --trigger the importer
		return tbl:import(key)
	end
})

setmetatable(_G, {__index = webylene}) -- so that people don't have to write webylene.this and webylene.that and so forth all the time.	

----

table.contains = function(tbl, value)
	for i,v in pairs(tbl) do
		if v == value then
			return true
		end
	end
	return nil
end

table.locate = function(tbl, value)
	for i,v in pairs(tbl) do
		if v == value then
			return i
		end
	end
	return nil
end

function table.mergeRecursivelyWith(t1, t2)
	for i,v in pairs(t2) do
		if type(v) == "table" and type(t1[i]) == "table" then
			t1[i] = table.mergeRecursivelyWith(v, t2[i])
		else
			t1[i] = t2[i]
		end
	end
end

function extractFilename(path)
	local i = #path
	while i > 0 and path[i] ~= "/" do i = i-1 end
	return path:sub(i)
end



-- do some webylene stuff

webylene.config={}

--config getter shorthand

-----

webylene:import("core")