---The Defold Schedule module for scheduling timed events with cycles, conditions, and lifecycle management.
---Require at game startup, restore saved state with `set_state()` if needed, then call `update()` at your desired refresh rate.
---All times are Unix seconds in UTC, ISO date strings are parsed as UTC as well.
---
---# Usage Example:
---```lua
---local schedule = require("schedule.schedule")
---
---local event = schedule.event("craft_sword")
---	:category("craft")
---	:after(60)
---	:duration(120)
---	:payload({ item = "sword" })
---	:on_end(function(event_data)
---		give_item(event_data.payload.item)
---	end)
---	:save()
---
---print(event:get_id(), event:get_time_left())
---
---schedule.on_event:subscribe(function(event_data)
---	print("Schedule event:", event_data.callback_type, event_data.event_id)
---	return true -- Mark the event as handled and drop it from the queue
---end)
---
---timer.delay(1, true, function()
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
---Unhandled events are kept for late subscribers, ideal for UI that needs to catch up (the last 128 are kept).
---Use it for cross-cutting concerns (logging, analytics), use lifecycle callbacks for event-specific logic.
---Callback: `fun(event: table): boolean|nil`. Return `true` to mark the event as handled and drop it from
---the queue, return `nil` to leave it for other subscribers. Note that returning `false` also marks it handled.
---Event table contains: `callback_type`, `event_id`, `category`, `payload`, `status`, `start_time`, `end_time`
---`callback_type` is one of `"start"`, `"enabled"`, `"disabled"`, `"end"`, `"fail"`
---@class schedule.queue.on_event: queue
---@field push fun(_, event: table)
---@field subscribe fun(_, callback: fun(event: table): boolean|nil, context: any): any
---@field unsubscribe fun(_, subscription: any)
M.on_event = lifecycle.event_queue


---Reset all schedule state. Clears all events, callbacks, conditions, subscriptions and time tracking.
---The custom time function set with `set_time_function()` is kept, it is a system setting and not game state.
---Use for testing or implementing a "reset game" feature.
function M.reset_state()
	state.reset()
	lifecycle.reset_callbacks()
	conditions.reset()
	processor.clear_active_events()
end


---Get the complete schedule state for serialization. Call when saving your game to persist events.
---Critical for offline progression. Save to your save file system and restore with `set_state()` on load.
---@return schedule.state state Complete state object suitable for serialization
function M.get_state()
	return state.get_state()
end


---Restore schedule state from serialization. Call immediately after loading saved game data,
---before declaring your events. Restores all events to their previous state, the next `update()` catches up
---the time that passed since the state was saved. Lifecycle callbacks are not serializable: re-declare your
---events with `schedule.event(id)` after restoring to attach them again, it keeps the stored timings.
---@param new_state schedule.state State object previously obtained from `get_state()`
function M.set_state(new_state)
	state.set_state(new_state)
	processor.clear_active_events()
end


---Create a new event builder for scheduling timed events. Returns a builder with fluent API.
---Chain methods like `:category()`, `:after()`, `:duration()`, then call `:save()` to finalize.
---Nothing happens until `:save()` is called.
---@param id string|nil Unique identifier for the event for persistence, or nil to generate one
---@return schedule.event_builder builder Builder instance for configuring and saving the event
function M.event(id)
	return event_builder.create(id)
end


---Get an event object by ID. Returns a rich event object with methods like `get_time_left()`, `get_status()`, `get_payload()`.
---Use this for convenience methods and type-safe access. Use `get_event_state()` for raw state table access.
---@param event_id string The event ID returned from `event():save()` or passed to `schedule.event(id)`
---@return schedule.event|nil event Event object with query methods, or nil if event doesn't exist
function M.get(event_id)
	local event_state = state.get_event_state(event_id)
	if not event_state then
		return nil
	end
	return event_class.create(event_state)
end


---Get the raw event state table by ID. Use for direct state access.
---The returned table is the live internal state, changing it changes the event.
---Prefer `get()` unless you specifically need raw state access.
---@param event_id string The event ID to query
---@return schedule.event.state|nil event_state Raw event state table, or nil if event doesn't exist
function M.get_event_state(event_id)
	return state.get_event_state(event_id)
end


---Get the raw event state table by ID.
---@deprecated Use `get_event_state()` instead, `get_status()` is easy to confuse with `event:get_status()`
---@param event_id string The event ID to query
---@return schedule.event.state|nil event_state Raw event state table, or nil if event doesn't exist
function M.get_status(event_id)
	return state.get_event_state(event_id)
end


---Remove an event completely, dropping its state and its lifecycle callbacks.
---Completed events stay in the state until removed, so clean up one-shot events you no longer need
---to keep the save file small.
---@param event_id string The event ID to remove
---@return boolean is_removed True if the event existed and was removed
function M.remove(event_id)
	local is_removed = state.remove_event_state(event_id)
	if is_removed then
		lifecycle.clear_callbacks(event_id)
	end

	return is_removed
end


---Remove every event matching the given category and/or status. Both arguments are optional,
---`clear()` removes all events. Useful to drop completed one-shot events on save.
---@param category string|nil Category to match, nil for any category
---@param status string|nil Status to match ("completed", "cancelled", ...), nil for any status
---@return number removed_count Number of removed events
function M.clear(category, status)
	local removed_count = 0

	for event_id in pairs(M.filter(category, status)) do
		if M.remove(event_id) then
			removed_count = removed_count + 1
		end
	end

	return removed_count
end


---Set the function used to read the current time. Return Unix time in seconds.
---Use it to drive the schedule from server time instead of the device clock, which is the
---recommended setup for LiveOps events and anything a player could cheat by changing the clock.
---Pass nil to go back to the device clock (`socket.gettime`).
---@param callback (fun(): number)|nil Function returning the current Unix time in seconds
function M.set_time_function(callback)
	time.set_time_function(callback)
end


---Get the current time used by the schedule, as returned by the time function.
---@return number time Current Unix time in seconds
function M.get_time()
	return time.get_time()
end


---Register a condition evaluator function. Call before creating events that use `:condition()`.
---Conditions check game state (tokens, progression, inventory) before activation. Multiple conditions
---use AND logic - all must pass. If any fails and `abort_on_fail()` is set, event status becomes "aborted" and will not retry.
---@param name string Condition name to use in `event():condition(name, data)`
---@param evaluator (fun(data: any): boolean)|nil Function that returns true if condition passes, nil to unregister
function M.register_condition(name, evaluator)
	assert(type(name) == "string", "Condition name should be a string")
	assert(evaluator == nil or type(evaluator) == "function", "Condition evaluator should be a function or nil")

	conditions.register_condition(name, evaluator)
end


---Update the schedule system. Call this at your desired refresh rate (e.g., in your game loop or timer callback).
---Processes all events, handles time progression, and triggers lifecycle callbacks. Initializes time tracking on first call.
---Once per second is enough for most games, the schedule works on absolute time and does not need frequent updates.
function M.update()
	processor.update_all(time.get_time())
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
---Logging is disabled by default. Pass any object with `trace`, `debug`, `info`, `warn` and `error`
---methods (a defold-log logger fits), or nil to turn logging off again.
---@param logger_instance schedule.logger|table|nil Logger object with `info`, `debug`, `error` methods, or nil to disable
function M.set_logger(logger_instance)
	logger.set_logger(logger_instance)
end


return M
