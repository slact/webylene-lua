require "wsapi.cgi"

dofile("../../bootstrap.lua")
require "remdebug.engine"
wsapi.cgi.run(
	function(env)
		remdebug.engine.start()
		webylene:initialize(env)
		return webylene:wsapi_request(env)
	end
)