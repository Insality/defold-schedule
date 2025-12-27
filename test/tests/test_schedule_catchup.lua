return function()
	describe("Schedule Catchup", function()
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

		it("Should catch up missed events when catch_up is true", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" then
					trigger_count = trigger_count + 1
				end
				return true
			end)

			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:catch_up(true)
				:save()

			set_time(60)
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			set_time(1000)
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed events")
		end)


		it("Should skip missed events when catch_up is false", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" then
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

			set_time(60)
			schedule.update()
			local initial_count = trigger_count

			set_time(1000)
			schedule.update()
			assert(trigger_count == initial_count, "Should not catch up missed events")
		end)


		it("Should catch up with duration events", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			set_time(1000)
			schedule.update()

			local status = schedule.get_status(event_id)
			assert(status.status == "completed", "Event should be completed after catch up")
		end)


		it("Should catch up with cycle events", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" then
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

			set_time(60)
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			set_time(1000)
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed cycles")
		end)


		it("Should simulate offline progression", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active", "Event should be active")

			set_time(10000)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status.status == "completed", "Event should complete after offline period")
		end)


		it("Should handle catch_up default behavior with duration", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			set_time(1000)
			schedule.update()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle catch_up default behavior without duration", function()
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:save()

			set_time(1000)
			schedule.update()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)
	end)
end

