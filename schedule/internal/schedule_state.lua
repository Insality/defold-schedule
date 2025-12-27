---@class schedule.event_status
---@field status "pending"|"active"|"completed"|"cancelled"|"aborted"|"failed"
---@field start_time number|nil
---@field end_time number|nil
---@field last_update_time number|nil
---@field cycle_count number|nil
---@field next_cycle_time number|nil

---@class schedule.state
---@field events table<string, schedule.event_status> Event ID -> status
---@field last_update_time number|nil Last time update was called

local M = {}


---Internal state
---@type schedule.state
local state = {
	events = {},
	last_update_time = nil
}


---Reset state to default
function M.reset()
	state = {
		events = {},
		last_update_time = nil
	}
end


---Get the entire state (for serialization)
---@return schedule.state
function M.get_state()
	return state
end


---Set the entire state (for deserialization)
---@param new_state schedule.state
function M.set_state(new_state)
	state = new_state or { events = {}, last_update_time = nil }
	if not state.events then
		state.events = {}
	end
end


---Get event status
---@param event_id string
---@return schedule.event_status|nil
function M.get_event_status(event_id)
	return state.events[event_id]
end


---Set event status
---@param event_id string
---@param status schedule.event_status
function M.set_event_status(event_id, status)
	state.events[event_id] = status
end


---Get last update time
---@return number|nil
function M.get_last_update_time()
	return state.last_update_time
end


---Set last update time
---@param time number
function M.set_last_update_time(time)
	state.last_update_time = time
end


return M

