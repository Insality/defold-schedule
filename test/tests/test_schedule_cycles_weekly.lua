return function()
	describe("Schedule Cycles Weekly", function()
		local schedule ---@type schedule
		local schedule_time
		local cycles
		local time = 0

		-- 2026-01-01T00:00:00 UTC is a Thursday
		local THURSDAY = 1767225600

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

		it("Should calculate next Sunday at midnight", function()
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "weekly", weekdays = { "sun" }, time = "00:00" }, THURSDAY)

			assert(as_date(next_cycle) == "2026-01-04 00:00", "Got " .. as_date(next_cycle))
		end)


		it("Should respect the time option", function()
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "weekly", weekdays = { "sun" }, time = "14:00" }, THURSDAY)

			assert(as_date(next_cycle) == "2026-01-04 14:00", "Got " .. as_date(next_cycle))
		end)


		it("Should accept seconds in the time option", function()
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "weekly", weekdays = { "sun" }, time = "14:30:45" }, THURSDAY)

			local _, _, _, hour, minute, second = schedule_time.timestamp_to_date(next_cycle)
			assert(hour == 14 and minute == 30 and second == 45, "Should keep hours, minutes and seconds")
		end)


		it("Should pick the closest of multiple weekdays", function()
			local config = { type = "weekly", weekdays = { "sat", "sun" }, time = "09:00" }

			local next_cycle = cycles.calculate_next_cycle(config, THURSDAY)
			assert(as_date(next_cycle) == "2026-01-03 09:00", "Should pick Saturday, got " .. as_date(next_cycle))

			local after_saturday = cycles.calculate_next_cycle(config, next_cycle + 1)
			assert(as_date(after_saturday) == "2026-01-04 09:00", "Should pick Sunday, got " .. as_date(after_saturday))
		end)


		it("Should return today when the target time is still ahead", function()
			-- Thursday 08:00, targeting Thursday 20:00
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "weekly", weekdays = { "thu" }, time = "20:00" }, THURSDAY + 8 * 3600)

			assert(as_date(next_cycle) == "2026-01-01 20:00", "Got " .. as_date(next_cycle))
		end)


		it("Should roll to the next week when the target time has passed", function()
			-- Thursday 21:00, targeting Thursday 20:00
			local next_cycle = cycles.calculate_next_cycle(
				{ type = "weekly", weekdays = { "thu" }, time = "20:00" }, THURSDAY + 21 * 3600)

			assert(as_date(next_cycle) == "2026-01-08 20:00", "Got " .. as_date(next_cycle))
		end)


		it("Should handle all weekdays", function()
			local weekdays = { "mon", "tue", "wed", "thu", "fri", "sat", "sun" }
			for _, weekday in ipairs(weekdays) do
				local next_cycle = cycles.calculate_next_cycle(
					{ type = "weekly", weekdays = { weekday }, time = "12:00" }, THURSDAY)

				assert(next_cycle ~= nil, "Should calculate a cycle for " .. weekday)
				assert(next_cycle >= THURSDAY, "Cycle should be in the future for " .. weekday)
				assert(next_cycle < THURSDAY + 8 * 86400, "Cycle should be within a week for " .. weekday)

				local _, _, _, hour, minute = schedule_time.timestamp_to_date(next_cycle)
				assert(hour == 12 and minute == 0, "Should be at 12:00 for " .. weekday)

				local _, _, _, _, _, _, result_weekday = schedule_time.timestamp_to_date(next_cycle)
				assert(schedule_time.number_to_weekday(result_weekday) == weekday,
					"Should land on " .. weekday .. ", got " .. schedule_time.number_to_weekday(result_weekday))
			end
		end)


		it("Should return nil without weekdays", function()
			assert(cycles.calculate_next_cycle({ type = "weekly", weekdays = {} }, THURSDAY) == nil)
		end)


		it("Should cycle a weekly event through update", function()
			time = THURSDAY
			local event = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "14:00" })
				:duration(3600)
				:save()

			schedule.update()
			assert(event:get_status() == "pending", "Should wait for the first Sunday")

			-- Sunday 14:00
			time = THURSDAY + 3 * 86400 + 14 * 3600
			schedule.update()
			assert(event:get_status() == "active", "Should activate on Sunday at 14:00")

			time = time + 3600
			schedule.update()
			assert(event:get_status() == "completed", "Should complete after the duration")
		end)
	end)
end
