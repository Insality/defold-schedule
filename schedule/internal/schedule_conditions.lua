---Condition system for event validation
local logger = require("schedule.internal.schedule_logger")


local M = {}


---Registered conditions
---@type table<string, fun(data: any): boolean>
local conditions = {}


---Register a condition evaluator
---@param name string Condition name
---@param evaluator fun(data: any): boolean
function M.register_condition(name, evaluator)
	conditions[name] = evaluator
	logger:debug("Condition registered", { name = name })
end


---Evaluate all conditions for an event
---@param event_status schedule.event_status
---@return boolean all_passed
---@return string|nil failed_condition_name
function M.evaluate_conditions(event_status)
	if not event_status.conditions or #event_status.conditions == 0 then
		return true, nil
	end

	for _, condition_data in ipairs(event_status.conditions) do
		local evaluator = conditions[condition_data.name]
		if not evaluator then
			logger:error("Condition not found", { name = condition_data.name })
			return false, condition_data.name
		end

		local result = evaluator(condition_data.data)
		if not result then
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

