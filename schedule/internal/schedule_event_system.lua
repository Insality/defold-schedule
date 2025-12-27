---Simple event system for schedule module
local M = {}


---Create a new event instance
---@return event
function M.create()
	local subscribers = {}
	local subscription_id_counter = 0

	local event_instance = {}

	function event_instance:subscribe(callback, context)
		subscription_id_counter = subscription_id_counter + 1
		local subscription_id = subscription_id_counter
		subscribers[subscription_id] = {
			callback = callback,
			context = context
		}
		return subscription_id
	end


	function event_instance:unsubscribe(subscription_id)
		subscribers[subscription_id] = nil
	end


	function event_instance:trigger(...)
		for _, subscriber in pairs(subscribers) do
			if subscriber.context then
				subscriber.callback(subscriber.context, ...)
			else
				subscriber.callback(...)
			end
		end
	end


	function event_instance:clear()
		subscribers = {}
		subscription_id_counter = 0
	end


	function event_instance:is_empty()
		for _ in pairs(subscribers) do
			return false
		end
		return true
	end

	return event_instance
end


return M

