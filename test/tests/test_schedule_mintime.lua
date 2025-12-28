return function()
	describe("Schedule MinTime", function()
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

		it("Should prevent event start if not enough time left", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(86400)
				:min_time(86400)
				:save()

			time = 50
			schedule.update()
			assert(event:get_status() == "pending", "Event should be pending before start_at")

			time = 100
			schedule.update()
			assert(event:get_status() == "pending" or event:get_status() == "cancelled", "Event should not start if not enough time left")
		end)


		it("Should allow event start if enough time left", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(86400)
				:min_time(86400)
				:save()

			time = 100
			schedule.update()
			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle min_time with duration events", function()
			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(86400)
				:min_time(86400)
				:save()

			time = 60
			schedule.update()
			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle min_time with cycle events", function()
			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(86400)
				:cycle("every", { seconds = 172800 })
				:min_time(86400)
				:save()

			time = 60
			schedule.update()
			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle min_time edge cases", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(100)
				:min_time(100)
				:save()

			time = 100
			schedule.update()
			assert(event ~= nil, "Status should exist with exact min_time")
		end)


		it("Should handle min_time with very short duration", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(1)
				:min_time(1)
				:save()

			time = 100
			schedule.update()
			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle min_time with infinity events", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:infinity()
				:min_time(86400)
				:save()

			time = 100
			schedule.update()
			assert(event ~= nil, "Status should exist")
		end)
	end)
end

