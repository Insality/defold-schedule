---Callback registry for lifecycle callbacks
---Callbacks cannot be serialized, so they are stored in memory only
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
function M.reset()
	callbacks = {}
end


return M

