LP example
<pre>
session key: <%=session.id%>
session data: <%=table.show(session.data, "data")%>

logged in? <%=user:loggedIn() and "yes" or "no" %>
userdata: <%= table.show(user.data or {}, "user.data") %>

results: <%=table.show(res)%>
</pre>


<form name="login" action="" method="post">
	<input type="text" name="username" />
	<input type="text" name="password" />
	<input type="hidden" name="action" value="log in" />
	<input type="submit" name="login" value="log in" />
</form>

<form name="login" action="" method="post">
	<input type="text" name="username" />
	<input type="text" name="password" />
	<input type="hidden" name="action" value="register" />
	<input type="submit" name="register" value="register!" />
</form>

<form name="logout" action="" method="post">
	<input type="hidden" name="action" value="log out" />
	<input type="submit" name="register" value="log out" />
</form>