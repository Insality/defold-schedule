return function()
	describe("Schedule Status Transitions", function()
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

		it("Should transition pending → active → completed (normal flow)", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			assert(event:get_status() == "pending", "Event should start as pending")

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should transition to active")

			time = 180
			schedule.update()
			assert(event:get_status() == "completed", "Event should transition to completed")
		end)


		it("Should handle cancelled status", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			event:cancel()
			assert(event:get_status() == "cancelled", "Event should be cancelled")

			time = 60
			schedule.update()
			assert(event:get_status() == "cancelled", "Cancelled event should not activate")
		end)


		it("Should handle aborted status", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Event should be aborted when condition fails with abort_on_fail")
		end)


		it("Should handle failed status", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Event should be aborted when condition fails with abort_on_fail")
		end)


		it("Should handle paused status", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			event:pause()
			assert(event:get_status() == "paused", "Event should be paused")

			time = 500
			schedule.update()
			assert(event:get_status() == "paused", "Paused event should not progress")
		end)


		it("Should allow startable statuses to transition to active", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local event2 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			local event3 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			event1:cancel()
			assert(event1:get_status() == "cancelled", "Event1 should be cancelled")

			time = 60
			schedule.update()
			assert(event2:get_status() == "aborted", "Event2 should be aborted")
			assert(event3:get_status() == "aborted", "Event3 should be aborted")

			event1:start()
			assert(event1:get_status() == "active", "Cancelled event should be able to start")

			event2:start()
			assert(event2:get_status() == "active", "Aborted event should be able to start")

			event3:start()
			assert(event3:get_status() == "active", "Failed event should be able to start")
		end)


		it("Should not allow completed events to be cancelled", function()
			local event = schedule.event()
				:category("craft")
				:duration(10)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10
			schedule.update()
			assert(event:get_status() == "completed", "Event should be completed")

			local success = event:cancel()
			assert(not success, "Should not be able to cancel completed event")
			assert(event:get_status() == "completed", "Event should remain completed")
		end)


		it("Should handle all seven statuses", function()
			local events = {}
			time = 0

			events.pending = schedule.event()
				:category("test")
				:after(100)
				:duration(60)
				:save()

			events.active = schedule.event()
				:category("test")
				:duration(60)
				:save()
			schedule.update()

			events.completed = schedule.event()
				:category("test")
				:duration(10)
				:save()
			time = 10
			schedule.update()

			events.cancelled = schedule.event()
				:category("test")
				:duration(60)
				:save()
			events.cancelled:cancel()

			schedule.register_condition("always_false", function(data)
				return false
			end)

			events.aborted = schedule.event()
				:category("test")
				:duration(60)
				:condition("always_false", {})
				:abort_on_fail()
				:save()
			schedule.update()

			events.failed = schedule.event()
				:category("test")
				:duration(60)
				:condition("always_false", {})
				:abort_on_fail()
				:save()
			schedule.update()

			events.paused = schedule.event()
				:category("test")
				:duration(60)
				:save()
			schedule.update()
			events.paused:pause()

			assert(events.pending:get_status() == "pending", "Should have pending status")
			assert(events.active:get_status() == "active", "Should have active status")
			assert(events.completed:get_status() == "completed", "Should have completed status")
			assert(events.cancelled:get_status() == "cancelled", "Should have cancelled status")
			assert(events.aborted:get_status() == "aborted", "Should have aborted status")
			assert(events.failed:get_status() == "aborted", "Should have aborted status")
			assert(events.paused:get_status() == "paused", "Should have paused status")
		end)
	end)
end

