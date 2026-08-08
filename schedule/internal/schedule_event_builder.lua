local state = require("schedule.internal.schedule_state")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local logger = require("schedule.internal.schedule_logger")
local event = require("schedule.internal.schedule_event")
local time = require("schedule.internal.schedule_time")
local cycles = require("schedule.internal.schedule_cycles")

---The event builder. Configure the event with the chained methods, then call `save()`
---to store it and get a `schedule.event` back.
---@class schedule.event_builder
---@field config table
local M = {}


---Cycle types accepted by `cycle()`
local CYCLE_TYPES = {
	every = true,
	weekly = true,
	monthly = true,
	yearly = true,
}


---Check that a value is a time point: a number of seconds or an ISO date string
---@param value any
---@return boolean
local function is_time_value(value)
	if type(value) == "number" then
		return true
	end

	return type(value) == "string" and time.parse_iso_date(value) ~= nil
end


---Create a new event builder instance (internal - use schedule.event() instead).
---@param event_id string|nil Unique identifier for the event for persistence, or nil to generate one
---@return schedule.event_builder New builder instance
function M.create(event_id)
	local self = setmetatable({}, { __index = M })
	self.config = {
		event_id = event_id,
	}
	return self
end


---Set the event category for grouping and filtering. Enables filtering with `schedule.filter()`.
---Use consistent lowercase names (e.g., "craft", "offer", "liveops", "cooldown").
---@param category string Category name
---@return schedule.event_builder Self for method chaining
function M:category(category)
	assert(type(category) == "string", "Event category should be a string")

	self.config.category = category
	return self
end


---Set event to start after a relative delay or after another event completes (event chaining).
---Use for relative timing or sequential events. Use `start_at()` for absolute calendar-based timing.
---Set `wait_online = true` in options to start counting when the player is back online, so an offline gap
---between the two events is not spent by this one. Without it the event starts right when the parent ended,
---which means it can already be finished when the player returns.
---@param after number|string|schedule.event Seconds to wait (number) or event ID to chain after (string)
---@param options table|nil Options table with `wait_online` (boolean) for chaining behavior
---@return schedule.event_builder Self for method chaining
function M:after(after, options)
	assert(type(after) == "number" or type(after) == "string" or event.is_event(after),
		"Event after should be a number of seconds, an event id or an event")
	assert(options == nil or type(options) == "table", "Event after options should be a table")

	if event.is_event(after) then
		---@cast after schedule.event
		self.config.after = after:get_id()
		self.config.after_options = options or {}
	elseif type(after) == "string" then
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
	assert(is_time_value(start_at), "Event start_at should be a timestamp or an ISO date string (YYYY-MM-DDTHH:MM:SS)")

	self.config.start_at = start_at
	return self
end


---Set event to end at an absolute time (calendar-based end date). Use for fixed-date events like LiveOps.
---Use `duration()` for relative durations calculated from start time.
---@param end_at number|string Unix timestamp (seconds) or ISO date string (YYYY-MM-DDTHH:MM:SS)
---@return schedule.event_builder Self for method chaining
function M:end_at(end_at)
	assert(is_time_value(end_at), "Event end_at should be a timestamp or an ISO date string (YYYY-MM-DDTHH:MM:SS)")

	self.config.end_at = end_at
	return self
end


---Set the event duration. Use for crafting timers, cooldowns, temporary buffs, or any relative-duration event.
---End time is calculated as start_time + duration. For recurring events, each cycle uses the same duration.
---@param duration number Duration in seconds (use `schedule.HOUR`, `schedule.DAY`, etc. for clarity)
---@return schedule.event_builder Self for method chaining
function M:duration(duration)
	assert(type(duration) == "number" and duration >= 0, "Event duration should be a positive number of seconds")

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
	assert(CYCLE_TYPES[cycle_type], "Unknown cycle type: " .. tostring(cycle_type) .. ". Use every, weekly, monthly or yearly")
	assert(type(options) == "table", "Cycle options should be a table")

	if cycle_type == "every" then
		assert(type(options.seconds) == "number" and options.seconds > 0,
			"Cycle 'every' requires a positive seconds option")
	end
	if cycle_type == "weekly" then
		assert(type(options.weekdays) == "table" and #options.weekdays > 0,
			"Cycle 'weekly' requires a weekdays option, for example { \"sun\" }")
		for _, weekday in ipairs(options.weekdays) do
			assert(type(weekday) == "string" and time.weekday_to_number(weekday),
				"Unknown weekday: " .. tostring(weekday))
		end
	end
	if options.time ~= nil then
		assert(time.parse_time_string(options.time), "Cycle time should be a HH:MM or HH:MM:SS string")
	end
	if options.day ~= nil then
		assert(type(options.day) == "number" and options.day >= 1 and options.day <= 31, "Cycle day should be between 1 and 31")
	end
	if options.month ~= nil then
		assert(type(options.month) == "number" and options.month >= 1 and options.month <= 12, "Cycle month should be between 1 and 12")
	end
	assert(options.anchor == nil or options.anchor == "start" or options.anchor == "end",
		"Cycle anchor should be 'start' or 'end'")

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
---Multiple conditions use AND logic - all must pass. If any fails and `abort_on_fail()` is set, event status becomes "aborted" and will not retry.
---@param name string Condition name (must be registered via `schedule.register_condition()`)
---@param data any Data passed to the condition evaluator function
---@return schedule.event_builder Self for method chaining
function M:condition(name, data)
	assert(type(name) == "string", "Condition name should be a string")

	self.config.conditions = self.config.conditions or {}

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
	assert(type(catch_up) == "boolean", "Event catch_up should be a boolean")

	self.config.catch_up = catch_up
	return self
end


---Set the minimum time remaining required for the event to start. If less time remains, the event is cancelled.
---Use for LiveOps events or limited-time offers to prevent wasted activations.
---@param min_time number Minimum seconds remaining required to start (use `schedule.DAY`, etc.)
---@return schedule.event_builder Self for method chaining
function M:min_time(min_time)
	assert(type(min_time) == "number" and min_time >= 0, "Event min_time should be a positive number of seconds")

	self.config.min_time = min_time
	return self
end


---Set callback called once when the event activates. Use for one-time activation logic (notifications, achievements).
---Called once per activation cycle. Use `on_enabled` for state changes that should happen during catch-up.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_start(callback)
	assert(type(callback) == "function", "Event on_start callback should be a function")

	self.config.on_start = callback
	return self
end


---Set callback called whenever the event becomes active, including during offline catch-up.
---Use for UI updates, state changes, or effects that should apply whenever the event is active.
---Use `on_start` for one-time activation actions.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_enabled(callback)
	assert(type(callback) == "function", "Event on_enabled callback should be a function")

	self.config.on_enabled = callback
	return self
end


---Set callback called when the event becomes inactive. Use for cleanup, UI updates, or state changes.
---Paired with `on_enabled` to manage active state. Use to toggle UI elements or enable/disable features.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_disabled(callback)
	assert(type(callback) == "function", "Event on_disabled callback should be a function")

	self.config.on_disabled = callback
	return self
end


---Set callback called when the event completes naturally. Use for completion rewards, notifications, or achievements.
---Called when duration expires or end time is reached. Use `on_disabled` for general cleanup on any deactivation.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_end(callback)
	assert(type(callback) == "function", "Event on_end callback should be a function")

	self.config.on_end = callback
	return self
end


---Set callback called when the event fails (aborted due to condition failure). Use for handling failure cases.
---@param callback function Callback receives event data: `{id, category, payload, status, start_time, end_time}`
---@return schedule.event_builder Self for method chaining
function M:on_fail(callback)
	assert(type(callback) == "function", "Event on_fail callback should be a function")

	self.config.on_fail = callback
	return self
end


---Set flag to abort event when conditions fail. When conditions fail, event status will be set to "aborted" and will not retry.
---@return schedule.event_builder Self for method chaining
function M:abort_on_fail()
	self.config.abort_on_fail = true
	return self
end


---Calendar cycle types compute their own first occurrence when no explicit start is set
local CALENDAR_CYCLES = {
	weekly = true,
	monthly = true,
	yearly = true,
}


---Calculate start time from config
---@param config table Builder config
---@param current_time number Current time
---@param existing_start_time number|nil Existing start time to preserve (nil for new events)
---@return number|nil calculated_start_time
function M._calculate_start_time(config, current_time, existing_start_time)
	if config.start_at then
		return time.normalize_time(config.start_at)
	end

	-- A persisted start time always wins, otherwise re-declaring an event on game start
	-- would push its timer forward on every launch
	if existing_start_time then
		return existing_start_time
	end

	if config.after then
		if type(config.after) == "number" then
			return current_time + config.after
		end
		return nil
	end

	-- Calendar cycles without an explicit start begin at their next occurrence
	if config.cycle and CALENDAR_CYCLES[config.cycle.type] then
		return cycles.calculate_next_cycle(config.cycle, current_time) or current_time
	end

	return current_time
end


---Calculate end time from config
---@param config table Builder config
---@param start_time number|nil Calculated start time
---@param existing_end_time number|nil Existing end time to preserve (nil for new events)
---@return number|nil calculated_end_time
function M._calculate_end_time(config, start_time, existing_end_time)
	if config.end_at then
		return time.normalize_time(config.end_at)
	elseif config.duration and start_time then
		return start_time + config.duration
	end
	return existing_end_time
end


---Determine initial status for new event
---@param config table Builder config
---@param current_time number Current time
---@param start_time number|nil Calculated start time
---@param end_time number|nil Calculated end time
---@return string initial_status "pending" or "active"
function M._determine_initial_status(config, current_time, start_time, end_time)
	if config.end_at and not config.start_at and not config.after then
		if start_time and current_time >= start_time and end_time and current_time < end_time then
			return "active"
		end
	end
	return "pending"
end


---Pick the configured value, falling back to the existing one.
---Written as an explicit nil check so that `false` is a valid override.
---@param config_value any Value from the builder config
---@param existing_value any Value from the existing event state
---@return any value
local function merge_value(config_value, existing_value)
	if config_value ~= nil then
		return config_value
	end
	return existing_value
end


---Resolve the catch up flag. Events with a duration do not catch up by default,
---events without one (plain timers) do.
---@param config table Builder config
---@param existing_state schedule.event.state|nil Existing state
---@return boolean catch_up
function M._resolve_catch_up(config, existing_state)
	local catch_up = merge_value(config.catch_up, existing_state and existing_state.catch_up)
	if catch_up ~= nil then
		return catch_up
	end

	local has_duration = config.duration or config.end_at or
		(existing_state and (existing_state.duration or existing_state.end_at))
	return not has_duration
end


---Build event state table from config
---@param config table Builder config
---@param event_id string Event ID
---@param current_time number Current time
---@param existing_state schedule.event.state|nil Existing state (nil for new events)
---@return schedule.event.state event_state
function M._build_event_state(config, event_id, current_time, existing_state)
	local start_time = existing_state and existing_state.start_time or nil
	local end_time = existing_state and existing_state.end_time or nil
	local calculated_start_time = M._calculate_start_time(config, current_time, start_time)
	local calculated_end_time = M._calculate_end_time(config, calculated_start_time, end_time)
	local initial_status = existing_state and (existing_state.status or "pending")
		or M._determine_initial_status(config, current_time, calculated_start_time, calculated_end_time)

	return {
		event_id = event_id,
		status = initial_status,
		start_time = calculated_start_time,
		end_time = calculated_end_time,
		last_update_time = existing_state and existing_state.last_update_time or nil,
		cycle_count = existing_state and (existing_state.cycle_count or 0) or 0,
		next_cycle_time = existing_state and existing_state.next_cycle_time or nil,
		category = merge_value(config.category, existing_state and existing_state.category),
		payload = merge_value(config.payload, existing_state and existing_state.payload),
		after = merge_value(config.after, existing_state and existing_state.after),
		after_options = merge_value(config.after_options, existing_state and existing_state.after_options),
		start_at = merge_value(config.start_at, existing_state and existing_state.start_at),
		end_at = merge_value(config.end_at, existing_state and existing_state.end_at),
		duration = merge_value(config.duration, existing_state and existing_state.duration),
		infinity = merge_value(config.infinity, existing_state and existing_state.infinity),
		cycle = merge_value(config.cycle, existing_state and existing_state.cycle),
		conditions = merge_value(config.conditions, existing_state and existing_state.conditions),
		abort_on_fail = merge_value(config.abort_on_fail, existing_state and existing_state.abort_on_fail),
		catch_up = M._resolve_catch_up(config, existing_state),
		min_time = merge_value(config.min_time, existing_state and existing_state.min_time)
	}
end


---Check the configuration for combinations that cannot work
---@param config table Builder config
function M._validate_config(config)
	assert(config.event_id == nil or type(config.event_id) == "string", "Event id should be a string")
	assert(not (config.duration and config.end_at), "Event can not have both duration() and end_at(), pick one")
	assert(not (config.infinity and (config.duration or config.end_at)),
		"Event can not be infinity() and have duration() or end_at() at the same time")
	assert(not (config.start_at and config.after), "Event can not have both start_at() and after(), pick one")

	if config.end_at and config.start_at then
		local start_time = time.normalize_time(config.start_at)
		local end_time = time.normalize_time(config.end_at)
		assert(start_time and end_time and end_time > start_time, "Event end_at should be after start_at")
	end
end


---Save the event to the schedule system and return the event instance. Call as the final step after configuration.
---Nothing happens until `save()` is called. The event is validated, times are calculated, state is stored,
---and callbacks are registered. If an existing event with the same ID exists, its state is merged.
---Returns the created event object, with methods like `get_time_left()` and `get_status()`.
---@return schedule.event event Created event instance
function M:save()
	M._validate_config(self.config)

	local current_time = time.get_time()
	local event_id = self.config.event_id or state.get_next_event_id()
	local existing_state = event_id and state.get_event_state(event_id) or nil

	local event_state = M._build_event_state(self.config, event_id, current_time, existing_state)
	state.set_event_state(event_id, event_state)

	lifecycle.register_callback(event_id, "on_start", self.config.on_start)
	lifecycle.register_callback(event_id, "on_enabled", self.config.on_enabled)
	lifecycle.register_callback(event_id, "on_disabled", self.config.on_disabled)
	lifecycle.register_callback(event_id, "on_end", self.config.on_end)
	lifecycle.register_callback(event_id, "on_fail", self.config.on_fail)

	local saved_state = state.get_event_state(event_id)
	assert(saved_state, "Event state must exist")
	local event_instance = event.create(saved_state)

	logger:debug("Event saved", { event_id = event_id, category = self.config.category })
	return event_instance
end


return M

