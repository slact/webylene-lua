 
 
 addons = {
	init = function(self)
		return self:discover('addons')
	end,
	
	discover = function(self, path)
		for file in lfs.dir(path) do
			if lfs.attributes(file).mode='directory' then
				--LOAD ADDON
			end
		end
	end
	
 }