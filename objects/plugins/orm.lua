---ORM wrapper for tables.
--[[ 
	usage:
	table_orm = orm(model, tbl, row) --or orm.new(model, table, row)
	model is a table {table="tablename", columns={col1="columntype",...}, keys={key1="type", key2="type", ...}} 
	or a table name (string) to fetch model information from via a SHOW TABLE query.
	
	tbl is a the table that the orm will be wrapped around. it should provide table-level functions
	
	row is a row-level table of functions and whatnot
	
	This plugin registers objects/models as an expected directory for ORM models.
]]

--- EVENTS:
--[[
	<databaseTransaction source="db">
		start: ONLY ONCE: load up models with SHOW TABLE queries.
		
	</initialize>
]]

local db, query = db, query --locals do it faster.
local tinsert, format = table.insert, string.format
-- for the equality operator
local models = setmetatable({}, {__mode="k", __index=function() error("model not initialized yet") end})

--- private usage. returns sanitized, valid SQL assignment strings for columns present in given table
-- @param column_list optionally, use only the columns found in columns_list
local valid_columns_table = function(self, model,  column_list)
	if not model.columns then return nil, "no column list for table <" .. (model.table or "UNKNOWN") .. ">" end
	local SET = {}
	local existing_columns = model.columns
	for i, name in ipairs(column_list or table.keys(self)) do
		if existing_columns[name] then
			local val = rawget(self, name)
			tinsert(SET, format("`%s`=%s", name, (val and ("'"..db:esc(val).."'") or "NULL")))
		end
	end
	return SET
end

local generate_select = function(self, select, where_arg, having_arg, limit)
	local arg, where, model, db = where_arg or {}, {}, models[self], conn or db
	if not model.table then return nil, "table model unavailable" end
	for k,v in pairs(arg) do
		if v then --everything but nil and false
			tinsert(where, format("`%s` = '%s'",db:esc(k), db:esc(v)))
		else --if v == false
			tinsert(where, format("ISNULL(`%s`)", db:esc(k)))
		end
	end
	return format("SELECT %s FROM `%s` %s %s;", select, model.table, (#where > 0 and " WHERE " .. table.concat(where, " AND ") or ""), limit and (" LIMIT " .. tostring(limit)) or "")
end

local table_meta = {
	__metatable=true, --lock the sonovabitch
	__index = {
		--- builds WHERE query part based on arg. arg[v]=false => ISNULL(v), otherwise `v`=arg[v]
		search = function(self, arg, conn, limit)
			--build WHERE clause
			local res = {}
			if not db.query then error(table.show(db)) end
			local cursor = assert(db:query(generate_select(self, '*', arg, nil, limit)))
			for row in db:rows(cursor) do
				tinsert(res, self:new(row, conn))
			end
			cursor:close()
			return res
		end,

		count = function(self, arg, conn)
			local db = conn or db
			local cursor = assert(db:query(generate_select(self, 'count(*) as count', arg)))
			return assert(db:firstRow(cursor)).count
		end,
		
		--- given a column/value key table, find exactly one row corresponding to the key
		find = function(self, arg, conn)
			if type(arg) ~= "table" then
				local key = models[self].key
				local thekey, _ = next(key)
				if not next(key, thekey) then 
					arg = {[thekey]=arg}
				else
					error("key requires multiple columns, but only one given. The key column cannot be inferred.")
				end
			end
			
			local res, err = self:search(arg, conn, 1)
			if res then
				local _, found = next(res)
				return found
			else
				return res, err
			end
		end,
		
		--- return a number of ORM-wrapped rows resulting from performing a given query, as specified by the query 'query'
		from_query = function(self, query, conn)
			local db, res, tinsert = conn or db, {}, table.insert
			local cursor, err = db:query(query)
			if cursor then
				for row in db:rows(cursor) do
					tinsert(res, self:new(row, conn))
				end
			else
				return nil, err
			end
			cursor:close()
			return res
		end,
		
		--- return a number of ORM-wrapped rows resulting from performing a given query, as specified by the query object q
		from_query_object = function(self, q, conn)
			local db, model = conn or db, models[self]
			if not model.table or not model.columns then return nil, "model for this table is unavailable" end
			if q and type(q)~='table' then return nil, string.format("expected a query object, got some funky %s instead", type(q)) end
			q = q or {} --in case a nil was given. we accept that.
			local query_string, err = query:new():merge({
				select = table.keys(model.columns),
				from = {model.table}
			}):merge(q):generate()
			if not query_string then return nil, err end
			return self:from_query(query_string, db)
		end,
		
		get_model = function(self)
			return models[self]
		end
	}
}


--- MySQL-specific auto-table initializer
local function from_database_table (table_name)
	local safe_name = db:esc(table_name)
	local cursor = assert(db:query("SHOW COLUMNS FROM `" .. safe_name .. "`;"), "No table `" .. safe_name .. "` exists.") --the mysql version
	local key, columns = {}, {}
	for column in db:rows(cursor) do
		if column.Key == "PRI" then
			key[column.Field]=column.Type
		end
		columns[column.Field]=column.Type
	end
	return {table=safe_name, columns=columns, key=key}
end

local certainly_containing_the_key_WHERE = function(self, model)
	if not model.key or not model.table then return nil, "table model unavailable" end
	local keys = {}
	for key, valtype in pairs(model.key) do
		local val = rawget(self, key)
		if val then
			tinsert(keys, "`" .. key .. "` = '" .. db:esc(rawget(self, key)) .. "'")
		elseif val == false then  
			tinsert(keys, "ISNULL(`" .. key .. "`)")
		else
			return nil, "missing key '" .. key .."' for table '" .. (model.table or "UNKNOWN") .. "'"
		end
	end 
	return keys
end

local function initialize_rows(tbl, row)
	
	local connections = setmetatable({}, {__mode='k'})
	local model, model_key, model_table
	local update_q, insert_q, delete_q
	
	local row_meta = {
		__index={
			---use a specific database connection instead of the global one for all subsequent queries for this row
			--@param conn database connection to use. if nil, connection used is unchanged.
			use_conn = function(self, conn)
				if conn then connections[self]=conn end
				return self
			end,

			--update one table row by key
			--last argument may be a database connection
			update = function(self, ...)
				local arg, db = {...}, connections[self] or db
				if type(arg[#arg])~='string' then --last argument is a database connection
					table.remove(arg, #arg)
				end
				local keys = assert(certainly_containing_the_key_WHERE(self, model))
				local set = table.concat(valid_columns_table(self, model,  #arg~=0 and arg or nil), ", ")
				if set == "" then return nil, "nothing to update" end
				local res, err = assert(db:query(update_q:format(set, table.concat(keys, " AND "))))
				if res then --success
					return self
				else --failure
					return res, err
				end
			end,
			
			---repetitive because vararg isn't a first-class element
			get_update_string = function(self, ...)
				local keys = assert(certainly_containing_the_key_WHERE(self, model))
				local set = table.concat(valid_columns_table(self, model, arg.n~=0 and arg or nil), ", ")
				if set == "" then return nil, "nothing to update" end
				return update_q:format(set, table.concat(keys, " AND "))
			end,
			
			get_table = function()
				return tbl
			end,
			
			--- get it?
			get = function(self, name)
				return rawget(self, name)
			end,
			
			--- set it.
			set = function(self, name, value)
				rawset(self, name, value)
				return self
			end,
			
			--- insert a new row. update last inserted id, if possible
			--accepts optional database connection
			-- @ return self on success; nil, err otherwise
			insert = function(self, upsert)
				local db = self.__db or db
				
				local cols = table.concat(valid_columns_table(self, model), ', ')
				upsert = upsert and (" ON DUPLICATE KEY UPDATE " .. cols) or ""
				local res, err = db:query(insert_q:format((#cols>0 and (" SET " .. cols) or " () VALUES()"), upsert))
				if res then --success
					local k, _ = next(model_key)
					if k and not next(model_key, k) and not self[k] then -- if there's just one key column, and it's nil
						local cursor = assert(db:query("SELECT LAST_INSERT_ID() as id")) --MySQL-speak.
						if cursor then  -- and the last id makes sense,
							rawset(self, k, cursor:fetch({},'a').id)
							cursor:close()
						end
					end
					return self
				else --failure
					return res, err
				end
			end,
			
			--- delete row
			delete = function(self)
				local db = self.__db or db
				local res, err = db:query(delete_q:format(table.concat(assert(certainly_containing_the_key_WHERE(self, model)), " AND ")))
				if res then --success
					--res:close()
					for col, typ in pairs(model.columns) do
						rawset(self, col, nil)
					end
				else
					return res, err
				end
				return self
			end
		},
		__meta = true, 
		__eq = function(a, b) 
			for i, table_row in pairs({a,b}) do --yeah, okay, so there'll be an overlap. feh, i say!
				for key, ktype in pairs(model_key) do
					if a[key] ~= b[key] then
						return false
					end
				end
			end
			return true
		end

	}
	
	--now the custom row stuff. a bit dangerous, as it can overwrite row:insert, row:delete and so on
	--however, as DOOP president Glab says, "I'm going to allow this."
	for i, v in pairs(row) do
		row_meta.__index[i]=v
	end
	
	tbl.row=row_meta.__index -- let's have a reference to row in case you guys want to add or remove functions to rows later
	tbl.new = function(self, arg, conn) 
	--this is directly in the table instead of the metatable mostly because it is
	--easier to write in closures, and because it's faster and this method will be called very frequently
		local newrow = arg or {}
		assert(type(newrow) == "table", "Expected a table, got a " .. type(arg) ..".")
		setmetatable(newrow, row_meta)
		if conn then connections[newrow]=conn end
		return newrow
	end
	
	return function(newmodel) --delayed initialization
		model = newmodel
		update_q = ("UPDATE `%s` SET %%s WHERE %%s ;"):format(model.table)
		insert_q = ("INSERT INTO `%s` %%s %%s;"):format(model.table)
		delete_q = ("DELETE FROM `%s` WHERE %%s;"):format(model.table)
		model_table, model_key = model.table, model.key
		
	end
end

---------------------------
local new = function(...)
	local arg = {...}
	assert(#arg > 0, "more than zero arguments, please (got " .. #arg .. ")")
	local model, tbl, row
	
	--parse the arguments, extract the model
	if #arg==1 and type(arg[1])=="table" then
		assert(arg[1].model, "invalid shorthand ORM initialization parameter")
		model, tbl, row=arg[1].model, arg[1].table or {}, arg[1].row or {}
	else
		model, tbl, row = arg[1], arg[2] or {}, arg[3] or {}
	end
	local initrow = initialize_rows(tbl, row)
	if type(model)=="table" then --it was already give to us
		assert(type(model.table)=="string" and type(model.columns)=="table" and type(model.key)=="table", "invalid model given")
		models[tbl]=model
		initrow(model)
	elseif type(model)=="string" then --we need to figure out the model from a table in the database by making a few educated queries
		--Because it is not guaranteed that a database connection is available at this time,
		--we will set the model on the first databaseTransaction available.
		local function modelit(do_not_remove)
			local m = from_database_table(model)
			models[tbl]=m
			initrow(m)
			if not do_not_remove then
				event:removeListener("databaseTransaction", modelit)
			end
		end
		if event:active("databaseTransaction") then
			modelit(true)
		else
			event:addListener("databaseTransaction", modelit)
			event:addStartListener("databaseTransaction", modelit)
		end
	else
		error("unexpected model type " .. type(model))
	end
	setmetatable(tbl, table_meta)
	return tbl
end

orm = setmetatable({
	new=new, 
	model=function(t)
		return rawget(models, t)
	end,
	init=function(self)
		webylene:add_object_import_path("objects" .. cf('path_separator') .. "models")
	end
}, { __call = function(tbl, ...) return new(...) end })
