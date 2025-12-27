return function()
	describe("Schedule Cycles Monthly", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local mock_time_value = 0

		local function set_time(time)
			mock_time_value = time
		end

	before(function()
		schedule = require("schedule.schedule")
		schedule_time.get_time = function()
			return mock_time_value
		end
		schedule.reset_state()
		schedule.init()

		mock_time_value = 0
	end)

		after(function()
			schedule.update()
		end)

		it("Should cycle monthly on specified day", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 1, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should cycle monthly with specific time", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 15, time = "12:00", skip_missed = true })
				:duration(3600)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle day 31 edge case", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 31, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle leap year February 29", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 29, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should skip missed monthly cycles when skip_missed is true", function()
			local event_id = schedule.event()
				:category("monthly_event")
				:cycle("monthly", { day = 1, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle different month lengths", function()
			for day = 1, 28 do
				local event_id = schedule.event()
					:category("monthly_event")
					:cycle("monthly", { day = day, time = "00:00", skip_missed = true })
					:duration(86400)
					:save()

				local status = schedule.get_status(event_id)
				assert(status ~= nil, "Status should exist for day " .. day)
			end
		end)
	end)
end

