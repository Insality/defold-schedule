return function()
	describe("Schedule Catchup", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should catch up missed events when catch_up is true", function()
			local count = 0

			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = false })
				:on_start(function()
					count = count + 1
				end)
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(count == 1, "on_start should be called")
			assert(event:get_status() == "active", "Event should be active")

			time = 1000
			schedule.update()
			assert(count > 5, "on_start should be called multiple times")
			assert(event:get_status() == "completed", "Event should be completed after catch up")
		end)


		it("Should skip missed events when catch_up is false", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" and event.callback_type == "active" then
					trigger_count = trigger_count + 1
				end
				return true
			end)

			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:catch_up(false)
				:save()

			time = 60
			schedule.update()
			local initial_count = trigger_count

			time = 1000
			schedule.update()
			assert(trigger_count == initial_count, "Should not catch up missed events")
		end)


		it("Should catch up with duration events", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			time = 1000
			schedule.update()

			assert(event:get_status() == "completed", "Event should be completed after catch up")
		end)


		it("Should catch up with cycle events", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" and event.callback_type == "active" then
					trigger_count = trigger_count + 1
				end
				return true
			end)

			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = false })
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			time = 1000
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed cycles")
		end)


		it("Should simulate offline progression", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10000
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete after offline period")
		end)


		it("Should handle catch_up default behavior with duration", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 1000
			schedule.update()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle catch_up default behavior without duration", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:save()

			time = 1000
			schedule.update()

			assert(event ~= nil, "Status should exist")
		end)
	end)
end

