local math = math
module(...)

--- round a number to a number of decimal places
-- @param num number to be rounded
-- @param idp decimal places to be rounded by. undefined behavior for non-integers.
function math.round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end
