---Event processor - main update loop
local state = require("schedule.internal.schedule_state")
local time = require("schedule.internal.schedule_time")
local cycles = require("schedule.internal.schedule_cycles")
local conditions = require("schedule.internal.schedule_conditions")
local chaining = require("schedule.internal.schedule_chaining")
local lifecycle = require("schedule.internal.schedule_lifecycle")
local logger = require("schedule.internal.schedule_logger")

local M = {}

---Safety cap for walking over cycle occurrences, so a broken cycle config can never hang the update loop
local MAX_CYCLE_STEPS = 512

local active_events = {}

---How many cycles each event replayed during the current update, so max_catches is a per update limit
local catchup_counts = {}

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
		local can_start, chain_time = chaining.can_start_chain(event_state.after, event_state, current_time, last_update_time)
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
			logger:debug("Event aborted, condition failed", { event_id = event_id, condition = failed_condition })
		end
		return false
	end

	if M._is_below_min_time(event_state, start_time, current_time) then
		event_state.status = "cancelled"
		return false
	end

	return true
end


---Check if too little time is left for the event to be worth starting
---@param event_state schedule.event.state
---@param start_time number
---@param current_time number
---@return boolean is_below_min_time
function M._is_below_min_time(event_state, start_time, current_time)
	if not event_state.min_time then
		return false
	end

	local end_time = M.calculate_end_time(event_state, start_time)
	if not end_time then
		return false
	end

	return (end_time - current_time) <= event_state.min_time
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
					-- The whole event happened while offline, replay it as one activation
					M._replay_event_run(event_id, event_state, start_time, end_time, current_time)
					event_state.status = "completed"
					return true
				end
			else
				local skip_missed = event_state.cycle.skip_missed or false
				local processed_cycles = M._collect_missed_cycles(event_id, event_state, start_time, current_time, skip_missed)

				if #processed_cycles > 0 then
					for _, cycle_data in ipairs(processed_cycles) do
						M._apply_catchup_cycle(event_id, event_state, cycle_data.start, cycle_data.end_time, current_time)
					end

					-- Every replayed cycle already emitted its full lifecycle, so only the
					-- state is settled here. A cycle that is running right now is picked up
					-- by the regular cycle processing afterwards
					local last_cycle = processed_cycles[#processed_cycles]
					event_state.status = "completed"
					event_state.start_time = last_cycle.start
					event_state.end_time = last_cycle.end_time
					event_state.last_update_time = current_time
					return true
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


---Activate a cycle for an event
---@param event_id string
---@param event_state schedule.event.state
---@param new_start_time number
---@param new_end_time number|nil
function M._activate_cycle(event_id, event_state, new_start_time, new_end_time)
	event_state.status = "active"
	event_state.start_time = new_start_time
	event_state.end_time = new_end_time
	event_state.cycle_count = (event_state.cycle_count or 0) + 1
	event_state.next_cycle_time = nil

	M._update_chained_events(event_id)

	local event_data = M._create_event_data(event_id, event_state)
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)
end


---Check if cycle should be skipped due to min_time
---@param event_state schedule.event.state
---@param new_start_time number
---@param new_end_time number|nil
---@param current_time number
---@return boolean should_skip True if cycle should be skipped
---@return number|nil next_cycle_time Next cycle time if skipped
function M._should_skip_cycle(event_state, new_start_time, new_end_time, current_time)
	if not new_end_time or not M._is_below_min_time(event_state, new_start_time, current_time) then
		return false, nil
	end

	local skipped_cycle_time = cycles.calculate_next_cycle(
		event_state.cycle,
		current_time,
		new_end_time,
		event_state.start_time
	)
	return true, skipped_cycle_time
end


---Get the occurrence right after the given one, without skipping anything in between
---@param event_state schedule.event.state
---@param cycle_time number Occurrence to step from
---@return number|nil next_cycle_time
function M._following_cycle(event_state, cycle_time)
	local cycle_config = event_state.cycle

	if cycle_config.type == "every" then
		local interval = cycle_config.seconds
		if not interval or interval <= 0 then
			return nil
		end
		return cycle_time + interval
	end

	return cycles.calculate_next_cycle(cycle_config, cycle_time + 1, cycle_time, event_state.start_time)
end


---Get how many more cycles this event may replay during the current update
---@param event_id string
---@param event_state schedule.event.state
---@return number|nil budget Remaining number of cycles, nil when unlimited
function M._get_catchup_budget(event_id, event_state)
	local max_catches = event_state.cycle and event_state.cycle.max_catches
	if not max_catches then
		return nil
	end

	return math.max(0, max_catches - (catchup_counts[event_id] or 0))
end


---Collect the cycle occurrences that already started and ended, one by one.
---Used for catch-up, where every missed occurrence has to be replayed.
---@param event_state schedule.event.state
---@param from_time number|nil First occurrence to check
---@param current_time number
---@param budget number|nil Maximum number of occurrences to collect, nil when unlimited
---@return table finished_cycles Array of { start, end_time }, oldest first
---@return number|nil next_cycle_time First occurrence that has not finished yet
function M._collect_finished_cycles(event_state, from_time, current_time, budget)
	local finished_cycles = {}
	local cycle_start = from_time

	for _ = 1, MAX_CYCLE_STEPS do
		if not cycle_start or cycle_start > current_time then
			break
		end
		if budget and #finished_cycles >= budget then
			break
		end

		local cycle_end = M.calculate_end_time(event_state, cycle_start)
		if not cycle_end or cycle_end > current_time then
			break
		end

		table.insert(finished_cycles, { start = cycle_start, end_time = cycle_end })
		cycle_start = M._following_cycle(event_state, cycle_start)
	end

	-- Hitting the step limit means the rest of the missed occurrences are dropped and the event
	-- jumps to the current one. Set max_catches to make that a deliberate number
	if #finished_cycles >= MAX_CYCLE_STEPS and cycle_start and cycle_start <= current_time then
		logger:warn("Catch-up stopped at the step limit, remaining missed cycles are skipped", {
			collected = #finished_cycles,
			limit = MAX_CYCLE_STEPS
		})
	end

	return finished_cycles, cycle_start
end


---Collect missed cycles of a completed event for catch-up
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@return table processed_cycles Array of { start, end_time }, oldest first
---@return number|nil next_cycle_time Next cycle time if any
function M._collect_catchup_cycles(event_id, event_state, current_time)
	local cycle_config = event_state.cycle
	if not cycle_config or not event_state.start_time then
		return {}, nil
	end

	local anchor_time = (cycle_config.anchor == "end" and event_state.end_time) or event_state.start_time
	if not anchor_time then
		return {}, nil
	end

	return M._collect_finished_cycles(event_state, M._following_cycle(event_state, anchor_time), current_time,
		M._get_catchup_budget(event_id, event_state))
end


---Process catch-up cycles for completed event
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@return boolean processed True if cycles were processed
function M._process_catchup_cycles(event_id, event_state, current_time)
	local cycle_config = event_state.cycle
	if not cycle_config then
		return false
	end

	local skip_missed = cycle_config.skip_missed
	local catch_up = event_state.catch_up

	if not catch_up or skip_missed then
		return false
	end

	local processed_cycles, next_cycle_time = M._collect_catchup_cycles(event_id, event_state, current_time)

	if #processed_cycles == 0 then
		return false
	end

	for _, cycle_data in ipairs(processed_cycles) do
		M._activate_cycle(event_id, event_state, cycle_data.start, cycle_data.end_time)
		M._complete_event(event_id, event_state, cycle_data.start, cycle_data.end_time, current_time)
	end

	event_state.next_cycle_time = next_cycle_time

	-- The occurrence after the replayed ones may be running right now, activate it in the same update
	M._process_next_cycle(event_id, event_state, current_time)
	return true
end


---Get the cycle occurrence to look at, which can be in the past.
---It has to be the occurrence right after the last one, not the next future one: an occurrence
---that started while the game was closed can still be running now.
---@param event_state schedule.event.state
---@param current_time number
---@return number|nil next_cycle_time
function M._get_next_cycle_time(event_state, current_time)
	if event_state.next_cycle_time then
		return event_state.next_cycle_time
	end

	local cycle_config = event_state.cycle
	local anchor_time = (cycle_config.anchor == "end" and event_state.end_time) or event_state.start_time
	if anchor_time then
		return M._following_cycle(event_state, anchor_time)
	end

	return cycles.calculate_next_cycle(cycle_config, current_time, event_state.end_time, event_state.start_time)
end


---Get the cycle occurrence that follows the given one
---@param event_state schedule.event.state
---@param cycle_time number Occurrence to step from
---@param current_time number
---@return number|nil next_cycle_time
function M._next_cycle_after(event_state, cycle_time, current_time)
	local cycle_config = event_state.cycle

	-- Interval cycles are evenly spaced, so a long offline period is one jump instead of a walk
	if cycle_config.type == "every" then
		local interval = cycle_config.seconds
		if not interval or interval <= 0 then
			return nil
		end

		if cycle_time + interval <= current_time then
			local missed_intervals = math.floor((current_time - cycle_time) / interval)
			return cycle_time + missed_intervals * interval
		end

		return cycle_time + interval
	end

	return cycles.calculate_next_cycle(cycle_config, cycle_time + 1, cycle_time, event_state.start_time)
end


---Resolve which cycle occurrence the event should be on right now.
---Occurrences that already ended are stepped over, so a single update never activates a stale cycle
---and never swallows the cycles in between.
---@param event_state schedule.event.state
---@param current_time number
---@return number|nil cycle_time Occurrence that is still running, or the next upcoming one
function M._resolve_cycle_time(event_state, current_time)
	local cycle_time = M._get_next_cycle_time(event_state, current_time)
	if not cycle_time or cycle_time > current_time then
		return cycle_time
	end

	for _ = 1, MAX_CYCLE_STEPS do
		local cycle_end = M.calculate_end_time(event_state, cycle_time)
		if not cycle_end or cycle_end > current_time then
			-- This occurrence is still running (or never ends)
			return cycle_time
		end

		local next_cycle_time = M._next_cycle_after(event_state, cycle_time, current_time)
		if not next_cycle_time or next_cycle_time <= cycle_time then
			return cycle_time
		end

		cycle_time = next_cycle_time
		if cycle_time > current_time then
			return cycle_time
		end
	end

	return cycle_time
end


---Process next cycle for event
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@return boolean processed True if cycle was processed
function M._process_next_cycle(event_id, event_state, current_time)
	local next_cycle_time = M._resolve_cycle_time(event_state, current_time)

	if not next_cycle_time or next_cycle_time > current_time then
		event_state.next_cycle_time = next_cycle_time
		return false
	end

	local new_start_time = next_cycle_time
	local new_end_time = M.calculate_end_time(event_state, new_start_time)

	local should_skip, skipped_cycle_time = M._should_skip_cycle(event_state, new_start_time, new_end_time, current_time)
	if should_skip then
		if skipped_cycle_time then
			event_state.next_cycle_time = skipped_cycle_time
		end
		return false
	end

	M._activate_cycle(event_id, event_state, new_start_time, new_end_time)
	return true
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
		if M._process_catchup_cycles(event_id, event_state, current_time) then
			return true
		end
		return M._process_next_cycle(event_id, event_state, current_time)
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
			local after_status = state.get_event_state(event_state.after)
			if after_status and after_status.status == "completed" and after_status.end_time then
				if not start_time or start_time < after_status.end_time then
					start_time = chaining.get_chain_start_time(event_state, after_status, current_time)
					event_state.start_time = start_time
				end
			end
		end

		-- Catch-up (or other earlier work in this call) may have already moved the event
		-- out of a startable status; only start/cancel when it is still pending
		if M._is_startable_status(event_state.status) and start_time and current_time >= start_time then
			if M._is_below_min_time(event_state, start_time, current_time) then
				event_state.status = "cancelled"
				return false
			end

			local should_start = M.should_start_event(event_id, event_state, current_time, last_update_time)
			if should_start then
				local end_time = M.calculate_end_time(event_state, start_time)

				-- The event ran out while the game was closed. Emit the whole lifecycle at once
				-- instead of reporting a window that is already over as active
				if end_time and current_time >= end_time then
					M._replay_event_run(event_id, event_state, start_time, end_time, current_time)
					event_state.status = "completed"

					if event_state.cycle then
						M.process_cycle(event_id, event_state, current_time)
					end

					return true
				end

				M._activate_event(event_id, event_state, start_time, end_time, current_time)

				if not end_time and not event_state.infinity and event_state.after and not event_state.start_at then
					M._complete_event(event_id, event_state, start_time, end_time, current_time)

					if event_state.cycle then
						M.process_cycle(event_id, event_state, current_time)
					end

					return true
				end

				return true
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

	-- The device clock can move backwards (player changed it, or the clock got corrected).
	-- Catch-up windows are meaningless then, so skip them for this update
	if last_update_time and current_time < last_update_time then
		logger:warn("Time moved backwards, skipping catch-up for this update", {
			current_time = current_time,
			last_update_time = last_update_time
		})
		last_update_time = nil
	end

	if next(active_events) == nil then
		for event_id, event_state in pairs(all_events) do
			if event_state.status == "active" then
				local event_data = M._create_event_data(event_id, event_state)
				lifecycle.on_enabled(event_id, event_data)
			end
		end
	end

	for event_id in pairs(catchup_counts) do
		catchup_counts[event_id] = nil
	end

	local events_to_update = {}
	for event_id, event_state in pairs(all_events) do
		local status = event_state.status
		if M._is_startable_status(status) or status == "paused" or status == "active" or (status == "completed" and event_state.cycle) then
			events_to_update[event_id] = true
		end
	end

	for event_id, _ in pairs(events_to_update) do
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


---Check if event status allows starting.
---"cancelled", "aborted" and "failed" are terminal: the update loop never revives them,
---they can only be restarted explicitly with `event:start()`.
---@param status string
---@return boolean
function M._is_startable_status(status)
	return status == "pending"
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
	all_events = all_events or state.get_all_events()
	for chained_event_id, chained_event_state in pairs(all_events) do
		if type(chained_event_state.after) == "string" and chained_event_state.after == event_id then
			if chained_event_state.status == "pending" or chained_event_state.status == "completed" then
				chained_event_state.start_time = nil
				chained_event_state.status = "pending"
			end
		end
	end
end


---Collect the cycles a pending event missed while the game was offline
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number First occurrence of the event
---@param current_time number
---@param skip_missed boolean Keep only the last missed occurrence
---@return table cycles Array of {start, end_time} cycle data, oldest first
function M._collect_missed_cycles(event_id, event_state, start_time, current_time, skip_missed)
	local cycles_list = M._collect_finished_cycles(event_state, start_time, current_time,
		M._get_catchup_budget(event_id, event_state))

	-- Only the last missed occurrence is replayed when the game asked to skip the ones in between
	if skip_missed and #cycles_list > 1 then
		cycles_list = { cycles_list[#cycles_list] }
	end

	return cycles_list
end


---Replay a run of an event that started and ended while the game was offline.
---The whole lifecycle is emitted at once, so the game can apply its result.
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number
---@param end_time number
---@param current_time number
function M._replay_event_run(event_id, event_state, start_time, end_time, current_time)
	event_state.status = "active"
	event_state.start_time = start_time
	event_state.end_time = end_time
	event_state.last_update_time = current_time

	local event_data = M._create_event_data(event_id, event_state)
	lifecycle.on_start(event_id, event_data)
	lifecycle.on_enabled(event_id, event_data)
	lifecycle.on_end(event_id, event_data)
	lifecycle.on_disabled(event_id, event_data)
end


---Apply a single catch-up cycle
---@param event_id string
---@param event_state schedule.event.state
---@param cycle_start number
---@param cycle_end number
---@param current_time number
function M._apply_catchup_cycle(event_id, event_state, cycle_start, cycle_end, current_time)
	catchup_counts[event_id] = (catchup_counts[event_id] or 0) + 1
	event_state.cycle_count = (event_state.cycle_count or 0) + 1
	M._replay_event_run(event_id, event_state, cycle_start, cycle_end, current_time)
end


return M

