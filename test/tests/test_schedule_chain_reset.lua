return function()
	describe("Schedule Chain Reset", function()
		local schedule ---@type schedule
		local schedule_time
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule_time = require("schedule.internal.schedule_time")

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should reset chained event start_time when parent reactivates for cycling events", function()
			local parent = schedule.event()
				:category("craft")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100 })
				:save()

			local child = schedule.event()
				:category("craft")
				:after(parent:get_id())
				:duration(20)
				:save()

			time = 60
			schedule.update()
			assert(parent:get_status() == "active", "Parent should be active")

			time = 90
			schedule.update()
			assert(parent:get_status() == "completed", "Parent should complete")
			assert(child:get_status() == "active", "Child should start after parent completes")
			assert(child:get_start_time() == 90, "Child should start at parent end time")

			time = 110
			schedule.update()
			assert(child:get_status() == "completed", "Child should complete")

			time = 190
			schedule.update()
			assert(parent:get_status() == "active", "Parent should reactivate for second cycle")
			assert(child:get_start_time() == nil, "Child start_time should be reset when parent reactivates")
			assert(child:get_status() == "pending", "Child should be pending again")
		end)


		it("Should update chained events in loop until no more can start", function()
			local event1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(30)
				:save()

			local event2 = schedule.event()
				:category("craft")
				:after(event1:get_id())
				:duration(20)
				:save()

			local event3 = schedule.event()
				:category("craft")
				:after(event2:get_id())
				:duration(10)
				:save()

			time = 60
			schedule.update()
			assert(event1:get_status() == "active", "Event1 should be active")

			time = 90
			schedule.update()
			assert(event1:get_status() == "completed", "Event1 should complete")
			assert(event2:get_status() == "active", "Event2 should start after event1")

			time = 110
			schedule.update()
			assert(event2:get_status() == "completed", "Event2 should complete")
			assert(event3:get_status() == "active", "Event3 should start after event2 in same update cycle")
		end)


		it("Should handle chained events with cycling parent that resets child multiple times", function()
			local parent = schedule.event()
				:category("craft")
				:after(60)
				:duration(20)
				:cycle("every", { seconds = 50, anchor = "end" })
				:save()

			local child = schedule.event()
				:category("craft")
				:after(parent:get_id())
				:duration(10)
				:save()

			time = 60
			schedule.update()
			assert(parent:get_status() == "active", "Parent cycle 1 active")

			time = 80
			schedule.update()
			assert(parent:get_status() == "completed", "Parent cycle 1 complete")
			assert(child:get_status() == "active", "Child should start")
			assert(child:get_start_time() == 80, "Child start time should be set")

			time = 90
			schedule.update()
			assert(child:get_status() == "completed", "Child should complete")

			time = 130
			schedule.update()
			assert(parent:get_status() == "active", "Parent cycle 2 active")
			local child_start_before = child:get_start_time()
			assert(child_start_before == nil or child:get_status() == "pending", "Child start_time should be reset or child should be pending")

			time = 150
			schedule.update()
			assert(parent:get_status() == "completed", "Parent cycle 2 complete")
			assert(child:get_status() == "active", "Child should start again")
			assert(child:get_start_time() ~= nil, "Child start time should be set again")
		end)


		it("Should not reset start_time for non-cycling parent events", function()
			local parent = schedule.event()
				:category("craft")
				:after(60)
				:duration(30)
				:save()

			local child = schedule.event()
				:category("craft")
				:after(parent:get_id())
				:duration(20)
				:save()

			time = 60
			schedule.update()
			assert(parent:get_status() == "active", "Parent should be active")

			time = 90
			schedule.update()
			assert(parent:get_status() == "completed", "Parent should complete")
			assert(child:get_status() == "active", "Child should start")
			local child_start_time = child:get_start_time()

			time = 110
			schedule.update()
			assert(child:get_status() == "completed", "Child should complete")
			assert(child:get_start_time() == child_start_time, "Child start_time should not change for non-cycling parent")
		end)
	end)
end

