---Event chaining logic
local config = require("schedule.internal.schedule_config")
local state = require("schedule.internal.schedule_state")
local time_utils = require("schedule.internal.schedule_time")


local M = {}


---Check if event can start based on chaining
---@param after_event_id string Event ID to chain after
---@param event_config schedule.event_config
---@param current_time number
---@return boolean can_start
---@return number|nil start_time Calculated start time if can start
function M.can_start_chain(after_event_id, event_config, current_time)
	if not after_event_id or type(after_event_id) ~= "string" then
		return true, nil
	end
	local after_status = state.get_event_status(after_event_id)
	local after_config = config.get_event_config(after_event_id)

	if not after_status or not after_config then
		return false, nil
	end

	if after_status.status ~= "completed" then
		return false, nil
	end

	local wait_online = event_config.after_options and event_config.after_options.wait_online
	if wait_online then
		if after_status.end_time and after_status.end_time > current_time then
			return false, nil
		end
		return true, after_status.end_time or current_time
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
		local after_status = state.get_event_status(after)
		if after_status and after_status.status == "completed" and after_status.end_time then
			return after_status.end_time
		end
		return nil
	end
	return nil
end


return M

