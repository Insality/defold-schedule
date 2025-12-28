local state = require("schedule.internal.schedule_state")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local logger = require("schedule.internal.schedule_logger")
local event_class = require("schedule.internal.schedule_event")

local event_id_counter = 0

---@class schedule.event_builder : schedule.event
---@field config table
---@field event_id string|nil
local M = {}


---Create new event builder
---@return schedule.event_builder
function M.create()
	local self = setmetatable({}, { __index = M })
	self.config = {}
	self.event_id = nil
	return self
end


---Set event category
---@param category string
---@return schedule.event_builder
function M:category(category)
	self.config.category = category
	return self
end


---Set event to start after N seconds or after another event
---@param after number|string Event ID or seconds
---@param options table|nil Options for chaining (wait_online, etc.)
---@return schedule.event_builder
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


---Set event to start at specific time
---@param start_at number|string Timestamp or ISO date string
---@return schedule.event_builder
function M:start_at(start_at)
	self.config.start_at = start_at
	return self
end


---Set event to end at specific time
---@param end_at number|string Timestamp or ISO date string
---@return schedule.event_builder
function M:end_at(end_at)
	self.config.end_at = end_at
	return self
end


---Set event duration
---@param duration number Duration in seconds
---@return schedule.event_builder
function M:duration(duration)
	self.config.duration = duration
	return self
end


---Set event to never end
---@return schedule.event_builder
function M:infinity()
	self.config.infinity = true
	return self
end


---Set event cycle
---@param cycle_type "every"|"weekly"|"monthly"|"yearly"
---@param options table Cycle options
---@return schedule.event_builder
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


---Add condition
---@param name string Condition name
---@param data any Condition data
---@return schedule.event_builder
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


---Set event payload
---@param payload any
---@return schedule.event_builder
function M:payload(payload)
	self.config.payload = payload
	return self
end


---Set catch up behavior
---@param catch_up boolean
---@return schedule.event_builder
function M:catch_up(catch_up)
	self.config.catch_up = catch_up
	return self
end


---Set minimum time required to start
---@param min_time number
---@return schedule.event_builder
function M:min_time(min_time)
	self.config.min_time = min_time
	return self
end


---Set on_start callback
---@param callback function
---@return schedule.event_builder
function M:on_start(callback)
	self.config.on_start = callback
	return self
end


---Set on_enabled callback
---@param callback function
---@return schedule.event_builder
function M:on_enabled(callback)
	self.config.on_enabled = callback
	return self
end


---Set on_disabled callback
---@param callback function
---@return schedule.event_builder
function M:on_disabled(callback)
	self.config.on_disabled = callback
	return self
end


---Set on_end callback
---@param callback function
---@return schedule.event_builder
function M:on_end(callback)
	self.config.on_end = callback
	return self
end


---Set on_fail callback or action
---@param on_fail string|function "cancel", "abort", or function
---@return schedule.event_builder
function M:on_fail(on_fail)
	self.config.on_fail = on_fail
	return self
end


---Set persistent event ID
---@param id string
---@return schedule.event_builder
function M:id(id)
	self.config.id = id
	return self
end


---Save event and return event instance
---@return schedule.event
function M:save()
	local time_utils = require("schedule.internal.schedule_time")
	local current_time = time_utils.get_time()
	
	local event_id = nil
	local existing_status = nil
	
	if self.config.id then
		local existing_id = state.find_by_persistent_id(self.config.id)
		if existing_id then
			event_id = existing_id
			existing_status = state.get_event_status(event_id)
		else
			event_id = self.config.id
		end
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

		state.set_event_status(event_id, {
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

		state.set_event_status(event_id, {
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

	local event_status = state.get_event_status(event_id)
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

