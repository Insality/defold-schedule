---The Defold Schedule module.
---Use this module to schedule timed events with cycles, conditions, and lifecycle management.
---
---# Usage Example:
---```lua
---local schedule = require("schedule.schedule")
---schedule.init()
---
---local event_id = schedule.event()
---	:category("craft")
---	:after(60)
---	:duration(120)
---	:payload({ item = "sword" })
---	:save()
---
---schedule.on_event:subscribe(function(event)
---	print("Event activated:", event.id)
---end)
---```

local event_system = require("schedule.internal.schedule_event_system")
local event_builder = require("schedule.internal.schedule_event_builder")
local config = require("schedule.internal.schedule_config")
local state = require("schedule.internal.schedule_state")
local time_utils = require("schedule.internal.schedule_time")
local processor = require("schedule.internal.schedule_processor")
local conditions = require("schedule.internal.schedule_conditions")
local logger = require("schedule.internal.schedule_logger")


---@class schedule
local M = {}


---Time constants
M.SECOND = 1
M.MINUTE = 60
M.HOUR = 3600
M.DAY = 86400
M.WEEK = 604800


---Global event subscription
---@class schedule.event.on_event: event
---@field subscribe fun(_, callback: fun(event: table): boolean|nil, context: any): number
---@field unsubscribe fun(_, subscription_id: number)
---@field trigger fun(_, event: table)
M.on_event = event_system.create()


---Timer handle for update loop
---@type any
M.timer_id = nil


---Initialize schedule system
function M.init()
	config.reset()
	if not state.get_last_update_time() then
		state.set_last_update_time(time_utils.get_time())
	end

	if M.timer_id then
		timer.cancel(M.timer_id)
	end
	M.timer_id = timer.delay(1/60, true, M.update)

	logger:info("Schedule system initialized")
end


---Reset schedule state
function M.reset_state()
	state.reset()
	config.reset()
	conditions.reset()
	M.on_event:clear()
	emitted_events = {}

	if M.timer_id then
		timer.cancel(M.timer_id)
		M.timer_id = nil
	end
end


---Get state for serialization
---@return schedule.state
function M.get_state()
	return state.get_state()
end


---Set state from serialization
---@param new_state schedule.state
function M.set_state(new_state)
	state.set_state(new_state)
end


---Create new event builder
---@return schedule.event_builder
function M.event()
	return event_builder.create()
end


---Get event status
---@param event_id string
---@return schedule.event_status|nil
function M.get_status(event_id)
	return state.get_event_status(event_id)
end


---Register condition evaluator
---@param name string Condition name
---@param evaluator fun(data: any): boolean
function M.register_condition(name, evaluator)
	conditions.register_condition(name, evaluator)
end


---Track which events have already emitted
local emitted_events = {}


---Update schedule system
function M.update()
	local current_time = time_utils.get_time()
	local last_update_time = state.get_last_update_time() or current_time
	local any_updated = processor.update_all(current_time)

	local all_events = config.get_all_events()
	for event_id, event_config in pairs(all_events) do
		local event_status = state.get_event_status(event_id)
		if event_status and event_status.status == "active" then
			local emit_key = event_id .. "_" .. (event_status.start_time or 0)
			if not emitted_events[emit_key] and event_status.start_time and current_time >= event_status.start_time then
				emitted_events[emit_key] = true
				M.on_event:trigger({
					id = event_id,
					category = event_config.category,
					payload = event_config.payload,
					status = event_status.status,
					start_time = event_status.start_time,
					end_time = event_status.end_time
				})
			end
		elseif event_status and event_status.status ~= "active" then
			local emit_key = event_id .. "_" .. (event_status.start_time or 0)
			emitted_events[emit_key] = nil
		end
	end
end


---Set logger
---@param logger_instance schedule.logger|table|nil
function M.set_logger(logger_instance)
	logger.set_logger(logger_instance)
end


return M
