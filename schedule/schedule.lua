---The Defold Schedule module for scheduling timed events with cycles, conditions, and lifecycle management.
---Require at game startup, restore saved state with `set_state()` if needed, then call `update()` at your desired refresh rate.
---
---# Usage Example:
---```lua
---local schedule = require("schedule.schedule")
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
---
---timer.delay(1/60, true, function()
---	schedule.update()
---end)
---```

local event_builder = require("schedule.internal.schedule_event_builder")
local state = require("schedule.internal.schedule_state")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local time = require("schedule.internal.schedule_time")
local processor = require("schedule.internal.schedule_processor")
local conditions = require("schedule.internal.schedule_conditions")
local logger = require("schedule.internal.schedule_logger")
local event_class = require("schedule.internal.schedule_event")


---@class schedule
local M = {}


---Time constants. Prefer these over raw numbers (e.g., `schedule.HOUR` instead of `3600`) for readability.
M.SECOND = 1
M.MINUTE = 60
M.HOUR = 3600
M.DAY = 86400
M.WEEK = 604800


---Global event subscription queue. Subscribe for centralized event handling across multiple categories.
---Late subscribers receive queued events, ideal for UI that needs to catch up. Use for cross-cutting
---concerns (logging, analytics); use lifecycle callbacks for event-specific logic.
---Callback: `fun(event: table): boolean|nil` (return `true` to mark as handled)
---Event table contains: `callback_type`, `id`, `category`, `payload`, `status`, `start_time`, `end_time`
---@class schedule.queue.on_event: queue
---@field push fun(_, event: table)
---@field subscribe fun(_, callback: fun(event: table): boolean|nil, context: any): any
---@field unsubscribe fun(_, subscription: any)
M.on_event = lifecycle.event_queue


---Reset all schedule state. Clears all events, callbacks, conditions, subscriptions, and resets time tracking.
---Use for testing or implementing a "reset game" feature.
function M.reset_state()
	state.reset()
	lifecycle.reset_callbacks()
	conditions.reset()
	M.on_event:clear()
	time.set_time_function(nil)
end


---Get the complete schedule state for serialization. Call when saving your game to persist events.
---Critical for offline progression. Save to your save file system and restore with `set_state()` on load.
---@return schedule.state state Complete state object suitable for serialization
function M.get_state()
	return state.get_state()
end


---Restore schedule state from serialization. Call immediately after loading saved game data.
---Restores all events to their previous state. The system calculates catch-up time from saved time to current time.
---@param new_state schedule.state State object previously obtained from `get_state()`
function M.set_state(new_state)
	state.set_state(new_state)
end


---Create a new event builder for scheduling timed events. Returns a builder with fluent API.
---Chain methods like `:category()`, `:after()`, `:duration()`, then call `:save()` to finalize.
---Nothing happens until `:save()` is called.
---@param id string|nil Unique identifier for the event for persistence, or nil to generate a random one
---@return schedule.event_builder builder Builder instance for configuring and saving the event
function M.event(id)
	return event_builder.create(id)
end


---Get an event object by ID. Returns a rich event object with methods like `get_time_left()`, `get_status()`, `get_payload()`.
---Use this for convenience methods and type-safe access. Use `get_status()` for raw state table access.
---@param event_id string The event ID returned from `event():save()` or set via `event():id()`
---@return schedule.event|nil event Event object with query methods, or nil if event doesn't exist
function M.get(event_id)
	local event_state = state.get_event_state(event_id)
	if not event_state then
		return nil
	end
	return event_class.create(event_state)
end


---Get the raw event state table by ID. Use for direct state access or legacy compatibility.
---Prefer `get()` for new code unless you specifically need raw state access.
---@param event_id string The event ID to query
---@return schedule.event.state|nil status Raw event state table, or nil if event doesn't exist
function M.get_status(event_id)
	return state.get_event_state(event_id)
end


---Register a condition evaluator function. Call before creating events that use `:condition()`.
---Conditions check game state (tokens, progression, inventory) before activation. Multiple conditions
---use AND logic - all must pass. If any fails and `abort_on_fail()` is set, event status becomes "aborted" and will not retry.
---@param name string Condition name to use in `event():condition(name, data)`
---@param evaluator fun(data: any): boolean Function that returns true if condition passes
function M.register_condition(name, evaluator)
	conditions.register_condition(name, evaluator)
end


---Update the schedule system. Call this at your desired refresh rate (e.g., in your game loop or timer callback).
---Processes all events, handles time progression, and triggers lifecycle callbacks. Initializes time tracking on first call.
function M.update()
	local current_time = time.get_time()
	local was_first_update = not state.get_last_update_time()
	if was_first_update then
		state.set_last_update_time(current_time)
	end

	-- TODO seems better to remove this? just callbacks in event
	if was_first_update then
		local all_events = state.get_all_events()
		for event_id, event_state in pairs(all_events) do
			if event_state.status == "active" then
				local event_data = {
					id = event_id,
					category = event_state.category,
					payload = event_state.payload,
					status = "active",
					start_time = event_state.start_time,
					end_time = event_state.end_time
				}
				lifecycle.on_enabled(event_id, event_data)
			end
		end
	end

	processor.update_all(current_time)
end


---Filter events by category and/or status. Returns events matching the criteria.
---Iterates all events, so consider caching results for large event counts.
---@param category string|nil Category to filter by (e.g., "craft", "offer"), nil for any category
---@param status string|nil Status to filter by ("pending", "active", "completed", etc.), nil for any status
---@return table<string, schedule.event> events Table mapping event_id -> event object
function M.filter(category, status)
	local result = {}
	local all_events = state.get_all_events()

	for event_id, event_state in pairs(all_events) do
		local matches_category = true
		local matches_status = true

		if category ~= nil then
			matches_category = (event_state.category == category)
		end

		if status ~= nil then
			local event_status_str = event_state.status or "pending"
			matches_status = (event_status_str == status)
		end

		if matches_category and matches_status then
			local event = event_class.create(event_state)
			if event then
				result[event_id] = event
			end
		end
	end

	return result
end


---Set a custom logger instance. Integrates schedule logging with your game's logging system.
---Useful for debugging, production tracking, or analytics integration. Pass nil to disable logging.
---@param logger_instance schedule.logger|table|nil Logger object with `info`, `debug`, `error` methods, or nil to disable
function M.set_logger(logger_instance)
	logger.set_logger(logger_instance)
end


return M
