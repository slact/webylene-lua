response.status = "500 Internal Server Error"

if string.lower(response['content-type'] or "") == 'text/plain' then
	print("An error occurred while processing this request")
	print(request.params.error or "")
	print(request.params.trace or "")
else
	template:out("500", {error = request.params.error, trace = request.params.trace})
end
