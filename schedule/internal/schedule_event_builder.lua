local state = require("schedule.internal.schedule_state")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local logger = require("schedule.internal.schedule_logger")
local event_class = require("schedule.internal.schedule_event")

local event_id_counter = 0

---@class schedule.event_builder : schedule.event
---@field config table
local M = {}


---Create a new event builder instance (internal - use schedule.event() instead).
---@return schedule.event_builder New builder instance
function M.create()
	local self = setmetatable({}, { __index = M })
	self.config = {}
	return self
end


---Set the event category for grouping and filtering. Enables filtering with `schedule.filter()`.
---Use consistent lowercase names (e.g., "craft", "offer", "liveops", "cooldown").
---@param category string Category name
---@return schedule.event_builder Self for method chaining
function M:category(category)
	self.config.category = category
	return self
end


---Set event to start after a relative delay or after another event completes (event chaining).
---Use for relative timing or sequential events. Use `start_at()` for absolute calendar-based timing.
---Set `wait_online = true` in options to wait for player to be online before starting chained events.
---@param after number|string Seconds to wait (number) or event ID to chain after (string)
---@param options table|nil Options table with `wait_online` (boolean) for chaining behavior
---@return schedule.event_builder Self for method chaining
function M:after(after, options)
	if type(after) == "string" then
		self.config.after = after
		self.config.after_options = options or {}
	else
		self.config.after = after
		self.config.after_options = options
	end
	return self
end


---Set event to start at an absolute time (calendar-based scheduling). Use for LiveOps events or scheduled promotions.
---ISO date strings (e.g., "2026-01-01T00:00:00") are more readable; use timestamps for programmatic calculation.
---@param start_at number|string Unix timestamp (seconds) or ISO date string (YYYY-MM-DDTHH:MM:SS)
---@return schedule.event_builder Self for method chaining
function M:start_at(start_at)
	self.config.start_at = start_at
	return self
end


---Set event to end at an absolute time (calendar-based end date). Use for fixed-date events like LiveOps.
---Use `duration()` for relative durations calculated from start time.
---@param end_at number|string Unix timestamp (seconds) or ISO date string (YYYY-MM-DDTHH:MM:SS)
---@return schedule.event_builder Self for method chaining
function M:end_at(end_at)
	self.config.end_at = end_at
	return self
end


---Set the event duration. Use for crafting timers, cooldowns, temporary buffs, or any relative-duration event.
---End time is calculated as start_time + duration. For recurring events, each cycle uses the same duration.
---@param duration number Duration in seconds (use `schedule.HOUR`, `schedule.DAY`, etc. for clarity)
---@return schedule.event_builder Self for method chaining
function M:duration(duration)
	self.config.duration = duration
	return self
end


---Set event to never end automatically (runs until manually cancelled). Use for permanent buffs,
---continuous effects, or events that end based on game state rather than time.
---@return schedule.event_builder Self for method chaining
function M:infinity()
	self.config.infinity = true
	return self
end


---Set the event to repeat on a cycle. Types: `"every"` (interval-based), `"weekly"` (calendar-based),
---`"monthly"`, `"yearly"`. Set `skip_missed = true` for LiveOps (skip missed cycles), `false` for
---daily rewards (catch-up). `anchor = "start"` (default) or `"end"` (gaps between cycles).
---`max_catches` limits catch-up cycles during offline time.
---@param cycle_type "every"|"weekly"|"monthly"|"yearly" Type of cycle repetition
---@param options table Cycle options: `seconds` (for "every"), `weekdays`, `day`, `month`, `time`, `anchor`, `skip_missed`, `max_catches`
---@return schedule.event_builder Self for method chaining
function M:cycle(cycle_type, options)
	self.config.cycle = {
		type = cycle_type,
		seconds = options.seconds,
		anchor = options.anchor,
		skip_missed = options.skip_missed,
		max_catches = options.max_catches,
		weekdays = options.weekdays,
		time = options.time,
		day = options.day,
		month = options.month
	}
	return self
end


---Add a condition that must pass for the event to activate. Register evaluator with `schedule.register_condition()` first.
---Multiple conditions use AND logic - all must pass. If any fails, `on_fail` is triggered.
---@param name string Condition name (must be registered via `schedule.register_condition()`)
---@param data any Data passed to the condition evaluator function
---@return schedule.event_builder Self for method chaining
function M:condition(name, data)
	if not self.config.conditions then
		self.config.conditions = {}
	end
	table.insert(self.config.conditions, {
		name = name,
		data = data
	})
	return self
end


---Set custom data payload passed to event handlers and callbacks. Included in all event notifications.
---Store lightweight data (IDs, configuration objects). Avoid large objects or functions.
---@param payload any Custom data object to attach to the event
---@return schedule.event_builder Self for method chaining
function M:payload(payload)
	self.config.payload = payload
	return self
end


---Set whether the event should catch up on missed time when the game resumes after being offline.
---Enable for offline progression (crafting, daily rewards). Disable for LiveOps or time-sensitive events.
---Events with duration default to `false`; events without duration default to `true`.
---@param catch_up boolean true to enable offline catch-up, false to disable
---@return schedule.event_builder Self for method chaining
function M:catch_up(catch_up)
	self.config.catch_up = catch_up
	return self
end


---Set the minimum time remaining required for the event to start. If less time remains, the event is cancelled.
---Use for LiveOps events or limited-time offers to prevent wasted activations.
---@param min_time number Minimum seconds remaining required to start (use `schedule.DAY`, etc.)
---@return schedule.event_builder Self for method chaining
function M:min_time(min_time)
	self.config.min_time = min_time
	return self
end


---Set callback called once when the event activates. Use for one-time activation logic (notifications, achievements).
---Called once per activation cycle. Use `on_enabled` for state changes that should happen during catch-up.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_start(callback)
	self.config.on_start = callback
	return self
end


---Set callback called whenever the event becomes active, including during offline catch-up.
---Use for UI updates, state changes, or effects that should apply whenever the event is active.
---Use `on_start` for one-time activation actions.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_enabled(callback)
	self.config.on_enabled = callback
	return self
end


---Set callback called when the event becomes inactive. Use for cleanup, UI updates, or state changes.
---Paired with `on_enabled` to manage active state. Use to toggle UI elements or enable/disable features.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_disabled(callback)
	self.config.on_disabled = callback
	return self
end


---Set callback called when the event completes naturally. Use for completion rewards, notifications, or achievements.
---Called when duration expires or end time is reached. Use `on_disabled` for general cleanup on any deactivation.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_end(callback)
	self.config.on_end = callback
	return self
end


---Set callback or action to handle condition failures. `"cancel"` permanently cancels (won't retry),
---`"abort"` temporarily aborts (will retry when conditions pass), or use a function for custom logic (status becomes "failed").
---Use "abort" for temporary failures, "cancel" for permanent failures.
---@param on_fail string|function "cancel" to cancel permanently, "abort" to abort temporarily, or function for custom logic
---@return schedule.event_builder Self for method chaining
function M:on_fail(on_fail)
	self.config.on_fail = on_fail
	return self
end


---Set a persistent event ID for finding and updating existing events. Required for events that persist across sessions.
---Allows finding events with `schedule.get(id)` and updating them by creating a new builder with the same ID.
---Use descriptive, unique IDs (e.g., "event_new_year_2026", "craft_iron_sword_123").
---@param id string Unique identifier for this event (must be unique across all events)
---@return schedule.event_builder Self for method chaining
function M:id(id)
	self.config.id = id
	return self
end


---Save the event to the schedule system and return the event instance. Call as the final step after configuration.
---Nothing happens until `save()` is called. The event is validated, times are calculated, state is stored,
---and callbacks are registered. If an existing event with the same ID exists, its state is merged.
---Returns the builder instance, which also acts as an event object with methods like `get_time_left()`, `get_status()`.
---@return schedule.event Event instance (builder also acts as event object)
function M:save()
	local time_utils = require("schedule.internal.schedule_time")
	local current_time = time_utils.get_time()

	local event_id = nil
	local existing_status = nil

	if self.config.id then
		event_id = self.config.id
		existing_status = state.get_event_state(event_id)
	else
		event_id_counter = event_id_counter + 1
		event_id = "schedule_" .. event_id_counter
	end

	assert(event_id ~= nil, "Event ID must be generated")

	if existing_status then
		local calculated_start_time = existing_status.start_time
		local calculated_end_time = existing_status.end_time
		local initial_status = existing_status.status or "pending"

		if self.config.start_at then
			local start_at = self.config.start_at
			if type(start_at) == "string" then
				calculated_start_time = time_utils.parse_iso_date(start_at)
			elseif type(start_at) == "number" then
				calculated_start_time = start_at
			end
		elseif self.config.after then
			local after = self.config.after
			if type(after) == "number" then
				calculated_start_time = current_time + after
			end
		end

		if self.config.end_at then
			local end_at = self.config.end_at
			if type(end_at) == "string" then
				calculated_end_time = time_utils.parse_iso_date(end_at)
			elseif type(end_at) == "number" then
				calculated_end_time = end_at
			end
		elseif self.config.duration and calculated_start_time then
			calculated_end_time = calculated_start_time + self.config.duration
		end

		state.set_event_state(event_id, {
			id = self.config.id,
			status = initial_status,
			start_time = calculated_start_time,
			end_time = calculated_end_time,
			last_update_time = existing_status.last_update_time,
			cycle_count = existing_status.cycle_count or 0,
			next_cycle_time = existing_status.next_cycle_time,
			category = self.config.category or existing_status.category,
			payload = self.config.payload or existing_status.payload,
			after = self.config.after or existing_status.after,
			after_options = self.config.after_options or existing_status.after_options,
			start_at = self.config.start_at or existing_status.start_at,
			end_at = self.config.end_at or existing_status.end_at,
			duration = self.config.duration or existing_status.duration,
			infinity = self.config.infinity ~= nil and self.config.infinity or existing_status.infinity,
			cycle = self.config.cycle or existing_status.cycle,
			conditions = self.config.conditions or existing_status.conditions,
			catch_up = self.config.catch_up ~= nil and self.config.catch_up or existing_status.catch_up,
			min_time = self.config.min_time or existing_status.min_time
		})
	else
		local calculated_start_time = nil
		local calculated_end_time = nil
		local initial_status = "pending"

		if self.config.start_at then
			local start_at = self.config.start_at
			if type(start_at) == "string" then
				calculated_start_time = time_utils.parse_iso_date(start_at)
			elseif type(start_at) == "number" then
				calculated_start_time = start_at
			end
		elseif self.config.after then
			local after = self.config.after
			if type(after) == "number" then
				calculated_start_time = current_time + after
			end
		else
			calculated_start_time = current_time
		end

		if self.config.end_at then
			local end_at = self.config.end_at
			if type(end_at) == "string" then
				calculated_end_time = time_utils.parse_iso_date(end_at)
			elseif type(end_at) == "number" then
				calculated_end_time = end_at
			end
		elseif self.config.duration and calculated_start_time then
			calculated_end_time = calculated_start_time + self.config.duration
		end

		if self.config.end_at and not self.config.start_at and not self.config.after then
			if calculated_start_time and current_time >= calculated_start_time and calculated_end_time and current_time < calculated_end_time then
				initial_status = "active"
			end
		end

		state.set_event_state(event_id, {
			id = self.config.id,
			status = initial_status,
			start_time = calculated_start_time,
			end_time = calculated_end_time,
			last_update_time = nil,
			cycle_count = 0,
			next_cycle_time = nil,
			category = self.config.category,
			payload = self.config.payload,
			after = self.config.after,
			after_options = self.config.after_options,
			start_at = self.config.start_at,
			end_at = self.config.end_at,
			duration = self.config.duration,
			infinity = self.config.infinity,
			cycle = self.config.cycle,
			conditions = self.config.conditions,
			catch_up = self.config.catch_up,
			min_time = self.config.min_time
		})
	end

	if self.config.on_start then
		lifecycle.register_callback(event_id, "on_start", self.config.on_start)
	end
	if self.config.on_enabled then
		lifecycle.register_callback(event_id, "on_enabled", self.config.on_enabled)
	end
	if self.config.on_disabled then
		lifecycle.register_callback(event_id, "on_disabled", self.config.on_disabled)
	end
	if self.config.on_end then
		lifecycle.register_callback(event_id, "on_end", self.config.on_end)
	end
	if self.config.on_fail then
		lifecycle.register_callback(event_id, "on_fail", self.config.on_fail)
	end

	self.event_id = event_id

	local event_status = state.get_event_state(event_id)
	if event_status then
		local event_instance = event_class.create(event_status)
		if event_instance then
			setmetatable(self, {
				__index = function(t, k)
					if M[k] then
						return M[k]
					end
					local method = event_instance[k]
					if method and type(method) == "function" then
						return function(...)
							local args = {...}
							args[1] = event_instance
							return method(unpack(args))
						end
					end
					return method
				end
			})
		end
	end

	logger:debug("Event saved", { event_id = event_id, category = self.config.category })
	return self
end


return M

