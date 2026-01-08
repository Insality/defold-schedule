return function()
	describe("Schedule Catchup Requirements", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should only catch up if catch_up is true AND last_update_time exists", function()
			local start_count = 0

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:on_start(function()
					start_count = start_count + 1
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_count == 1, "Event should start normally")
			assert(event:get_status() == "active", "Event should be active")

			time = 500
			schedule.update()
			assert(start_count == 1, "Should not catch up without last_update_time on first update")

			time = 1000
			schedule.update()
			assert(start_count == 1, "Should not catch up - last_update_time was set in previous update")
			assert(event:get_status() == "completed", "Event should complete normally")
		end)


		it("Should catch up when both catch_up and last_update_time are present", function()
			local start_count = 0

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:on_start(function()
					start_count = start_count + 1
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_count == 1, "Event should start")
			assert(event:get_status() == "active", "Event should be active")

			time = 200
			schedule.update()
			assert(start_count == 1, "Event should still be active")

			time = 500
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete after catch-up")
		end)


		it("Should not catch up when catch_up is false even with last_update_time", function()
			local start_count = 0

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(false)
				:on_start(function()
					start_count = start_count + 1
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_count == 1, "Event should start")
			assert(event:get_status() == "active", "Event should be active")

			time = 200
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete normally when time passes (not catch-up, just normal progression)")

			time = 500
			schedule.update()
			assert(event:get_status() == "completed", "Event should remain completed")
		end)


		it("Should mark non-cycling events completed immediately if offline period spans entire duration", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 500
			schedule.update()
			assert(event:get_status() == "completed", "Event should be completed immediately if offline period spans entire duration")
		end)


		it("Should handle catch-up for pending events that should have started during offline", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			time = 500
			schedule.update()

			-- FIX
			-- TODO: here is double due the last update time logic, it's not calling a catchup to finish first time
			schedule.update()

			assert(event:get_status() == "completed", "Event should complete if it should have started and ended during offline")
		end)


		it("Should handle catch-up for active events that should have completed during offline", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 500
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete after catch-up")
		end)
	end)
end

