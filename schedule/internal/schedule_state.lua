---@class schedule.cycle_config
---@field type "every"|"weekly"|"monthly"|"yearly"
---@field seconds number|nil For "every" type
---@field anchor "start"|"end"|nil For "every" type
---@field skip_missed boolean|nil
---@field max_catches number|nil Maximum number of cycles to catch up
---@field weekdays string[]|nil For "weekly" type (e.g., {"sun", "mon"})
---@field time string|nil Time string (e.g., "14:00")
---@field day number|nil For "monthly" type
---@field month number|nil For "yearly" type

---@class schedule.condition_data
---@field name string
---@field data any

---@class schedule.event_status
---@field event_id string|nil Event ID (key in state table)
---@field id string|nil Persistent event ID
---@field status "pending"|"active"|"completed"|"cancelled"|"aborted"|"failed"
---@field start_time number|nil
---@field end_time number|nil
---@field last_update_time number|nil
---@field cycle_count number|nil
---@field next_cycle_time number|nil
---@field category string|nil
---@field payload any|nil
---@field after number|string|nil Seconds or event ID to chain after
---@field after_options table|nil Options for chaining (wait_online, etc.)
---@field start_at number|string|nil Timestamp or ISO date string
---@field end_at number|string|nil Timestamp or ISO date string
---@field duration number|nil Duration in seconds
---@field infinity boolean|nil Event never ends
---@field cycle schedule.cycle_config|nil
---@field conditions schedule.condition_data[]|nil
---@field catch_up boolean|nil
---@field min_time number|nil Minimum time required to start

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
	status.event_id = event_id
	state.events[event_id] = status
end


---Find event by persistent ID
---@param persistent_id string
---@return string|nil Event ID, nil if not found
function M.find_by_persistent_id(persistent_id)
	for event_id, event_status in pairs(state.events) do
		if event_status.id == persistent_id then
			return event_id
		end
	end
	return nil
end


---Get all events
---@return table<string, schedule.event_status>
function M.get_all_events()
	return state.events
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

