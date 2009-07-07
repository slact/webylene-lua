--- just a silly wrapper for the kepler file logger

--EVENTS:
--[[
<initialize source="core">
	log this
</initialize>
]]
--[[
<loadUtilities source="core">
	finish: log this 
</loadUtilities>
]]
--[[
<loadConfig source="core">
	finish: log this 
</loadConfig>
]]
--[[
<loadCore source="core">
	finish: log this 
</loadCore>
]]
--[[
<loadPlugins source="core">
	finish: log this 
</loadPlugins>
]]
--[[
<shutdown source="core">
	log this.
</loadPlugins>
]]

require "logging.file"
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