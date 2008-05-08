
if cgilua.REQUEST.action == "register" then
	res={user:register(cgilua.REQUEST.username, cgilua.REQUEST.password)}
end
if cgilua.REQUEST.action == "log in" then
	res={user:login(cgilua.REQUEST.username, cgilua.REQUEST.password)}
end
if cgilua.REQUEST.action == "log out" then
	res={user:logout()}
end

webylene.template:out("example")