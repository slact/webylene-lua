require "cgilua.cookies"
require "cgilua.serialize"
require "sha1"


--- session managing object
-- attaches itself to some core and sendHeaders events
-- events
--  - readSession:			after initializing the storage engine. prolonged event. (started after "configLoaded")
--  - writeSession:			prolonged event associated with writing and storing session data. (started after "ready" finishes)

session = {
	init = function(self)
	
		cgilua.SESSION = self.data	--might come in handy?...
		
		event:addAfterListener("configLoaded", function() 
			self.config = cf("session")
			if not self.config or self.config.disabled == true or self.config.enabled == false or self.config.disabled == "true" or self.config.enabled == "false" then return end --do we want to try a session?
			local engine = self.storage[self.config.storage]
			--retrieve session id or create new one
			self.id = cgilua.cookies.get(self.config.name) or self:generate_id()
			
			event:addAfterListener("loadCore", function()
				engine:init()
				event:start("readSession")
				self.data = engine:read(self.id) or {}
				event:finish("readSession")
			end)
			
			event:addListener("sendHeaders", function()
				local buf = {}
				cgilua.cookies.set(self.config.name, session.id, {expires = os.time()+self.config.expires, path="/"})
			end)
			
			event:addFinishListener("ready", function()
				local buf = {}
				event:start("writeSession")
				cgilua.serialize(self.data, function(s) table.insert(buf, s) end)
				buf = table.concat(buf, "")
				engine:write(self.id, buf)
				event:finish("writeSession")
				
				math.randomseed(os.time())
				if math.random(1, math.ceil(1/(self.config.gc_chance))) == 1 then
					engine:gc(self.config.expires)
				end
				
				engine:close() 
			end)
			
			--prevent session hijacking
			event:addListener("login", function()
				self:change_id()
			end)
		end)
	
	end,
	
	
	--- change the session id
	change_id = function(self)
		--assumes engine's already been initialized.
		local new_id = self:generate_id()
		local engine = self.storage[self.config.storage]
		local stored_session = engine:read(self.id)
		engine:delete(self.id)
		engine:write(new_id, stored_session)
		self.id = new_id
	end,
		
	--- generate the session id with [bits] or 256 bits of entropy. presently reads /dev/urandom for randomness
	generate_id = function(self, bits)
		bits = bits or 256
		local res = sha1.digest(io.open("/dev/urandom", "r"):read(bits/16))
		return res
	end,

	data = {}
}


do
	local session = session
	--- these be different session storage engines
	session.storage = {
		---database storage engine
		database = {
			init = function(self)
				--assumes an established connection
				assert(db.conn, "Cannot initialize database session storage: not connected to database.")
				
				self.db = db
				tbl_name = session.config.table or "session"
				self.table = tbl_name
				return self
			end,
			
			close = function(self)
				--nothin'
				return self
			end, 
			
			read = function(self, id)
				local cur = assert(self.db:query("SELECT data FROM " .. self.table .. " WHERE id = '" .. self.db:esc(id) .. "';"))
				local res = cur:fetch({},'n')
				if res then res = assert(loadstring("return " .. res[1]))() end --the column
				cur:close()
				return res
			end,
			
			write = function(self, id, data)
				local db = self.db
				local safe_id, safe_data = db:esc(id), db:esc(data)
				assert(db:query("INSERT INTO " .. self.table .. " SET id = '" .. safe_id .. "', data = '" .. safe_data .. "', timestamp=NOW() ON DUPLICATE KEY UPDATE data = '" .. safe_data .. "', timestamp = NOW();"))
			end, 
			
			delete = function(self, id)
				assert(self.db:query("DELETE FROM " .. self.table .. " WHERE id='" .. self.db:esc(id) .. "';"))
				return self
			end,
			
			gc = function(self, max_lifetime)
				assert(self.db:query("DELETE FROM " .. self.table .. " WHERE `timestamp` < from_unixtime(UNIX_TIMESTAMP() - " .. max_lifetime .. ");"))
				return self
			end
		}
	}
end 
