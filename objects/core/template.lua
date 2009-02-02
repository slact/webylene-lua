require "lp"
require "wsapi.util"
local webylene, event, cf= webylene, event, cf
local insider --stuff available from inside a template

template = {
	init = function(self)
		event:addListener("initialize", function()

			--load 'em on in!
			self.settings = {templates = cf("templates") or {}, layouts = cf("layouts") or {}}
			
			--take care of any shorthand there may be
			for key, val in pairs(self.settings.templates) do
				if type(val) == "string" then
					self.settings.templates[key]={path=val}
				end
			end
			
			local discover_templates=true
			local discovered = {}
			if discover_templates then
				table.mergeWith(self.settings.templates, self.discover_templates(self))
			end
			
			lp.setoutfunc("write")
		end)
	end, 
	
	layout = false,
	
	discover_templates = function(self, extension) --recursive traversal of templates/ for, um, templates...
		local slash = webylene.path_separator
		local templates_prefix = webylene.path .. slash .. "templates" .. slash
		local extension = extension or ".lp"
		local known_template_files = {}
		if type(self.settings.templates) == "table" then
			for i,v in pairs(self.settings.templates) do
				known_template_files[v.path]=true
			end
		end
		
		local discovered = {}
		local err = {}
		local function discover(path)
			path = path or ""
			local thispath = templates_prefix .. path
			table.insert(err, "take a look at " .. thispath)
			for entry in lfs.dir(thispath) do
				if entry ~= "." and entry ~= ".." then
					local mode = lfs.attributes(thispath .. entry, "mode")
					if mode =="file" and entry:sub(-#extension) == extension and not known_template_files[path .. entry] then
						table.insert(err, "entry is a file: " .. entry)
						discovered[path .. entry:sub(1,-(#extension+1))]={path=path .. entry}
					elseif mode == "directory" then 
						table.insert(err, "entry is a directory: " .. entry)	
						discover(path .. entry .. slash)
					end
				end
			end
		end
		discover()
		return discovered
	end, 
	
	--- output a template with environment [locals]. 
	-- @param templateName name of the template to be output
	out = function(self, templateName, locals)
		locals = locals or {}
		print(self:pageOut(templateName, locals))
	end,
	
	--- template output workhorse. mostly for internal use only. 
	pageOut = function(self, templateName, locals)
		local sets = self.settings
		local template_settings = self.settings.templates[templateName]
		assert(template_settings, "template '" .. templateName .. "' not found")
		
		locals = locals or {}
		local layout = self.layout or sets.layouts.default
		

		local template_data = template_settings.data
		if template_data then
			table.mergeWith(locals, template_data)
		end
		
		if template_settings.stub or template_settings.standalone or not layout then
			self:include(template_settings, locals)
		else
			locals.child = template_settings --let the parent template know what to include
			
			local templateRefs, layoutRefs
			for i,ref in pairs({"css","js"}) do
				templateRefs = template_settings[ref] or {}
				layoutRefs   = sets.templates[layout][ref] or {}
				locals[ref] = table.merge(templateRefs, layoutRefs)
			end
			
			--TODO: add recursive parent support. this might involve reworking this whole thing.
			
			self:include(sets.templates[layout], locals)
		end
	end,
	
	prepareLocals = function(self, locals)
		locals = locals or {}
		return setmetatable(locals, {__index=insider})
	end
}

do
	-- mmm, cache...
	local memoized_path = setmetatable({}, {__mode='k', __index = function(t,template)
		local absolute_path = webylene.path .. webylene.path_separator .. "templates" .. webylene.path_separator .. template.path
		rawset(t, template, absolute_path)
		return absolute_path
	end})
	local memoized_chunk = setmetatable({}, {__index=function(t,filename)
		local fh = assert(io.open(filename))
		local src = fh:read("*a")
		fh:close()
		-- translates the file into a function
		local prog = lp.compile(src, '@'..filename)
		rawset(t, filename, prog)
		return prog
	end})
	
	template.include = function(self, template, locals)
		setfenv(memoized_chunk[memoized_path[template]], self:prepareLocals(locals))()
	end	
end

--- stuff available from inside a template. 
insider = setmetatable({ 
	myChild = function(locals)
		locals = locals or getfenv(2)
		local child = locals.child
		locals.child = nil
		--any way i can make the following relative?
		webylene.template:include(child, locals)
	end,
	
	pageTitle = function()
		--print(table.show(webylene.router.currentRoute))
		return router:getTitle()
	end,
	
	ref = function()
		return router:getRef()
	end,
	
	url_encode = wsapi.util.url_encode,
	url_decode = wsapi.util.url_decode
	
}, {__index=_G})