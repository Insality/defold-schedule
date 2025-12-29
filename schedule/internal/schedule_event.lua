local time = require("schedule.internal.schedule_time")
local state = require("schedule.internal.schedule_state")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local processor = require("schedule.internal.schedule_processor")


---@class schedule.event
---@field state schedule.event.state
local M = {}


---Create event instance
---@param event_state schedule.event.state
---@return schedule.event event Event instance
function M.create(event_state)
	return setmetatable({ state = event_state }, { __index = M })
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
	local current_time = time.get_time()

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
	local current_time = time.get_time()

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


---Get event progress
---@return number progress Progress value between 0 and 1
function M:get_progress()
	local status = self:get_status()
	local current_time = time.get_time()

	if status == "completed" then
		return 1
	end

	if status == "pending" then
		return 0
	end

	if status == "active" or status == "paused" then
		if self.state.infinity or not self.state.end_time then
			return 0
		end
		if not self.state.start_time then
			return 0
		end
		local duration = self.state.end_time - self.state.start_time
		if duration <= 0 then
			return 1
		end
		local elapsed = current_time - self.state.start_time
		return math.max(0, math.min(1, elapsed / duration))
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

	local event_state = state.get_event_state(event_id)
	if not event_state then
		return false
	end
	local current_time = time.get_time()
	local event_data = { event_id = event_id, category = event_state.category, payload = event_state.payload }

	if event_state.status == "pending" or event_state.status == "cancelled" or event_state.status == "aborted" or event_state.status == "failed" or event_state.status == "paused" then
		if not event_state.start_time then
			event_state.start_time = current_time
		end
		lifecycle.on_start(event_id, event_data)
		lifecycle.on_enabled(event_id, event_data)
	end

	event_state.status = "completed"
	event_state.last_update_time = current_time
	event_state.start_time = event_state.start_time or current_time
	event_state.end_time = event_state.end_time or current_time
	self.state = event_state

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

	local event_state = state.get_event_state(event_id)
	if not event_state then
		return false
	end

	if event_state.status == "active" or event_state.status == "completed" then
		return false
	end

	local current_time = time.get_time()
	if not event_state.start_time then
		event_state.start_time = current_time
	end

	event_state.status = "active"
	event_state.last_update_time = current_time
	if event_state.infinity then
		event_state.end_time = nil
	else
		local end_time = processor.calculate_end_time(event_state, event_state.start_time)
		event_state.end_time = end_time
	end

	self.state = event_state

	local event_data = { event_id = event_id, category = event_state.category, payload = event_state.payload }
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

	local event_state = state.get_event_state(event_id)
	if not event_state then
		return false
	end

	if event_state.status == "completed" then
		return false
	end

	event_state.status = "cancelled"
	event_state.last_update_time = time.get_time()
	self.state = event_state

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

	local event_state = state.get_event_state(event_id)
	if not event_state then
		return false
	end

	if event_state.status ~= "active" then
		return false
	end

	event_state.status = "paused"
	event_state.last_update_time = time.get_time()
	self.state = event_state

	local event_data = {
		event_id = event_id,
		category = event_state.category,
		payload = event_state.payload,
		status = "paused",
		start_time = event_state.start_time,
		end_time = event_state.end_time
	}
	lifecycle.on_disabled(event_id, event_data)

	return true
end


---Resume this paused event. Sets status back to "active".
---Only works on paused events.
---For events with duration (not end_at), extends end_time by the pause duration.
---@return boolean success True if event was resumed
function M:resume()
	local event_id = self.state.event_id
	if not event_id then
		return false
	end

	local event_state = state.get_event_state(event_id)
	if not event_state then
		return false
	end

	if event_state.status ~= "paused" then
		return false
	end

	local current_time = time.get_time()
	local pause_start_time = event_state.last_update_time

	-- Calculate pause duration
	local pause_duration = 0
	if pause_start_time then
		pause_duration = current_time - pause_start_time
	end

	-- Extend end_time by pause duration for events with relative duration, not end_at
	if pause_duration > 0 and event_state.duration and not event_state.end_at and event_state.end_time and not event_state.infinity then
		event_state.end_time = event_state.end_time + pause_duration
	end

	event_state.status = "active"
	event_state.last_update_time = current_time
	self.state = event_state

	local event_data = {
		event_id = event_id,
		category = event_state.category,
		payload = event_state.payload,
		status = "active",
		start_time = event_state.start_time,
		end_time = event_state.end_time
	}
	lifecycle.on_enabled(event_id, event_data)

	return true
end


return M

