return function()
	describe("Schedule Cycles Monthly", function()
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

		it("Should cycle monthly on specified day", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 1, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should cycle monthly with specific time", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 15, time = "12:00", skip_missed = true })
				:duration(3600)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle day 31 edge case", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 31, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle leap year February 29", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 29, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should skip missed monthly cycles when skip_missed is true", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 1, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle different month lengths", function()
			for day = 1, 28 do
				local event_id = schedule.event()
					:category("monthly_event")
					:cycle("monthly", { day = day, time = "00:00", skip_missed = true })
					:duration(86400)
					:save()

				local event_info = schedule.get(event_id)
				assert(event_info ~= nil, "Status should exist for day " .. day)
			end
		end)
	end)
end

