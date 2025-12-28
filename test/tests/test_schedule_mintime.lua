return function()
	describe("Schedule MinTime", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should prevent event start if not enough time left", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(schedule.WEEK)
				:min_time(schedule.DAY)
				:save()

			time = 50
			schedule.update()
			assert(event:get_status() == "pending", "Event should be pending before start_at")

			time = 100 + schedule.WEEK - schedule.DAY + 1
			schedule.update()
			assert(event:get_status() == "cancelled", "Event should be cancelled if remaining time is less than min_time")
		end)


		it("Should allow event start if enough time left", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(schedule.WEEK)
				:min_time(schedule.DAY)
				:save()

			time = 100
			schedule.update()
			assert(event:get_status() == "active", "Event should start if enough time left")
		end)


		it("Should handle min_time with duration events", function()
			local event = schedule.event()
				:category("liveops")
				:after(schedule.MINUTE)
				:duration(schedule.WEEK)
				:min_time(schedule.DAY)
				:save()

			time = schedule.MINUTE
			schedule.update()
			assert(event:get_status() == "active", "Event should start with enough time remaining")
		end)


		it("Should handle min_time with cycle events", function()
			local event = schedule.event()
				:category("liveops")
				:after(schedule.MINUTE)
				:duration(schedule.WEEK)
				:cycle("every", { seconds = schedule.WEEK * 2 })
				:min_time(schedule.DAY)
				:save()

			time = schedule.MINUTE
			schedule.update()
			assert(event:get_status() == "active", "Event should start with enough time remaining")
		end)


		it("Should cancel event when min_time equals duration", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(schedule.WEEK)
				:min_time(schedule.WEEK)
				:save()

			time = 100
			schedule.update()
			assert(event:get_status() == "cancelled", "Event should be cancelled when min_time equals duration")
		end)


		it("Should cancel event when min_time exceeds duration", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(schedule.WEEK)
				:min_time(schedule.WEEK * 2)
				:save()

			time = 100
			schedule.update()
			assert(event:get_status() == "cancelled", "Event should be cancelled when min_time exceeds duration")
		end)


		it("Should handle min_time with very short duration", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:duration(100 * schedule.SECOND)
				:min_time(50 * schedule.SECOND)
				:save()

			time = 100
			schedule.update()
			assert(event:get_status() == "active", "Event should start when min_time is less than duration")
		end)


		it("Should handle min_time with infinity events", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(100)
				:infinity()
				:min_time(schedule.DAY)
				:save()

			time = 100
			schedule.update()
			assert(event:get_status() == "active", "Infinity event should start regardless of min_time")
		end)


		it("Should handle min_time with typical week-long event", function()
			local event = schedule.event()
				:category("liveops")
				:start_at(1000)
				:duration(schedule.WEEK)
				:min_time(schedule.DAY)
				:save()

			time = 1000
			schedule.update()
			assert(event:get_status() == "active", "Week-long event should start with one day min_time")

			time = 1000 + schedule.WEEK - schedule.DAY
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active with exactly min_time remaining")
		end)
	end)
end

