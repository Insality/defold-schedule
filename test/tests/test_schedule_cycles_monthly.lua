return function()
	describe("Schedule Cycles Monthly", function()
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

		it("Should calculate the next monthly occurrence", function()
			local next_cycle = cycles.calculate_next_cycle({ type = "monthly", day = 15 }, JAN_1)

			assert(as_date(next_cycle) == "2026-01-15 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should respect the time option", function()
			local next_cycle = cycles.calculate_next_cycle({ type = "monthly", day = 15, time = "09:30" }, JAN_1)

			assert(as_date(next_cycle) == "2026-01-15 09:30", "Got " .. as_date(next_cycle))
		end)


		it("Should roll to the next month when the day has passed", function()
			-- 2026-01-20, targeting day 15
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "monthly", day = 15, time = "09:30" }, JAN_1 + 19 * 86400)

			assert(as_date(next_cycle) == "2026-02-15 09:30", "Got " .. as_date(next_cycle))
		end)


		it("Should return the same day when the target time is still ahead", function()
			-- 2026-01-15 08:00, targeting 09:30 the same day
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "monthly", day = 15, time = "09:30" }, JAN_1 + 14 * 86400 + 8 * 3600)

			assert(as_date(next_cycle) == "2026-01-15 09:30", "Got " .. as_date(next_cycle))
		end)


		it("Should clamp day 31 to the last day of a short month", function()
			-- February 2026 has 28 days
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "monthly", day = 31 }, JAN_1 + 31 * 86400)

			assert(as_date(next_cycle) == "2026-02-28 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should default to the first day of the month", function()
			local next_cycle = cycles.calculate_next_cycle({ type = "monthly" }, JAN_1 + 5 * 86400)

			assert(as_date(next_cycle) == "2026-02-01 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should cycle a monthly event through update", function()
			time = JAN_1
			local event = schedule.event()
				:category("reward")
				:cycle("monthly", { day = 15, time = "00:00" })
				:duration(86400)
				:save()

			schedule.update()
			assert(event:get_status() == "pending", "Should wait for the 15th")

			time = JAN_1 + 14 * 86400
			schedule.update()
			assert(event:get_status() == "active", "Should activate on the 15th")

			time = time + 86400
			schedule.update()
			assert(event:get_status() == "completed", "Should complete after the duration")

			-- February 15th
			time = JAN_1 + 45 * 86400
			schedule.update()
			assert(event:get_status() == "active", "Should activate again next month")
		end)
	end)
end
