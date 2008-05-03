--- the eventer

event = {
	activeEvents = {},
	
	active = function(self, eventName)
		return table.contains(self.activeEvents, eventName)
	end,
	
	finishedEvents = {},
	
	finished = function(self, eventName)
		return table.contains(self.finishedEvents, eventName)
	end,
	
	fire = function(self, event)
		self:start(event)
		self:finish(event)
		return self
	end,
	
	start = function(self, event)
		--activeEvents println
		--cgi write("starting #{event}\n" interpolate)
		if self:active(event) then
			error("tried starting event <" .. event .. "> but it's already started.")
		end
		table.insert(self.activeEvents, event)
		for i, event_handler in pairs(self.handlers[event].start) do --yep.
			event_handler()
		end
		for i, event_handler in pairs(self.handlers[event].during) do 
			event_handler()
		end
		return self
	end,
	
	
	finish = function(self, event)
		if not self:active(event) then
			error("tried finishing event <" .. event .. "> but it's not active and hadn't been started.")
		end
		table.remove(self.activeEvents, table.locate(self.activeEvents, event))
		table.insert(self.finishedEvents, event)
		for i, event_handler in pairs(self.handlers[event].finish) do --yep.
			event_handler()
		end
		for i, event_handler in pairs(self.handlers[event].after) do 
			event_handler()
		end
		return self
	end,
	
	addListener = function(self, eventName, listener)
		--adding  eventName
		table.insert(self.handlers[eventName].during, listener) --add the event!
		if self:active(eventName) then
			listener()
		end
		return self
	end,
	
	addStartListener = function(self, eventName, listener)
		table.insert(self.handlers[eventName].start, listener) --add the event!
		return self
	end,
		
	addFinishListener = function(self, eventName, listener)
		table.insert(self.handlers[eventName].finish, listener) --add the event!
		return self
	end,
	
	addAfterListener = function(self, eventName, listener)
		table.insert(self.handlers[eventName].after, listener) --add the event!
		if self:finished(eventName) then
			listener()
		end
		return self
	end,
	
	handlers = setmetatable({},{ 
		__index = function(tbl, eventName)
		-- creates a new event handler table
			tbl[eventName]= {
				start  = {},
				during = {},
				finish = {},
				after  = {}
			}
			return tbl[eventName]
		end
	})
}	