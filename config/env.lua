-- configure environment stuff here
local env
for i, a in ipairs(_G.arg) do
	if a=="-e" or a=="--env" or a=="--environment" then
		env=_G.arg[i+1]
	end
end
webylene.env = env or "dev"