--- Time utilities for schedule system
local M = {}


-- Constants
local EPOCH_YEAR = 1970
local DAYS_IN_YEAR = 365
local DAYS_IN_LEAP_YEAR = 366
local SECONDS_PER_DAY = 86400
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_MINUTE = 60

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local DAYS_IN_MONTH_LEAP = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local WEEKDAY_TO_NUMBER = {
	sun = 1, sunday = 1,
	mon = 2, monday = 2,
	tue = 3, tuesday = 3,
	wed = 4, wednesday = 4,
	thu = 5, thursday = 5,
	fri = 6, friday = 6,
	sat = 7, saturday = 7
}

local NUMBER_TO_WEEKDAY = { "sun", "mon", "tue", "wed", "thu", "fri", "sat" }


---Check if year is a leap year
---@param year number
---@return boolean
local function is_leap_year(year)
	return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
end


---Get days in year
---@param year number
---@return number
local function get_days_in_year(year)
	return is_leap_year(year) and DAYS_IN_LEAP_YEAR or DAYS_IN_YEAR
end


local get_time_callback = socket.gettime


---Set custom time function callback
---@param callback (fun():number)|nil
function M.set_time_function(callback)
	get_time_callback = callback or socket.gettime
end


---Get current time in seconds
---@return number
function M.get_time()
	return get_time_callback()
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

	local is_leap = is_leap_year(year)
	local days_in_month = is_leap and DAYS_IN_MONTH_LEAP or DAYS_IN_MONTH

	if month < 1 or month > 12 or day < 1 or day > days_in_month[month] then
		return nil
	end

	local timestamp = 0
	for y = EPOCH_YEAR, year - 1 do
		timestamp = timestamp + get_days_in_year(y) * SECONDS_PER_DAY
	end

	for m = 1, month - 1 do
		timestamp = timestamp + days_in_month[m] * SECONDS_PER_DAY
	end

	timestamp = timestamp + (day - 1) * SECONDS_PER_DAY
	timestamp = timestamp + hour * SECONDS_PER_HOUR
	timestamp = timestamp + min * SECONDS_PER_MINUTE
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
	local days_since_epoch = math.floor(timestamp / SECONDS_PER_DAY)
	local seconds_in_day = timestamp % SECONDS_PER_DAY

	local year = EPOCH_YEAR
	while days_since_epoch >= get_days_in_year(year) do
		days_since_epoch = days_since_epoch - get_days_in_year(year)
		year = year + 1
	end

	local is_leap = is_leap_year(year)
	local days_in_month = is_leap and DAYS_IN_MONTH_LEAP or DAYS_IN_MONTH

	local month = 1
	local day = days_since_epoch + 1
	while day > days_in_month[month] do
		day = day - days_in_month[month]
		month = month + 1
	end

	local hour = math.floor(seconds_in_day / SECONDS_PER_HOUR)
	local minute = math.floor((seconds_in_day % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
	local second = seconds_in_day % SECONDS_PER_MINUTE

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
	if is_leap_year(year) and month == 2 then
		return DAYS_IN_MONTH_LEAP[month]
	end
	return DAYS_IN_MONTH[month] or 31
end


---Weekday name to number (1=Sunday, 7=Saturday)
---@param weekday_name string
---@return number|nil
function M.weekday_to_number(weekday_name)
	return WEEKDAY_TO_NUMBER[weekday_name:lower()]
end


---Number to weekday name (short)
---@param weekday_number number
---@return string
function M.number_to_weekday(weekday_number)
	return NUMBER_TO_WEEKDAY[weekday_number] or "sun"
end


return M

