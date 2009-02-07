local webylene, event = webylene, event

local db_mt --closured

--- the database class.
--- database connection will be available as webylene.db
database = {
	--- initialize db connection
	init = function(self)
		
		--TODO: rework this stuff to make compatible with persistent connections.
		
		local db_settings, db_instance -- upvalues, baby, upvalues.
		
		event:addListener("initialize",function()
			db_settings=cf("database") -- these will be loaded by now.
			if not db_settings then return nil, "no database config. ain't even gonna try to connect" end
			db_instance = assert(self:new(db_settings.type))
			webylene.db = db_instance --- ############ Let this not slip by thine eyes ############
		end)
		if db_settings.persist==true or db_settings.persist == "true" then
			assert(db_instance:connect(db_settings.db, db_settings.username, db_settings.password, db_settings.host, db_settings.port or 3306))
			event:addStartListener("request", function()
				if not db_instance:connected() then assert(db_instance:connect(db_settings.db, db_settings.username, db_settings.password, db_settings.host, db_settings.port or 3306)) end
				event:start("databaseTransaction")
			end)
			
			event:addFinishListener("request", function()
				event:finish("databaseTransaction")
				--disconnect
			end)
			
			event:addListener("shutdown", function()
				if db_instance:connected() then 
					db_instance:close()
					--db_instance = nil --no, keep these around
					--webylene.db = nil
				end
			end)
		else
			event:addStartListener("request", function()
				--connect
				assert(db_instance:connect(db_settings.db, db_settings.username, db_settings.password, db_settings.host, db_settings.port or 3306))
				event:start("databaseTransaction")
			end)
			
			event:addFinishListener("request", function()
				event:finish("databaseTransaction")
				--disconnect
				if db_instance:connected() then 
					db_instance:close()
					--db_instance = nil --no, keep these around
					--webylene.db = nil
				end
			end)
		end
	end,
	
	--- new db connection object maybe? (doesn't actually connect, that happens later.
	new = function(self, database_type) 
		if not database_type then 
			return nil, "no database type specified..."
		elseif type(database_type)~='string' then 
			return nil, "unrecognized database type " .. tostring(database_type) 
		end
		local luasql_dbtype = string.format("luasql.%s", database_type)
		require(luasql_dbtype)
		local env = luasql[database_type]()
		return setmetatable({
			connect = function(self, ...)
				self.connected = function(self)
					return self.connection and true
				end
				local arg = {...}
				self.clone = function(self) -- love them closures, eh?
					return database:new(database_type):connect(unpack(arg))
				end
				
				local connection, err = env:connect(unpack(arg))
				self.connection = connection
				--self.logging_conn = env:connect(unpack(arg))
				if not self.connection then return nil, err end
				return self 
			end,
			close = function(self)
				if self.connection:close() then
					self.connection = nil
					return self
				else 
					return nil, "can't close connection -- it's still being used."
				end
			end,	
			query = db_mt.__index.query -- speed hack. is it desired, or just ugly?
		}, db_mt)
	end	
}

--database instance methods
db_mt = { __index = {
--- perform an SQL query. returns a cursor for SELECT queries, number of rows touched for all other queries,(nil, error) on error.
	-- @param str query
	-- @return query result or [nil, err_message] on error
	query = function(self, str)
		
		--assert(self.logging_conn:execute(("INSERT INTO logsql SET connection = '%s', query= '%s', stack='%s'"):format(self:esc(tostring(self.connection)), self:esc(str), self:esc(debug.traceback("", 2)))))
		
		local res, err = self.connection:execute(str)
		if res == nil then
			return nil, err .. ". QUERY WAS: " .. str
		end
		return res
	end,
	
	--- for loop iterator for a database result cursor. see the luaSQL cursor documentation
	-- @param cur database query cursor. returns nil if (not cur)
	-- @param mode (optional) 'i' for numeric or 'a' for text row keys. defaults to 'a'.
	-- @return generic-for iterator function
	rows = function(self, cur, mode)
		if not cur then
			return nil, "no cursor provided."
		end
		local mode = mode or 'a'
		return function()
			return cur:fetch({}, mode)
		end
	end,
	
	--- returns a table containing all result rows for a given cursor
	-- @param cur database query cursor. undefined behavior if cur is anything else.
	-- @return table of resulting rows or nil, err on error
	results = function(self, cur)
		local res = {}
		for row in self:rows(cur) do
			table.insert(res, row)
		end
		return res
	end,	
	
	--- returns first row of query result cursor.
	-- behavior undefined if cur isn't a valid database result cursor
	firstRow = function(self, cur, mode)
		local mode = mode or 'a'
		local res = cur:fetch({}, mode)
		cur:close()
		return res
	end,
	
	--- perform query, return results as a table.
	--@return table of resultant rows, or nil, err_msg on error
	niceQuery = function(self, str)
		local cur, err = self.connection:execute(str)
		if not cur then
			return cur, err
		end
		local rows = {}
		for row in self:rows(cur) do
			table.insert(rows, row)
		end
		cur:close()
		return rows
	end,
	
	--- escape quotes n' such to avoid an SQL injection
	-- @param str string to escape
	esc = function(self, str)
		return self.connection:escape(str)
	end,
	
	--- format a time to sql-standard date format
	date = function(self, timestamp)
		return os.date("%Y-%m-%d %X",timestamp)
	end,
	
	--- produce a unix timestamp from sql-standard date stamp
	timestamp = function(self, datestring)
		-- yyyy-mm-dd hh:mm:ss
		if not datestring or datestring == "" then 
			return nil 
		end
		return tonumber(self:firstRow(self:query("SELECT UNIX_TIMESTAMP('" .. self:esc(datestring).. "') as stamp;"))["stamp"])
	end,
	
	--- asks the database what time it is. 
	now = function(self)
		return self:firstRow(self:query("SELECT NOW() as now;"))["now"]
	end,
	
	--- asks the database what Unix-time it is. 
	unix_timestamp = function(self)
		return tonumber(self:firstRow(self:query("SELECT UNIX_TIMESTAMP() as now;"))["now"])
	end,
	
	commit = function(self)
		return self.connection:commit()
	end,
	
	setautocommit = function(self, bool)
		return self.connection:setautocommit(bool)
	end,
	
	rollback = function(self)
		return self.connection:rollback()
	end
}}