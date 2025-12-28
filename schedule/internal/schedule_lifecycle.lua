---Lifecycle callback management
---Callbacks cannot be serialized, so they are stored in memory only
local logger = require("schedule.internal.schedule_logger")
local queue = require("event.queue")


local M = {}


---Internal callback storage
---@type table<string, table<string, function|string>>
local callbacks = {}


---Event queue for emitting events
M.event_queue = queue.create()


---Register callback for event
---@param event_id string
---@param callback_type "on_start"|"on_enabled"|"on_disabled"|"on_end"
---@param callback function|string|nil
function M.register_callback(event_id, callback_type, callback)
	if not callbacks[event_id] then
		callbacks[event_id] = {}
	end
	callbacks[event_id][callback_type] = callback
end


---Get callback for event
---@param event_id string
---@param callback_type "on_start"|"on_enabled"|"on_disabled"|"on_end"
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


---Push event to queue
---@param callback_type string Lifecycle callback type ("active", "start", "end", "disabled")
---@param event_data table Event data to push
function M.push_event(callback_type, event_data)
	M.event_queue:push({
		callback_type = callback_type,
		id = event_data.id,
		category = event_data.category,
		payload = event_data.payload,
		status = event_data.status,
		start_time = event_data.start_time,
		end_time = event_data.end_time
	})
end


---Call lifecycle callback safely
---@param callback function|nil
---@param event_data table Event data to pass
---@param callback_name string Name for logging
function M.call_callback(callback, event_data, callback_name)
	if not callback then
		return
	end

	local success, err = pcall(callback, event_data)
	if not success then
		logger:error("Lifecycle callback failed", {
			callback = callback_name,
			error = tostring(err),
			event_id = event_data.id
		})
	end
end


---Trigger on_start callback
---@param event_id string
---@param event_data table
function M.on_start(event_id, event_data)
	logger:info("Lifecycle: on_start", { event_id = event_id, category = event_data.category })
	local callback = M.get_callback(event_id, "on_start")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_start")
	end
end


---Trigger on_enabled callback
---@param event_id string
---@param event_data table
function M.on_enabled(event_id, event_data)
	logger:info("Lifecycle: on_enabled", { event_id = event_id, category = event_data.category })
	if event_data.status == "active" then
		M.push_event("active", event_data)
	end
	local callback = M.get_callback(event_id, "on_enabled")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_enabled")
	end
end


---Trigger on_disabled callback
---@param event_id string
---@param event_data table
function M.on_disabled(event_id, event_data)
	logger:info("Lifecycle: on_disabled", { event_id = event_id, category = event_data.category })
	local callback = M.get_callback(event_id, "on_disabled")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_disabled")
	end
end


---Trigger on_end callback
---@param event_id string
---@param event_data table
function M.on_end(event_id, event_data)
	logger:info("Lifecycle: on_end", { event_id = event_id, category = event_data.category })
	local callback = M.get_callback(event_id, "on_end")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_end")
	end
end


return M
