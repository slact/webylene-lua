--- an object to access crisps
-- a crisp is a variable that persists until the next request from the owner of a given session, and then gets removed -- unless explicitly prolonged
crisp = {
	init = function(self)
		event:addListener("sessionReady", function() session.data.crisps = session.data.crisps or {}; end)
		event:addFinishListener("sessionReady", function() self:clean() end)
	end,
	
	exists = function(self, name)
		return self.crisps[name]
	end,
	
	set = function(self, name, value, cleaner)
		self.crisps[name]={val=value, keep=true, cleaners={cleaner}}
	end,
	
	--- attach a function to be called when it's time to remove a crisp. function gets passed the crisp value.
	-- @param string crisp crisp name
	-- @param function func function name. func([crisp val], [crisp name]) will be called when it's time to delete the crisp.
	-- @return boolean 	 	  
	addCleaner = function(self, crisp, func)
		if self.crisps[name] and type(func)=="function" then
			table.insert(session.data.crisps[name].cleaners, func)
		else
			return nil
		end
		return self
		
	end,
	

	--- reset all cleaners associated with a crisp
	resetCleaners = function(self, crisp)
		if not self.crisps[name] then return false end
		self.crisps[name].cleaners={}
		return self
	end,
	
	--- retrieve crisp value	 	
	get = function (self, crisp)
		if self.crisps[name] then
			return self.crisps[name].val
		end
	end,
	
	--- renew crisp -- make sure it won't get erased next time	
	renew = function(self, name, val)
		local crisp_table = self.crisps[name]
		if not crisp_table then
			return nil
		end
		if val then
			crisp_table.val = val
		end
			
		crisp_table.keep = true
		return self;
	end,
	
	--- renew all crisps
	renewAll = function(self)
		for name, crisp_table in pairs(self.crisps) do
			self:renew(name)
		end
		return self
	end,
	
	--- run in bootstrap to clean the crisps.
	clean = function(self)
		if not self.crisps then self.crisps = {} end
		local crisps = self.crisps
		
		for name, crisp in pairs(crisps) do
			if not crisp.keep then 
				for i, func  in ipairs(crisp.cleaners) do
					func(crisp.val, name)
				end
				if not crisp.keep then -- re-check, in case a cleaner decided to renew the crisp
					crisps[name] = nil
				end
			else
				crisp.keep=false
			end
		end
	end
}