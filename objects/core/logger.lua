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
		local logpath = cf("log_file") or "logs/webylene.log"
		if not logpath:match("^" .. cf('path_separator')) then
			logpath = cf('path') .. cf('path_separator') .. logpath
		end
		local logger, err = logging.file(logpath)
		if not logger then error("logger: " .. err, 0) end
		
		
		setmetatable(self, cf('verbose') and { __index=function(t, k) 
			if k=='log' then
				return function(self, level, msg)
					io.write(("%s: %s\r\n"):format(level, msg))
					logger.log(self, level, msg)
				end
			end
			return logger[k]
		end} or {__index=logger})
		
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
		
		event:addStartListener("shutdown", function()
			self:info("shutting down.")
		end)
	end
}