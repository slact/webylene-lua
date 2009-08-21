response.status = "500 Internal Server Error"

if string.lower(response['content-type'] or "") == 'text/plain' then
	print("An error occurred while processing this request")
	print(request.params.error or "")
	print(request.params.trace or "")
else
	template:out("500", {error = webylene.config.show_errors and request.params.error, trace = webylene.config.show_backtrace and request.params.trace})
end
