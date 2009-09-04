--- the eventer

-- this sucker kepps track of events n' stuff. sort of the central orchestrator for webylene internals.

--[[
 As you might be able to tell already, events in webylene are _not_ bound to 
 partucular objects (like, say, with JS). Instead, all events share the same 
 global namespace. This makes coding, debugging and documenting much simpler.
 Unfortunately, this means that every plugin must fire publish uniquely-named
 events, which doesn't work drastically well when considering any decentralized
 plugin ecosystem. Considerations and solutions to this problem are welcome.
]]

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
	
		init = function(self)
			self:addFinishListener("shutdown", function()
				self:reset()
			end)
		end,
	
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
		-- @param when string: "start", "during", "finish". at what point in the event should this listener be executed?
		addListener = function(self, eventName, listener, when)
			--adding  eventName
			when = when and string.lower(tostring(when)) or "during"
			if when ~= "start" and when ~= "during" and when ~= "finish" then
				error("unknown event timing: " .. when .. ". must be 'start', 'during', or 'finish'... or nil")
			end
			table.insert(listeners[eventName][when], listener) --add the event!
			if when=="during" and self:active(eventName) then
				listener()
			end
			return self
		end,
		
		removeListener = function(self, eventName, listener)
			local found = false
			for when, listeners in pairs(listeners[eventName]) do
				for i, lis in ipairs(listeners) do
					if lis==listener then
						found = true
						table.remove(listeners,i)
					end
				end
			end
			if found then return self end
			return nil, "listener not found"
		end,
		
		addStartListener = function(self, eventName, listener)
			return self:addListener(eventName, listener, "start")
		end,
			
		addFinishListener = function(self, eventName, listener)
			return self:addListener(eventName, listener, "finish")
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