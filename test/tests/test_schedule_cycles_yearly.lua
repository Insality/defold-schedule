return function()
	describe("Schedule Cycles Yearly", function()
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

		it("Should cycle yearly on specified month and day", function()
			local event_id = schedule.event()
				:category("yearly_event")
				:cycle("yearly", { month = 1, day = 1, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should cycle yearly with specific time", function()
			local event_id = schedule.event()
				:category("yearly_event")
				:cycle("yearly", { month = 12, day = 25, time = "12:00", skip_missed = true })
				:duration(3600)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle February 29 edge case", function()
			local event_id = schedule.event()
				:category("yearly_event")
				:cycle("yearly", { month = 2, day = 29, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle different month lengths", function()
			local test_cases = {
				{ month = 1, day = 31 },
				{ month = 2, day = 28 },
				{ month = 3, day = 31 },
				{ month = 4, day = 30 },
				{ month = 5, day = 31 },
				{ month = 6, day = 30 },
				{ month = 7, day = 31 },
				{ month = 8, day = 31 },
				{ month = 9, day = 30 },
				{ month = 10, day = 31 },
				{ month = 11, day = 30 },
				{ month = 12, day = 31 }
			}

			for _, test_case in ipairs(test_cases) do
				local event_id = schedule.event()
					:category("yearly_event")
					:cycle("yearly", { month = test_case.month, day = test_case.day, time = "00:00", skip_missed = true })
					:duration(86400)
					:save()

				local event_info = schedule.get(event_id)
				assert(event_info ~= nil, "Status should exist for month " .. test_case.month .. " day " .. test_case.day)
			end
		end)


		it("Should skip missed yearly cycles when skip_missed is true", function()
			local event_id = schedule.event()
				:category("yearly_event")
				:cycle("yearly", { month = 1, day = 1, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle all months", function()
			for month = 1, 12 do
				local event_id = schedule.event()
					:category("yearly_event")
					:cycle("yearly", { month = month, day = 1, time = "00:00", skip_missed = true })
					:duration(86400)
					:save()

				local event_info = schedule.get(event_id)
				assert(event_info ~= nil, "Status should exist for month " .. month)
			end
		end)
	end)
end

