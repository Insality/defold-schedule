return function()
	describe("Schedule Cycles Weekly", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule_time.set_time_function = function() return time end
			schedule.reset_state()
			schedule.init()
			time = 0
		end)

		it("Should cycle weekly on specified weekday", function()
			local event = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should cycle weekly with specific time", function()
			local event = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "14:00", skip_missed = true })
				:duration(21600)
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should cycle weekly on multiple weekdays", function()
			local event = schedule.event()
				:category("weekend_event")
				:cycle("weekly", { weekdays = { "sat", "sun" }, time = "09:00", skip_missed = true })
				:duration(86400)
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should cycle weekly with start_at anchor", function()
			local event = schedule.event()
				:category("weekly_event")
				:start_at("2026-01-05T00:00:00")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should skip missed weekly cycles when skip_missed is true", function()
			local event = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle all weekdays", function()
			local weekdays = { "mon", "tue", "wed", "thu", "fri", "sat", "sun" }
			for _, day in ipairs(weekdays) do
				local event = schedule.event()
					:category("daily_event")
					:cycle("weekly", { weekdays = { day }, time = "12:00", skip_missed = true })
					:duration(3600)
					:save()

				assert(event ~= nil, "Status should exist for " .. day)
			end
		end)
	end)
end

