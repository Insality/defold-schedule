---Lifecycle callback management
---Callbacks cannot be serialized, so they are stored in memory only
local logger = require("schedule.internal.schedule_logger")


local M = {}


---Internal callback storage
---@type table<string, table<string, function|string>>
local callbacks = {}


---Register callback for event
---@param event_id string
---@param callback_type "on_start"|"on_enabled"|"on_disabled"|"on_end"|"on_fail"
---@param callback function|string|nil
function M.register_callback(event_id, callback_type, callback)
	if not callbacks[event_id] then
		callbacks[event_id] = {}
	end
	callbacks[event_id][callback_type] = callback
end


---Get callback for event
---@param event_id string
---@param callback_type "on_start"|"on_enabled"|"on_disabled"|"on_end"|"on_fail"
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


---Reset all callbacks
function M.reset_callbacks()
	callbacks = {}
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
	local callback = M.get_callback(event_id, "on_start")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_start")
	end
end


---Trigger on_enabled callback
---@param event_id string
---@param event_data table
function M.on_enabled(event_id, event_data)
	local callback = M.get_callback(event_id, "on_enabled")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_enabled")
	end
end


---Trigger on_disabled callback
---@param event_id string
---@param event_data table
function M.on_disabled(event_id, event_data)
	local callback = M.get_callback(event_id, "on_disabled")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_disabled")
	end
end


---Trigger on_end callback
---@param event_id string
---@param event_data table
function M.on_end(event_id, event_data)
	local callback = M.get_callback(event_id, "on_end")
	if callback and type(callback) == "function" then
		M.call_callback(callback, event_data, "on_end")
	end
end


---Trigger on_fail callback
---@param event_id string
---@param event_data table
---@return string|nil action "cancel", "abort", or nil
function M.on_fail(event_id, event_data)
	local on_fail_value = M.get_callback(event_id, "on_fail")
	if not on_fail_value then
		return nil
	end

	local on_fail_type = type(on_fail_value)

	if on_fail_type == "string" then
		return on_fail_value
	elseif on_fail_type == "function" then
		M.call_callback(on_fail_value, event_data, "on_fail")
		return nil
	end

	return nil
end


return M

