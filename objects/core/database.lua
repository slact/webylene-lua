require "luasql.mysql"
database = {
	init = function(self)
		webylene.db = self -- shorthand for everyone else to use.
		
		event:addAfterListener("loadConfig",function()
			self.settings=cf("database")
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
	
	query = function(self, str)
		return self.conn:execute(str)
	end,
	
	rows = function(self, cur, mode)
		mode = mode or 'a'
		return function()
			return cur:fetch({}, mode)
		end
	end,
	
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
	
	esc = function(self, str)
		return self.conn:escape(str)
	end
}