local webylene, event = webylene, event
local tinsert = table.insert
require "redis"
local function checkAndSetter(self)
	if pcall(self.watch, self, 'bar') then --WATCH command implemented
		self:unwatch()
		return function(self, key, before, multiexec, _times_checked)
			self:watch(key)
			if type(before)=='function' then before() end
			if type(multiexec)=='function' then 
				self:multi()
				multiexec() 
				local res = self:exec()
				
				if not res then
					--rinse and repeat
					_times_checked=(_times_checked or 0) + 1
					if _times_checked > (self.maxWatchRetries or 5) then
						logger:error(("Redis Check And Set failed on key %s %s time%s. Giving up."):format(key, _times_checked, _times_checked~=1 and "s" or ""))
						return nil
					else
						logger:warn(("Redis Check And Set failed on key %s %s time%s. Trying again."):format(key, _times_checked, _times_checked~=1 and "s" or ""))
						return self:checkAndSet(key, before, multiexec, _times_checked)
					end
				else
					return res
				end
			else
				self:unwatch()
				return nil, "nothing to MULTI/EXEC"
			end
		end
	else
		return function(self, key, before, multiexec, _times_checked)
			return nil, "Your redis server does not support the WATCH command. Please use Redis >= 2.1.0"
		end
	end
end

redis = {
	init = function(self)
		local settings=cf("redis") -- these will be loaded by now.
		if not settings then return nil, "redis settings not found" end
		if settings.disabled==true or settings.enabled==false then
			logger:warn("redis connection disabled")
			return nil, "redis connection disabled"
		end
		
		self.connect = function(self)
			local success, redis_instance = pcall(Redis.connect, settings.host, settings.port)
			if success then
				setmetatable(self, {__index=redis_instance})
				
				--add custom commands
				local custom_commands = {
					hset = false,
					hmset = {
						request = function(client, command, ...)
							local args, arguments = {...}, {}
							table.insert(arguments, args[1])
							for k,v in pairs(args[2]) do
								table.insert(arguments, k)
								table.insert(arguments, v)
							end
							redis.requests.multibulk(client, command, unpack(arguments))
						end
					},
					hget = false,
					hmget = {
						request = function(client, command, ...)
							local args, arguments, tinsert = {...}, {}, table.insert
							if (#args == 2 and type(args[2]) == 'table') then
								tinsert(arguments, args[1])
								for _,v in ipairs(args[2]) do
									tinsert(arguments, v)
								end
								redis.requests.multibulk(client, command, unpack(arguments))
							else
								redis.requests.multibulk(client, command, ...)
							end
						end
					},
					hgetall = {
						response = function(reply, command, ...)
							local new_reply = { }
							for i = 1, #reply, 2 do new_reply[reply[i]] = reply[i + 1] end
							return new_reply
						end 
					},
					multi = false,
					exec= false,
					discard = false,
					watch = false,
					unwatch = false,
					setnx = false
				}
				for command_name, opt in pairs(custom_commands) do
					pcall(redis_instance.add_command, redis_instance, command_name, opt and opt or nil)
				end
				
				event:start("redisConnection")
				return self
			else	
				local err = "Error connecting to redis server: " .. tostring(redis_instance)
				logger:error(err)
				return nil, err
			end
		end
		
		local res, err = self:connect()
		
		event:addListener("shutdown", function()
			if self:connected() then 
				self:close()
				--db_instance = nil --no, keep these around
				--webylene.db = nil
			end
		end)
		
		
		event:addStartListener("request", function()
			if event:active("redisConnection") then
				event:start("redisTransaction")
			end
		end)
		
		event:addFinishListener("request", function()
			event:finish("redisTransaction", true)
		end)
		
		self.checkAndSet = checkAndSetter(self)
		self.CAS=self.checkAndSet
		return self
	end,
	
	close = function(self) 
		if self.quit then
			event:finish("redisTransaction", true)
			event:finish("redisConnnection")
			self:quit()
			setmetatable(self, nil)
		end
		return self
	end,
	
}
