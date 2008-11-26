require "wsapi.cgi"
dofile("../../bootstrap.lua")
wsapi.cgi.run(
	function(env)
		webylene:initialize(env)
		return webylene:wsapi_request(env)
	end
)