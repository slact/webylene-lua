--- the eventer

do
	--- event listener container
	local listeners = setmetatable({},{ 
		__index = function(tbl, eventName)
		-- creates a new event handler table
			tbl[eventName]= {
				start  = {},
				during = {},
				finish = {}
			}
			return tbl[eventName]
		end
	})
	local activeEvents = {}
	
	--- the event thinger
	event = {
		--- is eventName active?
		active = function(self, eventName)
			return activeEvents[eventName]
		end,
			
		--- fire event [event]
		-- @param event event name
		-- @return self
		fire = function(self, event)
			self:start(event)
			self:finish(event)
			return self
		end,
		
		--- start event [event]
		-- fires start and during [event] listeners
		-- @param event event name
		-- @return self
		start = function(self, event)
			if self:active(event) then --aw, crap
				local actives = {}
				for ev, _ in pairs(activeEvents) do
					table.insert(actives, ("%q"):format(ev))
				end
				error('tried starting event "' .. event .. '" but it\'s already started. active events: {' ..
					table.concat(actives, ", ")
					.. "}"
				)
			end
			activeEvents[event]=true
			for i, listener_table in ipairs({listeners[event].start, listeners[event].during}) do
				for i, event_handler in pairs(listener_table) do --yep.
					event_handler()
				end
			end
			return self
		end,
		
		--- finish event [event]
		-- fires finish and after [event] listeners
		finish = function(self, event)
			if not self:active(event) then
				error("tried finishing event '" .. event .. "' but it's not active and hadn't been started.")
			end
			for i, event_handler in pairs(listeners[event].finish) do --yep.
				event_handler()
			end
			activeEvents[event]=nil
			return self
		end,
		
		
		--- add a during [eventName] listener
		-- @param listener listener function
		addListener = function(self, eventName, listener)
			--adding  eventName
			if self:active("request") then
				error("shit.")
			end
			table.insert(listeners[eventName].during, listener) --add the event!
			if self:active(eventName) then
				listener()
			end
			return self
		end,
		
		addStartListener = function(self, eventName, listener)
			if self:active("request") then
				error("shit.")
			end
			table.insert(listeners[eventName].start, listener) --add the event!
			return self
		end,
			
		addFinishListener = function(self, eventName, listener)
			if self:active("request") then
				error("shit.")
			end
			table.insert(listeners[eventName].finish, listener) --add the event!
			return self
		end,
		
		reset = function(self)
			activeEvents = {}
			for i, v in pairs(listeners) do
				rawset(listeners, i, nil)
			end
			return self
		end
	}	
end 