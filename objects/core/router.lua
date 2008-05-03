require "rex_pcre"
rex = rex_pcre

router = {

	init = function(self)
		--route when it's time to do so
		
		event:addListener("route", function()
			self:route(cgilua.servervariable("SCRIPT_URI"))
		end)
		
		--set our configgy stuff
		event:addAfterListener("loadConfig",function()
			self.settings=cf("router") or error("No router config found. bailing.")
		end)
	end,
	
	parseurl = function(self, url) 
		local url_rex = rex.new("(?P<scheme>(?:http|ftp)s?)://(?:(?P<userinfo>\w+(?::\w+)?)@)?(?P<hostname>[^/:]+)(:(?P<port>[0-9]+))?(?P<path>/[^?#]*)?(?:\\?(?P<query>[^#]*))?(?:#(?P<fragment>.*))?")
		local res = {url_rex:tfind(url)}
		return res[3]
	end,

	route = function(self, uri)
		local url = self:parseurl(uri).path
		for i,route in pairs(self.settings.routes) do
			route = self.parser:parseRoute(route)
			if self:walkPath(url, route.path) then
				return self:arriveAtDestination(route)
			end
		end
		--no route matched. 404 that sucker.
		self:route404()
	end,
	
	route404 = function(self)
		self:arriveAtDestination(self.parser:parseRoute({path=" ", ref="404", destination=self.settings["404"]}))
	end,
	
	arriveAtDestination = function(self, route)
		table.mergeWith(cgilua.REQUEST, route.destination.param) --add route's predefined params to the REQUEST table
		self.currentRoute = route
		
		event:fire("arriveAtDestination")
		
		--this part?...
		dofile(webylene.path .. "/" .. self.settings.destinations.location .. "/" .. route.destination.script .. self.settings.destinations.extension)
	end,
	
	walkPath = function(self, url, path)
	--see if the path matches
		local match = { url = false, param = true }
		
		--TODO: this whole thing's kind of ugly. prettify later.
		local request = cgilua.REQUEST
		for param, val in pairs(path.param) do
		--path params. it's an or.
			if request[param] ~= val then
				match.param = false
				break
			end
		end
		
		for i, furl in pairs(path.url) do
			--path urls. it's an and.
			if self:oughtToRegex(furl) then
				--regex comparison
				local matches = {rex.new("^" .. furl .. "$"):exec(url)}
				if #matches ~= 0 then --the regexp matched!
					for name, val in pairs(matches[3]) do
					--expand named regex captures into REQUEST parameters
						if type(name) == "string" and val ~= false then
							cgilua.REQUEST[name]=val
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
	end,

	
	oughtToRegex = function(self, urlPattern)
		return urlPattern:sub(1,2) ~= "|"
	end,
	
	parser = {
		knownParams = {"title", "ref"},
		
		destination = function(self, contents)
			if type(contents)=="table" then
				--expanded destination notation
				contents.param = contents.param or {}
				assert(contents.script, "Destination script path not set. that's bad. check config/routes.yaml")
			elseif type(contents) == "string" or type(contents) == "number" then
				contents = {script=contents, param={}}
			else 
				error("Couldn't parse route destination: expected to be a Map or Sequence, but was a "  .. type(contents))
			end
			return contents
		end,
		
		pathUrl = function(self, url)
			if type(url) == "string" then
				return {url}
			elseif type(url) == "table" then
				return url
			else
				error("Couldn't parse route path URL: expected a Sequence or a List, found " .. type(url) .. ". Check your config/routes.yaml")
			end
		end,
		
		path = function(self, contents)
			if type(contents) == "table" and not table.isarray(contents) then
				assert(contents.url, "Couldn't parse route path: path explicitly stated, but no url given")	--no url. can't do anything about that, error out.
				contents.url=self:pathUrl(contents.url)
				contents.param = contents.param or {}
			else  --it's a shorthand
				contents = {url=self:pathUrl(contents), param={}}
			end
			return contents
		end,
		
		param = function(self, contents)
			assert(type(contents) == "table", "Couldn't make sense of params")
			return contents
		end,
			
		extractBaseParam = function(self, contents) 
			local param = {}
			for i,key in pairs(self.knownParams) do
				if contents[key] then 
					param[key]=contents[key]
					contents[key]=nil
				end
			end
			return param
		end,
		
		parseRoute = function(self, contents)
			local route = {}
			assert(type(contents) == "table", "expected route to be a table, found a " .. type(contents) .. " instead")
			local baseParam = self:extractBaseParam(contents)
			local key, val = next(contents)
			route.path = self:path(contents.path or val) --path or first value in contents
			route.destination = self:destination(contents.destination or key) --destination or first key in contents
			route.param = self:param(table.mergeRecursivelyWith(baseParam, contents.param))
			route.param.ref = route.param.ref or route.destination.script -- auto-ref
			return route
		end
	}
}