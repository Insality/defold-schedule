local time_utils = require("schedule.internal.schedule_time")
local state = require("schedule.internal.schedule_state")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local processor = require("schedule.internal.schedule_processor")


---@class schedule.event
---@field state schedule.event.state
local M = {}


---Create event instance
---@param event_state schedule.event.state
---@return schedule.event|nil event Event instance
function M.create(event_state)
	local self = setmetatable({}, { __index = M })
	self.state = event_state
	return self
end


---Get event ID
---@return string id Event ID
function M:get_id()
	return self.state.event_id
end


---Get event status
---@return string status Event status ("pending", "active", "completed", etc.)
function M:get_status()
	return self.state.status or "pending"
end


---Get time left until event ends
---@return number time_left Returns -1 for infinity events, 0 for completed events, or remaining seconds
function M:get_time_left()
	local status = self:get_status()
	local current_time = time_utils.get_time()

	if self.state.infinity and status == "active" then
		return -1
	end

	if status == "completed" then
		if not self.state.end_time then
			return 0
		end
		return math.max(0, self.state.end_time - current_time)
	end

	if status == "pending" then
		if self.state.infinity then
			return -1
		end
		if self.state.end_time and self.state.start_time then
			return math.max(0, self.state.end_time - self.state.start_time)
		end
		return 0
	end

	if status == "active" then
		if not self.state.end_time then
			return -1
		end
		return math.max(0, self.state.end_time - current_time)
	end

	return 0
end


---Get time until event starts
---@return number time_to_start Time in seconds until event starts
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
---@return any payload Event payload data
function M:get_payload()
	return self.state.payload
end


---Get event category
---@return string|nil category Event category or nil
function M:get_category()
	return self.state.category
end


---Get event start time
---@return number|nil start_time Event start time in seconds or nil
function M:get_start_time()
	return self.state.start_time
end


---Force finish this event. Sets status to "completed" and triggers lifecycle callbacks.
---Works on active, pending, paused, or any other status. If event is pending, it will be started first.
---@return boolean success True if event was finished
function M:finish()
	local event_id = self.state.event_id
	if not event_id then
		return false
	end

	local event_status = state.get_event_state(event_id)
	if not event_status then
		return false
	end
	local current_time = time_utils.get_time()
	local event_data = { id = event_id, category = event_status.category, payload = event_status.payload }

	if event_status.status == "pending" or event_status.status == "cancelled" or event_status.status == "aborted" or event_status.status == "failed" or event_status.status == "paused" then
		if not event_status.start_time then
			event_status.start_time = current_time
		end
		lifecycle.on_start(event_id, event_data)
		lifecycle.on_enabled(event_id, event_data)
	end

	event_status.status = "completed"
	event_status.last_update_time = current_time
	if not event_status.start_time then
		event_status.start_time = current_time
	end
	if not event_status.end_time then
		event_status.end_time = current_time
	end
	state.set_event_state(event_id, event_status)
	self.state = event_status

	lifecycle.on_end(event_id, event_data)
	lifecycle.on_disabled(event_id, event_data)

	return true
end


---Force start this event. Sets status to "active" and triggers lifecycle callbacks.
---Works on pending, cancelled, aborted, failed, or paused events.
---@return boolean success True if event was started
function M:start()
	local event_id = self.state.event_id
	if not event_id then
		return false
	end

	local event_status = state.get_event_state(event_id)
	if not event_status then
		return false
	end

	if event_status.status == "active" or event_status.status == "completed" then
		return false
	end

	local current_time = time_utils.get_time()
	if not event_status.start_time then
		event_status.start_time = current_time
	end

	event_status.status = "active"
	event_status.last_update_time = current_time
	if event_status.infinity then
		event_status.end_time = nil
	else
		local end_time = processor.calculate_end_time(event_status, event_status.start_time)
		event_status.end_time = end_time
	end
	state.set_event_state(event_id, event_status)
	self.state = event_status

	local event_data = { id = event_id, category = event_status.category, payload = event_status.payload }
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)

	return true
end


---Cancel this event. Sets status to "cancelled".
---Works on any status except "completed".
---@return boolean success True if event was cancelled
function M:cancel()
	local event_id = self.state.event_id
	if not event_id then
		return false
	end

	local event_status = state.get_event_state(event_id)
	if not event_status then
		return false
	end

	if event_status.status == "completed" then
		return false
	end

	event_status.status = "cancelled"
	event_status.last_update_time = time_utils.get_time()
	state.set_event_state(event_id, event_status)
	self.state = event_status

	return true
end


---Pause this event. Sets status to "paused" and preserves current state.
---Only works on active events.
---@return boolean success True if event was paused
function M:pause()
	local event_id = self.state.event_id
	if not event_id then
		return false
	end

	local event_status = state.get_event_state(event_id)
	if not event_status then
		return false
	end

	if event_status.status ~= "active" then
		return false
	end

	event_status.status = "paused"
	event_status.last_update_time = time_utils.get_time()
	state.set_event_state(event_id, event_status)
	self.state = event_status

	return true
end


---Resume this paused event. Sets status back to "active".
---Only works on paused events.
---@return boolean success True if event was resumed
function M:resume()
	local event_id = self.state.event_id
	if not event_id then
		return false
	end

	local event_status = state.get_event_state(event_id)
	if not event_status then
		return false
	end

	if event_status.status ~= "paused" then
		return false
	end

	event_status.status = "active"
	event_status.last_update_time = time_utils.get_time()
	state.set_event_state(event_id, event_status)
	self.state = event_status

	local event_data = { id = event_id, category = event_status.category, payload = event_status.payload }
	lifecycle.on_enabled(event_id, event_data)

	return true
end


return M

