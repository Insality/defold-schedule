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

---False until the first update after restore/reset, so `on_enabled` can fire once
local active_events_ready = false

---True only during the first update after a restore/reset, where legacy state is repaired
local is_cold_start = false

---How many cycles each event replayed during the current update, so max_catches is a per update limit
local catchup_counts = {}

function M.clear_active_events()
	active_events_ready = false
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


---Join window end: last moment this occurrence may still start.
---Clip: occurrence + duration, capped by `end_at`. Exceed: next occurrence if cyclic, else `end_at`.
---@param event_state schedule.event.state
---@param occurrence_start number
---@return number|nil join_end
function M.join_end(event_state, occurrence_start)
	if not occurrence_start or event_state.infinity then
		return nil
	end

	local end_at = event_state.end_at and time.normalize_time(event_state.end_at) or nil

	if event_state.exceed_end_time then
		local slot_end = M._exceed_slot_end(event_state, occurrence_start)
		if slot_end and end_at then
			return math.min(slot_end, end_at)
		end
		if slot_end or end_at then
			return slot_end or end_at
		end
		if event_state.duration then
			return occurrence_start + event_state.duration
		end
		return nil
	end

	local duration_end = event_state.duration and (occurrence_start + event_state.duration) or nil
	if duration_end and end_at then
		return math.min(duration_end, end_at)
	end
	return duration_end or end_at
end


---Slot end for an exceed join window (until the next occurrence, without using join_end).
---@param event_state schedule.event.state
---@param occurrence_start number
---@return number|nil slot_end
function M._exceed_slot_end(event_state, occurrence_start)
	local cycle_config = event_state.cycle
	if not cycle_config then
		return nil
	end

	if cycle_config.type == "every" and cycle_config.seconds and cycle_config.seconds > 0 then
		if cycle_config.anchor == "end" then
			if event_state.duration then
				return occurrence_start + event_state.duration
			end
			return occurrence_start + cycle_config.seconds
		end
		return occurrence_start + cycle_config.seconds
	end

	return M._following_cycle(event_state, occurrence_start)
end


---Run start and end when this occurrence actually activates.
---Exceed starts at `now` and always runs `duration` seconds. Clip keeps the occurrence window.
---@param event_state schedule.event.state
---@param occurrence_start number
---@param current_time number
---@return number actual_start
---@return number|nil run_end
function M._run_times(event_state, occurrence_start, current_time)
	if event_state.exceed_end_time and event_state.duration then
		return current_time, current_time + event_state.duration
	end

	return occurrence_start, M.calculate_end_time(event_state, occurrence_start)
end


---Calculate event run end time (when an already started run finishes).
---@param event_state schedule.event.state
---@param start_time number
---@return number|nil end_time Calculated end time in seconds, or nil for infinity events
function M.calculate_end_time(event_state, start_time)
	if event_state.infinity or not start_time then
		return nil
	end

	if event_state.exceed_end_time and event_state.duration then
		return start_time + event_state.duration
	end

	local duration_end = event_state.duration and (start_time + event_state.duration) or nil
	local end_at = event_state.end_at and time.normalize_time(event_state.end_at) or nil
	if duration_end and end_at then
		return math.min(duration_end, end_at)
	end
	return duration_end or end_at
end


---Check if event should start
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time for wait_online logic
---@return boolean should_start True if event should start, false otherwise
function M.should_start_event(event_id, event_state, current_time, last_update_time)
	if not M._is_pending(event_state.status) then
		return false
	end

	local start_time = event_state.start_time
	if not start_time then
		return false
	end

	if start_time > current_time then
		return false
	end

	local after = event_state.after
	if type(after) == "string" then
		local can_start, chain_time = chaining.can_start_chain(after, event_state, current_time, last_update_time)
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

	local end_time = M.join_end(event_state, start_time)
	if not end_time then
		return false
	end

	return (end_time - current_time) <= event_state.min_time
end


---If the remaining window is shorter than min_time, cancel a one-shot event.
---A cyclic event skips this occurrence instead, the same way later cycles are skipped.
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number
---@param current_time number
---@return boolean handled True if the start was rejected (cancelled or skipped)
function M._cancel_or_skip_min_time(event_id, event_state, start_time, current_time)
	if not M._is_below_min_time(event_state, start_time, current_time) then
		return false
	end

	if not event_state.cycle then
		event_state.status = "cancelled"
		return true
	end

	event_state.status = "completed"
	event_state.start_time = start_time
	event_state.end_time = M.join_end(event_state, start_time)
	event_state.last_update_time = current_time
	M.process_cycle(event_id, event_state, current_time)
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
				local join_end = M.join_end(event_state, start_time)
				if join_end and current_time >= join_end then
					-- The whole join window happened while offline, replay it as one activation
					local run_end = M.calculate_end_time(event_state, start_time) or join_end
					M._replay_event_run(event_id, event_state, start_time, run_end, current_time)
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

					-- Replayed cycles emitted their own lifecycle, only the final state is settled here
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


---Occurrence index on an `every` + `start_at` grid (0 for the first window).
---Nil when the event has no calendar grid, the caller should then increment.
---@param event_state schedule.event.state
---@param occurrence_start number
---@return number|nil index
function M._occurrence_index(event_state, occurrence_start)
	local cycle_config = event_state.cycle
	if not cycle_config or cycle_config.type ~= "every" or not occurrence_start then
		return nil
	end

	-- `anchor = "end"` spaces occurrences by duration + seconds, so there is no `start_at` grid
	if cycle_config.anchor == "end" then
		return nil
	end

	local interval = cycle_config.seconds
	if not interval or interval <= 0 then
		return nil
	end

	local anchor = event_state.start_at and time.normalize_time(event_state.start_at) or nil
	if not anchor then
		return nil
	end

	return math.max(0, math.floor((occurrence_start - anchor) / interval + 1e-9))
end


---Set cycle_count to the calendar occurrence index, or increment when there is no grid.
---@param event_state schedule.event.state
---@param occurrence_start number
---@param increment_if_unknown boolean
function M._set_cycle_count(event_state, occurrence_start, increment_if_unknown)
	local index = M._occurrence_index(event_state, occurrence_start)
	if index then
		event_state.cycle_count = index
	elseif increment_if_unknown then
		event_state.cycle_count = (event_state.cycle_count or 0) + 1
	end
end


---Activate a cycle for an event
---@param event_id string
---@param event_state schedule.event.state
---@param new_start_time number
---@param new_end_time number|nil
---@param occurrence_start number|nil Grid occurrence this run belongs to
function M._activate_cycle(event_id, event_state, new_start_time, new_end_time, occurrence_start)
	occurrence_start = occurrence_start or new_start_time
	event_state.status = "active"
	event_state.start_time = new_start_time
	event_state.end_time = new_end_time
	M._set_cycle_count(event_state, occurrence_start, true)
	event_state.next_cycle_time = M._following_cycle(event_state, occurrence_start)

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
	local window_ended = new_end_time and current_time >= new_end_time
	if not window_ended and not M._is_below_min_time(event_state, new_start_time, current_time) then
		return false, nil
	end

	-- Stay on the same interval grid as later cycles, do not jump from `now`
	local skipped_cycle_time = M._next_cycle_after(event_state, new_start_time, current_time)
	if skipped_cycle_time == new_start_time then
		skipped_cycle_time = M._following_cycle(event_state, new_start_time)
	end
	return true, skipped_cycle_time
end


---How far apart two occurrence starts are for an `every` cycle.
---`anchor = "end"` waits the interval after the window closes, so its period is the window
---plus the interval.
---@param event_state schedule.event.state
---@param occurrence_start number
---@return number|nil period
function M._occurrence_period(event_state, occurrence_start)
	local cycle_config = event_state.cycle
	local interval = cycle_config and cycle_config.seconds
	if not interval or interval <= 0 then
		return nil
	end

	if cycle_config.anchor ~= "end" then
		return interval
	end

	-- No window to wait after, fall back to the plain interval
	local occurrence_end = M.join_end(event_state, occurrence_start)
	if not occurrence_end or occurrence_end <= occurrence_start then
		return interval
	end

	return interval + (occurrence_end - occurrence_start)
end


---Get the occurrence right after the given one, without skipping anything in between
---@param event_state schedule.event.state
---@param occurrence_start number Occurrence start to step from
---@return number|nil next_cycle_time
function M._following_cycle(event_state, occurrence_start)
	local cycle_config = event_state.cycle
	if not cycle_config then
		return nil
	end

	if cycle_config.type == "every" then
		local period = M._occurrence_period(event_state, occurrence_start)
		if not period then
			return nil
		end
		return occurrence_start + period
	end

	return cycles.calculate_next_cycle(cycle_config, occurrence_start + 1, occurrence_start, event_state.start_time)
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

		local cycle_join_end = M.join_end(event_state, cycle_start)
		if not cycle_join_end or cycle_join_end > current_time then
			break
		end

		local occurrence_start = cycle_start
		local cycle_run_end = M.calculate_end_time(event_state, occurrence_start) or cycle_join_end
		table.insert(finished_cycles, { start = occurrence_start, end_time = cycle_run_end })
		cycle_start = M._following_cycle(event_state, occurrence_start)
	end

	-- At the step limit the remaining missed occurrences are dropped, use max_catches to bound this
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

	return M._collect_finished_cycles(event_state, M._following_cycle(event_state, event_state.start_time),
		current_time, M._get_catchup_budget(event_id, event_state))
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
---It has to be the one right after the last, not the next future one: an occurrence started
---while the game was closed can still be running.
---@param event_state schedule.event.state
---@param current_time number
---@return number|nil next_cycle_time
function M._get_next_cycle_time(event_state, current_time)
	if event_state.next_cycle_time then
		return event_state.next_cycle_time
	end

	local cycle_config = event_state.cycle
	if not cycle_config then
		return nil
	end

	local occurrence_start = event_state.start_time
	if occurrence_start then
		return M._following_cycle(event_state, occurrence_start)
	end

	return cycles.calculate_next_cycle(cycle_config, current_time, event_state.end_time, event_state.start_time)
end


---Get the cycle occurrence that follows the given one
---@param event_state schedule.event.state
---@param occurrence_start number Occurrence start to step from
---@param current_time number
---@return number|nil next_cycle_time
function M._next_cycle_after(event_state, occurrence_start, current_time)
	local cycle_config = event_state.cycle
	if not cycle_config then
		return nil
	end

	-- Interval cycles are evenly spaced, so a long offline period is one jump instead of a walk
	if cycle_config.type == "every" then
		local period = M._occurrence_period(event_state, occurrence_start)
		if not period then
			return nil
		end

		if occurrence_start + period <= current_time then
			local missed_periods = math.floor((current_time - occurrence_start) / period)
			return occurrence_start + missed_periods * period
		end

		return occurrence_start + period
	end

	return cycles.calculate_next_cycle(cycle_config, occurrence_start + 1, occurrence_start, event_state.start_time)
end


---Resolve which cycle occurrence the event should be on right now.
---Occurrences that already ended are stepped over, never activated and never swallowed.
---@param event_state schedule.event.state
---@param current_time number
---@param from_time number|nil Start from this occurrence instead of the stored next cycle
---@return number|nil cycle_time Occurrence that is still running, or the next upcoming one
function M._resolve_cycle_time(event_state, current_time, from_time)
	local cycle_time = from_time or M._get_next_cycle_time(event_state, current_time)
	if not cycle_time or cycle_time > current_time then
		return cycle_time
	end

	for _ = 1, MAX_CYCLE_STEPS do
		local cycle_end = M.join_end(event_state, cycle_time)
		if not cycle_end or cycle_end > current_time then
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
	for _ = 1, MAX_CYCLE_STEPS do
		local next_cycle_time = M._resolve_cycle_time(event_state, current_time)

		if not next_cycle_time or next_cycle_time > current_time then
			event_state.next_cycle_time = next_cycle_time
			if next_cycle_time then
				event_state.start_time = next_cycle_time
				event_state.status = "pending"
			end
			return false
		end

		local new_start_time = next_cycle_time
		local new_end_time = M.join_end(event_state, new_start_time)

		local should_skip, skipped_cycle_time = M._should_skip_cycle(event_state, new_start_time, new_end_time, current_time)
		if should_skip then
			event_state.next_cycle_time = skipped_cycle_time
		else
			-- Land on this occurrence as pending first. min_time skip of an old window
			-- must not activate the current one without conditions (LiveOps level gate).
			event_state.status = "pending"
			event_state.start_time = new_start_time
			event_state.end_time = new_end_time
			if not M.should_start_event(event_id, event_state, current_time, nil) then
				return false
			end

			local actual_start, run_end = M._run_times(event_state, new_start_time, current_time)
			M._activate_cycle(event_id, event_state, actual_start, run_end, new_start_time)
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
		if M._process_catchup_cycles(event_id, event_state, current_time) then
			return true
		end
		return M._process_next_cycle(event_id, event_state, current_time)
	end

	return false
end


---Fill `start_time` from config, chained parent, or a stale calendar start.
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil
---@return number|nil start_time
function M._ensure_start_time(event_state, current_time, last_update_time)
	local start_time = event_state.start_time
	if not start_time then
		start_time = M.calculate_start_time(event_state, current_time, last_update_time)
		if start_time then
			event_state.start_time = start_time
		end
	end

	local after = event_state.after
	if type(after) == "string" then
		local after_status = state.get_event_state(after)
		if after_status and chaining.is_chain_parent_ready(after_status, current_time) then
			if not start_time or start_time < after_status.end_time then
				start_time = chaining.get_chain_start_time(event_state, after_status, current_time)
				event_state.start_time = start_time
			end
		end
	end

	return M._align_stale_calendar_start(event_state, start_time, current_time)
end


---Pending waits until `now >= start_time`. A stale future start_time would never start.
---Land on the current or next occurrence from `start_at`. Do not rewind to the first
---window: that marks the event completed on restart.
---Only restored state can be stale, so this runs once per restore, not on every update.
---@param event_state schedule.event.state
---@param start_time number|nil
---@param current_time number
---@return number|nil start_time
function M._align_stale_calendar_start(event_state, start_time, current_time)
	if not is_cold_start then
		return start_time
	end

	if not M._is_pending(event_state.status) or not event_state.cycle or not event_state.start_at then
		return start_time
	end
	if not start_time or start_time <= current_time then
		return start_time
	end

	local anchor = time.normalize_time(event_state.start_at)
	if not anchor or start_time <= anchor then
		return start_time
	end

	local occurrence = M._resolve_cycle_time(event_state, current_time, anchor)
	if occurrence and occurrence ~= start_time then
		event_state.start_time = occurrence
		event_state.end_time = M.join_end(event_state, occurrence)
		return occurrence
	end

	return start_time
end


---The window already ended before this update. Replay it when catch_up is on,
---otherwise close it silently (LiveOps) and let the cycle path move forward.
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number
---@param end_time number
---@param current_time number
function M._close_elapsed_start(event_id, event_state, start_time, end_time, current_time)
	if event_state.catch_up then
		M._replay_event_run(event_id, event_state, start_time, end_time, current_time)
	else
		event_state.start_time = start_time
		event_state.end_time = end_time
		event_state.last_update_time = current_time
	end
	event_state.status = "completed"
	M.process_cycle(event_id, event_state, current_time)
end


---Start a pending event whose start_time is due, or close it if the window already ended.
---@param event_id string
---@param event_state schedule.event.state
---@param start_time number
---@param current_time number
---@return boolean started
function M._open_or_close_window(event_id, event_state, start_time, current_time)
	local join_end = M.join_end(event_state, start_time)

	if join_end and current_time >= join_end then
		M._close_elapsed_start(event_id, event_state, start_time, join_end, current_time)
		return true
	end

	local actual_start, run_end = M._run_times(event_state, start_time, current_time)
	M._activate_event(event_id, event_state, actual_start, run_end, current_time, start_time)

	-- A chained event with no duration is a trigger: fire and complete in the same update
	if not run_end and not event_state.infinity and event_state.after and not event_state.start_at then
		M._complete_event(event_id, event_state, actual_start, run_end, current_time)
		M.process_cycle(event_id, event_state, current_time)
	end

	return true
end


---Catch up, resolve start, then start if the event is still pending and due.
---Paused events only resolve start_time here.
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil
---@return boolean handled True if this update already finished the event
function M._step_pending(event_id, event_state, current_time, last_update_time)
	local status = event_state.status
	if not M._is_pending(status) and status ~= "paused" then
		return false
	end

	if event_state.catch_up and last_update_time then
		M.process_catchup(event_id, event_state, last_update_time, current_time)
	end

	local start_time = M._ensure_start_time(event_state, current_time, last_update_time)

	-- Catch-up may have already moved the event out of pending
	if not M._is_pending(event_state.status) or not start_time or current_time < start_time then
		return false
	end

	if M._cancel_or_skip_min_time(event_id, event_state, start_time, current_time) then
		return true
	end

	if not M.should_start_event(event_id, event_state, current_time, last_update_time) then
		return false
	end

	return M._open_or_close_window(event_id, event_state, start_time, current_time)
end


---Complete an active event that has reached its end, including offline catch-up.
---@param event_id string
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil
---@return boolean handled
function M._step_active(event_id, event_state, current_time, last_update_time)
	if event_state.status ~= "active" then
		return false
	end

	if event_state.catch_up and last_update_time then
		if M.process_catchup(event_id, event_state, last_update_time, current_time) then
			M.process_cycle(event_id, event_state, current_time)
			return true
		end
		return false
	end

	local end_time = event_state.end_time
	if end_time and current_time >= end_time then
		M._complete_event(event_id, event_state, nil, end_time, current_time)
		M.process_cycle(event_id, event_state, current_time)
		return true
	end

	return false
end


---Update a single event: start, end, then advance cycles.
---@param event_id string
---@param current_time number
---@param last_update_time number|nil
---@return boolean event_updated True if event was updated, false otherwise
function M.update_event(event_id, current_time, last_update_time)
	local event_state = state.get_event_state(event_id)
	if not event_state then
		return false
	end

	if M._step_pending(event_id, event_state, current_time, last_update_time) then
		return true
	end

	if M._step_active(event_id, event_state, current_time, last_update_time) then
		return true
	end

	if event_state.status == "paused" then
		return false
	end

	if event_state.status == "completed" and M.process_cycle(event_id, event_state, current_time) then
		return true
	end

	event_state.last_update_time = current_time
	return false
end


---Update all events
---@param current_time number
function M.update_all(current_time)
	local last_update_time = state.get_last_update_time()
	local all_events = state.get_all_events()
	-- A gate condition that looks at other events relies on the higher priority event
	-- being processed already, so the order must not come from the table hash order
	local ordered_event_ids = state.get_ordered_event_ids()
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

	is_cold_start = not active_events_ready
	if is_cold_start then
		for _, event_id in ipairs(ordered_event_ids) do
			local event_state = all_events[event_id]
			if event_state and event_state.status == "active" then
				lifecycle.on_enabled(event_id, M._create_event_data(event_id, event_state))
			end
		end
	end

	for event_id in pairs(catchup_counts) do
		catchup_counts[event_id] = nil
	end

	local has_chained_events = false
	for _, event_id in ipairs(ordered_event_ids) do
		-- A lifecycle callback of an earlier event could have removed this one
		local event_state = all_events[event_id]
		if event_state then
			if type(event_state.after) == "string" then
				has_chained_events = true
			end

			local status = event_state.status
			if M._is_pending(status) or status == "paused" or status == "active"
				or (status == "completed" and event_state.cycle) then
				if M.update_event(event_id, current_time, last_update_time) then
					any_updated = true
				end
			end
		end
	end

	if has_chained_events then
		any_updated = chaining.update_chained_events(ordered_event_ids, current_time, last_update_time, M._is_pending, M.update_event) or any_updated
	end

	is_cold_start = false
	active_events_ready = true

	state.set_last_update_time(current_time)
	return any_updated
end


---Check if event status allows starting. "cancelled", "aborted" and "failed" are terminal:
---the update loop never revives them, only an explicit `event:start()` does.
---@param status string
---@return boolean
function M._is_pending(status)
	return status == "pending"
end


---If payload was never set (legacy save), store `{}` once so later reads share the same table.
---@param event_state schedule.event.state
---@return any payload
function M._normalize_payload(event_state)
	if event_state.payload == nil then
		event_state.payload = {}
	end
	return event_state.payload
end


---Create event data table
---@param event_id string
---@param event_state schedule.event.state
---@return table event_data
function M._create_event_data(event_id, event_state)
	return {
		event_id = event_id,
		category = event_state.category,
		payload = M._normalize_payload(event_state),
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
---@param occurrence_start number|nil Grid occurrence this run belongs to
function M._activate_event(event_id, event_state, start_time, end_time, current_time, occurrence_start)
	occurrence_start = occurrence_start or start_time
	local increment = event_state.cycle and event_state.end_time and occurrence_start > event_state.end_time
	event_state.status = "active"
	event_state.start_time = start_time
	event_state.end_time = end_time
	event_state.last_update_time = current_time
	M._set_cycle_count(event_state, occurrence_start, increment)
	if event_state.cycle then
		event_state.next_cycle_time = M._following_cycle(event_state, occurrence_start)
	end
	M._update_chained_events(event_id)

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
	M._set_cycle_count(event_state, cycle_start, true)
	M._replay_event_run(event_id, event_state, cycle_start, cycle_end, current_time)
end


return M

