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
			local res, err = redis:incr(autoincr_key)
			return res
		else
			return nil, "don't know how to autoincrement ids for key pattern " .. (keypattern or "???")
		end
	end
	
	local cache = setmetatable({},{__mode='k', __index=function(t,k)
		local this = {}
		t[k]=this
		return this
	end}) --store private stuff here
	local tablemeta, objectmeta
	local crud={
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
		end,
		insert = function(self)
			debug.print(self, debug.traceback())
			assert(self, "did you call foo.insert() instead of foo:insert()?")
			if not self:getId() then
				local newId, err = self:reserveId()
				if not newId then return nil, err end
				self:setId(newId)
			end
			if table.empty(self) then
				self._created = os.time()
			end
			return self:update()
		end,

		delete = function(self)
			redis:del(self:getKey())
		end,
		
		--what's this guy doing here?...
		new = function(self, id, res)
			debug.print(objectmeta or "NOT A GODDAMN THING")
			local res = res or {}
			setmetatable(res, objectmeta)
			if id then
				return res:setId(id) 
			else
				return res
			end
		end
	}

	objectmeta = {__index={
		
		setId = function(self, id)
			assert(self, "self missing")
			cache[self].key, cache[self].id = keymaker(id), id
			return self
		end,
		
		getKey = function(self)
			return cache[self].key
		end,

		getId = function(self)
			assert(self, "self missing")
			return cache[self].id
		end,

		reserveId = reserveId,
		
		insert = crud.insert,
		update = crud.update,
		delete = crud.delete
	}}
	
	table.mergeWith(objectmeta.__index, object)

	tablemeta = { __index = {
		new = crud.new,
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
		
		fromSort = function(self, key, pattern, maxResults, offset, descending, lexicographic)
			local res, err = redis:sort(key, {
				by=pattern or "nosort", 
				get="# GET " .. self:getKey():format("*"),  --oh the ugly!
				sort=descending and "desc" or nil, 
				alpha = lexicographic or nil,
				limit = maxResults and {offset or 0, maxResults}
			})
			if res then
				for i=0, #res, 2 do
					res[i+1]=self:new(res[i], res[i+1])
					table.remove(res, i)
				end
			end
			return res
		end,
		
		fromExternalSet = function(self, setKey, maxResults, offset, descending, lexicographic)
			return self:fromSort(setKey, nil, maxResults, offset, descending, lexicographic)			
		end,

		setAutoIncrementKey = function(self, key)
			assert(type(key)=="string", "Autoincrement key must be a string")
			autoincr_key = key
			return self
		end,
		
		reserveId = reserveId,

		getDefaultFunction = function(self, whatThing)
			return assert(crud[whatThing], "Default function " .. whatThing .. " not found.")
		end
	}}
	
	setmetatable(self, tablemeta)
	return self
end

redisobject = setmetatable({
	new=new, 
}, { __call = function(tbl, ...) return new(...) end })
