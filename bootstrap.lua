#!/usr/bin/env luajit
local PATH_SEPARATOR = "/" --filesystem path separator. "/" for unixy/linuxy/posixy things, "\" for windowsy systems
local protocol, path, reload, environment, log_path
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
					  Can be any of: cgi, fcgi, scgi, proxy.
  -e, --env, --environment=STR
                      The environment webylene should expect to be in.
      --reload        Reinitialize webylene on every request.
                      Useful for development. This does not reload modules and
                      does _not_ reset the lua environment. Applicable only 
                      when a persistent protocol is used (fcgi, proxy, scgi).
  -h, --help          This help message.
  -v, --version       Display version information.
]]
local success, opts = pcall(getopt.get_opts, {...}, "p:P:e:hv", {
	path='p', protocol='P', env='e', environment='e', reload=0, help='h', version='v'
})
if not success then io.stderr:write(opts) return 1 end
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
	path = string.match(arg[1] or "", "^@?(.-)" .. PATH_SEPARATOR .. "bootstrap.lua$") or string.match(arg[0] or "", "^@?(.-)" .. PATH_SEPARATOR .. "bootstrap.lua$") --getting desperate
	if not path and debug then 	--last-ditch attempt
		path = ((debug.getinfo(1, 'S').source):match("^@?(.-)" .. PATH_SEPARATOR .. "bootstrap.lua$"))
	end
	if path then io.stderr:write("path was not specified. guessed it to be '" .. tostring(path) .. "'\n") end
end
if not path then io.stderr:write("couldn't find webylene project path. try -h for help.\n") return 1 end

local protocol_connector = { --known protocol handlers
	cgi = 'cgi',
	fastcgi = 'fastcgi',
	fcgi = 'fastcgi',
	proxy = false, -- not yet implemented
	scgi = false --not yet implemented
}
local connector = protocol_connector[protocol]
if not connector then print(protocol .. ' protocol ' .. (connector == false and 'not yet implemented.' or 'unknown.')) return 1 end
require (("wsapi.%s"):format(connector))

--let local requires work
package.path =	   path .. PATH_SEPARATOR .. "share" .. PATH_SEPARATOR .. "?.lua;" 
				.. path .. PATH_SEPARATOR .. "share" .. PATH_SEPARATOR .. "?" .. PATH_SEPARATOR .. "init.lua;" 
				.. package.path

local wsapi_request
local function initialize()
	require "webylene"
	setmetatable(_G, {__index = webylene}) -- so that we don't have to write webylene.this and webylene.that and so forth all the time.	
	webylene:set_config("log_path", log_path)
	local res, err = pcall(webylene.initialize, webylene, path, environment, PATH_SEPARATOR)
	if not res then
		if rawget(webylene, 'logger') then pcall(webylene.logger.fatal, webylene.logger, err) end
		wsapi_request = function() error(err, 0) end
	else
		wsapi_request = webylene.wsapi_request
	end
end
initialize()

wsapi[connector].run(function(env)
	local success, status, headers, iterator = pcall(wsapi_request, webylene, env)
	if not success or reload then -- oh shit, bad error. let the parent environment handle it.
		if not success and rawget(webylene, "logger") then  pcall(webylene.logger.fatal, webylene.logger, status) end
		if rawget(webylene, "core") then pcall(webylene.core.shutdown) end --to to tell it to shut down
		initialize()
		if not success then 
			return "500 Server Error", {['Content-Type']='text/plain'}, coroutine.wrap(function() 
				coroutine.yield((webylene and webylene.config.show_errors~=false) and ("FATAL ERROR: " .. status) or "A bad error happened. We'll fix it, we promise!") 
			end)
		end
	end
	return status, headers, iterator
end)
