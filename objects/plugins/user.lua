require "sha1"

--- basic user management object. 
-- events:
--  - login: 			after a login succeeded
--  - login failed: 	after a login failed
--  - logout:			just before logging out
user = {
	init = function(self)
		event:addAfterListener("configLoaded", function()
			self.config = cf("user")
		end)
		
		event:addAfterListener("readSession", function()
			self.data = session.data.user
		end)
	end,
	
	login = function(self, username, plaintext_password, hashed_password)
		local user = self:find(username)
		if user and (self:hash(plaintext_password) == user[self.config.password_column] or hashed_password == user[self.config.password_column]) then
			--log in!
			session.data.user = user
			self.data = session.data.user
			event:fire("login")
		else
			event:fire("login failed")
			return nil, "Wrong username or password."
		end
		return user
	end,
	
	register = function(self, username, plaintext_password, ...)
		local hashed_password = self:hash(plaintext_password)
		if not (self:find(username)) then
			--TODO: add the trailing args. 
			webylene.db:query(string.format("INSERT INTO `%s` SET `%s`='%s', `%s`='%s';", self.config.table, self.config.username_column, db:esc(username), self.config.password_column, db:esc(hashed_password)))
			return self
		end
		return nil, "username already exists"
	end, 
	
	loggedIn = function(self)
		return self.data
	end,
	
	logout = function(self)
		if not self.data then
			return nil, "No one to log out."
		end
		event:fire("logout")
		session.data.user = nil
		self.data = nil
		return self
	end,
	
	find = function(self, username)
		local db = webylene.db
		local cur = db:query(string.format("SELECT * FROM %s WHERE `%s` = '%s'", self.config.table, self.config.username_column, db:esc(username)))
		local user = cur and cur:fetch({},'a')
		cur:close()
		if user then
			return user
		end
		return nil, "User <" .. username .. "> not found."
	end,
	
	hash = function(self, plaintext)
		return sha1.digest(plaintext .. (self.config.password_salt or ""))
	end
}

user.exists = user.find