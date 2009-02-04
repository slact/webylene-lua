#!/usr/bin/env luajit
local path_separator = "/"
local protocol, path, reload
for i, a in ipairs(arg) do
	if a=="-m"  or a == "--method" or a == "--protocol" then --this is the protocol we will use
		protocol = arg[i+1]
	elseif a=="-p" or a == "--path" then --webylene root! woot!
		path=arg[i+1]
	elseif a=="-r" or a=="--reload" then
		reload = true
	elseif a=="-h" or a=="--help" then
		print([[webylene bootstrap.
Options:
  -p/--path <path>    path to webylene project
  --protocol {cgi|fcgi|fcgi|proxy}   protocol used by webylene to talk to server
  -m/--method {...}   alias for --protocol
  -r/--reload         reload webylene on every request. useful for development.
  -e/--env            probably the environment webylene should use
  -h/--help           this help message
Example:
   ./bootstrap.lua -p /var/www/webylene/ --protocol fcgi --env dev]])  
		os.exit(0);
	end
end
if not protocol then print("couldn't figure out what protocol to use. try -h for help.") os.exit(1) end
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
if not path then print("Tried really hard, but couldn't find webylene project path. try -h for help.") os.exit(1) end

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
elseif protocol=="fastcgi" or protocol=="fcgi" then
	require "wsapi.fastcgi"
	init()
	local runner = function(reload)
		if reload then
			webylene.logger:warn("webylene running in reload mode -- every request reloads webylene. i bet you're doing dev work.")
			return function(env)
				dump(webylene)
				webylene.event:fire("shutdown")
				init()
				return webylene:wsapi_request(env)
			end
		else
			return function(env)
				local success, status, headers, iterator = pcall(function()
					return webylene:wsapi_request(env)
				end)
				if not success then -- bad, bad error. recover
					pcall(webylene.event:fire("shutdown"))
					init()
					pcall(webylene.logger:fatal(status .. " ... had to reboot webylene."))
					return 500, {['Content-Type']='text/plain'}, coroutine.wrap(function() 
						if webylene and webylene.config.show_errors==true then 
							coroutine.yield("ERROR: " .. status) 
						else
							coroutine.yield("A bad error happened. We'll fix it, we promise!")
						end
					end)
				end
				return status, headers, iterator
			end
		end
	end
	wsapi.fastcgi.run(runner(reload))
elseif protocol=="proxy" then 
	print("proxy protocol not yet implemented. stay tuned.") os.exit(1)
else
	print("unknown protocol " .. protocol) os.exit(1)
end 
