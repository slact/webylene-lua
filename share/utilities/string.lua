local pairs, string = pairs, string
module(...)

local entities={
	['"'] = '&quot;' ,
	["'"] = '&#39;' ,
	['<'] = '&lt;' ,
	['>'] = '&gt;' ,
	['&'] = '&amp;',
}
local unentities = {}
for k,v in pairs(entities) do unentities[v]=k end

string.htmlentities = function(str) --ascii or utf-8 only, it seems...
	return (string.gsub(str or "", '(.)', entities))
end

string.htmlunentities = function(str) --ascii or utf-8 only, it seems...
	return (string.gsub(str or "", '(&[^;];)', unentities))
end


string.charat = function(str, i)
	return str:sub(i,i)
end

string.gchars = function(str)
	local len = #str
	return function(str, i)
		i = (i or 0) + 1
		if i > len then return nil end
		return i, str:charat(i)
	end, str, nil
end
