---Lifecycle callback management
local logger = require("schedule.internal.schedule_logger")


local M = {}


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
---@param event_config schedule.event_config
---@param event_data table
function M.on_start(event_config, event_data)
	M.call_callback(event_config.on_start, event_data, "on_start")
end


---Trigger on_enabled callback
---@param event_config schedule.event_config
---@param event_data table
function M.on_enabled(event_config, event_data)
	M.call_callback(event_config.on_enabled, event_data, "on_enabled")
end


---Trigger on_disabled callback
---@param event_config schedule.event_config
---@param event_data table
function M.on_disabled(event_config, event_data)
	M.call_callback(event_config.on_disabled, event_data, "on_disabled")
end


---Trigger on_end callback
---@param event_config schedule.event_config
---@param event_data table
function M.on_end(event_config, event_data)
	M.call_callback(event_config.on_end, event_data, "on_end")
end


---Trigger on_fail callback
---@param event_config schedule.event_config
---@param event_data table
---@return string|nil action "cancel", "abort", or nil
function M.on_fail(event_config, event_data)
	if not event_config.on_fail then
		return nil
	end

	local on_fail_value = event_config.on_fail
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

