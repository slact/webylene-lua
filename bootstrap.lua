#!/usr/bin/env luajit
local path_separator = "/"
local protocol, path, reload, environment
local version = "0.dev"
--parse command-line parameters
local arguments = {...}
for i, a in ipairs(arguments) do
	if a=="-m"  or a == "--method" or a == "--protocol" then --this is the protocol we will use
		protocol = arguments[i+1]
	elseif a=="-p" or a == "--path" then --webylene root! woot!
		path=arguments[i+1]
	elseif a=="-r" or a=="--reload" then
		reload = true
	elseif a=="-e" or a=="--env" or a=="--environment" then
		environment=arguments[i+1]
	elseif a=="--version" then
		print("webylene " .. version)
		os.exit(0)
	elseif a=="-h" or a=="--help" then
		print([[webylene bootstrap.
Usage: bootstrap.lua [OPTIONS]
Options:
  -p, --path          Path to webylene project. Required.
  --protocol, -m, --method
                      Protocol used by webylene to talk to server.
					  Can be either of: cgi, fcgi, scgi, proxy.
  -e, --env, --environment
                      The environment webylene should expect to be in.
  -r, --reload        Reload webylene on every request. useful for development.
                      Not entirely clean: does not reload modules and does _not_
					  completely reset the environment.
  -h, --help          This help message.
  --version           Display version information.
Example:
  ./bootstrap.lua --path /var/www/webylene --protocol fcgi --env dev]])  
		os.exit(0);
	end
end
if not protocol then io.stderr:write("couldn't figure out what protocol to use. try -h for help.\n") os.exit(1) end
if not path then --framework, find thyself!
	--extract path from command invocation
	path = string.match(arg[1] or "", "^@?(.-)" .. path_separator .. "bootstrap.lua$") or string.match(arg[0] or "", "^@?(.-)" .. path_separator .. "bootstrap.lua$") --getting desperate
	if not path and debug then 	--last-ditch attempt
		path = (debug.getinfo(1, 'S').source):match("^@?(.-)" .. path_separator .. "bootstrap.lua$")
	end
end
if not path then io.stderr:write("couldn't find webylene project path. try -h for help.\n") os.exit(1) end
local protocol_connector = { --known protocol handlers
	cgi = 'cgi',
	fastcgi = 'fastcgi',
	fcgi = 'fastcgi',
	proxy = 'xavante',
	scgi = false --not yet implemented
}
local connector = protocol_connector[protocol]
if not connector then print(protocol .. ' protocol ' .. (connector == false and 'not yet implemented.' or 'unknown.')) os.exit(1) end

local webylene_object_path = path .. path_separator .. "objects" .. path_separator .. "core" .. path_separator .. "webylene.lua"
require (("wsapi.%s"):format(connector))

function initialize(previous_error)
	dofile(webylene_object_path)
	if previous_error then
		pcall(webylene.logger.fatal, webylene.logger, previous_error)
	end
	setmetatable(_G, {__index = webylene}) -- so that we don't have to write webylene.this and webylene.that and so forth all the time.	
	webylene:initialize(path, environment)
end
initialize()

local wsapi_request = webylene.wsapi_request
wsapi[connector].run(function(env)
	local success, status, headers, iterator = pcall(wsapi_request, webylene, env)
	if not success or reload then -- oh shit, bad error. let the parent environment handle it.
		pcall(webylene.event.fire, webylene.event, "shutdown")
		if not success then error(status, 0) end
		initialize((not success) and status)
	end
	return status, headers, iterator
end)
