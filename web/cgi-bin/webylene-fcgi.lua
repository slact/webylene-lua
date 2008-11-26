require "wsapi.fastcgi"
dofile("../../bootstrap.lua")
webylene:initialize()
wsapi.fastcgi.run(
	function(env)
		return webylene:wsapi_request(env)
	end
)