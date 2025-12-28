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
---@param event_status schedule.event_status|nil
---@return number|nil start_time
function M.calculate_start_time(event_config, current_time, event_status)
	if event_config.start_at then
		local start_at = event_config.start_at
		if type(start_at) == "string" then
			return time_utils.parse_iso_date(start_at)
		elseif type(start_at) == "number" then
			return start_at
		end
		return nil
	elseif event_config.after then
		local after = event_config.after
		if type(after) == "string" then
			local can_start, chain_time = chaining.can_start_chain(after, event_config, current_time)
			if can_start and chain_time then
				return chain_time
			end
			return nil
		elseif type(after) == "number" then
			return current_time + after
		end
		return nil
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
		local end_at = event_config.end_at
		if type(end_at) == "string" then
			return time_utils.parse_iso_date(end_at)
		elseif type(end_at) == "number" then
			return end_at
		end
		return nil
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
function M.should_start_event(event_id, event_config, current_time)
	local event_status = state.get_event_status(event_id)
	if event_status and event_status.status ~= "pending" and event_status.status ~= "cancelled" and event_status.status ~= "aborted" and event_status.status ~= "failed" then
		return false
	end

	local start_time = event_status and event_status.start_time
	if not start_time then
		return false
	end

	if start_time > current_time then
		return false
	end

	if type(event_config.after) == "string" then
		local after_event_id = event_config.after
		assert(type(after_event_id) == "string", "after_event_id must be string")
		local can_start, chain_time = chaining.can_start_chain(after_event_id, event_config, current_time)
		if not can_start then
			return false
		end
		if chain_time and chain_time > current_time then
			return false
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
		return false
	end

	if event_config.min_time then
		local end_time = M.calculate_end_time(event_config, start_time)
		if end_time then
			local remaining = end_time - current_time
			if remaining < event_config.min_time then
				return false
			end
		end
	end

	return true
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
	if not event_status then
		return false
	end

	if event_status.status == "pending" then
		local start_time = event_status.start_time
		if start_time and current_time >= start_time then
			local end_time = M.calculate_end_time(event_config, start_time)
			if end_time and current_time >= end_time then
				event_status.status = "completed"
				event_status.start_time = start_time
				event_status.end_time = end_time
				event_status.last_update_time = current_time
				state.set_event_status(event_id, event_status)
				lifecycle.on_start(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
				lifecycle.on_enabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
				lifecycle.on_end(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
				lifecycle.on_disabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
				return true
			end
		end
	end

	if event_status.status == "active" then
		local end_time = event_status.end_time
		if end_time and current_time >= end_time then
			event_status.status = "completed"
			event_status.last_update_time = current_time
			state.set_event_status(event_id, event_status)
			lifecycle.on_end(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
			lifecycle.on_disabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
			return true
		end
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
		local next_cycle_time = event_status.next_cycle_time
		if not next_cycle_time then
			next_cycle_time = cycles.calculate_next_cycle(
				event_config.cycle,
				current_time,
				event_status.end_time,
				event_status.start_time
			)
		end

		if next_cycle_time and next_cycle_time <= current_time then
			local skip_missed = event_config.cycle.skip_missed
			local catch_up = event_config.catch_up

			if skip_missed then
				while next_cycle_time and next_cycle_time < current_time do
					next_cycle_time = cycles.calculate_next_cycle(
						event_config.cycle,
						current_time,
						next_cycle_time,
						event_status.start_time
					)
				end
			elseif catch_up and not skip_missed then
				local processed_cycles = {}
				local cycle_start = next_cycle_time
				while cycle_start and cycle_start <= current_time do
					table.insert(processed_cycles, cycle_start)
					local cycle_end = M.calculate_end_time(event_config, cycle_start)
					if cycle_end then
						local next_cycle = cycles.calculate_next_cycle(
							event_config.cycle,
							current_time,
							cycle_end,
							event_status.start_time
						)
						if next_cycle and next_cycle > current_time then
							next_cycle_time = next_cycle
							break
						elseif next_cycle then
							cycle_start = next_cycle
						else
							break
						end
					else
						break
					end
				end

				if #processed_cycles > 0 then
					for i, cycle_time in ipairs(processed_cycles) do
						if cycle_time then
							local new_start_time = cycle_time
							local new_end_time = M.calculate_end_time(event_config, new_start_time)
							if new_end_time then
								event_status.status = "active"
								event_status.start_time = new_start_time
								event_status.end_time = new_end_time
								event_status.cycle_count = (event_status.cycle_count or 0) + 1
								state.set_event_status(event_id, event_status)

								lifecycle.on_start(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
								lifecycle.on_enabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })

								if current_time >= new_end_time then
									event_status.status = "completed"
									event_status.last_update_time = current_time
									state.set_event_status(event_id, event_status)
									lifecycle.on_end(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
									lifecycle.on_disabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
								end
							end
						end
					end

					if next_cycle_time and next_cycle_time > current_time then
						event_status.next_cycle_time = next_cycle_time
						state.set_event_status(event_id, event_status)
					else
						event_status.next_cycle_time = nil
						state.set_event_status(event_id, event_status)
					end

					return true
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

		if next_cycle_time and next_cycle_time > current_time then
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
		if event_config.catch_up and last_update_time then
			M.process_catchup(event_id, event_config, last_update_time, current_time)
		end

		local start_time = event_status.start_time
		if not start_time then
			start_time = M.calculate_start_time(event_config, current_time, event_status)
			if start_time then
				event_status.start_time = start_time
				state.set_event_status(event_id, event_status)
			end
		end

		if type(event_config.after) == "string" then
			local after_event_id = event_config.after
			assert(type(after_event_id) == "string", "after_event_id must be string")
			local after_status = state.get_event_status(after_event_id)
			if after_status and after_status.status == "completed" and after_status.end_time then
				if not start_time or start_time < after_status.end_time then
					start_time = after_status.end_time
					event_status.start_time = start_time
					state.set_event_status(event_id, event_status)
				end
			end
		end

		if start_time and current_time >= start_time then
			local should_start = M.should_start_event(event_id, event_config, current_time)
			if should_start then
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
	end

	if event_status.status == "active" then
		if not event_config.catch_up or not last_update_time then
			local end_time = event_status.end_time
			if end_time and current_time >= end_time then
				event_status.status = "completed"
				event_status.last_update_time = current_time
				state.set_event_status(event_id, event_status)

				lifecycle.on_end(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })
				lifecycle.on_disabled(event_config, { id = event_id, category = event_config.category, payload = event_config.payload })

				if event_config.cycle then
					M.process_cycle(event_id, event_config, current_time)
				end

				return true
			end
		else
			if M.process_catchup(event_id, event_config, last_update_time, current_time) then
				if event_config.cycle then
					M.process_cycle(event_id, event_config, current_time)
				end
				return true
			end
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

