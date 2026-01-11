---Event processor - main update loop
local state = require("schedule.internal.schedule_state")
local time = require("schedule.internal.schedule_time")
local cycles = require("schedule.internal.schedule_cycles")
local conditions = require("schedule.internal.schedule_conditions")
local chaining = require("schedule.internal.schedule_chaining")
local lifecycle = require("schedule.internal.schedule_lifecycle")

local M = {}

local active_events = {}

function M.clear_active_events()
	for k in pairs(active_events) do
		active_events[k] = nil
	end
end


---Calculate event start time
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time for wait_online logic
---@return number|nil start_time Calculated start time in seconds, or nil if cannot be calculated
function M.calculate_start_time(event_state, current_time, last_update_time)
	if event_state.start_at then
		return time.normalize_time(event_state.start_at)
	elseif event_state.after then
		local after = event_state.after
		if type(after) == "string" then
			local can_start, chain_time = chaining.can_start_chain(after, event_state, current_time, last_update_time)
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
---@param event_state schedule.event.state
---@param start_time number
---@return number|nil end_time Calculated end time in seconds, or nil for infinity events
function M.calculate_end_time(event_state, start_time)
	if event_state.infinity then
		return nil
	end

	if event_state.end_at then
		return time.normalize_time(event_state.end_at)
	elseif event_state.duration then
		return start_time + event_state.duration
	end

	return nil
end


---Check if event should start
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time for wait_online logic
---@return boolean should_start True if event should start, false otherwise
function M.should_start_event(event_id, event_state, current_time, last_update_time)
	if not M._is_startable_status(event_state.status) then
		return false
	end

	local start_time = event_state.start_time
	if not start_time then
		return false
	end

	if start_time > current_time then
		return false
	end

	if type(event_state.after) == "string" then
		local after_event_id = event_state.after
		assert(type(after_event_id) == "string", "after_event_id must be string")
		local can_start, chain_time = chaining.can_start_chain(after_event_id, event_state, current_time, last_update_time)
		if not can_start then
			return false
		end
		if chain_time and chain_time > current_time then
			return false
		end
	end

	local all_conditions_passed, failed_condition = conditions.evaluate_conditions(event_state)
	if not all_conditions_passed then
		if event_state.abort_on_fail then
			event_state.status = "aborted"
			local event_data = M._create_event_data(event_id, event_state)
			lifecycle.on_fail(event_id, event_data)
		end
		return false
	end

	if event_state.min_time then
		local end_time = M.calculate_end_time(event_state, start_time)
		if end_time then
			local remaining = end_time - current_time
			if remaining <= event_state.min_time then
				event_state.status = "cancelled"
				return false
			end
		end
	end

	return true
end


---Process catch-up for offline period
---@param event_id string
---@param event_state schedule.event.state
---@param last_update_time number|nil
---@param current_time number
---@return boolean was_caught_up True if catch-up was processed, false otherwise
function M.process_catchup(event_id, event_state, last_update_time, current_time)
	if not event_state.catch_up or not last_update_time then
		return false
	end

	if event_state.status == "pending" then
		local start_time = event_state.start_time
		if start_time and current_time >= start_time then
			if not event_state.cycle then
				local end_time = M.calculate_end_time(event_state, start_time)
				if end_time and current_time >= end_time then
					event_state.status = "active"
					event_state.start_time = start_time
					event_state.end_time = end_time

					local event_data = M._create_event_data(event_id, event_state)
					lifecycle.on_start(event_id, event_data)
					lifecycle.on_enabled(event_id, event_data)
					lifecycle.on_end(event_id, event_data)
					lifecycle.on_disabled(event_id, event_data)

					event_state.status = "completed"
					event_state.start_time = start_time
					event_state.end_time = end_time
					event_state.last_update_time = current_time
					return true
				end
			else
				local skip_missed = event_state.cycle.skip_missed or false
				local processed_cycles, catch_count = M._collect_missed_cycles(event_state, start_time, current_time, skip_missed)

				if #processed_cycles > 0 then
					for i, cycle_data in ipairs(processed_cycles) do
						M._apply_catchup_cycle(event_id, event_state, cycle_data.start, cycle_data.end_time, current_time)
					end

					local last_cycle = processed_cycles[#processed_cycles]
					if last_cycle.end_time and current_time >= last_cycle.end_time then
						M._complete_event(event_id, event_state, last_cycle.start, last_cycle.end_time, current_time)
						return true
					else
						event_state.status = "active"
						event_state.start_time = last_cycle.start
						event_state.end_time = last_cycle.end_time
						event_state.last_update_time = current_time
						return true
					end
				end
			end
		end
	end

	if event_state.status == "active" then
		local end_time = event_state.end_time
		if end_time and current_time >= end_time then
			M._complete_event(event_id, event_state, nil, end_time, current_time)
			return true
		end
	end

	return false
end


---Process cycle for event
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@return boolean cycle_processed True if cycle was processed, false otherwise
function M.process_cycle(event_id, event_state, current_time)
	if not event_state.cycle then
		return false
	end

	if event_state.status == "completed" then
		local skip_missed = event_state.cycle.skip_missed
		local catch_up = event_state.catch_up

		if catch_up and not skip_missed then
			local processed_cycles = {}
			local anchor = event_state.cycle.anchor or "start"
			local cycle_interval = event_state.cycle.seconds
			local next_cycle_time = nil
			local max_catches = event_state.cycle.max_catches
			local catch_count = 0

			if cycle_interval and event_state.start_time then
				local base_time
				if anchor == "end" and event_state.end_time then
					base_time = event_state.end_time
				else
					base_time = event_state.start_time
				end

				local cycle_start = base_time + cycle_interval
				while cycle_start and cycle_start <= current_time do
					if max_catches and catch_count >= max_catches then
						break
					end
					local cycle_end = M.calculate_end_time(event_state, cycle_start)
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
						local new_end_time = M.calculate_end_time(event_state, new_start_time)
						if new_end_time then
							event_state.status = "active"
							event_state.start_time = new_start_time
							event_state.end_time = new_end_time
							event_state.cycle_count = (event_state.cycle_count or 0) + 1

							M._update_chained_events(event_id)

							local event_data = M._create_event_data(event_id, event_state)
							lifecycle.on_start(event_id, event_data)
							lifecycle.on_enabled(event_id, event_data)

							if current_time >= new_end_time then
								M._complete_event(event_id, event_state, new_start_time, new_end_time, current_time)
							end
						end
					end
				end

				event_state.next_cycle_time = (next_cycle_time and next_cycle_time > current_time) and next_cycle_time or nil

				return true
			end
		end

		local next_cycle_time = event_state.next_cycle_time
		if not next_cycle_time then
			next_cycle_time = cycles.calculate_next_cycle(
				event_state.cycle,
				current_time,
				event_state.end_time,
				event_state.start_time
			)
		end

		if next_cycle_time and next_cycle_time <= current_time then
			if skip_missed then
				while next_cycle_time and next_cycle_time < current_time do
					next_cycle_time = cycles.calculate_next_cycle(
						event_state.cycle,
						current_time,
						next_cycle_time,
						event_state.start_time
					)
				end
			end

			if next_cycle_time and next_cycle_time <= current_time then
				local new_start_time = next_cycle_time
				local new_end_time = M.calculate_end_time(event_state, new_start_time)

				if event_state.min_time and new_end_time then
					local remaining = new_end_time - current_time
					if remaining < event_state.min_time then
						local skipped_cycle_time = cycles.calculate_next_cycle(
							event_state.cycle,
							current_time,
							new_end_time,
							event_state.start_time
						)
						if skipped_cycle_time then
							event_state.next_cycle_time = skipped_cycle_time
						end
						return false
					end
				end

				event_state.status = "active"
				event_state.start_time = new_start_time
				event_state.end_time = new_end_time
				event_state.cycle_count = (event_state.cycle_count or 0) + 1
				event_state.next_cycle_time = nil

				M._update_chained_events(event_id)

				local event_data = M._create_event_data(event_id, event_state)
				lifecycle.on_start(event_id, event_data)
				lifecycle.on_enabled(event_id, event_data)

				return true
			end
		end

		if next_cycle_time and next_cycle_time > current_time then
			event_state.next_cycle_time = next_cycle_time
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
	local event_state = state.get_event_state(event_id)

	if not event_state then
		return false
	end

	if M._is_startable_status(event_state.status) or event_state.status == "paused" then
		if event_state.catch_up and last_update_time then
			M.process_catchup(event_id, event_state, last_update_time, current_time)
		end

		local start_time = event_state.start_time
		if not start_time then
			start_time = M.calculate_start_time(event_state, current_time, last_update_time)
			if start_time then
				event_state.start_time = start_time
			end
		end

		if type(event_state.after) == "string" then
			local after_event_id = event_state.after
			assert(type(after_event_id) == "string", "after_event_id must be string")
			local after_status = state.get_event_state(after_event_id)
			if after_status and after_status.status == "completed" and after_status.end_time then
				if not start_time or start_time < after_status.end_time then
					start_time = after_status.end_time
					event_state.start_time = start_time
				end
			end
		end

		if start_time and current_time >= start_time then
			if event_state.status == "cancelled" then
				return false
			end

			if event_state.min_time then
				local end_time = M.calculate_end_time(event_state, start_time)
				if end_time then
					local remaining = end_time - current_time
					if remaining <= event_state.min_time then
						event_state.status = "cancelled"
						return false
					end
				end
			end

			local should_start = M.should_start_event(event_id, event_state, current_time, last_update_time)
			if should_start then
				local end_time = M.calculate_end_time(event_state, start_time)
				M._activate_event(event_id, event_state, start_time, end_time, current_time)

				if not end_time and not event_state.infinity and event_state.after and not event_state.start_at then
					M._complete_event(event_id, event_state, start_time, end_time, current_time)

					if event_state.cycle then
						M.process_cycle(event_id, event_state, current_time)
					end

					return true
				end

				return true
			elseif M._is_startable_status(event_state.status) and event_state.status ~= "pending" then
				local all_conditions_passed, failed_condition = conditions.evaluate_conditions(event_state)
				if all_conditions_passed then
					event_state.status = "pending"
				end
			end
		end
	end

	if event_state.status == "active" then
		if not event_state.catch_up or not last_update_time then
			local end_time = event_state.end_time
			if end_time and current_time >= end_time then
				M._complete_event(event_id, event_state, nil, end_time, current_time)

				if event_state.cycle then
					M.process_cycle(event_id, event_state, current_time)
				end

				return true
			end
		else
			if M.process_catchup(event_id, event_state, last_update_time, current_time) then
				if event_state.cycle then
					local cycle_processed = M.process_cycle(event_id, event_state, current_time)
					if cycle_processed then
						return true
					end
				end
				return true
			end
		end
	end

	if event_state.status == "paused" then
		return false
	end

	if event_state.status == "completed" and event_state.cycle then
		local cycle_processed = M.process_cycle(event_id, event_state, current_time)
		if cycle_processed then
			return true
		end
	end

	event_state.last_update_time = current_time
	return false
end


---Update all events
---@param current_time number
function M.update_all(current_time)
	local last_update_time = state.get_last_update_time()
	local all_events = state.get_all_events()
	local any_updated = false

	if next(active_events) == nil then
		for event_id, event_state in pairs(all_events) do
			if event_state.status == "active" then
				local event_data = M._create_event_data(event_id, event_state)
				lifecycle.on_enabled(event_id, event_data)
			end
		end
	end

	for event_id, event_state in pairs(all_events) do
		local updated = M.update_event(event_id, current_time, last_update_time)
		if updated then
			any_updated = true
		end
	end

	local chained_updated = chaining.update_chained_events(
		all_events,
		current_time,
		last_update_time,
		M._is_startable_status,
		M.update_event
	)
	any_updated = any_updated or chained_updated

	for k in pairs(active_events) do
		active_events[k] = nil
	end

	all_events = state.get_all_events()
	for event_id, event_state in pairs(all_events) do
		if event_state.status == "active" then
			active_events[event_id] = true
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
---@param event_state schedule.event.state
---@return table event_data
function M._create_event_data(event_id, event_state)
	return {
		event_id = event_id,
		category = event_state.category,
		payload = event_state.payload,
		status = event_state.status,
		start_time = event_state.start_time,
		end_time = event_state.end_time
	}
end


---Activate an event
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number
---@param end_time number|nil
---@param current_time number
function M._activate_event(event_id, event_state, start_time, end_time, current_time)
	event_state.status = "active"
	event_state.start_time = start_time
	event_state.end_time = end_time
	event_state.last_update_time = current_time

	local event_data = M._create_event_data(event_id, event_state)
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)
end


---Complete an event
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number|nil
---@param end_time number|nil
---@param current_time number
function M._complete_event(event_id, event_state, start_time, end_time, current_time)
	event_state.status = "completed"
	if start_time then
		event_state.start_time = start_time
	end
	if end_time then
		event_state.end_time = end_time
	end
	event_state.last_update_time = current_time

	local event_data = M._create_event_data(event_id, event_state)
	lifecycle.on_end(event_id, event_data)
	lifecycle.on_disabled(event_id, event_data)
end


---Update all events chained after this event
---@param event_id string
---@param all_events table|nil Optional cached events table
function M._update_chained_events(event_id, all_events)
	if not all_events then
		all_events = state.get_all_events()
	end
	for chained_event_id, chained_event_state in pairs(all_events) do
		if type(chained_event_state.after) == "string" and chained_event_state.after == event_id then
			if chained_event_state.status == "pending" or chained_event_state.status == "completed" then
				chained_event_state.start_time = nil
				chained_event_state.status = "pending"
			end
		end
	end
end


---Collect missed cycles for catch-up
---@param event_state schedule.event.state
---@param start_time number
---@param current_time number
---@param skip_missed boolean
---@return table cycles Array of {start, end_time} cycle data
---@return number catch_count Number of cycles caught up
function M._collect_missed_cycles(event_state, start_time, current_time, skip_missed)
	local cycles_list = {}
	local cycle_start = start_time
	local max_catches = event_state.cycle.max_catches
	local catch_count = 0

	while cycle_start and cycle_start <= current_time do
		if max_catches and catch_count >= max_catches then
			break
		end
		local cycle_end = M.calculate_end_time(event_state, cycle_start)
		if cycle_end and cycle_end <= current_time then
			if not skip_missed then
				table.insert(cycles_list, { start = cycle_start, end_time = cycle_end })
			end
			catch_count = catch_count + 1
			local next_cycle = cycles.calculate_next_cycle(
				event_state.cycle,
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
			local cycle_end = M.calculate_end_time(event_state, last_cycle_start)
			if cycle_end then
				local next_cycle = cycles.calculate_next_cycle(
					event_state.cycle,
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
		local final_end = M.calculate_end_time(event_state, last_cycle_start)
		if final_end then
			table.insert(cycles_list, { start = last_cycle_start, end_time = final_end })
		end
	end

	return cycles_list, catch_count
end


---Apply a single catch-up cycle
---@param event_id string
---@param event_state schedule.event.state
---@param cycle_start number
---@param cycle_end number
---@param current_time number
function M._apply_catchup_cycle(event_id, event_state, cycle_start, cycle_end, current_time)
	event_state.status = "active"
	event_state.start_time = cycle_start
	event_state.end_time = cycle_end
	event_state.cycle_count = (event_state.cycle_count or 0) + 1
	event_state.last_update_time = current_time

	local event_data = M._create_event_data(event_id, event_state)
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)
	lifecycle.on_end(event_id, event_data)
	lifecycle.on_disabled(event_id, event_data)
end


return M

