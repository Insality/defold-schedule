---Event processor - main update loop
local state = require("schedule.internal.schedule_state")
local time = require("schedule.internal.schedule_time")
local cycles = require("schedule.internal.schedule_cycles")
local conditions = require("schedule.internal.schedule_conditions")
local chaining = require("schedule.internal.schedule_chaining")
local lifecycle = require("schedule.internal.schedule_lifecycle")

local M = {}


---Calculate event start time
---@param event_status schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time for wait_online logic
---@return number|nil start_time Calculated start time in seconds, or nil if cannot be calculated
function M.calculate_start_time(event_status, current_time, last_update_time)
	if event_status.start_at then
		local start_at = event_status.start_at
		if type(start_at) == "string" then
			return time.parse_iso_date(start_at)
		elseif type(start_at) == "number" then
			return start_at
		end
		return nil
	elseif event_status.after then
		local after = event_status.after
		if type(after) == "string" then
			local can_start, chain_time = chaining.can_start_chain(after, event_status, current_time, last_update_time)
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
---@param event_status schedule.event.state
---@param start_time number
---@return number|nil end_time Calculated end time in seconds, or nil for infinity events
function M.calculate_end_time(event_status, start_time)
	if event_status.infinity then
		return nil
	end

	if event_status.end_at then
		local end_at = event_status.end_at
		if type(end_at) == "string" then
			return time.parse_iso_date(end_at)
		elseif type(end_at) == "number" then
			return end_at
		end
		return nil
	elseif event_status.duration then
		return start_time + event_status.duration
	end

	return nil
end


---Check if event should start
---@param event_id string
---@param event_status schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time for wait_online logic
---@return boolean should_start True if event should start, false otherwise
function M.should_start_event(event_id, event_status, current_time, last_update_time)
	if not M._is_startable_status(event_status.status) then
		return false
	end

	local start_time = event_status.start_time
	if not start_time then
		return false
	end

	if start_time > current_time then
		return false
	end

	if type(event_status.after) == "string" then
		local after_event_id = event_status.after
		assert(type(after_event_id) == "string", "after_event_id must be string")
		local can_start, chain_time = chaining.can_start_chain(after_event_id, event_status, current_time, last_update_time)
		if not can_start then
			return false
		end
		if chain_time and chain_time > current_time then
			return false
		end
	end

	local all_conditions_passed, failed_condition = conditions.evaluate_conditions(event_status)
	if not all_conditions_passed then
		if event_status.abort_on_fail then
			event_status.status = "aborted"
			state.set_event_state(event_id, event_status)
			local event_data = M._create_event_data(event_id, event_status)
			lifecycle.on_fail(event_id, event_data)
		end
		return false
	end

	if event_status.min_time then
		local end_time = M.calculate_end_time(event_status, start_time)
		if end_time then
			local remaining = end_time - current_time
			if remaining <= event_status.min_time then
				M._cancel_event(event_id, event_status)
				return false
			end
		end
	end

	return true
end


---Process catch-up for offline period
---@param event_id string
---@param event_status schedule.event.state
---@param last_update_time number|nil
---@param current_time number
---@return boolean was_caught_up True if catch-up was processed, false otherwise
function M.process_catchup(event_id, event_status, last_update_time, current_time)
	if not event_status.catch_up or not last_update_time then
		return false
	end

	if event_status.status == "pending" then
		local start_time = event_status.start_time
		if start_time and current_time >= start_time then
			if not event_status.cycle then
				local end_time = M.calculate_end_time(event_status, start_time)
				if end_time and current_time >= end_time then
					event_status.status = "active"
					event_status.start_time = start_time
					event_status.end_time = end_time
					state.set_event_state(event_id, event_status)
					local event_data = M._create_event_data(event_id, event_status)
					M._trigger_event_cycle(event_id, event_data)
					event_status.status = "completed"
					event_status.start_time = start_time
					event_status.end_time = end_time
					event_status.last_update_time = current_time
					state.set_event_state(event_id, event_status)
					return true
				end
			else
				local skip_missed = event_status.cycle.skip_missed or false
				local processed_cycles, catch_count = M._collect_missed_cycles(event_status, start_time, current_time, skip_missed)

				if #processed_cycles > 0 then
					for i, cycle_data in ipairs(processed_cycles) do
						M._apply_catchup_cycle(event_id, event_status, cycle_data.start, cycle_data.end_time, current_time)
					end

					local last_cycle = processed_cycles[#processed_cycles]
					if last_cycle.end_time and current_time >= last_cycle.end_time then
						M._complete_event(event_id, event_status, last_cycle.start, last_cycle.end_time, current_time)
						return true
					else
						event_status.status = "active"
						event_status.start_time = last_cycle.start
						event_status.end_time = last_cycle.end_time
						event_status.last_update_time = current_time
						state.set_event_state(event_id, event_status)
						return true
					end
				end
			end
		end
	end

	if event_status.status == "active" then
		local end_time = event_status.end_time
		if end_time and current_time >= end_time then
			M._complete_event(event_id, event_status, nil, end_time, current_time)
			return true
		end
	end

	return false
end


---Process cycle for event
---@param event_id string
---@param event_status schedule.event.state
---@param current_time number
---@return boolean cycle_processed True if cycle was processed, false otherwise
function M.process_cycle(event_id, event_status, current_time)
	if not event_status.cycle then
		return false
	end

	if event_status.status == "completed" then
		local skip_missed = event_status.cycle.skip_missed
		local catch_up = event_status.catch_up

		if catch_up and not skip_missed then
			local processed_cycles = {}
		local anchor = event_status.cycle.anchor or "start"
		local cycle_interval = event_status.cycle.seconds
		local next_cycle_time = nil
		local max_catches = event_status.cycle.max_catches
		local catch_count = 0

		if cycle_interval and event_status.start_time then
			local base_time
			if anchor == "end" and event_status.end_time then
				base_time = event_status.end_time
			else
				base_time = event_status.start_time
			end

			local cycle_start = base_time + cycle_interval
			while cycle_start and cycle_start <= current_time do
				if max_catches and catch_count >= max_catches then
					break
				end
				local cycle_end = M.calculate_end_time(event_status, cycle_start)
					if cycle_end and cycle_end <= current_time then
						table.insert(processed_cycles, cycle_start)
						catch_count = catch_count + 1
						cycle_start = cycle_start + cycle_interval
					else
						break
					end
				end

				if cycle_start and cycle_start > current_time then
					next_cycle_time = cycle_start
				end
			end

			if #processed_cycles > 0 then
				for i, cycle_time in ipairs(processed_cycles) do
					if cycle_time then
						local new_start_time = cycle_time
						local new_end_time = M.calculate_end_time(event_status, new_start_time)
						if new_end_time then
							event_status.status = "active"
							event_status.start_time = new_start_time
							event_status.end_time = new_end_time
							event_status.cycle_count = (event_status.cycle_count or 0) + 1
							state.set_event_state(event_id, event_status)

							M._update_chained_events(event_id)

							local event_data = M._create_event_data(event_id, event_status)
							M._trigger_event_start(event_id, event_data)

							if current_time >= new_end_time then
								M._complete_event(event_id, event_status, new_start_time, new_end_time, current_time)
							end
						end
					end
				end

				event_status.next_cycle_time = (next_cycle_time and next_cycle_time > current_time) and next_cycle_time or nil
				state.set_event_state(event_id, event_status)

				return true
			end
		end

		local next_cycle_time = event_status.next_cycle_time
		if not next_cycle_time then
			next_cycle_time = cycles.calculate_next_cycle(
				event_status.cycle,
				current_time,
				event_status.end_time,
				event_status.start_time
			)
		end

		if next_cycle_time and next_cycle_time <= current_time then
			if skip_missed then
				while next_cycle_time and next_cycle_time < current_time do
					next_cycle_time = cycles.calculate_next_cycle(
						event_status.cycle,
						current_time,
						next_cycle_time,
						event_status.start_time
					)
				end
			end

			if next_cycle_time and next_cycle_time <= current_time then
				local new_start_time = next_cycle_time
				local new_end_time = M.calculate_end_time(event_status, new_start_time)

				if event_status.min_time and new_end_time then
					local remaining = new_end_time - current_time
					if remaining < event_status.min_time then
						local skipped_cycle_time = cycles.calculate_next_cycle(
							event_status.cycle,
							current_time,
							new_end_time,
							event_status.start_time
						)
						if skipped_cycle_time then
							event_status.next_cycle_time = skipped_cycle_time
							state.set_event_state(event_id, event_status)
						end
						return false
					end
				end

				event_status.status = "active"
				event_status.start_time = new_start_time
				event_status.end_time = new_end_time
				event_status.cycle_count = (event_status.cycle_count or 0) + 1
				event_status.next_cycle_time = nil
				state.set_event_state(event_id, event_status)

				M._update_chained_events(event_id)

				local event_data = M._create_event_data(event_id, event_status)
				M._trigger_event_start(event_id, event_data)
				return true
			end
		end

		if next_cycle_time and next_cycle_time > current_time then
			event_status.next_cycle_time = next_cycle_time
			state.set_event_state(event_id, event_status)
		end
	end

	return false
end


---Update single event
---@param event_id string
---@param current_time number
---@param last_update_time number|nil
---@return boolean event_updated True if event was updated, false otherwise
function M.update_event(event_id, current_time, last_update_time)
	local event_status = state.get_event_state(event_id)

	if not event_status then
		return false
	end

	if M._is_startable_status(event_status.status) or event_status.status == "paused" then
		if event_status.catch_up and last_update_time then
			M.process_catchup(event_id, event_status, last_update_time, current_time)
		end

		local start_time = event_status.start_time
		if not start_time then
			start_time = M.calculate_start_time(event_status, current_time, last_update_time)
			if start_time then
				event_status.start_time = start_time
				state.set_event_state(event_id, event_status)
			end
		end

		if type(event_status.after) == "string" then
			local after_event_id = event_status.after
			assert(type(after_event_id) == "string", "after_event_id must be string")
			local after_status = state.get_event_state(after_event_id)
			if after_status and after_status.status == "completed" and after_status.end_time then
				if not start_time or start_time < after_status.end_time then
					start_time = after_status.end_time
					event_status.start_time = start_time
					state.set_event_state(event_id, event_status)
				end
			end
		end

		if start_time and current_time >= start_time then
			if event_status.status == "cancelled" then
				return false
			end

			if event_status.min_time then
				local end_time = M.calculate_end_time(event_status, start_time)
				if end_time then
					local remaining = end_time - current_time
					if remaining <= event_status.min_time then
						M._cancel_event(event_id, event_status)
						return false
					end
				end
			end

			local should_start = M.should_start_event(event_id, event_status, current_time, last_update_time)
			if should_start then
				local end_time = M.calculate_end_time(event_status, start_time)
				M._activate_event(event_id, event_status, start_time, end_time, current_time)

				if not end_time and not event_status.infinity and event_status.after and not event_status.start_at then
					M._complete_event(event_id, event_status, start_time, end_time, current_time)

					if event_status.cycle then
						M.process_cycle(event_id, event_status, current_time)
					end

					return true
				end

				return true
			elseif M._is_startable_status(event_status.status) and event_status.status ~= "pending" then
				local all_conditions_passed, failed_condition = conditions.evaluate_conditions(event_status)
				if all_conditions_passed then
					event_status.status = "pending"
					state.set_event_state(event_id, event_status)
				end
			end
		end
	end

	if event_status.status == "active" then
		if not event_status.catch_up or not last_update_time then
			local end_time = event_status.end_time
			if end_time and current_time >= end_time then
				M._complete_event(event_id, event_status, nil, end_time, current_time)

				if event_status.cycle then
					M.process_cycle(event_id, event_status, current_time)
				end

				return true
			end
		else
			if M.process_catchup(event_id, event_status, last_update_time, current_time) then
				if event_status.cycle then
					local cycle_processed = M.process_cycle(event_id, event_status, current_time)
					if cycle_processed then
						return true
					end
				end
				return true
			end
		end
	end

	if event_status.status == "paused" then
		return false
	end

	if event_status.status == "completed" and event_status.cycle then
		local cycle_processed = M.process_cycle(event_id, event_status, current_time)
		if cycle_processed then
			return true
		end
	end

	event_status.last_update_time = current_time
	state.set_event_state(event_id, event_status)
	return false
end


---Update all events
---@param current_time number
function M.update_all(current_time)
	local last_update_time = state.get_last_update_time()
	local all_events = state.get_all_events()
	local any_updated = false

	for event_id, event_status in pairs(all_events) do
		local updated = M.update_event(event_id, current_time, last_update_time)
		if updated then
			any_updated = true
		end
	end

	local continue_chain = true
	while continue_chain do
		continue_chain = false
		for event_id, event_status in pairs(all_events) do
			if type(event_status.after) == "string" then
				local after_event_id = event_status.after
				assert(type(after_event_id) == "string", "after_event_id must be string")
				local after_status = state.get_event_state(after_event_id)
				if after_status and after_status.status == "completed" and after_status.end_time then
					local current_event_status = state.get_event_state(event_id)
					if current_event_status and (M._is_startable_status(current_event_status.status) or current_event_status.status == "paused") then
						if not current_event_status.start_time or current_event_status.start_time < after_status.end_time then
							current_event_status.start_time = after_status.end_time
							state.set_event_state(event_id, current_event_status)
							local updated = M.update_event(event_id, current_time, last_update_time)
							if updated then
								any_updated = true
								continue_chain = true
							end
						end
					end
				end
			end
		end
	end

	state.set_last_update_time(current_time)
	return any_updated
end


---Check if event status allows starting
---@param status string
---@return boolean
function M._is_startable_status(status)
	return status == "pending" or status == "cancelled" or status == "aborted" or status == "failed"
end


---Create event data table
---@param event_id string
---@param event_status schedule.event.state
---@return table event_data
function M._create_event_data(event_id, event_status)
	return {
		id = event_id,
		category = event_status.category,
		payload = event_status.payload,
		status = event_status.status,
		start_time = event_status.start_time,
		end_time = event_status.end_time
	}
end


---Trigger event start lifecycle callbacks
---@param event_id string
---@param event_data table
function M._trigger_event_start(event_id, event_data)
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)
end


---Trigger event end lifecycle callbacks
---@param event_id string
---@param event_data table
function M._trigger_event_end(event_id, event_data)
	lifecycle.on_end(event_id, event_data)
	lifecycle.on_disabled(event_id, event_data)
end


---Trigger full cycle lifecycle callbacks
---@param event_id string
---@param event_data table
function M._trigger_event_cycle(event_id, event_data)
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)
	lifecycle.on_end(event_id, event_data)
	lifecycle.on_disabled(event_id, event_data)
end


---Activate an event
---@param event_id string
---@param event_status schedule.event.state
---@param start_time number
---@param end_time number|nil
---@param current_time number
function M._activate_event(event_id, event_status, start_time, end_time, current_time)
	event_status.status = "active"
	event_status.start_time = start_time
	event_status.end_time = end_time
	event_status.last_update_time = current_time
	state.set_event_state(event_id, event_status)

	local event_data = M._create_event_data(event_id, event_status)
	M._trigger_event_start(event_id, event_data)
end


---Complete an event
---@param event_id string
---@param event_status schedule.event.state
---@param start_time number|nil
---@param end_time number|nil
---@param current_time number
function M._complete_event(event_id, event_status, start_time, end_time, current_time)
	event_status.status = "completed"
	if start_time then
		event_status.start_time = start_time
	end
	if end_time then
		event_status.end_time = end_time
	end
	event_status.last_update_time = current_time
	state.set_event_state(event_id, event_status)

	local event_data = M._create_event_data(event_id, event_status)
	M._trigger_event_end(event_id, event_data)
end


---Cancel an event
---@param event_id string
---@param event_status schedule.event.state
function M._cancel_event(event_id, event_status)
	event_status.status = "cancelled"
	state.set_event_state(event_id, event_status)
end


---Update all events chained after this event
---@param event_id string
---@param all_events table|nil Optional cached events table
function M._update_chained_events(event_id, all_events)
	if not all_events then
		all_events = state.get_all_events()
	end
	for chained_event_id, chained_event_status in pairs(all_events) do
		if type(chained_event_status.after) == "string" and chained_event_status.after == event_id then
			if chained_event_status.status == "pending" or chained_event_status.status == "completed" then
				chained_event_status.start_time = nil
				chained_event_status.status = "pending"
				state.set_event_state(chained_event_id, chained_event_status)
			end
		end
	end
end


---Collect missed cycles for catch-up
---@param event_status schedule.event.state
---@param start_time number
---@param current_time number
---@param skip_missed boolean
---@return table cycles Array of {start, end_time} cycle data
---@return number catch_count Number of cycles caught up
function M._collect_missed_cycles(event_status, start_time, current_time, skip_missed)
	local cycles_list = {}
	local cycle_start = start_time
	local max_catches = event_status.cycle.max_catches
	local catch_count = 0

	while cycle_start and cycle_start <= current_time do
		if max_catches and catch_count >= max_catches then
			break
		end
		local cycle_end = M.calculate_end_time(event_status, cycle_start)
		if cycle_end and cycle_end <= current_time then
			if not skip_missed then
				table.insert(cycles_list, { start = cycle_start, end_time = cycle_end })
			end
			catch_count = catch_count + 1
			local next_cycle = cycles.calculate_next_cycle(
				event_status.cycle,
				current_time,
				cycle_end,
				start_time
			)
			if next_cycle then
				cycle_start = next_cycle
			else
				break
			end
		else
			break
		end
	end

	if skip_missed and catch_count > 0 then
		local last_cycle_start = start_time
		for i = 1, catch_count - 1 do
			local cycle_end = M.calculate_end_time(event_status, last_cycle_start)
			if cycle_end then
				local next_cycle = cycles.calculate_next_cycle(
					event_status.cycle,
					current_time,
					cycle_end,
					start_time
				)
				if next_cycle then
					last_cycle_start = next_cycle
				else
					break
				end
			else
				break
			end
		end
		local final_end = M.calculate_end_time(event_status, last_cycle_start)
		if final_end then
			table.insert(cycles_list, { start = last_cycle_start, end_time = final_end })
		end
	end

	return cycles_list, catch_count
end


---Apply a single catch-up cycle
---@param event_id string
---@param event_status schedule.event.state
---@param cycle_start number
---@param cycle_end number
---@param current_time number
function M._apply_catchup_cycle(event_id, event_status, cycle_start, cycle_end, current_time)
	event_status.status = "active"
	event_status.start_time = cycle_start
	event_status.end_time = cycle_end
	event_status.cycle_count = (event_status.cycle_count or 0) + 1
	event_status.last_update_time = current_time
	state.set_event_state(event_id, event_status)

	local event_data = M._create_event_data(event_id, event_status)
	M._trigger_event_cycle(event_id, event_data)
end


return M

