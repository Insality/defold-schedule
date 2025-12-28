local time_utils = require("schedule.internal.schedule_time")


---@class schedule.event
---@field state schedule.event.state
local M = {}


---Create event instance
---@param event_state schedule.event.state
---@return schedule.event|nil
function M.create(event_state)
	if not event_state then
		return nil
	end

	local self = setmetatable({}, { __index = M })
	self.state = event_state
	return self
end


---Get event ID
---@return string|nil
function M:get_id()
	return self.state.event_id
end


---Get event status
---@return string
function M:get_status()
	return self.state.status or "pending"
end


---Get time left until event ends
---@return number
function M:get_time_left()
	local status = self:get_status()
	local current_time = time_utils.get_time()

	if status == "completed" then
		if not self.state.end_time then
			return 0
		end
		return math.max(0, self.state.end_time - current_time)
	end

	if status == "pending" then
		if self.state.end_time and self.state.start_time then
			return math.max(0, self.state.end_time - self.state.start_time)
		end
		return 0
	end

	if status == "active" then
		if not self.state.end_time then
			return 0
		end
		return math.max(0, self.state.end_time - current_time)
	end

	return 0
end


---Get time until event starts
---@return number
function M:get_time_to_start()
	local status = self:get_status()
	local current_time = time_utils.get_time()

	if status == "completed" then
		return 0
	end

	if status == "pending" or status == "active" then
		if not self.state.start_time then
			return 0
		end
		return math.max(0, self.state.start_time - current_time)
	end

	return 0
end


---Get event payload
---@return any
function M:get_payload()
	return self.state.payload
end


---Get event category
---@return string|nil
function M:get_category()
	return self.state.category
end


---Get event start time
---@return number|nil
function M:get_start_time()
	return self.state.start_time
end


return M

