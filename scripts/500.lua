response.status = "500 Internal Server Error"
template:out("500", {error = request.params.error, trace = request.params.trace})