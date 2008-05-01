--require "cgilua"

do
	local headers_sent = false
	print = function(...)
		if not headers_sent then
			cgilua.contentheader("text", "html")
		end
		cgilua.print(unpack(arg))
	end
end

webylene = {
	path = "/home/leop/sandbox/webylene/lua/trunk", --this sucks
	
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
	
	importFile = function(self, file_path, object_name)
		object_name = object_name or extractFilename(file_path):sub(1, (-#".lua"-1))
		--print("OBJ:" .. object_name .. " PATH:" .. file_path .. "\n" )
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

do
	local notFound = {}
	webylene.import = function(self, object_name)
		if rawget(self, object_name) ~= nil then
			return self.object_name
		elseif notFound[object_name] then
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

----
function cf(...)
	local config = webylene.config
	for i,v in ipairs(arg) do
		config = config[v]
	end
	return config
end

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
	for i,v in pairs(t2 or {}) do
		if type(v) == "table" and type(t1[i]) == "table" then
			t1[i] = table.mergeRecursivelyWith(t1[i], v)
		else
			t1[i] = v
		end
	end
	return t1
end

function table.mergeWith(t1, t2)
	for i,v in pairs(t2) do
		t1[i]=v
	end
	return t1
end

function table.merge(t, u)
  local r = {}
  for i, v in pairs(t) do
    r[i] = v
  end
  for i, v in pairs(u) do
    r[i] = v
  end
  return r
end

function table.key(t,k)
	return t[k]
end


function extractFilename(path)
	local i = #path
	while i > 0 and path[i] ~= "/" do i = i-1 end
	return path:sub(i)
end

function table.isarray(t)
	for i,v in pairs(t) do
		if(type(i) ~= "number") then
			return false
		end
	end
	return true
end

function table.show(t, name, indent)
   local cart     -- a container
   local autoref  -- for self references

   --[[ counts the number of elements in a table
   local function tablecount(t)
      local n = 0
      for _, _ in pairs(t) do n = n+1 end
      return n
   end
   ]]
   -- (RiciLake) returns true if the table is empty
   local function isemptytable(t) return next(t) == nil end

   local function basicSerialize (o)
      local so = tostring(o)
      if type(o) == "function" then
         local info = debug.getinfo(o, "S")
         -- info.name is nil because o is not a calling level
         if info.what == "C" then
            return string.format("%q", so .. ", C function")
         else 
            -- the information is defined through lines
            return string.format("%q", so .. ", defined in (" ..
                info.linedefined .. "-" .. info.lastlinedefined ..
                ")" .. info.source)
         end
      elseif type(o) == "number" then
         return so
      else
         return string.format("%q", so)
      end
   end

   local function addtocart (value, name, indent, saved, field)
      indent = indent or ""
      saved = saved or {}
      field = field or name

      cart = cart .. indent .. field

      if type(value) ~= "table" then
         cart = cart .. " = " .. basicSerialize(value) .. ";\n"
      else
         if saved[value] then
            cart = cart .. " = {}; -- " .. saved[value] 
                        .. " (self reference)\n"
            autoref = autoref ..  name .. " = " .. saved[value] .. ";\n"
         else
            saved[value] = name
            --if tablecount(value) == 0 then
            if isemptytable(value) then
               cart = cart .. " = {};\n"
            else
               cart = cart .. " = {\n"
               for k, v in pairs(value) do
                  k = basicSerialize(k)
                  local fname = string.format("%s[%s]", name, k)
                  field = string.format("[%s]", k)
                  -- three spaces between levels
                  addtocart(v, fname, indent .. "   ", saved, field)
               end
               cart = cart .. indent .. "};\n"
            end
         end
      end
   end

   name = name or "__unnamed__"
   if type(t) ~= "table" then
      return name .. " = " .. basicSerialize(t)
   end
   cart, autoref = "", ""
   addtocart(t, name, indent)
   return cart .. autoref
end

-- do some webylene stuff

webylene.config={}

--config getter shorthand

-----

webylene:import("core")