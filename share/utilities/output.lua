module(..., package.seeall)
--- wsapi write function
local write = function(...)
	for i, arg in ipairs({...}) do
		webylene.response:write(arg and tostring(arg) or "")
	end
end
_G.write = write

--- print replacement. expects all paramenters to already be concatenable as strings
_G.print = function(...)
	write(table.concat({...},"\t") .. "\n")
end 