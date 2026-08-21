---Event chaining logic
local state = require("schedule.internal.schedule_state")
local logger = require("schedule.internal.schedule_logger")

local M = {}

---Safety cap for walking a chain of events in a single update
local MAX_CHAIN_PASSES = 128


---Resolve the start time of an event chained after a completed one.
---With `wait_online` the child starts counting when the player is back, otherwise it starts
---right when the parent ended, so an offline gap counts towards the child.
---@param event_state schedule.event.state Chained event state
---@param after_status schedule.event.state Completed parent event state
---@param current_time number
---@return number start_time
function M.get_chain_start_time(event_state, after_status, current_time)
	local parent_end_time = after_status.end_time or current_time

	local wait_online = event_state.after_options and event_state.after_options.wait_online
	if wait_online == true then
		return math.max(parent_end_time, current_time)
	end

	return parent_end_time
end


---Check if event can start based on chaining
---@param after_event_id string Event ID to chain after
---@param event_state schedule.event.state
---@param current_time number
---@param last_update_time number|nil Last update time to check if parent just completed
---@return boolean can_start
---@return number|nil start_time Calculated start time if can start
function M.can_start_chain(after_event_id, event_state, current_time, last_update_time)
	if not after_event_id or type(after_event_id) ~= "string" then
		return true, nil
	end
	local after_status = state.get_event_state(after_event_id)

	if not after_status then
		return false, nil
	end

	if after_status.status ~= "completed" then
		return false, nil
	end

	if current_time < (after_status.end_time or current_time) then
		return false, nil
	end

	return true, M.get_chain_start_time(event_state, after_status, current_time)
end


---Update chained events - processes events that chain after other events
---Updates start_time for chained events when their parent events complete
---@param all_events table<string, schedule.event.state> All events to check
---@param current_time number Current time
---@param last_update_time number|nil Last update time
---@param is_startable_status fun(status: string): boolean Function to check if status allows starting
---@param update_event fun(event_id: string, current_time: number, last_update_time: number|nil): boolean Function to update an event
---@return boolean any_updated True if any events were updated
function M.update_chained_events(all_events, current_time, last_update_time, is_startable_status, update_event)
	local any_updated = false
	local continue_chain = true
	local passes = 0

	-- One pass can complete a parent and unlock its child, so the chain is walked until it settles.
	-- The cap keeps a cyclic chain from hanging the update loop
	while continue_chain and passes < MAX_CHAIN_PASSES do
		continue_chain = false
		passes = passes + 1
		for event_id, event_state in pairs(all_events) do
			if type(event_state.after) == "string" then
				local after_event_id = event_state.after
				local after_status = state.get_event_state(after_event_id)
				if after_status and after_status.status == "completed" and after_status.end_time then
					local current_event_state = state.get_event_state(event_id)
					if current_event_state and (is_startable_status(current_event_state.status) or current_event_state.status == "paused") then
						if not current_event_state.start_time or current_event_state.start_time < after_status.end_time then
							current_event_state.start_time = M.get_chain_start_time(current_event_state, after_status, current_time)
							local updated = update_event(event_id, current_time, last_update_time)
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

	if passes >= MAX_CHAIN_PASSES then
		logger:warn("Chain update stopped at the pass limit, check for events chained in a loop")
	end

	return any_updated
end


return M

