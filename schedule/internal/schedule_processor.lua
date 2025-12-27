---Event processor - main update loop
local config = require("schedule.internal.schedule_config")
local state = require("schedule.internal.schedule_state")
local time_utils = require("schedule.internal.schedule_time")
local cycles = require("schedule.internal.schedule_cycles")
local conditions = require("schedule.internal.schedule_conditions")
local chaining = require("schedule.internal.schedule_chaining")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local logger = require("schedule.internal.schedule_logger")


local M = {}


---Calculate event start time
---@param event_config schedule.event_config
---@param current_time number
---@return number|nil start_time
function M.calculate_start_time(event_config, current_time)
	if event_config.start_at then
		if type(event_config.start_at) == "string" then
			return time_utils.parse_iso_date(event_config.start_at)
		else
			return event_config.start_at
		end
	elseif event_config.after then
		if type(event_config.after) == "string" then
			local can_start, chain_time = chaining.can_start_chain(event_config.after, event_config, current_time)
			if can_start and chain_time then
				return chain_time
			end
			return nil
		else
			return current_time + event_config.after
		end
	end
	return current_time
end


---Calculate event end time
---@param event_config schedule.event_config
---@param start_time number
---@return number|nil end_time
function M.calculate_end_time(event_config, start_time)
	if event_config.infinity then
		return nil
	end

	if event_config.end_at then
		if type(event_config.end_at) == "string" then
			return time_utils.parse_iso_date(event_config.end_at)
		else
			return event_config.end_at
		end
	elseif event_config.duration then
		return start_time + event_config.duration
	end

	return nil
end


---Check if event should start
---@param event_id string
---@param event_config schedule.event_config
---@param current_time number
---@return boolean should_start
---@return number|nil start_time
function M.should_start_event(event_id, event_config, current_time)
	local event_status = state.get_event_status(event_id)
	if event_status and event_status.status ~= "pending" and event_status.status ~= "cancelled" and event_status.status ~= "aborted" and event_status.status ~= "failed" then
		return false, nil
	end

	local start_time = M.calculate_start_time(event_config, current_time)
	if not start_time or start_time > current_time then
		return false, nil
	end

	if event_config.min_time then
		local end_time = M.calculate_end_time(event_config, start_time)
		if end_time then
			local remaining = end_time - current_time
			if remaining < event_config.min_time then
				return false, nil
			end
		end
	end

	local all_conditions_passed, failed_condition = conditions.evaluate_conditions(event_config)
	if not all_conditions_passed then
		local fail_action = lifecycle.on_fail(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
		if fail_action == "cancel" then
			local status = state.get_event_status(event_id) or {}
			status.status = "cancelled"
			state.set_event_status(event_id, status)
		elseif fail_action == "abort" then
			local status = state.get_event_status(event_id) or {}
			status.status = "aborted"
			state.set_event_status(event_id, status)
		else
			local status = state.get_event_status(event_id) or {}
			status.status = "failed"
			state.set_event_status(event_id, status)
		end
		return false, nil
	end

	if type(event_config.after) == "string" then
		local can_start, chain_time = chaining.can_start_chain(event_config.after, event_config, current_time)
		if not can_start then
			return false, nil
		end
		if chain_time then
			start_time = chain_time
		end
	end

	return true, start_time
end


---Process catch-up for offline period
---@param event_id string
---@param event_config schedule.event_config
---@param last_update_time number|nil
---@param current_time number
---@return boolean was_caught_up
function M.process_catchup(event_id, event_config, last_update_time, current_time)
	if not event_config.catch_up or not last_update_time then
		return false
	end

	local event_status = state.get_event_status(event_id)
	if not event_status or event_status.status ~= "active" then
		return false
	end

	local end_time = event_status.end_time
	if not end_time then
		return false
	end

	if current_time >= end_time then
		event_status.status = "completed"
		event_status.end_time = end_time
		state.set_event_status(event_id, event_status)
		lifecycle.on_end(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
		lifecycle.on_disabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
		return true
	end

	return false
end


---Process cycle for event
---@param event_id string
---@param event_config schedule.event_config
---@param current_time number
---@return boolean cycle_processed
function M.process_cycle(event_id, event_config, current_time)
	if not event_config.cycle then
		return false
	end

	local event_status = state.get_event_status(event_id)
	if not event_status then
		return false
	end

	if event_status.status == "completed" then
		local next_cycle_time = cycles.calculate_next_cycle(
			event_config.cycle,
			current_time,
			event_status.end_time,
			event_status.start_time
		)

		if next_cycle_time and next_cycle_time <= current_time then
			local catch_up = event_config.catch_up
			if catch_up or (event_config.cycle.skip_missed and next_cycle_time < current_time) then
				if event_config.cycle.skip_missed then
					while next_cycle_time and next_cycle_time < current_time do
						next_cycle_time = cycles.calculate_next_cycle(
							event_config.cycle,
							current_time,
							next_cycle_time,
							event_status.start_time
						)
					end
				end

				if next_cycle_time and next_cycle_time <= current_time then
					local new_start_time = next_cycle_time
					local new_end_time = M.calculate_end_time(event_config, new_start_time)

					event_status.status = "active"
					event_status.start_time = new_start_time
					event_status.end_time = new_end_time
					event_status.cycle_count = (event_status.cycle_count or 0) + 1
					event_status.next_cycle_time = nil
					state.set_event_status(event_id, event_status)

					lifecycle.on_start(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
					lifecycle.on_enabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
					return true
				end
			end
		end

		if next_cycle_time then
			event_status.next_cycle_time = next_cycle_time
			state.set_event_status(event_id, event_status)
		end
	end

	return false
end


---Update single event
---@param event_id string
---@param event_config schedule.event_config
---@param current_time number
---@param last_update_time number|nil
---@return boolean event_updated
function M.update_event(event_id, event_config, current_time, last_update_time)
	local event_status = state.get_event_status(event_id)

	if not event_status then
		event_status = {
			status = "pending",
			start_time = nil,
			end_time = nil,
			last_update_time = nil,
			cycle_count = 0,
			next_cycle_time = nil
		}
		state.set_event_status(event_id, event_status)
	end

	if event_status.status == "pending" or event_status.status == "cancelled" or event_status.status == "aborted" or event_status.status == "failed" then
		local should_start, start_time = M.should_start_event(event_id, event_config, current_time)
		if should_start and start_time then
			local end_time = M.calculate_end_time(event_config, start_time)
			event_status.status = "active"
			event_status.start_time = start_time
			event_status.end_time = end_time
			event_status.last_update_time = current_time
			state.set_event_status(event_id, event_status)

			lifecycle.on_start(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
			lifecycle.on_enabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
			return true
		end
	end

	if event_status.status == "active" then
		if M.process_catchup(event_id, event_config, last_update_time, current_time) then
			return true
		end

		local end_time = event_status.end_time
		if end_time and current_time >= end_time then
			event_status.status = "completed"
			event_status.last_update_time = current_time
			state.set_event_status(event_id, event_status)

			lifecycle.on_end(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
			lifecycle.on_disabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })

			if event_config.cycle then
				local next_cycle_time = cycles.calculate_next_cycle(
					event_config.cycle,
					current_time,
					event_status.end_time,
					event_status.start_time
				)
				if next_cycle_time and next_cycle_time <= current_time then
					M.process_cycle(event_id, event_config, current_time)
				elseif next_cycle_time then
					event_status.next_cycle_time = next_cycle_time
					state.set_event_status(event_id, event_status)
				end
			end

			return true
		end
	end

	if event_status.status == "completed" and event_config.cycle then
		local next_cycle_time = event_status.next_cycle_time
		if next_cycle_time and current_time >= next_cycle_time then
			return M.process_cycle(event_id, event_config, current_time)
		elseif not next_cycle_time then
			local cycle_time = cycles.calculate_next_cycle(
				event_config.cycle,
				current_time,
				event_status.end_time,
				event_status.start_time
			)
			if cycle_time and cycle_time <= current_time then
				return M.process_cycle(event_id, event_config, current_time)
			elseif cycle_time then
				event_status.next_cycle_time = cycle_time
				state.set_event_status(event_id, event_status)
			end
		end
	end

	event_status.last_update_time = current_time
	state.set_event_status(event_id, event_status)
	return false
end


---Update all events
---@param current_time number
function M.update_all(current_time)
	local last_update_time = state.get_last_update_time()
	local all_events = config.get_all_events()
	local any_updated = false

	for event_id, event_config in pairs(all_events) do
		local updated = M.update_event(event_id, event_config, current_time, last_update_time)
		if updated then
			any_updated = true
		end
	end

	state.set_last_update_time(current_time)
	return any_updated
end


return M

