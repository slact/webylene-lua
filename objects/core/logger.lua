require "logging.file"
--- just a silly wrapper for the kepler file logger
logger = 
{
	init = function(self)
		local logger = assert(logging.file(webylene.path .. "/logs/webylene.log"))
		setmetatable(self, {__index=logger})
		
		--log important webylene loading events
		for i, ev in pairs({"Utilities", "Config", "Core", "Plugins"}) do
			event:addFinishListener('load' .. ev, function()
				self:info(ev .. " loaded without incident.")
			end)
		end
		event:addStartListener("initialize", function()
			self:info("initializing")
		end)
		event:addFinishListener("initialize", function()
			self:info("initialized without incident.")
		end)
		
		event:addFinishListener("shutdown", function()
			self:info("shutting down.")
		end)
	end
}