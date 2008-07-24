--- the eventer

do
	--- event listener container
	local listeners = setmetatable({},{ 
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
	local activeEvents = {}
	local finishedEvents = {}
	
	--- the event thinger
	event = {
		--- is eventName active?
		active = function(self, eventName)
			return table.contains(activeEvents, eventName)
		end,
			
		--- is eventName finished?
		finished = function(self, eventName)
			return table.contains(finishedEvents, eventName)
		end,
		
		--- fire event [event]
		-- @param event event name
		fire = function(self, event)
			self:start(event)
			self:finish(event)
			return self
		end,
		
		--- start event [event]
		-- fires start and during [event] listeners
		start = function(self, event)
			--activeEvents println
			--cgi write("starting #{event}\n" interpolate)
			if self:active(event) then
				error("tried starting event <" .. event .. "> but it's already started.")
			end
			table.insert(activeEvents, event)
			for i, event_handler in pairs(listeners[event].start) do --yep.
				event_handler()
			end
			for i, event_handler in pairs(listeners[event].during) do 
				event_handler()
			end
			return self
		end,
		
		--- finish event [event]
		-- fires finish and after [event] listeners
		finish = function(self, event)
			if not self:active(event) then
				error("tried finishing event <" .. event .. "> but it's not active and hadn't been started.")
			end
			table.remove(activeEvents, table.find(activeEvents, event))
			table.insert(finishedEvents, event)
			for i, event_handler in pairs(listeners[event].finish) do --yep.
				event_handler()
			end
			for i, event_handler in pairs(listeners[event].after) do 
				event_handler()
			end
			return self
		end,
		
		
		--- add a during [eventName] listener
		addListener = function(self, eventName, listener)
			--adding  eventName
			table.insert(listeners[eventName].during, listener) --add the event!
			if self:active(eventName) then
				listener()
			end
			return self
		end,
		
		addStartListener = function(self, eventName, listener)
			table.insert(listeners[eventName].start, listener) --add the event!
			return self
		end,
			
		addFinishListener = function(self, eventName, listener)
			table.insert(listeners[eventName].finish, listener) --add the event!
			return self
		end,
		
		addAfterListener = function(self, eventName, listener)
			table.insert(listeners[eventName].after, listener) --add the event!
			if self:finished(eventName) then
				listener()
			end
			return self
		end
	}	
end 