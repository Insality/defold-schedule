--- Time utilities for schedule system
local M = {}


---Custom time function override (for testing)
---@type fun():number|nil
M.set_time_function = nil


---Get current time in seconds
---Override this to use custom time source
---@return number
function M.get_time()
	if M.set_time_function then
		local time = M.set_time_function()
		if time then
			return time
		end
	end
	return socket.gettime()
end


---Parse ISO date string to timestamp
---@param iso_string string ISO date string (e.g., "2026-01-01T00:00:00")
---@return number|nil Timestamp in seconds, nil if invalid
function M.parse_iso_date(iso_string)
	if type(iso_string) == "number" then
		return iso_string
	end

	if type(iso_string) ~= "string" then
		return nil
	end

	local year, month, day, hour, min, sec = iso_string:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)")
	if not year then
		return nil
	end

	year = tonumber(year)
	month = tonumber(month)
	day = tonumber(day)
	hour = tonumber(hour)
	min = tonumber(min)
	sec = tonumber(sec)

	if not year or not month or not day or not hour or not min or not sec then
		return nil
	end

	local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local is_leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
	if is_leap then
		days_in_month[2] = 29
	end

	if month < 1 or month > 12 or day < 1 or day > days_in_month[month] then
		return nil
	end

	local timestamp = 0
	for y = 1970, year - 1 do
		local is_leap_y = (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
		timestamp = timestamp + (is_leap_y and 366 or 365) * 86400
	end

	for m = 1, month - 1 do
		local days = days_in_month[m]
		if m == 2 and is_leap then
			days = 29
		end
		timestamp = timestamp + days * 86400
	end

	timestamp = timestamp + (day - 1) * 86400
	timestamp = timestamp + hour * 3600
	timestamp = timestamp + min * 60
	timestamp = timestamp + sec

	return timestamp
end


---Convert timestamp to date components
---@param timestamp number
---@return number year
---@return number month (1-12)
---@return number day (1-31)
---@return number hour (0-23)
---@return number minute (0-59)
---@return number second (0-59)
---@return number weekday (1=Sunday, 7=Saturday)
function M.timestamp_to_date(timestamp)
	local days_since_epoch = math.floor(timestamp / 86400)
	local seconds_in_day = timestamp % 86400

	local year = 1970
	local days_in_year = 365
	local is_leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
	if is_leap then
		days_in_year = 366
	end

	while days_since_epoch >= days_in_year do
		days_since_epoch = days_since_epoch - days_in_year
		year = year + 1
		is_leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
		days_in_year = is_leap and 366 or 365
	end

	local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if is_leap then
		days_in_month[2] = 29
	end

	local month = 1
	local day = days_since_epoch + 1
	while day > days_in_month[month] do
		day = day - days_in_month[month]
		month = month + 1
	end

	local hour = math.floor(seconds_in_day / 3600)
	local minute = math.floor((seconds_in_day % 3600) / 60)
	local second = seconds_in_day % 60

	local weekday = ((days_since_epoch + 4) % 7) + 1

	return year, month, day, hour, minute, second, weekday
end


---Parse time string (HH:MM or HH:MM:SS)
---@param time_string string
---@return number|nil hour (0-23)
---@return number|nil minute (0-59)
---@return number|nil second (0-59, default 0)
function M.parse_time_string(time_string)
	if type(time_string) ~= "string" then
		return nil, nil, nil
	end

	local hour, minute, second = time_string:match("^(%d%d):(%d%d):?(%d%d)?$")
	if not hour then
		return nil, nil, nil
	end

	hour = tonumber(hour)
	minute = tonumber(minute)
	second = tonumber(second) or 0

	if hour and minute and second and hour >= 0 and hour < 24 and minute >= 0 and minute < 60 and second >= 0 and second < 60 then
		return hour, minute, second
	end

	return nil, nil, nil
end


---Get days in month
---@param year number
---@param month number
---@return number
function M.get_days_in_month(year, month)
	local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local is_leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
	if is_leap and month == 2 then
		return 29
	end
	return days_in_month[month] or 31
end


---Weekday name to number (1=Sunday, 7=Saturday)
---@param weekday_name string
---@return number|nil
function M.weekday_to_number(weekday_name)
	local weekdays = {
		sun = 1, sunday = 1,
		mon = 2, monday = 2,
		tue = 3, tuesday = 3,
		wed = 4, wednesday = 4,
		thu = 5, thursday = 5,
		fri = 6, friday = 6,
		sat = 7, saturday = 7
	}
	return weekdays[weekday_name:lower()]
end


---Number to weekday name (short)
---@param weekday_number number
---@return string
function M.number_to_weekday(weekday_number)
	local weekdays = { "sun", "mon", "tue", "wed", "thu", "fri", "sat" }
	return weekdays[weekday_number] or "sun"
end


return M

