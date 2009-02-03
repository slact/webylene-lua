#!/usr/bin/env luajit
local path_separator = "/"
local protocol, path
for i, a in ipairs(arg) do
	if a=="-m"  or a == "--method" or a == "--protocol" then --this is the protocol we will use
		protocol = arg[i+1]
	elseif a=="-p" or a=="-r" or a == "--path" or a == "--prefix" or a == "--root" then --webylene root! woot!
		path=arg[i+1]
	end
end
assert(protocol, "couldn't figure out what protocol to use")
--webylene, find thyself!
if not path then
	--extract path from self maybe?... 
	path = string.match(arg[1] or "", "^@?(.-)" .. path_separator .. "bootstrap.lua$")
	path = path or string.match(arg[0] or "", "^@?(.-)" .. path_separator .. "bootstrap.lua$") --getting desperate
	--last-ditch attempt
	if not path then
		path = debug.getinfo(1, 'S').source
		if path then path = path:match("^@?(.-)" .. path_separator .. "bootstrap.lua$") end
	end
end
assert(path, "Tried really hard, but couldn't find webylene project path")
local init=function()
	_G.webylene=nil
	dofile(path .. path_separator .. "objects" .. path_separator .. "core" .. path_separator .. "webylene.lua")
	setmetatable(_G, {__index = webylene}) -- so that we don't have to write webylene.this and webylene.that and so forth all the time.	
	webylene:initialize(path)
end
if protocol=="cgi" then
	require "wsapi.cgi"
	init()
	wsapi.cgi.run(
		function(env)
			return webylene:wsapi_request(env)
		end
	)
elseif protocol=="fastcgi" or protocol=="fcgi" or protocol=="wsapi" then
	require "wsapi.fastcgi"
	init()
	wsapi.fastcgi.run(function(env)
		local success, status, headers, iterator = pcall(function()
			return webylene:wsapi_request(env)
		end)
		if not success then -- bad, bad error. recover
			init()
			webylene.logger:fatal(status .. " ... had to reboot webylene.")
			return 500, {['Content-Type']='text/plain'}, coroutine.wrap(function() 
				if webylene and webylene.config.show_errors==true then 
					coroutine.yield("ERROR: " .. status) 
				else
					coroutine.yield("A bad error happened. We'll fix it, we promise!")
				end
			end)
		end
		return status, headers, iterator
	end)
else 
	error("unknown protocol " .. protocol) 
end 
