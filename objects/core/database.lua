require "luasql.mysql"
require "gettimeofday" -- temp needed for debugging

--- the database talker object. also available as webylene.db
database = {
	init = function(self)
		webylene.db = self -- shorthand for everyone else to use.
		
		event:addAfterListener("loadConfig",function()
			self.settings=cf("database") -- these will be loaded by now.
			if not self.settings then return nil, "no database config. ain't even gonna try to connect" end
			self.env = luasql.mysql()
			--connect
			self.conn = assert(self.env:connect(self.settings.db, self.settings.username, self.settings.password, self.settings.host, self.settings.port or 3306))
			
			setmetatable(self, {__index=self.conn})
		end)
		
		event:addAfterListener("ready", function()
			--disconnect
			if self.conn then self.conn:close() end
		end)
	end,
	
	
	
	--- perform an SQL query. returns a cursor for SELECT queries, number of rows touched for all other queries,(nil, error) on error.
	-- @param str query
	query = function(self, str)
		local start = os.gettimeofday()
		local res, err = self.conn:execute(str)
		local finish = os.gettimeofday()
		if (finish - start) > 0.05 then
			logger:info("Unusually long query: '" .. str .. "' took " .. (finish - start) .. "msec")
		end
		if res == nil then
			return nil, err .. ". QUERY WAS: " .. str
		end
		return res
	end,
	
	--- for loop iterator for a database result cursor. see the luaSQL cursor documentation
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
	niceQuery = function(self, str)
		local cur, err = self.conn:execute(str)
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
		return self.conn:escape(str)
	end,
	
	--- format a time to sql-standard date format
	date = function(self, time)
		return os.date("%Y-%m-%d %X",time)
	end,
	
	--- asks the database what time it is. 
	now = function(self)
		local res = db:firstRow(db:query("SELECT NOW() as now;"))
		return res.now
	end,
	
	commit = function(self)
		return self.conn:commit()
	end,
	
	setautocommit = function(self, bool)
		return self.conn:setautocommit(bool)
	end,
	
	rollback = function(self)
		return self.conn:rollback()
	end
}