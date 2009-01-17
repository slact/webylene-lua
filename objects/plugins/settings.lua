--- settings taken from the database. useful for customizeable stuff.
local db, cf, event, session = db, cf, event, session
local cached = {}

settings = {
	init = function(self)
		self.table = cf("table") or ""
		event:addListener("sessionReady", function()
			if not session.data.settings then
				session.data.settings = {}
			end
			cached = session.data.settings
		end)
	end,
	
	get = function(self, setting)
		--get a setting. cache-smart.
		if not cached[setting] then
			local cursor = db:query("SELECT * FROM `" .. self.table .. "` WHERE name='" .. db:esc(setting) .. "'")
			if cursor then 	
				cached[setting]=cursor:fetch({},'a')
				cursor:close()
			else
				cached[setting]={}
			end
		end
		return cached[setting].value
	end,
	
	set = function(self, setting, value, setting_type, description)
		local the_setting = self:get(setting)
		if not the_setting then	
			cached[setting]={}
			cached[setting].type = setting_type or type(value)
		end
		if setting_type then
			cached[setting].type = setting_type
		end
		
		cached[setting].name = setting
		cached[setting].value = value
		cached[setting].description = description or cached[setting].description
	end
}