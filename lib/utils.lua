---- the following is dirty, and should be split up into libraries or something. --------

 
function math.round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

--- does tbl contain value?
table.contains = function(tbl, value)
	for i,v in pairs(tbl) do
		if v == value then
			return true
		end
	end
	return nil
end

--- does the table contain more than [number] elements?
table.longer_than = function(tbl, number)
	local len = 0
	for i, v in pairs(tbl) do
		if len > number then
			return true
		end
	end
	return false
end

--- reduce table to one value
-- callback(previous_value, current_value, index, table)
table.reduce = function(tbl, callback, initial_value)
	local i, prev
	if not initial_value then
		i, prev = next(tbl)
	else
		i, prev = nil, initial_value
	end
	local cur
	i, cur = next(tbl, i)
	while i do
		prev = callback(prev, cur, i, tbl)
		i, cur = next(tbl, i)
	end
	return prev
end

--- calls callback function once for each element in the table
-- callback(value, index, table)
table.each = function(tbl, callback)
	for i, v in pairs(tbl) do
		callback(v, i, tbl)
	end
	return tbl
end

--- does tbl contain value, and, if so, is i s.t. tbl[i]==value numeric?
table.icontains = function(tbl, value)
	for i,v in ipairs(tbl) do
		if v == value then
			return true
		end
	end
	return nil
end

--- returns the keys present in tbl 
table.keys = function(tbl)
	local t= {}
	for k, v in pairs(tbl) do
		table.insert(t,k)
	end
	return t
end

---return index x s.t. tbl[x]==value, or nil if no such x exists.
table.find = function(tbl, value)
	for i,v in pairs(tbl) do
		if v == value then
			return i
		end
	end
	return nil
end

--- return number of items in table, as traversed with pairs(tbl). note: this is NOT #tbl, which stops at the first numeric index whose value is nil.
--  if tbl is not a table, returns nil
-- O(n)
table.length = function(tbl)
	local size = 0
	if type(tbl) == "table" then
		for i,v in pairs(tbl) do
			size = size + 1
		end
		return size
	else
		return nil
	end
end


--- copy a table. does _not_ copy the metatable, but it does set the copy's metatable to theoriginal's
function table.copy(tbl)
	local c = {}
	for i, v in pairs(tbl) do
		c[i]=v
	end
	return c
end

--- perform function mapper on each element of table tbl. function modifies tbl.
-- mapper function is of the form mapper(key, value, tbl)
-- returns tbl
-- O(n)
function table.map_in_place(tbl, mapper)
	for k,v in pairs(tbl) do
		tbl[k] = mapper(k, v, tbl)
	end
	return tbl
end

--- perform function mapper on each element of table tbl.
-- mapper function is of the form mapper(key, value, tbl)
-- undefined functionality for non-table values of tbl
-- returns new, mapped table
-- O(n)
function table.map(tbl, mapper)
	local nt = {}
	for k,v in pairs(tbl) do
		nt[k] = mapper(k,v, tbl)
	end
	return nt
end

--- return the first element of table tbl, as found with pairs()
-- undefined functionality for non-table values of tbl
-- O(1)
function table.first(tbl)
	local k, v = next(tbl)
	return v
end

--- return the first index of table tbl, as found with pairs()
function table.firstindex(tbl)
	local k, v = next(tbl)
	return k
end

--- reverses numeric index positions
function table.reverse(tbl)
	local len, half_len = #tbl, math.ceil(#tbl/2)
	for i, val in ipairs(tbl) do
		if i > half_len then break end
		tbl[i], tbl[len+1-i] = tbl[len+1-i], tbl[i]
	end
	return tbl
end

--- returns a new table with keys and values flipped
function table.flipped(tbl)
	local flippy = {}
	for i, v in pairs(tbl) do
		flippy[v]=i
	end
	return flippy
end

-- returns a slice of the table with the start and end being the numeric keys start and End. if End is not specified, assumes #tbl
function table.slice(tbl, start, End)
	local ret = {}
	End = End or #tbl
	if not start then return tbl end
	if start < 0 then start = #tbl - start end
	local i, val = start, nil
	while i < End do
		table.insert(ret, tbl[i])
		i, val = next(tbl, i)
	end
	return ret
end

--- are the numerically-indexed contents identical, regardless of key?
-- O(~n)
function table.icontentsidentical(t1, t2)
	for i,v in ipairs(t2) do
		if not t1.icontains(v) then return false end
	end
	for i,v in ipairs(t1) do
		if not t2.icontains(v) then return false end
	end
	return true
end

function table.mergeRecursivelyWith(t1, t2)
	for i,v in pairs(t2 or {}) do
		if type(i) == "number" then
			table.insert(t1, v)
		elseif type(v) == "table" and type(t1[i]) == "table" then
			t1[i] = table.mergeRecursivelyWith(t1[i], v)
		else
			t1[i] = v
		end
	end
	return t1
end

--- merge tables t1 and t2. modifies table t1.
--  returns modified table t1 U t2
function table.mergeWith(t1, t2)
	for i,v in pairs(t2) do
		if type(i) == "number" then
			if not table.icontains(t1, v) then
				table.insert(t1, v)
			end
		else
			t1[i] = v
		end
	end
	return t1
end

--- merge tables t1 and t2
-- returns new table t = t1 U t2
function table.merge(t, u)
  local r = {}
  for i, v in pairs(u) do
    r[i] = v
  end
  for i, v in pairs(t) do
	if type(i) == "number" then
		if not table.icontains(r, v) then
			table.insert(r, v)
		end
	else
		r[i] = v
	end
  end
  return r
end

--- append anumerically-indexed table t1 to t2.
-- modifies t1. t2 overwrites t1 on matching non-numeric keys.
-- @param t1 table to be appended to. will be modified.
-- @param t2 table that we want to append.
-- @return t1
function table.append(t1, t2)
	local t1_length = #t1
	for i, v in pairs(t2) do
		if type(i) == "number" then
			t1[t1_length + i]=v
		else
			t1[i]=v
		end
	end
	return t1
end 

function table.empty(t) 
	return next(t) == nil 
end

---debuggery
function dump(tbl)
	local function tcopy(t) local nt={}; for i,v in pairs(t) do nt[i]=v end; return nt end
	local function printy(thing, prefix, tablestack)
		local t = type(thing)
		if     t == "nil" then return "nil"
		elseif t == "string" then return string.format('%q', thing)
		elseif t == "number" then return tostring(thing)
		elseif t == "table" then
			if tablestack[thing] then return string.format("%s (recursion)", tostring(thing)) end
			local kids, pre, substack = {}, "	" .. prefix, (tablestack and tcopy(tablestack) or {})
			substack[thing]=true	
			for k, v in pairs(thing) do
				table.insert(kids, string.format('%s%s=%s,',pre,printy(k, ''),printy(v, pre, substack)))
			end
			return string.format("%s{\n%s\n%s}", tostring(thing), table.concat(kids, "\n"), prefix)
		else
			return tostring(thing)
		end
	end
	local ret = printy(tbl, "", {})
	return ret
end
table.show = dump

---reversed ipairs
table.irpairs = function(tbl)
	local len = #tbl
	return function(tbl, index)
		index = index or #tbl
		return ((index ~= 1 and tbl[index-1]) and index-1 or nil), tbl[index]
	end
end 

do
	--- wsapi write function
	write = function(...)
		for i, arg in ipairs({...}) do
			webylene.response:write(arg and tostring(arg) or "")
		end
	end
	
	--- print replacement
	print = function(...)
		write(table.concat({...},"\t") .. "\n")
	end
	
	
	---self-explanatory
	set_content_type = function(arg)
		local content = {}
		if type(arg) == "string" then
			local slash = assert(string.find(arg, "/", 0, true), "Invalid content-type, must be something/something-else.")
			content[2]=string.sub(arg, slash+1)
			content[1]=string.sub(arg, 0, slash-1)
		elseif type(arg) == "table" and table.length(arg) == 2 then
			content = arg
		else
			error("unknown content-type format...")
		end
		webylene.response["Content-Type"]=table.concat(content, "/")
	end
end

--- config retrieval function. kinda redundant, but used in other languages' versions of webylene. here for consistency.
function cf(...)
	local config = webylene.config
	for i,v in ipairs({...}) do
		config = config[v]
	end
	return config
end

--- does the table t contain only numeric indices?
function table.isarray(t)
	for i,v in pairs(t) do
		if(type(i) ~= "number") then
			return false
		end
	end
	return true
end


do
	local entities={
		['"'] = '&quot;' ,
		["'"] = '&#39;' ,
		['<'] = '&lt;' ,
		['>'] = '&gt;' ,
		['&'] = '&amp;',
	}
	
	local unentities = table.flipped(entities)

	htmlentities = function(str) --ascii only, it seems...
		return (string.gsub(str or "", '(.)', entities))
	end
	
	htmlunentities = function(str)
		return (string.gsub(str or "", '(&[^;];)', unentities))
	end
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