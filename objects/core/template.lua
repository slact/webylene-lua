require "lp"
require "wsapi.util"

local output_function_name = "write"

local webylene, event, cf= webylene, webylene.event, cf
local discover_templates, stuff_available_to_a_template, page_out --this smells of header files...

--and finally the main course
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
			
			local should_discover_templates=true
			local discovered = {}
			if should_discover_templates then
				table.mergeWith(self.settings.templates, discover_templates(self))
			end
			
			lp.setoutfunc(output_function_name)
		end)
	end,
	
	--- output a template with environment [locals]. 
	-- this function produces actual output, and does not return a resulting string
	-- @param templateName name of the template to be output
	out = function(self, templateName, locals)
		locals = locals or {}
		print(page_out(self, templateName, locals))
	end,
	
	
	--- return the string for template with environment [locals]. 
	-- @return string with the result of including the template.
	get = function(self, templateName, locals)
		locals = locals or {}
		local buffer = {}
		local outfunc = function(arg)
			table.insert(buffer, arg)
		end
		page_out(self, templateName, locals, outfunc)
		return table.concat(buffer)
	end
}



--recursive traversal of templates/ for, um, discovering templates... so that they needn't be put into the templates config if they're simple.
discover_templates = function(self, extension)
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
	--local err = {} --debugstuff
	local function discover(path)
		path = path or ""
		local thispath = templates_prefix .. path
		--table.insert(err, "take a look at " .. thispath)
		for entry in lfs.dir(thispath) do
			if entry ~= "." and entry ~= ".." then
				local mode = lfs.attributes(thispath .. entry, "mode")
				if mode =="file" and entry:sub(-#extension) == extension and not known_template_files[path .. entry] then
					--table.insert(err, "entry is a file: " .. entry)
					discovered[path .. entry:sub(1,-(#extension+1))]={path=path .. entry}
				elseif mode == "directory" then 
					--table.insert(err, "entry is a directory: " .. entry)	
					discover(path .. entry .. slash)
				end
			end
		end
	end
	discover()
	return discovered
end

local prepare_locals = function(self, locals)
	locals = locals or {}
	return setmetatable(locals, {__index=stuff_available_to_a_template})
end

local include do
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
	
	include = function(self, template, locals, returnful)
		local success, err = pcall(setfenv(memoized_chunk[memoized_path[template]], prepare_locals(self, locals)))
		if not success then 
			if webylene.config.show_errors==true then print(err) end -- make this check less dynamic later
			logger:error(err)
		end
	end	
end

--- stuff available from inside a template. 
stuff_available_to_a_template = setmetatable({ 
	myChild = function(locals)
		locals = locals or getfenv(2)
		local child = locals.child
		locals.child = nil
		--any way i can make the following relative?
		include(self, child, locals)
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
	
--- template output workhorse.
page_out = function(self, templateName, locals, outputfunction)
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
		return include(self, template_settings, locals)
	else
		locals.child = template_settings --let the parent template know what to include
		
		local templateRefs, layoutRefs
		for i,ref in pairs({"css","js"}) do
			templateRefs = template_settings[ref] or {}
			layoutRefs   = sets.templates[layout][ref] or {}
			locals[ref] = table.merge(type(templateRefs)=='table' and templateRefs or {templateRefs}, type(layoutRefs)=='table' and layoutRefs or {layoutRefs})
		end
		locals[output_function_name]=outputfunction or locals[output_function_name]  --in case we want a custom output function. granted, this might clash with the provided locals, but we shall hope that it does not.		

		--TODO: add recursive parent support. this might involve reworking this whole thing.
		return include(self, sets.templates[layout], locals)
	end
end