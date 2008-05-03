<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<% --include all the necessary js
	if type(js)=="table" then 
		for i,script in ipairs(js) do%>
		<script language="javascript" type="text/javascript" src="/js/<%=script%> "></script>
		<%end
	end 
	--include necessary css
	if type(css)=="table" then 
		for i,stylesheet in ipairs(css) do%>
			<link rel="stylesheet" type="text/css" href="/css/<%=stylesheet%>" />
		<%end
	end%>
	<title><%=title()%></title>
</head>
<body>
	<%myChild()%>
</body>
</html>