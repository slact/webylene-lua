#!/usr/bin/env lua
function getopts(t, input)
	local alwaysatable=function(x) return type(x)=='table' and x or {x} end
	local indices=function(t, ind)
		local res
		for i, k in ipairs(ind) do
			res = t[k]
			if res~=nil then return res end
		end
	end
	local res = {}
	for i=1, #input do
		for j, matchstr in ipairs{"^-(%w)=?(.*)$", "^--(%w%w+)=?(.*)$" } do
			local name, val = input[i]:match(matchstr)
			if name and (not val or #val==0) then 
				val = (input[i+1] or ""):match("^([^%-].*)")
				if val then 
					i = i+1 
				end
			end
			if name then res[name]=val or false end
		end
	end
	for opt_aliases, callback in pairs(t) do
		local opt_found = indices(res, opt_aliases)
		if(opt_found~=nil) then 
			local n = callback(opt_found) 
			if(type(n)=="number") then
				os.exit(n)
			end
		end
	end
end

--luarocks
pcall( require, "luarocks.loader")
package.path = package.path .. ";./share/?.lua"
local PATH_SEPARATOR = "/" --filesystem path separator. "/" for unixy/linuxy/posixy things, "\" for windowsy systems
local protocol, path, reload, environment, log_file, serverstring, host, port
local version = "0.93"
--parse command-line parameters
local helpstr = ([[webylene %s bootstrap.
Usage: bootstrap.lua [OPTIONS]
Example: ./bootstrap.lua --path=/var/www/webylene --protocol=fcgi --env dev
Options:
  -p, --path=STR      Path to webylene project.
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
                      localhost:8080 for http.(Applicable when protocol=http)
  -l, --log           log file. Default to logs/webylene.log
  -V, --verbose       Print logs to stdout as well as a file.
  -h, --help          This help message.
  -v, --version       Display version information.
]]):format(version)
local arg = {}
local function setarg(name) return function(val) arg[name] = val or true end end
getopts({
	[{'P', 'protocol'}]		= function(val) if not arg.protocol then arg.protocol=val end end,
	[{'p', 'path'}]			= setarg('path'),
	[{'reload'}]			= setarg('reload'),
	[{'e', 'env', 'environment'}] = setarg('environment'),
	[{'l', 'log'}]			= setarg('log_file'),
	[{'s', 'server'}]		= function(val)
		if not val then
			print("No value given for --server (-s) parameter. Assuming localhost:8080")
			val="localhost:8080"
		end
		arg.host, arg.port = val:match("^([%w%.%-%_]+):?(%d*)$")
		if not arg.host then
			io.stderr:write("Invalid server hostname\r\n")
			return 1
		end
		if #arg.port==0 then arg.port=nil end
		if arg.protocol ~= 'proxy' then arg.protocol = 'http' end
	end,
	[{'h', '?', 'help'}]	= function() print(helpstr) return 0 end,
	[{'v', 'version'}]		= function() print("webylene " .. version) return 0 end,
	[{'V', 'verbose'}]		= setarg('verbose')
}, _G.arg)

if not arg.protocol then io.stderr:write("You must specify a protocol. check -h or --help for help.\r\n") return 1 end
arg.path_separator = PATH_SEPARATOR
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
	if (arg.path:sub(-1)~=PATH_SEPARATOR) then arg.path = arg.path .. PATH_SEPARATOR end
	if arg.path then io.stderr:write("Application path not specified. Guessed it to be '" .. tostring(arg.path) .. "'\n") end
end
if not arg.path then io.stderr:write("couldn't find webylene project path. try -h for help.\n") return 1 end

--let local requires work
package.path =	   arg.path .. "share" .. PATH_SEPARATOR .. "?.lua;" 
				.. arg.path .. "share" .. PATH_SEPARATOR .. "?" .. PATH_SEPARATOR .. "init.lua;" 
				.. package.path

local wsapi_request
local function initialize()
	package.loaded.webylene, webylene = nil, nil;
	require "webylene"
	local w = webylene.new()
	w:set_env(_G)
	local res, err = pcall(w.initialize, w, arg)
	
	if not res then
		if not wsapi_request then --first run -- first initialization
			io.stderr:write(err .. "\r\n")
		end
		wsapi_request = function() error(err, 0) end
	else
		wsapi_request = w.wsapi_request
	end
end
local function wsapi_request_recovery_pretender(self, ...)
	initialize()
	return wsapi_request(webylene, ...)
end
initialize()

local must_reload = arg.reload
local run_connector = webylene:initialize_connector(arg.protocol, function(env)
	local success, status, headers, iterator = pcall(wsapi_request, webylene, env)
	if not success or must_reload then -- oh shit, bad error. let the parent environment handle it.
		wsapi_request = wsapi_request_recovery_pretender
		if not success and rawget(webylene, "logger") then  pcall(webylene.logger.fatal, webylene.logger, status) end
		if rawget(webylene, "core") then pcall(webylene.core.shutdown) end --to to tell it to shut down
		if not success then 
			local msg = (webylene and webylene.config.show_errors~=false) and ("FATAL ERROR: " .. status) or "A bad error happened. We'll fix it, we promise!"
			return "500 Server Error", {['Content-Type']='text/plain', ['Content-Length']=#msg }, coroutine.wrap(function() 
				coroutine.yield(msg) 
			end)
		end
	end
	return status, headers, iterator
end, {host=arg.host, port=arg.port})

return run_connector()