#!/usr/bin/env lua
local path_separator = "/"
local protocol, path, reload, environment
local version = "0.dev"
--parse command-line parameters
local getopt = require "alt_getopt"
local helpstr = [[webylene bootstrap.
Usage: bootstrap.lua [OPTIONS]
Example: ./bootstrap.lua --path=/var/www/webylene --protocol=fcgi --env dev
Options:
  -p, --path=STR      Path to webylene project. Required.
  -P, --protocol=STR
                      Protocol used by webylene to talk to server.
					  Can be either of: cgi, fcgi, scgi, proxy.
  -e, --env, --environment=STR
                      The environment webylene should expect to be in.
      --reload        Reload webylene on every request. useful for development.
                      Not entirely clean: does not reload modules and does _not_
					  completely reset the environment.
  -h, --help          This help message.
  -v, --version       Display version information.
]]
local success, opts = pcall(getopt.get_opts, {...}, "p:P:e:hv", {
	path='p', protocol='P', env='e', environment='e', reload=0, help='h', version='v'
})
if not success then io.stderr:write(opts) return 0 end
for a, v in pairs(opts) do
	if a=="P" then --this is the protocol we will use
		protocol = v
	elseif a=="p" then --webylene root! woot!
		path = v
	elseif a=="reload" then
		reload = true
	elseif a=="e" then
		environment=v
	elseif a=="v" then
		print("webylene " .. version)
		return 0
	elseif a=="h" then
		print(helpstr)  
		return 0
	end
end
if not protocol then io.stderr:write("You must specify a protocol. check -h or --help for help.\n") return 1 end
if not path then --framework, find thyself!
	--extract path from command invocation
	path = string.match(arg[1] or "", "^@?(.-)" .. path_separator .. "bootstrap.lua$") or string.match(arg[0] or "", "^@?(.-)" .. path_separator .. "bootstrap.lua$") --getting desperate
	if not path and debug then 	--last-ditch attempt
		path = (debug.getinfo(1, 'S').source):match("^@?(.-)" .. path_separator .. "bootstrap.lua$")
	end
end
if not path then io.stderr:write("couldn't find webylene project path. try -h for help.\n") return 1 end
local protocol_connector = { --known protocol handlers
	cgi = 'cgi',
	fastcgi = 'fastcgi',
	fcgi = 'fastcgi',
	proxy = 'xavante',
	scgi = false --not yet implemented
}
local connector = protocol_connector[protocol]
if not connector then print(protocol .. ' protocol ' .. (connector == false and 'not yet implemented.' or 'unknown.')) return 1 end

local webylene_object_path = path .. path_separator .. "objects" .. path_separator .. "core" .. path_separator .. "webylene.lua"
require (("wsapi.%s"):format(connector))

local function initialize(previous_error)
	if previous_error then pcall(webylene.logger.fatal, webylene.logger, previous_error) end
	local s, err = pcall(dofile, webylene_object_path) if not s then error(err,0) end
	setmetatable(_G, {__index = webylene}) -- so that we don't have to write webylene.this and webylene.that and so forth all the time.	
	webylene:initialize(path, environment)
end
initialize()

local wsapi_request = webylene.wsapi_request
wsapi[connector].run(function(env)
	local success, status, headers, iterator = pcall(wsapi_request, webylene, env)
	if not success or reload then -- oh shit, bad error. let the parent environment handle it.
		pcall(function() webylene.event:fire("shutdown") end) --to to tell it to shut down
		initialize((not success) and status)
		if not success then 
			return 500, {['Content-Type']='text/plain'}, coroutine.wrap(function() 
				coroutine.yield((webylene and webylene.config.show_errors==true) and "ERROR: " .. status or "A bad error happened. We'll fix it, we promise!") 
			end)
		end
	end
	return status, headers, iterator
end)
