---Event builder for fluent API
local config = require("schedule.internal.schedule_config")
local time_utils = require("schedule.internal.schedule_time")
local logger = require("schedule.internal.schedule_logger")


local event_id_counter = 0


---@class schedule.event_builder
---@field config schedule.event_config
local M = {}


---Create new event builder
---@return schedule.event_builder
function M.create()
	---@type schedule.event_builder
	local builder = {
		config = {}
	}
	setmetatable(builder, { __index = M })
	return builder
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


---Save event and return event ID
---@return string event_id
function M:save()
	local event_id = nil
	if self.config.id then
		local existing_id = config.find_event_by_id(self.config.id)
		if existing_id then
			event_id = existing_id
			local existing_config = config.get_event_config(existing_id)
			if existing_config then
				if self.config.on_start then existing_config.on_start = self.config.on_start end
				if self.config.on_enabled then existing_config.on_enabled = self.config.on_enabled end
				if self.config.on_disabled then existing_config.on_disabled = self.config.on_disabled end
				if self.config.on_end then existing_config.on_end = self.config.on_end end
				if self.config.on_fail then existing_config.on_fail = self.config.on_fail end
				config.set_event_config(event_id, existing_config)
			end
		else
			event_id = self.config.id
			if event_id then
				config.set_event_config(event_id, self.config)
			end
		end
	else
		event_id_counter = event_id_counter + 1
		event_id = "event_" .. tostring(socket.gettime() * 1000000) .. "_" .. event_id_counter .. "_" .. math.random(1000000)
		config.set_event_config(event_id, self.config)
	end

	assert(event_id ~= nil, "Event ID must be generated")
	logger:debug("Event saved", { event_id = event_id, category = self.config.category })
	return event_id
end


return M

