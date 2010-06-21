 
require "utilities.debug"
require "lfs"

local env_values = {'assert', 'error', 'getfenv','getmetatable', 'ipairs', 
  'load', 'loadstring', 'loadfile', 'next', 'pairs', 'pcall', 'print', 
  'rawequal', 'rawget', 'rawset', 'select', 'setfenv', 'setmetatable', 
  'tonumber', 'tostring', 'type', 
  'coroutine', 'module', 'require', 'string', 'table', 'math', 'io', 'os', 
  'debug'}
  
local small_env = {}
for i, k in pairs(env_values) do
	small_env[k]=rawget(_G, k)
end
 
addons = {
	init = function(self)
		return self:discover(cf('path') .. cf('path_separator') .. 'addons')
	end,

	discover = function(self, addon_path)
		logger:info("looking for addons in " .. addon_path)
		local parent_webylene, _G = webylene, _G
		local abspathf = addon_path .. cf('path_separator') .. "%s"
		for file in lfs.dir(addon_path) do
			local mypath = abspathf:format(file)
			if lfs.attributes(mypath, "mode")=='directory' and file~='.' and file ~='..' then
				
				local addon_webylene
				local miniglobal = setmetatable(table.copy(small_env), {__index = function(t,k) 
					return addon_webylene[k] or _G[k]
				end})
				
				addon_webylene = (require "webylene").new(miniglobal, parent_webylene):set_config('name', "addon " .. file)
				
				miniglobal.webylene, miniglobal.write = addon_webylene, _G.write
				
				local success, err = pcall(addon_webylene.initialize, addon_webylene, {path=mypath, env=cf('env'), path_separator=cf('path_separator')})
				if not success then logger:error(("Failed to initialize addon %s: %s"):format(file, err)) end
				
			end
			
		end
	end

}