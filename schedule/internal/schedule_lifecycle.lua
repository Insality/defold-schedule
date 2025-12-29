---Lifecycle callback management
---Callbacks cannot be serialized, so they are stored in memory only
local logger = require("schedule.internal.schedule_logger")
local queue = require("event.queue")

---@alias schedule.lifecycle.event "on_start"|"on_enabled"|"on_disabled"|"on_end"|"on_pause"|"on_resume"|"on_fail"

local M = {}


---Internal callback storage
---@type table<string, table<string, function|string>>
local callbacks = {}


---Event queue for emitting events
M.event_queue = queue.create()


---Register callback for event
---@param event_id string
---@param callback_type schedule.lifecycle.event
---@param callback function?
function M.register_callback(event_id, callback_type, callback)
	if not callback then
		return
	end

	if not callbacks[event_id] then
		callbacks[event_id] = {}
	end
	callbacks[event_id][callback_type] = callback
end


---Get callback for event
---@param event_id string
---@param callback_type schedule.lifecycle.event
---@return function|string|nil
function M.get_callback(event_id, callback_type)
	if not callbacks[event_id] then
		return nil
	end
	return callbacks[event_id][callback_type]
end


---Clear all callbacks for event
---@param event_id string
function M.clear_callbacks(event_id)
	callbacks[event_id] = nil
end


---Reset all callbacks and clear event queue
function M.reset_callbacks()
	callbacks = {}
	M.event_queue:clear()
end


---Mapping from callback type to event type
local CALLBACK_TO_EVENT = {
	on_start = "start",
	on_enabled = "enabled",
	on_disabled = "disabled",
	on_end = "end",
	on_pause = "paused",
	on_resume = "resume",
	on_fail = "fail"
}


---Push event to queue
---@param event_type string Event type ("start", "end", "enabled", "disabled", "paused", "resume", "fail", "active")
---@param event_data table Event data to push
function M.push_event(event_type, event_data)
	M.event_queue:push({
		callback_type = event_type,
		id = event_data.id,
		category = event_data.category,
		payload = event_data.payload,
		status = event_data.status,
		start_time = event_data.start_time,
		end_time = event_data.end_time
	})
end


---Call lifecycle callback safely and push event to queue
---@param event_id string
---@param callback_type schedule.lifecycle.event
---@param event_data table Event data to pass
function M.trigger_callback(event_id, callback_type, event_data)
	logger:info("Schedule event: " .. callback_type, { event_id = event_id, category = event_data.category })

	local callback = M.get_callback(event_id, callback_type)
	if callback then
		local success, err = pcall(callback, event_data)
		if not success then
			logger:error("Lifecycle callback failed", {
				callback = callback_type,
				error = tostring(err),
				event_id = event_data.id
			})
		end
	end

	local event_type = CALLBACK_TO_EVENT[callback_type]
	if event_type then
		M.push_event(event_type, event_data)
	end
end


---Trigger on_start callback
---@param event_id string
---@param event_data table
function M.on_start(event_id, event_data)
	M.trigger_callback(event_id, "on_start", event_data)
end


---Trigger on_enabled callback
---@param event_id string
---@param event_data table
function M.on_enabled(event_id, event_data)
	M.trigger_callback(event_id, "on_enabled", event_data)
	if event_data.status == "active" then
		M.push_event("active", event_data)
	end
end


---Trigger on_disabled callback
---@param event_id string
---@param event_data table
function M.on_disabled(event_id, event_data)
	M.trigger_callback(event_id, "on_disabled", event_data)
end


---Trigger on_end callback
---@param event_id string
---@param event_data table
function M.on_end(event_id, event_data)
	M.trigger_callback(event_id, "on_end", event_data)
end


---Trigger on_pause callback
---@param event_id string
---@param event_data table
function M.on_pause(event_id, event_data)
	M.trigger_callback(event_id, "on_pause", event_data)
end


---Trigger on_resume callback
---@param event_id string
---@param event_data table
function M.on_resume(event_id, event_data)
	M.trigger_callback(event_id, "on_resume", event_data)
end


---Trigger on_fail callback
---@param event_id string
---@param event_data table
function M.on_fail(event_id, event_data)
	M.trigger_callback(event_id, "on_fail", event_data)
end


return M
