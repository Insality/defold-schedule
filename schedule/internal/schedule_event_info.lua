local config = require("schedule.internal.schedule_config")
local state = require("schedule.internal.schedule_state")
local time_utils = require("schedule.internal.schedule_time")


---@class schedule.event_info
---@field event_id string
---@field event_config schedule.event_config|nil
---@field event_status schedule.event_status|nil
---@field get_status fun(self: schedule.event_info): string
---@field get_time_left fun(self: schedule.event_info): number
---@field get_time_to_start fun(self: schedule.event_info): number
---@field get_payload fun(self: schedule.event_info): any
---@field get_category fun(self: schedule.event_info): string|nil

local M = {}


---Create event info object
---@param event_id string
---@return schedule.event_info|nil
function M.create(event_id)
	local event_config = config.get_event_config(event_id)
	local event_status = state.get_event_status(event_id)

	if not event_config and not event_status then
		return nil
	end

	local event_info = {
		event_id = event_id,
		event_config = event_config,
		event_status = event_status
	}

	setmetatable(event_info, { __index = M })
	return event_info
end


---Get event status
---@return string
function M:get_status()
	if not self.event_status then
		return "pending"
	end
	return self.event_status.status or "pending"
end


---Get time left until event ends
---@return number
function M:get_time_left()
	local status = self:get_status()
	local current_time = time_utils.get_time()

	if status == "completed" then
		if not self.event_status or not self.event_status.end_time then
			return 0
		end
		return math.max(0, self.event_status.end_time - current_time)
	end

	if status == "pending" then
		if not self.event_config or not self.event_config.duration then
			return 0
		end
		return self.event_config.duration
	end

	if status == "active" then
		if not self.event_status or not self.event_status.end_time then
			return 0
		end
		return math.max(0, self.event_status.end_time - current_time)
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
		if not self.event_status or not self.event_status.start_time then
			return 0
		end
		return math.max(0, self.event_status.start_time - current_time)
	end

	return 0
end


---Get event payload
---@return any
function M:get_payload()
	if not self.event_config then
		return nil
	end
	return self.event_config.payload
end


---Get event category
---@return string|nil
function M:get_category()
	if not self.event_config then
		return nil
	end
	return self.event_config.category
end


return M

