local params = request.params
if params.action == "register" then
	res={user:register(params.username, params.password)}
end
if params.action == "log in" then
	res={user:login(params.username, params.password)}
end
if params.action == "log out" then
	res={user:logout()}
end
webylene.template:out("example")