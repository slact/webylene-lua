--print(table.show(getfenv(1)))

local cur = assert(db:query("select * from foo"))

webylene.template:out("example", {escaped = db:esc("'\"hello;'\n\00\0x00 yeah? okay.... \"\"")})