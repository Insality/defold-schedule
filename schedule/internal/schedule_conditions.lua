---Condition system for event validation
local logger = require("schedule.internal.schedule_logger")


local M = {}


---Registered conditions
---@type table<string, fun(data: any): boolean>
local conditions = {}


---Register a condition evaluator
---@param name string Condition name
---@param evaluator (fun(data: any): boolean)|nil Evaluator function, nil to unregister
function M.register_condition(name, evaluator)
	conditions[name] = evaluator
	logger:debug(evaluator and "Condition registered" or "Condition unregistered", { name = name })
end


---Check if a condition with this name is registered
---@param name string Condition name
---@return boolean is_registered
function M.is_registered(name)
	return conditions[name] ~= nil
end


---Evaluate a single registered condition with the given data
---@param name string Condition name
---@param data any Data passed to the evaluator
---@return boolean is_passed False if the condition fails or is not registered
function M.check_condition(name, data)
	local evaluator = conditions[name]
	if not evaluator then
		logger:error("Condition not found", { name = name })
		return false
	end

	return not not evaluator(data)
end


---Evaluate all conditions for an event
---@param event_status schedule.event.state
---@return boolean all_passed
---@return string|nil failed_condition_name
function M.evaluate_conditions(event_status)
	if not event_status.conditions or #event_status.conditions == 0 then
		return true, nil
	end

	for _, condition_data in ipairs(event_status.conditions) do
		if not M.check_condition(condition_data.name, condition_data.data) then
			return false, condition_data.name
		end
	end

	return true, nil
end


---Reset conditions
function M.reset()
	conditions = {}
end


return M

