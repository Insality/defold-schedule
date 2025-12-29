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


return M

