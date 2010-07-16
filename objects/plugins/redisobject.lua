local redis = redis

local new = function(keypattern, self, object, autoincr_key)
	self, object = self or {}, object or {}
	
	assert(type(keypattern)=="string", "key pattern must be a string (i.e. 'foobar:%s')")
	assert(keypattern:format('foo')~=keypattern:format('bar'), "Invalid key pattern string (\""..keypattern.."\") produces same key for different ids.")

	local id = setmetatable({}, {__mode='k'}) --store ids here
	local function reserveId(self)
		if autoincr_key then
			local res, err = redis:increment(autoincr_key)
			return res
		else
			return nil, "don't know how to autoincrement ids for key pattern " .. (keypattern or "???")
		end
	end

	local objectmeta = {__index={
		getId = function(self)
			return id[self]
		end,
		
		setId = function(self, newId)
			id[self]=newId
		end,
		
		getKey = function(self)
			return keypattern:format(self:getId())
		end,
		
		delete = function(self)
			redis:delete(self:getKey())
		end,
		
		insert = function(self)
			if id[self] then 
				return nil, self:getKey() .. " already exists."
			else
				local newId, err = redis:increment(autoincr_key)
				if not newId then return nil, err end
				self:setId(newId)
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
	
	local tablemeta = { __index = {
		new = function(self, id, res)
			if not res and type(id)=='table' then
				--only one parameter, the res (and not the id) was given
				id, res = nil, id
			end
			res = res or {}
			setmetatable(res, objectmeta)
			return res
		end, 
		
		find = function(self, id)
			if not id then return nil, "Nothing to look for" end
			local res, err = redis:hgetall(keypattern:format(id))
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

	--support for custom-ish creation and deletion
	local custom = {[self]={'new'}, [object]={'update', 'delete'}}
	for tbl, customizeables in pairs(custom) do
		for i, v in ipairs(customizeables) do
			if type(tbl[v])=="function" then
				local normal, additional = getmetatable(tbl).__index[v], tbl[v]
				tbl[v] = function(...)
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

	return setmetatable(self, tablemeta)
end

redisobject = setmetatable({
	new=new, 
}, { __call = function(tbl, ...) return new(...) end })
