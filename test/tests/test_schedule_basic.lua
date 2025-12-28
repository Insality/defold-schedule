return function()
	describe("Schedule Basic", function()
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

		it("Should create basic event", function()
			local event_id = schedule.event()
				:duration(10)
				:save()

			assert(event_id ~= nil, "Event ID should be generated")

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Event info should exist")
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_left() == 10, "Event should have 10 seconds left")

			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_left() == 10, "Event should have 10 seconds left")

			time = 5
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_left() == 5, "Event should have 5 seconds left")

			time = 10
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			time = 15
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should still be completed")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should create event with after and duration", function()
			local event_id = schedule.event()
				:after(10)
				:duration(10)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 10, "Event should have 10 seconds to start")
			assert(event_info:get_time_left() == 10, "Event should have 10 seconds left")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")
			assert(event_info:get_time_to_start() == 10, "Event should have 10 seconds to start")
			assert(event_info:get_time_left() == 10, "Event should have 10 seconds left")

			time = 5
			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")
			assert(event_info:get_time_to_start() == 5, "Event should have 5 seconds to start")
			assert(event_info:get_time_left() == 10, "Event should have 10 seconds left")

			time = 10
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 10, "Event should have 10 seconds left")

			time = 15
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 5, "Event should have 5 seconds left")

			time = 20
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should still be completed")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)


		it("Should create event after current time", function()
			time = 50

			local event_id = schedule.event()
				:after(100)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 100, "Event should have 100 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")
			assert(event_info:get_time_to_start() == 100, "Event should have 100 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			time = 100
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should create event with start_at", function()
		end)

		it("Should create event with end_at", function()
		end)

		it("Should create event with start_at and duration", function()
		end)

		it("Should create event with start_at and end_at", function()
		end)

		it("Should create event with after and end_at", function()
		end)

		it("Should handle event with payload", function()
		end)

		it("Should handle event with category", function()
		end)

		it("Should able to get all events", function()
		end)

		it("Should able to filter events by category", function()
		end)

		it("Should able to filter events by status", function()
		end)
	end)
end

