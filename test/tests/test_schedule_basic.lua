return function()
	describe("Schedule Basic", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		local length = function(t)
			local count = 0
			for _ in pairs(t) do
				count = count + 1
			end
			return count
		end

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
			assert(event_info, "Event info should exist")
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
			assert(event_info, "Event info should exist")
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
			assert(event_info:get_status() == "active", "Event should be active")
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
			assert(event_info, "Event info should exist")
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 100, "Event should have 100 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")
			assert(event_info:get_time_to_start() == 100, "Event should have 100 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			time = 100
			schedule.update()
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should create event with start_at", function()
			time = 100

			local event_id = schedule.event()
				:start_at(150)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
		end)

		it("Should create event with end_at", function()
			time = 100

			local event_id = schedule.event()
				:end_at(150)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_status() == "active", "Event should be active immediately")
			assert(event_info:get_time_left() == 50, "Event should have 50 seconds left")

			schedule.update()
			assert(event_info:get_status() == "active", "Event should still be active")
			assert(event_info:get_time_left() == 50, "Event should have 50 seconds left")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should create event with start_at and duration", function()
			time = 100

			local event_id = schedule.event()
				:start_at(150)
				:duration(30)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")
			assert(event_info:get_time_left() == 30, "Event should have 30 seconds left")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 30, "Event should have 30 seconds left")

			time = 180
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should create event with start_at and end_at", function()
			time = 100

			local event_id = schedule.event()
				:start_at(150)
				:end_at(180)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")
			assert(event_info:get_time_left() == 30, "Event should have 30 seconds left")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 30, "Event should have 30 seconds left")

			time = 180
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should create event with after and end_at", function()
			time = 100

			local event_id = schedule.event()
				:after(50)
				:end_at(200)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_status() == "pending", "Event should be pending")
			assert(event_info:get_time_to_start() == 50, "Event should have 50 seconds to start")
			assert(event_info:get_time_left() == 50, "Event should have 50 seconds left")

			schedule.update()
			assert(event_info:get_status() == "pending", "Event should still be pending")

			time = 150
			schedule.update()
			assert(event_info:get_status() == "active", "Event should be active")
			assert(event_info:get_time_to_start() == 0, "Event should have 0 seconds to start")
			assert(event_info:get_time_left() == 50, "Event should have 50 seconds left")

			time = 200
			schedule.update()
			assert(event_info:get_status() == "completed", "Event should be completed")
			assert(event_info:get_time_left() == 0, "Event should have 0 seconds left")
		end)

		it("Should handle event with payload", function()
			local payload = { item = "sword", count = 1 }

			local event_id = schedule.event()
				:duration(10)
				:payload(payload)
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_payload() ~= nil, "Payload should exist")
			assert(event_info:get_payload().item == "sword", "Payload item should match")
			assert(event_info:get_payload().count == 1, "Payload count should match")
		end)

		it("Should handle event with category", function()
			local event_id = schedule.event()
				:duration(10)
				:category("craft")
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info, "Event info should exist")
			assert(event_info:get_category() == "craft", "Category should match")
		end)

		it("Should able to get all events", function()
			schedule.event()
				:id("event_1")
				:duration(10)
				:save()

			schedule.event()
				:id("event_2")
				:duration(20)
				:save()

			local all_events = schedule.filter(nil, nil)
			assert(all_events ~= nil, "All events should exist")
			assert(length(all_events) == 2, "Should have 2 events")
			assert(all_events["event_1"] ~= nil, "Event1 should be in all events")
			assert(all_events["event_2"] ~= nil, "Event2 should be in all events")
		end)

		it("Should able to filter events by category", function()
			schedule.event()
				:duration(10)
				:category("craft")
				:save()

			schedule.event()
				:duration(20)
				:category("craft")
				:save()

			schedule.event()
				:duration(30)
				:category("offer")
				:save()

			local craft_events = schedule.filter("craft", nil)
			local offer_events = schedule.filter("offer", nil)

			assert(length(craft_events) == 2, "Should have 2 craft events")
			assert(length(offer_events) == 1, "Should have 1 offer event")
		end)

		it("Should able to filter events by status", function()
			schedule.event()
				:id("event_1")
				:duration(10)
				:save()

			schedule.event()
				:id("event_2")
				:after(10)
				:duration(10)
				:save()

			schedule.update()
			local pending_events = schedule.filter(nil, "pending")
			assert(length(pending_events) == 1, "Should have 1 pending event")

			time = 15
			schedule.update()

			local active_events = schedule.filter(nil, "active")
			assert(length(active_events) == 1, "Should have 1 active event")
			assert(active_events["event_2"] ~= nil, "Event2 should be in active events")

			local completed_events = schedule.filter(nil, "completed")
			assert(length(completed_events) == 1, "Should have 1 completed event")
			assert(completed_events["event_1"] ~= nil, "Event1 should be in completed events")
		end)
	end)
end

