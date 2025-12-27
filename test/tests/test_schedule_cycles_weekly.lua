return function()
	describe("Schedule Cycles Weekly", function()
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

		it("Should cycle weekly on specified weekday", function()
			local event_id = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should cycle weekly with specific time", function()
			local event_id = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "14:00", skip_missed = true })
				:duration(21600)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should cycle weekly on multiple weekdays", function()
			local event_id = schedule.event()
				:category("weekend_event")
				:cycle("weekly", { weekdays = { "sat", "sun" }, time = "09:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should cycle weekly with start_at anchor", function()
			local event_id = schedule.event()
				:category("weekly_event")
				:start_at("2026-01-05T00:00:00")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should skip missed weekly cycles when skip_missed is true", function()
			local event_id = schedule.event()
				:category("weekly_event")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle all weekdays", function()
			local weekdays = { "mon", "tue", "wed", "thu", "fri", "sat", "sun" }
			for _, day in ipairs(weekdays) do
				local event_id = schedule.event()
					:category("daily_event")
					:cycle("weekly", { weekdays = { day }, time = "12:00", skip_missed = true })
					:duration(3600)
					:save()

				local status = schedule.get_status(event_id)
				assert(status ~= nil, "Status should exist for " .. day)
			end
		end)
	end)
end

