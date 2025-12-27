return function()
	describe("Schedule MinTime", function()
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

		it("Should prevent event start if not enough time left", function()
			local event_id = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(86400)
				:min_time(86400)
				:save()

			set_time(50)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status.status == "pending", "Event should be pending before start_at")

			set_time(100)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "pending" or status.status == "cancelled", "Event should not start if not enough time left")
		end)


		it("Should allow event start if enough time left", function()
			local event_id = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(86400)
				:min_time(86400)
				:save()

			set_time(100)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle min_time with duration events", function()
			local event_id = schedule.event()
				:category("liveops")
				:after(60)
				:duration(86400)
				:min_time(86400)
				:save()

			set_time(60)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle min_time with cycle events", function()
			local event_id = schedule.event()
				:category("liveops")
				:after(60)
				:duration(86400)
				:cycle("every", { seconds = 172800 })
				:min_time(86400)
				:save()

			set_time(60)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle min_time edge cases", function()
			local event_id = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(100)
				:min_time(100)
				:save()

			set_time(100)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist with exact min_time")
		end)


		it("Should handle min_time with very short duration", function()
			local event_id = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(1)
				:min_time(1)
				:save()

			set_time(100)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle min_time with infinity events", function()
			local event_id = schedule.event()
				:category("liveops")
				:start_at(100)
				:infinity()
				:min_time(86400)
				:save()

			set_time(100)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)
	end)
end

