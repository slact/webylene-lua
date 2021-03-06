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

local multiplog = {} --all the supported logging destinations

local multiplog_call = function(key)
	return function(notself, a, b, c)
		for i=1, #multiplog do
			local thislog = multiplog[i]
			thislog[key](thislog, a, b, c)
		end
	end
end

require "logging"
logger = setmetatable({
	init = function(self)
		local logpath = cf("log_file") or "logs/webylene.log"
		
		local log_to_console = cf('verbose')
		
		if not logpath:match("^" .. webylene.path_separator) then
			logpath = webylene.path .. webylene.path_separator .. logpath
		end
		require "logging.file"
		local file_logger, logger_err = logging.file(logpath)
		if file_logger then
			table.insert(multiplog, file_logger)
		else --fallback to console logging
			log_to_console = true
		end
		
		if log_to_console then
			require "logging.console"
			table.insert(multiplog, logging.console())
		end
		
		if logger_err then
			self:error("logger: " .. logger_err)
			self:info("logger: Falling back on logging to console.")
		end
		
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
	
}, logging)

--oh my what an upstanding first-class citizen you are.
for _, key in pairs{ 'log', 'debug', 'info', 'warn', 'error', 'fatal', 'setLevel' } do
	logger[key]=multiplog_call(key)
end