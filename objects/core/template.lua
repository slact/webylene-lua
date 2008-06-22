require "cgilua.lp"
template = {
	init = function(self)
		event:addAfterListener("loadConfig", function()

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
			
			cgilua.lp.setoutfunc("write")
		end)
	end, 
	
	layout = false,
	
	discover_templates = function(self)
		local absolutePath = webylene.path .. "/templates"
		local extension = ".lp"
		local known_template_files = {}
		if type(self.settings.templates) == "table" then
			for i,v in pairs(self.settings.templates) do
				known_template_files[v.path]=true
			end
		end
		
		local discovered = {}
		for file in lfs.dir(absolutePath) do
			if file ~= "." and file ~= ".."  and lfs.attributes(absolutePath .. "/" .. file, "mode")=="file" and file:sub(-#extension) == extension and not known_template_files[file] then
				discovered[file:sub(1,-(#extension+1))]={path=file}
			end
		end
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
		assert(self.settings.templates[templateName], "no such template <" .. templateName .. ">")
		
		locals = locals or {}
		
		local layout = self.layout or self.settings.layouts.default
		

		local template_data = self.settings.templates[templateName].data
		if template_data then
			table.mergeWith(locals, templateData)
		end
		
		if self.settings.templates[templateName].stub or self.settings.templates[templateName].standalone or not layout then
			self:include(settings.templates[templateName], locals)
		else
			locals.child = self.settings.templates[templateName] --let the layout know what to include
			
			local templateRefs, layoutRefs
			for i,ref in pairs({"css","js"}) do
				templateRefs = self.settings.templates[templateName][ref] or {}
				layoutRefs   = self.settings.templates[layout][ref] or {}
				locals[ref] = table.merge(templateRefs, layoutRefs)
			end
			
			--TODO: add recursive parent support. this might involve reworking this whole thing.
			
			self:include(self.settings.templates[layout], locals)
		end
	end,
	
	include = function(self, template, locals)
		--print(cgilua.lp.translate(io.open(webylene.path .. "/templates/" .. template.path, "r"):read("*all")))
		cgilua.lp.include(webylene.path .. "/templates/" .. template.path, self:prepareLocals(locals))
	end,
	
	prepareLocals = function(self, locals)
		locals = locals or {}
		return setmetatable(locals, {__index=self.insider})
	end,
		
	
	--- stuff available from inside a template. 
	insider = setmetatable({ 
		myChild = function(locals)
			locals = locals or getfenv(2)
			local child = locals.child
			locals.child = nil
			--any way i can make the following relative?
			webylene.template:include(child, locals)
		end,
		
		title = function()
			return webylene.router.currentRoute.param.title
		end,
		
		ref = function()
			return webylene.router.currentRoute.param.ref
		end
		
	}, {__index=_G})
	

}
	