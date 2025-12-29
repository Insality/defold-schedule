---Event chaining logic
local state = require("schedule.internal.schedule_state")

local M = {}


---Check if event can start based on chaining
---@param after_event_id string Event ID to chain after
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time to check if parent just completed
---@return boolean can_start
---@return number|nil start_time Calculated start time if can start
function M.can_start_chain(after_event_id, event_state, current_time, last_update_time)
	if not after_event_id or type(after_event_id) ~= "string" then
		return true, nil
	end
	local after_status = state.get_event_state(after_event_id)

	if not after_status then
		return false, nil
	end

	if after_status.status ~= "completed" then
		return false, nil
	end

	local wait_online = event_state.after_options and event_state.after_options.wait_online
	if wait_online == true then
		if after_status.end_time and current_time < after_status.end_time then
			return false, nil
		end
		if after_status.end_time and (not last_update_time or last_update_time < after_status.end_time) then
			return true, after_status.end_time or current_time
		end
		return false, nil
	else
		return true, after_status.end_time or current_time
	end
end


---Calculate start time from after value
---@param after number|string
---@param current_time number
---@return number|nil start_time
function M.calculate_after_time(after, current_time)
	if type(after) == "number" then
		return current_time + after
	elseif type(after) == "string" then
		local after_status = state.get_event_state(after)
		if after_status and after_status.status == "completed" and after_status.end_time then
			return after_status.end_time
		end
		return nil
	end
	return nil
end


---Update chained events - processes events that chain after other events
---Updates start_time for chained events when their parent events complete
---@param all_events table<string, schedule.event.state> All events to check
---@param current_time number Current time
---@param last_update_time number|nil Last update time
---@param is_startable_status fun(status: string): boolean Function to check if status allows starting
---@param update_event fun(event_id: string, current_time: number, last_update_time: number|nil): boolean Function to update an event
---@return boolean any_updated True if any events were updated
function M.update_chained_events(all_events, current_time, last_update_time, is_startable_status, update_event)
	local any_updated = false
	local continue_chain = true

	while continue_chain do
		continue_chain = false
		for event_id, event_state in pairs(all_events) do
			if type(event_state.after) == "string" then
				local after_event_id = event_state.after
				assert(type(after_event_id) == "string", "after_event_id must be string")
				local after_status = state.get_event_state(after_event_id)
				if after_status and after_status.status == "completed" and after_status.end_time then
					local current_event_state = state.get_event_state(event_id)
					if current_event_state and (is_startable_status(current_event_state.status) or current_event_state.status == "paused") then
						if not current_event_state.start_time or current_event_state.start_time < after_status.end_time then
							current_event_state.start_time = after_status.end_time
							local updated = update_event(event_id, current_time, last_update_time)
							if updated then
								any_updated = true
								continue_chain = true
							end
						end
					end
				end
			end
		end
	end

	return any_updated
end


return M

