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

---@class schedule.event_config
---@field id string|nil Persistent event ID
---@field category string|nil
---@field after number|string|nil Seconds or event ID to chain after
---@field after_options table|nil Options for chaining (wait_online, etc.)
---@field start_at number|string|nil Timestamp or ISO date string
---@field end_at number|string|nil Timestamp or ISO date string
---@field duration number|nil Duration in seconds
---@field infinity boolean|nil Event never ends
---@field cycle schedule.cycle_config|nil
---@field conditions schedule.condition_data[]|nil
---@field payload any|nil
---@field catch_up boolean|nil
---@field min_time number|nil Minimum time required to start
---@field on_start function|nil
---@field on_enabled function|nil
---@field on_disabled function|nil
---@field on_end function|nil
---@field on_fail string|function|nil "cancel", "abort", or function

---@class schedule.config
---@field events table<string, schedule.event_config> Event ID -> config

local M = {}


---Internal config storage
---@type schedule.config
local config = {
	events = {}
}


---Reset config to default
function M.reset()
	config = {
		events = {}
	}
end


---Get event config
---@param event_id string
---@return schedule.event_config|nil
function M.get_event_config(event_id)
	return config.events[event_id]
end


---Set event config
---@param event_id string
---@param event_config schedule.event_config
function M.set_event_config(event_id, event_config)
	config.events[event_id] = event_config
end


---Find event by persistent ID
---@param persistent_id string
---@return string|nil Event ID, nil if not found
function M.find_event_by_id(persistent_id)
	for event_id, event_config in pairs(config.events) do
		if event_config.id == persistent_id then
			return event_id
		end
	end
	return nil
end


---Get all event configs
---@return table<string, schedule.event_config>
function M.get_all_events()
	return config.events
end


return M

