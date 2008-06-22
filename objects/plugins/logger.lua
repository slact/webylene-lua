require "logging.file"
logger = 
{
	init = function(self)
		local logger = assert(logging.file(webylene.path .. "/logs/%s.log", "%Y-%m-%d"))
		setmetatable(self, {__index=logger})
	end
}
