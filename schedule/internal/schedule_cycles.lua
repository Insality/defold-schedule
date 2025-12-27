---Cycle calculations for recurring events
local time_utils = require("schedule.internal.schedule_time")


local M = {}


---Calculate next occurrence for "every" cycle
---@param cycle_config schedule.cycle_config
---@param current_time number
---@param last_cycle_time number|nil
---@param anchor_time number|nil Original anchor time
---@return number|nil next_cycle_time
function M.calculate_next_every(cycle_config, current_time, last_cycle_time, anchor_time)
	if not cycle_config.seconds or cycle_config.seconds <= 0 then
		return nil
	end

	local anchor = cycle_config.anchor or "start"
	local base_time
	if anchor == "end" and last_cycle_time then
		base_time = last_cycle_time
	elseif anchor_time then
		base_time = anchor_time
	else
		base_time = current_time
	end

	local next_time = base_time + cycle_config.seconds

	if cycle_config.skip_missed then
		while next_time < current_time do
			next_time = next_time + cycle_config.seconds
		end
	else
		if next_time < current_time then
			next_time = current_time + cycle_config.seconds
		end
	end

	return next_time
end


---Calculate next occurrence for "weekly" cycle
---@param cycle_config schedule.cycle_config
---@param current_time number
---@param anchor_time number|nil Original anchor time
---@return number|nil next_cycle_time
function M.calculate_next_weekly(cycle_config, current_time, anchor_time)
	if not cycle_config.weekdays or #cycle_config.weekdays == 0 then
		return nil
	end

	local current_year, current_month, current_day, current_hour, current_minute, current_second, current_weekday = time_utils.timestamp_to_date(current_time)
	local target_hour, target_minute, target_second = time_utils.parse_time_string(cycle_config.time or "00:00")
	if not target_hour then
		target_hour = 0
		target_minute = 0
		target_second = 0
	end

	local target_weekdays = {}
	for _, weekday_name in ipairs(cycle_config.weekdays) do
		local weekday_num = time_utils.weekday_to_number(weekday_name)
		if weekday_num then
			table.insert(target_weekdays, weekday_num)
		end
	end

	if #target_weekdays == 0 then
		return nil
	end

	table.sort(target_weekdays)

	local days_ahead = 0
	local max_days = 14

	for check_day = 0, max_days do
		local check_weekday = ((current_weekday - 1 + check_day) % 7) + 1
		for _, target_weekday in ipairs(target_weekdays) do
			if check_weekday == target_weekday then
				local candidate_time = current_time + (check_day * 86400)
				local candidate_year, candidate_month, candidate_day = time_utils.timestamp_to_date(candidate_time)
				local target_timestamp = time_utils.parse_iso_date(string.format("%04d-%02d-%02dT%02d:%02d:%02d",
					candidate_year, candidate_month, candidate_day, target_hour, target_minute, target_second))

				if target_timestamp and target_timestamp >= current_time then
					return target_timestamp
				end
			end
		end
	end

	return nil
end


---Calculate next occurrence for "monthly" cycle
---@param cycle_config schedule.cycle_config
---@param current_time number
---@param anchor_time number|nil Original anchor time
---@return number|nil next_cycle_time
function M.calculate_next_monthly(cycle_config, current_time, anchor_time)
	local target_day = cycle_config.day or 1
	local target_hour, target_minute, target_second = time_utils.parse_time_string(cycle_config.time or "00:00")
	if not target_hour then
		target_hour = 0
		target_minute = 0
		target_second = 0
	end

	local current_year, current_month, current_day = time_utils.timestamp_to_date(current_time)
	local days_in_current_month = time_utils.get_days_in_month(current_year, current_month)

	if target_day > days_in_current_month then
		target_day = days_in_current_month
	end

	local candidate_time = time_utils.parse_iso_date(string.format("%04d-%02d-%02dT%02d:%02d:%02d",
		current_year, current_month, target_day, target_hour, target_minute, target_second))

	if candidate_time and candidate_time >= current_time then
		return candidate_time
	end

	current_month = current_month + 1
	if current_month > 12 then
		current_month = 1
		current_year = current_year + 1
	end

	local days_in_next_month = time_utils.get_days_in_month(current_year, current_month)
	local final_day = target_day
	if final_day > days_in_next_month then
		final_day = days_in_next_month
	end

	return time_utils.parse_iso_date(string.format("%04d-%02d-%02dT%02d:%02d:%02d",
		current_year, current_month, final_day, target_hour, target_minute, target_second))
end


---Calculate next occurrence for "yearly" cycle
---@param cycle_config schedule.cycle_config
---@param current_time number
---@param anchor_time number|nil Original anchor time
---@return number|nil next_cycle_time
function M.calculate_next_yearly(cycle_config, current_time, anchor_time)
	local target_month = cycle_config.month or 1
	local target_day = cycle_config.day or 1
	local target_hour, target_minute, target_second = time_utils.parse_time_string(cycle_config.time or "00:00")
	if not target_hour then
		target_hour = 0
		target_minute = 0
		target_second = 0
	end

	local current_year, current_month, current_day = time_utils.timestamp_to_date(current_time)

	local candidate_year = current_year
	if current_month > target_month or (current_month == target_month and current_day >= target_day) then
		candidate_year = current_year + 1
	end

	local days_in_target_month = time_utils.get_days_in_month(candidate_year, target_month)
	local final_day = target_day
	if final_day > days_in_target_month then
		final_day = days_in_target_month
	end

	return time_utils.parse_iso_date(string.format("%04d-%02d-%02dT%02d:%02d:%02d",
		candidate_year, target_month, final_day, target_hour, target_minute, target_second))
end


---Calculate next cycle occurrence
---@param cycle_config schedule.cycle_config
---@param current_time number
---@param last_cycle_time number|nil
---@param anchor_time number|nil
---@return number|nil next_cycle_time
function M.calculate_next_cycle(cycle_config, current_time, last_cycle_time, anchor_time)
	if not cycle_config or not cycle_config.type then
		return nil
	end

	if cycle_config.type == "every" then
		return M.calculate_next_every(cycle_config, current_time, last_cycle_time, anchor_time)
	elseif cycle_config.type == "weekly" then
		return M.calculate_next_weekly(cycle_config, current_time, anchor_time)
	elseif cycle_config.type == "monthly" then
		return M.calculate_next_monthly(cycle_config, current_time, anchor_time)
	elseif cycle_config.type == "yearly" then
		return M.calculate_next_yearly(cycle_config, current_time, anchor_time)
	end

	return nil
end


return M

