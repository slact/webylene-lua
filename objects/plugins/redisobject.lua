local redis = redis

--[[
	new(
		key,  -- "key_pattern:%s" or key making function
		model, -- {} table of optional model methods (including new)
		object, -- {} table of optional object (row) methods (including new, delete, and insert)
		autoincr_key -- "autoincrement:bar" -- use this key as the autoincrement counter for these objects
	}

]]

local new = function(key, self, object, autoincr_key)
	self, object = self or {}, object or {}
	
	local keymaker
	assert(key, "Redisobject Must. Have. Key.")
	if type(key)=="string" then
		assert(key:format('foo')~=key:format('bar'), "Invalid key pattern string (\""..key.."\") produces same key for different ids.")
		keymaker = function(arg)
			return key:format(arg)
		end
	elseif type(key)=="function" then
		keymaker = key
	end
	
	local function reserveId(self)
		if autoincr_key then
			local res, err = redis:increment(autoincr_key)
			return res
		else
			return nil, "don't know how to autoincrement ids for key pattern " .. (keypattern or "???")
		end
	end
	
	local emptytable = {}
	local cache = setmetatable({},{__mode='k', __index=function(t,k,v)
		return emptytable
	end}) --store private stuff here

	local objectmeta = {__index={
		
		setKey = function(self, id)
			cache[self] = { key = keymaker(id), id = id }
			return self
		end,
		
		getKey = function(self)
			return cache[self].key
		end,

		getId = function(self)
			return cache[self].id
		end,
		
		delete = function(self)
			redis:delete(self:getKey())
		end,
		
		insert = function(self)
			assert(self, "did you call foo.insert() instead of foo:insert()?")
			if self:getId() then 
				return nil, self:getKey() .. " already exists."
			else
				local newId, err = redis:increment(autoincr_key)
				if not newId then return nil, err end
				self:setKey(newId)
				self._created = os.time()
				return self:update()
			end
		end,
		
		update = function(self, what)
			local key = self:getKey()
			local res, err
			if not what then
				res, err = redis:hmset(key, self)
			elseif type(what)=='string' then
				res, err = redis:hset(key, what, self[what])
			elseif type(what)=='table' then
				local delta = {}
				for i, k in pairs(what) do
					delta[k]=self[k]
				end
				res, err = redis:hmset(key, delta)
			end
			if res then 
				return self
			else 
				return nil, err
			end
		end
	}}
	
	table.mergeWith(objectmeta.__index, object, true)

	local tablemeta = { __index = {
		new = function(self, id, res)
			if #arg==0 then
				return nil, "id not given!"
			end
			
			local res = res or {}
			setmetatable(res, objectmeta)
			if id then
				return res:setKey(id) 
			else
				return res
			end
		end, 
		
		find = function(self, id)
			local key = keymaker(id)
			if not key then return nil, "Nothing to look for" end
			local res, err = redis:hgetall(key)
			if res then
				return self:new(id, res)
			else
				return nil, "Not found."
			end
		end,
		
		setAutoIncrementKey = function(self, key)
			assert(type(key)=="string", "Autoincrement key must be a string")
			autoincr_key = key
			return self
		end
	}}
	
	setmetatable(self, tablemeta)
	--support for custom-ish creation and deletion
	local custom = {
		{ src=self, dst=self, meta=tablemeta, 
			'new'
		}, 
		{ src=object, dst=objectmeta.__index, meta=objectmeta,
			'insert', 'update', 'delete'
		}
	}
	for _, c in pairs(custom) do
		for i, v in ipairs(c) do
			local additional = c.src[v]
			if type(additional)=="function" then
				local normal = c.meta.__index[v]
				c.dst[v] = function(...)
					local res, err = normal(...)
					if res then
						return additional(...)
					else
						return nil, err
					end
				end
			end
		end
	end
	return self
end

redisobject = setmetatable({
	new=new, 
}, { __call = function(tbl, ...) return new(...) end })
