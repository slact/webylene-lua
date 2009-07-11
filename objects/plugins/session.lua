--- session managing object

--EVENTS:
--[[
	<initialize source="core">
		load up session config, canonically in config/app.yaml.
	</initialize>
]]
--[[
	<databaseReady source="database">
		<sessionReady cond="session started without trouble">
			sessionReady remains active until databaseReady finishes
		</sessionReady>
	</databaseReady>
]]
--[[
	<request source="core">
		start: 
	</request>
]]

require "sha1"
require "serialize"

local engines
local webylene = webylene
session = {data={}, status={}}

do
	local mersenne_twister = require "random"
	local entropy_fountain
	
	session.init = function(self)
		local status = self.status
		
		---initialization and stuff.
		event:addListener("initialize", function() 
			self.config = cf("session")
			if not self.config or self.config.disabled == true or self.config.enabled == false or self.config.disabled == "true" or self.config.enabled == "false" then return end --do we want to try a session?
				
			local os_entropy_fountain, err = io.open("/dev/urandom", "r") --quality randomness, please.
			local seed
			if os_entropy_fountain then
				local rstr = os_entropy_fountain:read(6) --48 bits, please.
				os_entropy_fountain:close()
				seed=0
				for i=0,5 do
					seed = seed + (rstr:byte(i+1) * 256^i) --note: not necessarily platform-safe...
				end
			else --we aren't in a POSIX world, are we. oh well.
				seed = os.time() + 1/(math.abs(os.clock()) +1)
				logger:warn("Session ID RNG seed sucks.")
			end
			assert(seed, "Invalid seed for Session ID RNG. Bailing.")
			entropy_fountain = assert(mersenne_twister.new(seed), "Unable to start Session ID RNG (mersenne twister)")
			
			local start = function()
				--retrieve session id or create new one
				self.id = webylene.request.cookies[self.config.name] or self:generate_id()
				self.data = serialize.unserialize(self.engine:read(self.id)) or {}
				
				status.ready = true
				event:start("sessionReady")--announce it to the world.
			end
			
			math.randomseed(os.time())
			local libc_rand, ceiling=math.random, math.ceil
			local finish = function()
				status.ready = nil
				self.engine:write(self.id, serialize.serialize(self.data))
				local gc_chance = self.config.gc_chance
				if gc_chance~=0 and libc_rand(1, ceiling(1/tonumber(gc_chance))) == 1 then
					self.engine:gc(self.config.expires)
				end
				event:finish("sessionReady")--announce it to the world.
			end
			self.engine = engines[self.config.storage]
			self.engine:init(start, finish)
		end)
		
		event:addStartListener("request", function()
			status.cookie_sent = nil
		end)
			
		event:addFinishListener("request", function()
			status.cookie_sent = true
			if self.id then
				webylene.response:set_cookie(self.config.name, {expires = os.time()+self.config.expires, path="/", value=self.id})
			end
		end)
	end

	local thirtytwo=2^32
	session.generate_id = function(self)
		assert(entropy_fountain, "Session ID - generating Random Number Generator (mersenne twister) hasn't been seeded yet. I refuse to continue.")
		return ("%08x%08x%08x%08x"):format(
			entropy_fountain(0, thirtytwo), entropy_fountain(0, thirtytwo), 
			entropy_fountain(0, thirtytwo), entropy_fountain(0, thirtytwo))
		-- with a 128-bit session id, a collission will only start to
		-- occur once out of 10^18 times when the userbase reaches 10^10.
		-- Those are numbers I can live with without checking for collisions
		-- in the id generating function.
	end
end

	
--- change the session id
session.change_id = function(self)
	if self.status.ready and not self.status.cookie_sent then
		local new_id = self:generate_id()
		self.engine:delete(self.id)
		self.id = new_id
	else
		error("session not ready or cookie already sent.")
	end
end



--[[ Ahem. You may consider what you are about to see overkill. Normally, to generate
 a session ID, you would take some relatively short string (20-50 bits), hash
 the sucker, and bam! you've got your session ID. 
 
 Problem is, that only works if an attacker doesn't know how you generate those IDs. 
 Say an attacker wants to guess or brute-force a valid session ID. Looking at the ID
 as it is sent to the browser, he would need to request (and destroy) quite a few 
 session IDs from the server to determine the size of the ID space. But knowing this
 information still leaves him unable to guess the underlying method of ID generation
 (that is, the process of generating the string fed to the ID-producing hash remains
 to him a mystery). He cannot, therefore, put together 
 
 But should he have access to your code, he will immediately be able to see not only 
 the size of the key space, but he will be able to stage a brute-force attack 
 that targets this space _precisely_ -- since he knows exactly what IDs your server 
 could potentially produce. FYI, for a hashed string with 32 bits' worth of entropy,
 he'll have a session hijacked after about77000 tries. (Whereas, had he not known 
 the ID generation method, it might take him 10^19 tries generating 128-bit IDs 
 (as calculated via the birthday problem).)
 
 So, this being an open source project, security by code obscurity cannot do. Instead,
 a truly large-enough id space is provided via a sufficiently secure pseudorandom 
 number generator (the Mersenne Twister). This means that an attacker gains zero 
 advantage from knowing the code. So that's what we do here. 
 
 For now, 128 bits will do.
]]


engines = {
	---database storage engine
	database = {
		init = function(self, start, finish)
			event:addListener("initialize", function()
				self.table = session.config.table or "session"
			end)
		
			event:addListener("databaseTransaction", function()
				start()
			end)
			
			event:addFinishListener("databaseTransaction", function()
				finish()
			end)
			return self
		end,
		
		read = function(self, id)
			local db = db
			assert(db:connected(), "Cannot initialize database session storage: not connected to database.")
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
			local safe_id, safe_data, now = db:esc(id), db:esc(data), db:now()
			local res, err
			if db.driver=="mysql" then
				res, err = db:query(("INSERT INTO %s SET id='%s', data='%s', timestamp=%s ON DUPLICATE KEY UPDATE data='%s', timestamp=%s"):format(
									self.table,  safe_id,  safe_data,          now,                         safe_data,         now))
			elseif db.driver=="sqlite" then
				error("not yet.")
			else
				error("not yet.")
			end
			return self
		end, 
		
		--does the id exist?
		id_exists=function(self, id)
			local db=db
			local res, err = db:query(("SELECT id FROM %s WHERE id='%s';"):format(self.table, db:esc(id)))
			if not res then return nil, err end
			if db.numrows then return db:numrows()==1 else 
				
			end
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
