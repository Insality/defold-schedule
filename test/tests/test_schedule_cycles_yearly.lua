return function()
	describe("Schedule Cycles Yearly", function()
		local schedule ---@type schedule
		local schedule_time
		local cycles
		local time = 0

		-- 2026-01-01T00:00:00 UTC
		local JAN_1 = 1767225600

		before(function()
			schedule = require("schedule.schedule")
			schedule_time = require("schedule.internal.schedule_time")
			cycles = require("schedule.internal.schedule_cycles")

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		---Format a timestamp as "YYYY-MM-DD HH:MM" for readable assertions
		local function as_date(timestamp)
			local year, month, day, hour, minute = schedule_time.timestamp_to_date(timestamp)
			return string.format("%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
		end

		it("Should calculate the next yearly occurrence", function()
			local next_cycle = cycles.calculate_next_cycle({ type = "yearly", month = 12, day = 25 }, JAN_1)

			assert(as_date(next_cycle) == "2026-12-25 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should respect the time option", function()
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "yearly", month = 12, day = 25, time = "18:00" }, JAN_1)

			assert(as_date(next_cycle) == "2026-12-25 18:00", "Got " .. as_date(next_cycle))
		end)


		it("Should roll to the next year when the date has passed", function()
			-- 2026-12-26, targeting December 25th
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "yearly", month = 12, day = 25 }, JAN_1 + 359 * 86400)

			assert(as_date(next_cycle) == "2027-12-25 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should keep the current year when the target time is still ahead", function()
			-- 2026-01-01 08:00, targeting January 1st at 20:00
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "yearly", month = 1, day = 1, time = "20:00" }, JAN_1 + 8 * 3600)

			assert(as_date(next_cycle) == "2026-01-01 20:00", "Got " .. as_date(next_cycle))
		end)


		it("Should clamp February 29th on non leap years", function()
			-- 2027 is not a leap year
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "yearly", month = 2, day = 29 }, JAN_1 + 365 * 86400)

			assert(as_date(next_cycle) == "2027-02-28 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should default to January 1st", function()
			local next_cycle = cycles.calculate_next_cycle({ type = "yearly" }, JAN_1 + 5 * 86400)

			assert(as_date(next_cycle) == "2027-01-01 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should cycle a yearly event through update", function()
			time = JAN_1
			local event = schedule.event()
				:category("anniversary")
				:cycle("yearly", { month = 6, day = 1, time = "12:00" })
				:duration(86400)
				:save()

			schedule.update()
			assert(event:get_status() == "pending", "Should wait for June 1st")

			-- 2026-06-01 12:00
			time = JAN_1 + 151 * 86400 + 12 * 3600
			schedule.update()
			assert(event:get_status() == "active", "Should activate on June 1st")

			time = time + 86400
			schedule.update()
			assert(event:get_status() == "completed", "Should complete after the duration")
		end)
	end)
end
