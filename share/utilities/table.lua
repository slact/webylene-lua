local setmetatable, getmetatable, type, pairs, ipairs, table, next, math = setmetatable, getmetatable, type, pairs, ipairs, table, next, math
module(...)

--- does the table t contain only numeric indices?
function table.isarray(t)
	for i,v in pairs(t) do
		if(type(i) ~= "number") then
			return false
		end
	end
	return true
end

---reversed ipairs
function table.irpairs(tbl)
	local len = #tbl
	return function(tbl, index)
		index = index or #tbl
		return ((index ~= 1 and tbl[index-1]) and index-1 or nil), tbl[index]
	end
end 

table.show = dump

--- does the table contain 0 elements?
function table.empty(t) 
	return next(t) == nil 
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

--- merge tables t1 and t2. modifies table t1. numericcally-indexed values are always appended, non-numeric ones are replaced on collision.
-- @return new table t = t1 U t2 (union)
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

--- merge tables t1 and t2. modifies table t1. numericcally-indexed values are always appended, non-numeric ones are replaced on collision.
--  @return modified table t1 = t1 U t2 (union)
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

--- merge tables t1 and t2 recursively. modifies table t1. numericcally-indexed values are always appended, non-numeric ones are replaced on collision.
--  @return modified table t1 = t1 U t2 (union)
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

--- returns a slice of the table with the start and end being the numeric keys start and End. if End is not specified, assumes #tbl
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

--- returns a new table with keys and values flipped
function table.flipped(tbl)
	local flippy = {}
	for i, v in pairs(tbl) do
		flippy[v]=i
	end
	return flippy
end

--- reverses numeric index positions
-- @return modified tbl with numeric indices reversed.
function table.reverse(tbl)
	local len, half_len = #tbl, math.ceil(#tbl/2)
	for i, val in ipairs(tbl) do
		if i > half_len then break end
		tbl[i], tbl[len+1-i] = tbl[len+1-i], tbl[i]
	end
	return tbl
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

--- perform function mapper on each element of table tbl.
-- O(n)
-- @param tbl table to be mapped. undefined functionality for non-table values of tbl
-- @param mapper function is of the form mapper(key, value, tbl)
-- @return new, mapped table
function table.map(tbl, mapper)
	local nt = {}
	for k,v in pairs(tbl) do
		nt[k] = mapper(k,v, tbl)
	end
	return nt
end



--- perform function mapper on each element of table tbl. function modifies tbl. 
-- O(n)
-- @param tbl table to be mapped. undefined functionality for non-table values of tbl
-- @param mapper function is of the form mapper(key, value, tbl)
-- @return new, mapped table
function table.map_in_place(tbl, mapper)
	for k,v in pairs(tbl) do
		tbl[k] = mapper(k, v, tbl)
	end
	return tbl
end

--- copy a table.
-- @param
function table.copy(tbl, setmeta)
	local c = {}
	for i, v in pairs(tbl) do
		c[i]=v
	end
	if setmeta then setmetatable(c, getmetatable(tbl)) end
	return c
end

--- return number of items in table, as traversed with pairs(tbl). 
-- note: this is NOT #tbl, which stops at the first numerically-indexed nil.
-- O(n)
-- @param tbl table to be sided up. if tbl is not a table, return nil
function table.length(tbl)
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

--- calls callback function once for each element in the table
-- @param callback function callback(value, index, table)
function table.each(tbl, callback)
	for i, v in pairs(tbl) do
		callback(v, i, tbl)
	end
	return tbl
end

--- does tbl contain value, and, if so, is i s.t. tbl[i]==value numeric?
function table.icontains(tbl, value)
	for i,v in ipairs(tbl) do
		if v == value then
			return true
		end
	end
	return nil
end

--- returns the keys present in tbl 
function table.keys(tbl)
	local t= {}
	for k, v in pairs(tbl) do
		table.insert(t,k)
	end
	return t
end

---return index x s.t. tbl[x]==value, or nil if no such x exists.
function table.find(tbl, value)
	for i,v in pairs(tbl) do
		if v == value then
			return i
		end
	end
	return nil
end

--- reduce table to one value
-- @param tbl table in question
-- @param callback function callback(previous_value, current_value, index, table)
-- @param initial_value initial callback value. optional, obviously
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


