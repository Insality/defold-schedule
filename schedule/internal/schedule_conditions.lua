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
	return M._check(name, data, false)
end


---Evaluate a single condition, optionally without logging an unregistered name
---@param name string Condition name
---@param data any Data passed to the evaluator
---@param is_quiet boolean True to skip the error log for an unregistered condition
---@return boolean is_passed False if the condition fails or is not registered
function M._check(name, data, is_quiet)
	local evaluator = conditions[name]
	if not evaluator then
		if not is_quiet then
			logger:error("Condition not found", { name = name })
		end
		return false
	end

	return not not evaluator(data)
end


---Walk the event conditions in declaration order and report every failed one.
---@param event_status schedule.event.state
---@param is_quiet boolean True to skip the error log for unregistered conditions
---@param on_failed fun(condition_data: schedule.condition_data): boolean|nil Return true to stop the walk
function M._for_each_failed(event_status, is_quiet, on_failed)
	if not event_status.conditions then
		return
	end

	for _, condition_data in ipairs(event_status.conditions) do
		if not M._check(condition_data.name, condition_data.data, is_quiet) then
			if on_failed(condition_data) then
				return
			end
		end
	end
end


---Evaluate all conditions for an event
---@param event_status schedule.event.state
---@return boolean all_passed
---@return string|nil failed_condition_name
function M.evaluate_conditions(event_status)
	local failed_name = nil
	M._for_each_failed(event_status, false, function(condition_data)
		failed_name = condition_data.name
		return true
	end)

	return failed_name == nil, failed_name
end


---Collect every condition of the event that fails right now, in declaration order.
---Does not stop on the first failure, does not apply `abort_on_fail` and does not change the state.
---An unregistered condition counts as failed and is not logged as an error.
---The list and its entries are new tables, `data` is the same value the event was declared with: read it, do not change it.
---@param event_status schedule.event.state
---@return schedule.condition_data[] failed_conditions `{ name, data }` entries, empty when all pass
function M.get_failed_conditions(event_status)
	local failed = {}
	M._for_each_failed(event_status, true, function(condition_data)
		table.insert(failed, {
			name = condition_data.name,
			data = condition_data.data,
		})
	end)

	return failed
end


---Reset conditions
function M.reset()
	conditions = {}
end


return M

