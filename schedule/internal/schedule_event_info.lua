local state = require("schedule.internal.schedule_state")
local time_utils = require("schedule.internal.schedule_time")


---@class schedule.event_info
---@field event_id string
---@field get_status fun(self: schedule.event_info): string
---@field get_time_left fun(self: schedule.event_info): number
---@field get_time_to_start fun(self: schedule.event_info): number
---@field get_payload fun(self: schedule.event_info): any
---@field get_category fun(self: schedule.event_info): string|nil
---@field get_start_time fun(self: schedule.event_info): number|nil

local M = {}


---Create event info object
---@param event_id string
---@return schedule.event_info|nil
function M.create(event_id)
	local event_status = state.get_event_status(event_id)

	if not event_status then
		return nil
	end

	local event_info = {
		event_id = event_id
	}

	setmetatable(event_info, { __index = M })
	return event_info
end


---Get event status (fresh)
---@return schedule.event_status|nil
function M:_get_status()
	return state.get_event_status(self.event_id)
end


---Get event status
---@return string
function M:get_status()
	local event_status = self:_get_status()
	if not event_status then
		return "pending"
	end
	return event_status.status or "pending"
end


---Get time left until event ends
---@return number
function M:get_time_left()
	local status = self:get_status()
	local current_time = time_utils.get_time()
	local event_status = self:_get_status()
	local event_config = self:_get_config()

	if status == "completed" then
		if not event_status or not event_status.end_time then
			return 0
		end
		return math.max(0, event_status.end_time - current_time)
	end

	if status == "pending" then
		if event_status and event_status.duration then
			return event_status.duration
		end
		if event_status and event_status.end_time and event_status.start_time then
			return math.max(0, event_status.end_time - event_status.start_time)
		end
		return 0
	end

	if status == "active" then
		if not event_status or not event_status.end_time then
			return 0
		end
		return math.max(0, event_status.end_time - current_time)
	end

	return 0
end


---Get time until event starts
---@return number
function M:get_time_to_start()
	local status = self:get_status()
	local current_time = time_utils.get_time()
	local event_status = self:_get_status()

	if status == "completed" then
		return 0
	end

	if status == "pending" or status == "active" then
		if not event_status or not event_status.start_time then
			return 0
		end
		return math.max(0, event_status.start_time - current_time)
	end

	return 0
end


---Get event payload
---@return any
function M:get_payload()
	local event_status = self:_get_status()
	if not event_status then
		return nil
	end
	return event_status.payload
end


---Get event category
---@return string|nil
function M:get_category()
	local event_status = self:_get_status()
	if not event_status then
		return nil
	end
	return event_status.category
end


---Get event start time
---@return number|nil
function M:get_start_time()
	local event_status = self:_get_status()
	if not event_status then
		return nil
	end
	return event_status.start_time
end


return M

