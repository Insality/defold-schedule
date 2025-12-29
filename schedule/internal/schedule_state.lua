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

---@class schedule.event.state
---@field event_id string|nil Event ID (key in state table)
---@field id string|nil Persistent event ID
---@field status "pending"|"active"|"completed"|"cancelled"|"aborted"|"failed"|"paused"
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
---@field abort_on_fail boolean|nil If true, set status to "aborted" when conditions fail (event will not retry)
---@field catch_up boolean|nil
---@field min_time number|nil Minimum time required to start

---@class schedule.state
---@field events table<string, schedule.event.state> Event ID -> state
---@field last_update_time number|nil Last time update was called
---@field events_created number|nil

local M = {}


---Internal state
---@type schedule.state
local state = {
	events = {},
	last_update_time = nil,
	events_created = 0,
}


---Reset state to default
function M.reset()
	state.events = {}
	state.last_update_time = nil
	state.events_created = 0
end


---Get the entire state (for serialization)
---@return schedule.state state Complete state object for serialization
function M.get_state()
	return state
end


---Set the entire state (for deserialization)
---@param new_state schedule.state
function M.set_state(new_state)
	state = new_state or { events = {}, last_update_time = nil, events_created = 0 }
	if not state.events then
		state.events = {}
	end
end


---Get event state
---@param event_id string
---@return schedule.event.state|nil status Event state table or nil if event doesn't exist
function M.get_event_state(event_id)
	return state.events[event_id]
end


---Set event state
---@param event_id string
---@param event_state schedule.event.state
function M.set_event_state(event_id, event_state)
	event_state.event_id = event_id
	state.events[event_id] = event_state
end


---Get all events
---@return table<string, schedule.event.state> events Table mapping event_id -> event state
function M.get_all_events()
	return state.events
end


---Get last update time
---@return number|nil last_update_time Last update time in seconds, or nil if never updated
function M.get_last_update_time()
	return state.last_update_time
end


---Set last update time
---@param time number
function M.set_last_update_time(time)
	state.last_update_time = time
end


---Return the next generated event ID
---@return string event_id
function M.get_next_event_id()
	state.events_created = state.events_created + 1
	return "schedule_" .. state.events_created
end


return M

