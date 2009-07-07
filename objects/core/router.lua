--- route a request to a script in scripts/, as specified in config/routes.yaml

--EVENTS:
--[[
	<initialize source="core">
		access router configs. this is canonically stuff from config/routes.yaml
	</initialize>
]]
--[[
	<request source="core">
		<route>
			perform url-based routing
		</route>
		<arrive>
			fired immediately before executing a script from the scripts directory.
		</arrive>
	</request>
]]
--[[
	<request source="core">
		<route404 condition="no route matched against the requested url">
			make a note of this in the log. route to the 404 error page specified (canonically) in config/routes.yaml
		</route404>
	</request>
]]
--[[
	<request source="core">
		<route500 condition="an error occured processing a script or template (nothing else)">
			make a note of this in the log. route to the 500 error page specified (canonically) in config/routes.yaml
		</route500>
	</request>
]]


local rex = require "rex_pcre"
local webylene, event = webylene, event
local parser, script_printf_path, walk_path, parseurl, arrive --closureds

router = {
	init = function(self)
		--set our configgy stuff
		event:addListener("initialize",function()
			self.settings=assert(cf("router"), "No router config found. bailing.")
			script_printf_path = webylene.path .. webylene.path_separator .. self.settings.destinations.location .. webylene.path_separator .. "%s" .. self.settings.destinations.extension
		end)
		
		--route when it's time to do so
		event:addListener("request", function()
			local uri = request.SCRIPT_URI
			if not uri or #uri==0 then
				uri = request.env.REQUEST_URI
			end
			self:route(uri)
		end)
	end,

	--- perform the routing, besed on the uri given
	route = function(self, uri)
		event:start("route")
		local url = parseurl(uri).path
		for i,route in pairs(self.settings.routes) do
			route = parser.parseRoute(route)
			if walk_path(url, route.path) then
				event:finish("route")
				return arrive(self, route)
			end
		end
		--no route matched. 404 that sucker.
		event:finish("route")
		return self:route404(url)
	end,
	
	--- route to the 404 page. this gets its own function because it might be considered a default -- no route, so take Route 404.
	route404 = function(self)
		event:fire("route404")
		return arrive(self, parser.parseRoute({path=" ", ref="404", destination=self.settings["404"]}))
	end,
	
	--if there was an error executing a page script
	route500 = function(self, error_message, trace)
		event:start("route500")
		logger:error(error_message)
		local d500 = self.settings["500"]
		event:finish("route500")
		assert(d500, error_message .. ". Additionally, 500 page handler script not found -- bailing.")
		return arrive(self, parser.parseRoute({path=" ", ref="500", destination=self.settings["500"], param={error=error_message, trace=trace}}), true)
	end,
	
	setTitle=function(self, title)
		if not self.currentRoute then return nil, "not yet routed" end
		self.currentRoute.param.title=title
	end,
	getTitle=function(self)
		if not self.currentRoute then return nil, "not yet routed" end
		return self.currentRoute.param.title
	end,
	getRef=function(self)
		if not self.currentRoute then return nil, "not yet routed" end
		return currentRoute.param.ref
	end 
}


--cachy, cachy
local url_rex = rex.new("^((?P<scheme>(?:http|ftp)s?)://(?:(?P<userinfo>\w+(?::\w+)?)@)?(?P<hostname>[^/:]+)(:(?P<port>[0-9]+))?)?(?P<path>/[^?#]*)?(?:\\?(?P<query>[^#]*))?(?:#(?P<fragment>.*))?$")
--- parse a uri into its parts. returns a table with keys:
-- scheme	= protocol used (http, https, ftp, etc)
-- userinfo	= username:password
-- hostname	= hostname or ip address of server
-- port		= port, if any specified
-- path		= path part of the url, excluding the querystring (i.e. the path part of http://google.com/foo/bar?huh#1 would be /foo/bar
-- query	= query string, excluding leading ? character
-- fragment	= part of url after the # character
parseurl = function(url) 
	local start, finish, res = url_rex:tfind(url)
	return res
end
local path_regex = setmetatable({}, {__index=function(t,match_str)
	local r = rex.new("^" .. match_str .. "$")
	rawset(t, match_str, r)
	return r
end})

--- is the urlPattern intended to be  a simple match, or a regular expression?
local ought_to_regex = function(urlPattern)
	return urlPattern:sub(1,2) ~= "|"
end

--- see if the url matches the path given
walk_path = function(url, path)
	local match = { url = false, param = true }
	
	--TODO: this whole thing's kind of ugly. prettify later.
	local params = request.params
	for param, val in pairs(path.param) do
	--path params. it's an or.
		if params[param] ~= val then
			match.param = false
			break
		end
	end
	
	for i, furl in pairs(path.url) do
		--path urls. it's an and.
		if ought_to_regex(furl) then
			--regex comparison
			local start, finish, matches = path_regex[furl]:exec(url or "")
			if matches then --the regexp matched!
				local params = request.params
				for name, val in pairs(matches) do
				--expand named regex captures into REQUEST parameters
					if type(name) == "string" and val ~= false then
						params[name]=val
					end
				end
				match.url = true
			end
		else
			--plain old string comparison. get rid of the initial escape char, and compare
			match.url = url:sub(2) == furl
		end
		
		if match.url then
			break
		end
	end
	return (match.url and match.param)
end

--- parse a route. a bit tricky, since the route spec is pretty flexible
parser = {
	knownParams = {"title", "ref"},
	
	destination = function(contents)
		if type(contents)=="table" then
			--expanded destination notation
			contents.param = contents.param or {}
			assert(contents.script, "Destination script path not set. that's bad. check config/routes.yaml")
		elseif type(contents) == "string" or type(contents) == "number" then
			contents = {script=contents, param={}}
		else 
			error("Couldn't parse route destination: expected to be a table or string, but was a "  .. type(contents))
		end
		return contents
	end,
	
	pathUrl = function(url)
		if type(url) == "string" then
			return {url}
		elseif type(url) == "table" then
			return url
		else
			error("Couldn't parse route path URL: expected a table, found a " .. type(url) .. ". Check config/routes.yaml")
		end
	end,
	
	path = function(contents)
		if type(contents) == "table" and not table.isarray(contents) then
			assert(contents.url, "Couldn't parse route path: path explicitly stated, but no url given. Check config/routes.yaml")	--no url. can't do anything about that, error out.
			contents.url=parser.pathUrl(contents.url)
			contents.param = contents.param or {}
		else  --it's a shorthand
			contents = {url=parser.pathUrl(contents), param={}}
		end
		return contents
	end,
	
	param = function(contents)
		assert(type(contents) == "table", "Couldn't make sense of params. Check config/routes.yaml")
		return contents
	end,
		
	extractBaseParam = function(contents) 
		local param = {}
		for i,key in pairs(parser.knownParams) do
			if contents[key] then 
				param[key]=contents[key]
				contents[key]=nil
			end
		end
		return param
	end,
	
	parseRoute = function(contents)
		assert(type(contents) == "table", "expected route to be a table, found a " .. type(contents) .. " instead. Check config/routes.yaml")
		local key, val = next(contents) -- key may be the route target, or nothing important. 
		local baseParam = parser.extractBaseParam((table.length(contents) == 1) and val or contents)
		local route = {
			path=parser.path(contents.path or val), --path or first value in contents
			destination = parser.destination(contents.destination or key), --destination or first key in contents
			param = parser.param(table.mergeRecursivelyWith(baseParam, contents.param))
		}
		route.param.ref = route.param.ref or route.destination.script -- auto-ref
		return route
	end
}

do
	--i'm just a helper traceback function for xpcall. i return a table with the error message and a trace. It's a table because a traceback may return only one argument. i think...
	local function tracy(err)
		local trace
		if debug and debug.traceback then
			trace = debug.traceback("", 2)
		end
		return {error=err, trace=trace}
	end
	
	--a slightly hacky way of gracefully handling script errors (that is, from stuff in the scripts directory)
	local function mypcall(func)
		local success, res = xpcall(func, tracy)
		if not success then 
			return nil, router:route500(res.error, res.trace) 
		else
			return res
		end
	end
	
	local scriptcache = setmetatable({}, {__index=function(t, absolute_path)
		local chunk, err = loadfile(absolute_path)
		--[[should loadfile fail, we want to return a lua-chunk which, 
		upon execution, will error out with loadfile's error message. 
		this should not be cached.]]
		if not chunk then 
			return function() error(err, 0) end
		end
		rawset(t, absolute_path, chunk)
		return chunk
	end})
	
	--- stuff to do upon finishing the routing.
	-- @param self router object
	-- @param route the route that could. (could match the request url, that is.)
	-- @param unprotected set this to true only if you want an error to trigger a total shutdown (and restart) of webylene. used when routing to a 500 page to avoid possible infinite loops.
	arrive = function(self, route, unprotected)
		table.mergeWith(request.params, route.param) --add route's predefined params to the params table
		self.currentRoute = route
		
		event:start("arrive")
		local scriptpath=script_printf_path:format(route.destination.script)
		local script_return --a script will return a function when it wants said function to respond to routing requests. TODO: this comment needs to explain the idea better.
		if not unprotected then
			script_return = mypcall(scriptcache[scriptpath])
			if script_return and type(script_return)=="function" then
				scriptcache[scriptpath]=script_return
				script_return = mypcall(scriptcache[scriptpath])
			end
		else
			script_return = assert(scriptcache[scriptpath])()
			--violating DRY on purpose. this copypasta is the result of slightly premature optimization.
			if script_return and type(script_return)=="function" then
				scriptcache[scriptpath]=script_return
				script_return = assert(scriptcache[scriptpath])()
			end
			--yes, this means the 'arrive' event may not finish. but hell, if this errors out,
			-- an unfinished event is the least of your concerns. unless you were routing to 
			-- an error page, what the hell are you doing using an unprotected arrival?
		end
		event:finish("arrive")
	end
end 