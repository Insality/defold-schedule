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
---@field payload any Custom data, `{}` when omitted
---@field after number|string|nil Seconds or event ID to chain after
---@field after_options table|nil Options for chaining (wait_online, etc.)
---@field start_at number|string|nil Timestamp or ISO date string
---@field end_at number|string|nil Timestamp or ISO date string
---@field duration number|nil Duration in seconds
---@field exceed_end_time boolean|nil If true, run is now+duration and may pass the join window
---@field infinity boolean|nil Event never ends
---@field cycle schedule.cycle_config|nil
---@field conditions schedule.condition_data[]|nil
---@field abort_on_fail boolean|nil If true, set status to "aborted" when conditions fail (event will not retry)
---@field catch_up boolean|nil
---@field min_time number|nil Minimum time required to start
---@field priority number|nil Start priority within one update, higher goes first, unset means 10

---@class schedule.state
---@field events table<string, schedule.event.state> Event ID -> state
---@field last_update_time number|nil Last time update was called
---@field events_created number|nil

local M = {}


---Prefix for automatically generated event ids
local GENERATED_ID_PREFIX = "schedule_"


---Priority of an event that never called `priority()`. It is not written into the event state,
---so a save file only carries the priorities that were set on purpose
local DEFAULT_PRIORITY = 10


---Internal state
---@type schedule.state
local state = {
	events = {},
	last_update_time = nil,
	events_created = 0,
}


---Runtime data derived from `state`, it is never serialized and is rebuilt on `set_state()`
---@class schedule.state_runtime
---@field ordered_event_ids string[] Event ids in update order, see `get_ordered_event_ids`

---@type schedule.state_runtime
local runtime = {
	ordered_event_ids = {},
}


---@param event_id string
---@return number
local function get_priority(event_id)
	return state.events[event_id].priority or DEFAULT_PRIORITY
end


---Compare two events by update order: higher priority first, then by event id
---@param event_id_a string
---@param event_id_b string
---@return boolean
local function compare_update_order(event_id_a, event_id_b)
	local priority_a = get_priority(event_id_a)
	local priority_b = get_priority(event_id_b)
	if priority_a ~= priority_b then
		return priority_a > priority_b
	end

	return event_id_a < event_id_b
end


---Rebuild the update order from scratch, used when the whole events table is replaced
local function rebuild_order()
	local event_ids = {}
	for event_id in pairs(state.events) do
		event_ids[#event_ids + 1] = event_id
	end
	table.sort(event_ids, compare_update_order)
	runtime.ordered_event_ids = event_ids
end


---Put an event into the update order, or move it if it is already there.
---The order list is replaced, not changed in place: `update_all` may be iterating the old one
---while a lifecycle callback adds or removes events
---@param event_id string
---@param is_insert boolean False to only remove the event from the order
local function update_order(event_id, is_insert)
	local event_ids = {}
	local is_inserted = not is_insert
	for _, other_id in ipairs(runtime.ordered_event_ids) do
		-- An event removed from the raw events table directly is dropped here instead of breaking the compare
		if other_id ~= event_id and state.events[other_id] then
			if not is_inserted and compare_update_order(event_id, other_id) then
				event_ids[#event_ids + 1] = event_id
				is_inserted = true
			end
			event_ids[#event_ids + 1] = other_id
		end
	end
	if not is_inserted then
		event_ids[#event_ids + 1] = event_id
	end

	runtime.ordered_event_ids = event_ids
end


---Get event ids in update order: higher priority first, events with the same priority by event id.
---The order decides which event wins when several become available in the same update, so it must
---not depend on the hash order of the events table. It is kept in sync on every event write,
---editing `priority` on a raw state table directly does not move the event.
---@return string[] event_ids Ordered event ids, do not modify
function M.get_ordered_event_ids()
	return runtime.ordered_event_ids
end


---Reset state to default
function M.reset()
	state.events = {}
	state.last_update_time = nil
	state.events_created = 0
	runtime.ordered_event_ids = {}
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
	rebuild_order()

	-- The counter can be missing in states written by other tools or older versions.
	-- Restore it above the highest generated id to keep new ids unique
	if type(state.events_created) ~= "number" then
		local events_created = 0
		for event_id in pairs(state.events) do
			local generated_index = tonumber(string.match(event_id, "^" .. GENERATED_ID_PREFIX .. "(%d+)$"))
			if generated_index and generated_index > events_created then
				events_created = generated_index
			end
		end
		state.events_created = events_created
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
	local previous_state = state.events[event_id]
	state.events[event_id] = event_state

	if not previous_state or previous_state.priority ~= event_state.priority then
		update_order(event_id, true)
	end
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
	state.events_created = (state.events_created or 0) + 1

	-- Never hand out an id that is already taken by a user defined event
	while state.events[GENERATED_ID_PREFIX .. state.events_created] do
		state.events_created = state.events_created + 1
	end

	return GENERATED_ID_PREFIX .. state.events_created
end


---Remove event state
---@param event_id string
---@return boolean is_removed True if the event existed and was removed
function M.remove_event_state(event_id)
	if not state.events[event_id] then
		return false
	end

	state.events[event_id] = nil
	update_order(event_id, false)
	return true
end


return M

