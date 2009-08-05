local webylene, event = webylene, event

local db_mt --closured

--- the database class. uses LuaSQL to talk to databases.
--- see http://www.keplerproject.org/luasql/manual.html for more info.
--- LuaSQL (as of version 2.1.1) supports ODBC, ADO, Oracle, MySQL, SQLite, and PostgreSQL.
--- database connection will be available as webylene.db

--- EVENTS:
--[[ during initialization:
	<initialize source="core">
		access database-related config
		if using persistent connections, connect to database
	</initialize>
]]
--[[ during a request:
	<request source="core">
		<databaseTransaction>
			on start: if not using persistent connections, connect to db
	
			on finish: if not using persistent connections, disconnect from db
		</databaseTransaction>
	</request>
]]
--[[
	<shutdown source="core">
		close all active database connections
	</shutdown>
]]

database = {
	--- initialize db connection
	init = function(self)
		
		--TODO: rework this stuff to make compatible with persistent connections.
		
		local db_settings, db_instance -- upvalues, baby, upvalues.
		
		event:addListener("initialize",function()
			db_settings=cf("database") -- these will be loaded by now.
			if not db_settings then return nil, "no database config. ain't even gonna try to connect" end
			if db_settings.disabled==true or db_settings.enabled==false then
				logger:warn("database connection disabled")
				return nil, "database connection disabled"
			end
			db_instance = assert(self:new(db_settings.type))
			webylene.db = db_instance --- ############ Let this not slip by thine eyes ############
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
		end)
	end,
	
	--- new db connection object maybe? (doesn't actually connect, that happens a little later.)
	new = function(self, database_type) 
		if not database_type then 
			return nil, "no database type specified..."
		elseif type(database_type)~='string' then 
			return nil, "unrecognized database type " .. tostring(database_type) 
		end
		local luasql_dbtype = string.format("luasql.%s", database_type)
		require(luasql_dbtype)
		local env = luasql[database_type]()
		
		--here's some of the beef of a database object.
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
			query = db_mt.__index.query, -- speed hack. is it desired, or just ugly?
			driver = database_type:lower() --may come in handy
		}, db_mt)
	end	
}

--database instance methods
db_mt = { __index = {
--- perform an SQL query. returns a cursor for SELECT queries, number of rows touched for all other queries,(nil, error) on error.
	-- @param str query
	-- @return query result or [nil, err_message] on error
	query = function(self, str)
		local conn, success, res, err = self.connection, nil, nil, nil
		
		success, res, err = pcall(conn.execute, conn, str)
		if not success then -- connection closed maybe? try to reconnect then.
			logger:info("Failed executing query: " .. (tostring(res) or "?") .. ".")
			if not pcall(self.connect, self) then
				logger:info("Also, failed to reconnect to database.")
			end
			success, res, err = pcall(conn.execute, conn, str)
			res, err = success and res, success and err or res
		end
		if res == nil then
			local error = err .. ". QUERY WAS: " .. str
			logger:warn(error)
			return nil, error
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
		local res, tins = {}, table.insert
		for row in self:rows(cur) do
			tins(res, row)
		end
		return res
	end,	
	
	--- returns first row of query result cursor. closes the curson upon completion.
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
		local cur, err = self:query(str)
		if not cur then return nil, err end
		return self:results(cur)
	end,
	
	--- escape quotes n' such to avoid an SQL injection
	-- @param str string to escape
	esc = function(self, str)
		local t = type(str)
		if t=="string" or t=="number" then
			return self.connection:escape(str)
		else
			return nil, "bad argument to db esc (string or number expected, got " .. type(str)
		end
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
		local unixtime_function, dbtype = "", self.driver
		if dbtype=="mysql" then
			unixtime_function = "UNIX_TIMESTAMP('%s')"
		elseif dbtype == "sqlite" then -- EXTREME DANGER: extremely untested.
			unixtime_function = "strftime('%%s', '%s')"
		elseif dbtype == "oracle" then -- EXTREME DANGER: extremely untested.
			unixtime_function= "DATEDIFF(s, '19700101', '%s')"
		elseif dbtype == "odbc" or dbtype=="ado" then
			return nil, "not yet implemented"
		end
		return tonumber(self:firstRow(self:query("SELECT " .. unixtime_function:format(self:esc(datestring)) .. " as stamp;"))["stamp"])
	end,
	
	--- asks the database what time it is
	-- @return database-native timestamp string
	now = function(self)
		local fnow, dbtype = "", self.driver
		if dbtype=="mysql" then
			fnow = "NOW()"
		elseif dbtype == "sqlite" then -- mild danger: not terribly well-tested
			fnow = "date('now')"
		elseif dbtype == "oracle" then -- Notable Danger: not well-tested
			fnow= "CURRENT_DATE"
		elseif dbtype == "odbc" or dbtype=="ado" then
			return nil, "not yet implemented"
		end
		return self:firstRow(self:query("SELECT " .. fnow .. " as now;"))["now"]
	end,
	
	--- asks the database what Unix-time it is. 
	unix_timestamp = function(self)
	local fnow, dbtype = "", self.driver
		if dbtype=="mysql" then
			fnow = "UNIX_TIMESTAMP()"
		elseif dbtype == "sqlite" then -- mild danger: not terribly well-tested
			fnow = "strftime('%s','now')"
		elseif dbtype == "oracle" then -- EXTREME DANGER: extremely untested.
			fnow="DATEDIFF(s, '19700101', CURRENT_DATE)"
		elseif dbtype == "odbc" or dbtype=="ado" then
			return nil, "not yet implemented"
		end
		return tonumber(self:firstRow(self:query("SELECT " .. fnow .. " as now;"))["now"])
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