#!/usr/bin/env lua
--luarocks
pcall( require, "luarocks.loader")

local PATH_SEPARATOR = "/" --filesystem path separator. "/" for unixy/linuxy/posixy things, "\" for windowsy systems
local protocol, path, reload, environment, log_file, serverstring, host, port
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
					  Can be any of: cgi, fcgi, http.
  -e, --env, --environment=STR
                      The environment webylene should expect to be in.
      --reload        Reinitialize webylene on every request.
                      Useful for development. This does not reload modules and
                      does _not_ reset the lua environment. Applicable only 
                      when a persistent protocol is used (fcgi, http, scgi).
  -s, --server=*:80   If webylene is being started as a standalone server, sets
                      the hostname and port it listens on. Default value is
                      localhost:80 for http.(Applicable only when protocol=http)
  -l, --log           log file. Default to logs/webylene.log
  -V, --verbose       Print logs to stdout as well as a file.
  -h, --help          This help message.
  -v, --version       Display version information.
]]
local success, opts = pcall(getopt.get_opts, {...}, "p:P:e:l::hs:vV", {
	path='p', protocol='P', env='e', environment='e', reload=0, help='h', server='s', version='v', verbose='V', log='l'
})
local arg = {}
if not success then io.stderr:write(opts) return 1 end
for a, v in pairs(opts) do
	if a=="P" then --this is the protocol we will use
		arg.protocol = v
	elseif a=="p" then --webylene root! woot!
		arg.path = v
	elseif a=="reload" then
		arg.reload = true
	elseif a=='l' then
		arg.log_file = v
	elseif a=="e" then
		arg.environment = v
	elseif a=="s" then
		arg.host, arg.port = v:match("^([^:]+):?(%d*)$")
		if not arg.host then
			io.stderr:write("invalid server hostname")
			return 1
		end
		arg.protocol = 'http'
	elseif a=='V' then
		arg.verbose = true
	elseif a=="v" then
		print("webylene " .. version)
		return 0
	elseif a=="h" then 
		print(helpstr)  
		return 0
	end
end
if not arg.protocol then io.stderr:write("You must specify a protocol. check -h or --help for help.\n") return 1 end
if not arg.path then --framework, find thyself!
	--extract path from command invocation
	arg.path = string.match(arg[1] or "", "^@?(.-)" .. PATH_SEPARATOR .. "bootstrap.lua$") or string.match(arg[0] or "", "^@?(.-)" .. PATH_SEPARATOR .. "bootstrap.lua$") --getting desperate
	if not arg.path and debug then 	--last-ditch attempt
		arg.path = ((debug.getinfo(1, 'S').source):match("^@?(.-)" .. PATH_SEPARATOR .. "bootstrap.lua$"))
	end
	if arg.path == "." then
		local pwd = os.getenv("PWD")
		if type(pwd)=='string' and #pwd > 0 then
			arg.path = pwd
		end
	end
	
	if arg.path then io.stderr:write("path was not specified. guessed it to be '" .. tostring(arg.path) .. "'\n") end
end
if not arg.path then io.stderr:write("couldn't find webylene project path. try -h for help.\n") return 1 end

--let local requires work
package.path =	   arg.path .. PATH_SEPARATOR .. "share" .. PATH_SEPARATOR .. "?.lua;" 
				.. arg.path .. PATH_SEPARATOR .. "share" .. PATH_SEPARATOR .. "?" .. PATH_SEPARATOR .. "init.lua;" 
				.. package.path

local wsapi_request
local function initialize()
	package.loaded.webylene, webylene = nil, nil;
	require "webylene"
	setmetatable(_G, { __index = webylene }) -- so that we don't have to write webylene.this and webylene.that and so forth all the time.	
	for k, v in pairs(arg) do
		webylene:set_config(k, v)
	end
	for i,v in pairs(webylene.config) do
		print(i,v)
	end
	local res, err = pcall(webylene.initialize, webylene, arg.path, arg.environment, PATH_SEPARATOR)
	if not res then
		wsapi_request = function() error(err, 0) end
	else
		wsapi_request = webylene.wsapi_request
	end
end
local function wsapi_request_recovery_pretender(self, ...)
	initialize()
	return wsapi_request(webylene, ...)
end
initialize()

local run_connector = webylene.initialize_connector(arg.protocol, arg.path, function(env)
	local success, status, headers, iterator = pcall(wsapi_request, webylene, env)
	if not success or reload then -- oh shit, bad error. let the parent environment handle it.
		wsapi_request = wsapi_request_recovery_pretender
		if not success and rawget(webylene, "logger") then  pcall(webylene.logger.fatal, webylene.logger, status) end
		if rawget(webylene, "core") then pcall(webylene.core.shutdown) end --to to tell it to shut down
		if not success then 
			return "500 Server Error", {['Content-Type']='text/plain'}, coroutine.wrap(function() 
				coroutine.yield((webylene and webylene.config.show_errors~=false) and ("FATAL ERROR: " .. status) or "A bad error happened. We'll fix it, we promise!") 
			end)
		end
	end
	return status, headers, iterator
end, {host=arg.host, port=arg.port})

return run_connector()