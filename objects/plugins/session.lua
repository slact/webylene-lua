require "sha1"
require "serialize"

--- session managing object
--  attaches itself to some core and sendHeaders events
--  events
--   - sessionReady:			signals the availability of session data. prolonged event. (fired whenever the chosen session engine feels like it)

session = {
	init = function(self)
		event:addListener("initialize", function() 
			self.config = cf("session")
			if not self.config or self.config.disabled == true or self.config.enabled == false or self.config.disabled == "true" or self.config.enabled == "false" then return end --do we want to try a session?
			self.engine = self.storage[self.config.storage]
			self.engine:init()
		end)
		
		event:addStartListener("request", function()
			self.status.cookie_sent = nil
		end)
		
		event:addStartListener("sessionEngineReady", function()
			--retrieve session id or create new one
			self.engine:open()
			self.id = webylene.request.cookies[self.config.name] or self:generate_id()
			self.data = serialize.unserialize(self.engine:read(self.id)) or {}
			
			self.status.ready = true
			event:start("sessionReady")--announce it to the world.
		end)
		
		event:addFinishListener("sessionEngineReady", function()
			self.status.ready = nil
			self.engine:write(self.id, serialize.serialize(self.data))
			math.randomseed(os.time())
			if math.random(1, math.ceil(1/(self.config.gc_chance))) == 1 then
				self.engine:gc(self.config.expires)
			end
			event:finish("sessionReady")--announce it to the world.
		end)
		
		event:addFinishListener("request", function()
			self.status.cookie_sent = true
			if self.id then
				webylene.response:set_cookie(self.config.name, {expires = os.time()+self.config.expires, path="/", value=self.id})
			end
		end)
	end,
	
	--- change the session id
	change_id = function(self)
		if self.status.ready and not self.status.cookie_sent then
			local new_id = self:generate_id()
			self.engine:delete(self.id)
			self.id = new_id
		else
			error("session not ready or cookie already sent.")
		end
	end,
		
	--- generate the session id with [bits] or 256 bits of entropy. presently reads /dev/urandom for randomness
	generate_id = function(self, bits)
		bits = bits or 256
		local res = sha1.digest(io.open("/dev/urandom", "r"):read(bits/16))
		return res
	end,

	data = {},
	status = {}
}

session.storage = {
	---database storage engine
	database = {
		init = function(self)
			event:addListener("initialize", function()
				self.table = session.config.table or "session"
			end)
		
			event:addListener("databaseReady", function()
				event:start("sessionEngineReady")
			end)
			
			event:addFinishListener("databaseReady", function()
				event:finish("sessionEngineReady") 
			end)
			return self
		end,
		
		open = function(self)
			assert(db.conn, "Cannot initialize database session storage: not connected to database.")
		end,
		
		close = function(self)
			--nothin'
			return self
		end, 
		
		read = function(self, id)
			local cur = assert(db:query("SELECT data FROM " .. self.table .. " WHERE id = '" .. db:esc(id) .. "';"))
			local res = cur:fetch({},'n')
			if res then
				res = res[1] --load up the data
				cur:close()
				return res
			else
				return nil, "no such session id"
			end
		end,
		
		write = function(self, id, data)
			local db = db
			local safe_id, safe_data = db:esc(id), db:esc(data)
			assert(db:query("INSERT INTO " .. self.table .. " SET id = '" .. safe_id .. "', data = '" .. safe_data .. "', timestamp=NOW() ON DUPLICATE KEY UPDATE data = '" .. safe_data .. "', timestamp = NOW();"))
		end, 
		
		delete = function(self, id)
			local db = db
			assert(db:query("DELETE FROM " .. self.table .. " WHERE id='" .. db:esc(id) .. "';"))
			return self
		end,
		
		gc = function(self, max_lifetime)
			assert(db:query("DELETE FROM " .. self.table .. " WHERE `timestamp` < from_unixtime(UNIX_TIMESTAMP() - " .. max_lifetime .. ");"))
			return self
		end
	}
}
