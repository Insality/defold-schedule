return function()
	describe("Schedule API", function()
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

		after(function()
			schedule.set_time_function(nil)
		end)

		it("Should remove an event", function()
			schedule.event("craft"):duration(10):save()
			assert(schedule.get("craft") ~= nil, "Event should exist")

			assert(schedule.remove("craft"), "Should report the event as removed")
			assert(schedule.get("craft") == nil, "Event should be gone")
			assert(not schedule.remove("craft"), "Removing a missing event should return false")
		end)


		it("Should not call callbacks of a removed event", function()
			local ended = 0
			schedule.event("craft")
				:duration(10)
				:on_end(function() ended = ended + 1 end)
				:save()

			schedule.update()
			schedule.remove("craft")

			-- Re-create an event with the same id, the old callback should not be attached anymore
			schedule.event("craft"):duration(10):save()
			time = 100
			schedule.update()

			assert(ended == 0, "Removed event callbacks should not be called, got " .. ended)
		end)


		it("Should clear events by category and status", function()
			schedule.event("craft_1"):category("craft"):duration(10):save()
			schedule.event("craft_2"):category("craft"):duration(1000):save()
			schedule.event("quest_1"):category("quest"):duration(10):save()

			schedule.update()
			time = 50
			schedule.update()

			assert(schedule.get("craft_1"):get_status() == "completed", "First craft should be completed")

			local removed_count = schedule.clear("craft", "completed")
			assert(removed_count == 1, "Should remove only the completed craft, got " .. removed_count)
			assert(schedule.get("craft_1") == nil, "Completed craft should be removed")
			assert(schedule.get("craft_2") ~= nil, "Active craft should be kept")
			assert(schedule.get("quest_1") ~= nil, "Other category should be kept")

			schedule.clear()
			assert(next(schedule.filter()) == nil, "clear() without arguments should remove everything")
		end)


		it("Should use a custom time function", function()
			local server_time = 5000
			schedule.set_time_function(function() return server_time end)

			assert(schedule.get_time() == 5000, "Should read the custom time")

			local event = schedule.event("offer"):after(100):duration(50):save()
			assert(event:get_start_time() == 5100, "Should schedule from the custom time")

			server_time = 5100
			schedule.update()
			assert(event:get_status() == "active", "Should activate on the custom time")
		end)


		it("Should keep the time function after reset_state", function()
			schedule.set_time_function(function() return 777 end)
			schedule.reset_state()

			assert(schedule.get_time() == 777, "reset_state should not drop the time function")
		end)


		it("Should expose event getters", function()
			local event = schedule.event("craft")
				:category("craft")
				:payload({ item = "sword" })
				:after(10)
				:duration(100)
				:save()

			assert(event:get_id() == "craft", "Should return the id")
			assert(event:get_category() == "craft", "Should return the category")
			assert(event:get_payload().item == "sword", "Should return the payload")
			assert(event:get_end_time() == 110, "Should return the end time")
			assert(event:get_cycle_count() == 0, "Should start with no cycles")
			assert(not event:is_active(), "Should not be active yet")

			time = 10
			schedule.update()
			assert(event:is_active(), "Should be active after the start time")
		end)


		it("Should report the remaining time of a paused event", function()
			local event = schedule.event("craft"):duration(100):save()

			schedule.update()
			time = 40
			schedule.update()
			event:pause()

			time = 400
			assert(event:get_time_left() == 60, "Paused event should not consume time, got " .. event:get_time_left())

			event:resume()
			assert(event:get_time_left() == 60, "Resumed event should keep its remaining time, got " .. event:get_time_left())
		end)


		it("Should notify on_disabled when an active event is cancelled", function()
			local disabled = 0
			local event = schedule.event("craft")
				:duration(100)
				:on_disabled(function() disabled = disabled + 1 end)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			event:cancel()
			assert(disabled == 1, "Cancelling an active event should disable it, got " .. disabled)

			assert(event:get_status() == "cancelled", "Event should be cancelled")
			time = 200
			schedule.update()
			assert(event:get_status() == "cancelled", "Cancelled event should stay cancelled")
		end)


		it("Should pass the same event data from manual control and from update", function()
			local received = {}
			local event = schedule.event("craft")
				:category("craft")
				:duration(100)
				:on_start(function(event_data) received.start_data = event_data end)
				:on_end(function(event_data) received.end_data = event_data end)
				:save()

			event:start()
			assert(received.start_data.status == "active", "on_start should report the active status")
			assert(received.start_data.start_time ~= nil, "on_start should report the start time")
			assert(received.start_data.category == "craft", "on_start should report the category")

			event:finish()
			assert(received.end_data.status == "completed", "on_end should report the completed status")
			assert(received.end_data.end_time ~= nil, "on_end should report the end time")
		end)


		it("Should reject invalid event configuration", function()
			assert(not pcall(function() schedule.event():duration("ten") end), "duration should require a number")
			assert(not pcall(function() schedule.event():category(42) end), "category should require a string")
			assert(not pcall(function() schedule.event():start_at("tomorrow") end), "start_at should require a valid date")
			assert(not pcall(function() schedule.event():on_start("not a function") end), "callbacks should require a function")
			assert(not pcall(function() schedule.event():cycle("evry", { seconds = 10 }) end), "cycle type should be known")
			assert(not pcall(function() schedule.event():cycle("every", {}) end), "cycle every should require seconds")
			assert(not pcall(function() schedule.event():cycle("weekly", { weekdays = { "someday" } }) end), "weekday should be known")
			assert(not pcall(function() schedule.event():cycle("weekly", { weekdays = { "sun" }, time = "25:00" }) end), "time should be valid")
			assert(not pcall(function() schedule.event():duration(10):end_at(100):save() end), "duration and end_at should not be combined")
			assert(not pcall(function() schedule.event():infinity():duration(10):save() end), "infinity and duration should not be combined")
			assert(not pcall(function() schedule.event():start_at(10):after(10):save() end), "start_at and after should not be combined")
		end)


		it("Should keep the queue bounded without subscribers", function()
			local lifecycle = require("schedule.internal.schedule_lifecycle")

			schedule.event("tick"):duration(1):cycle("every", { seconds = 10 }):save()
			for step = 1, 200 do
				time = step * 5
				schedule.update()
			end

			assert(#lifecycle.event_queue:get_events() <= 128,
				"Unhandled events should be capped, got " .. #lifecycle.event_queue:get_events())
		end)


		it("Should ignore a clock that moved backwards", function()
			local event = schedule.event("craft"):duration(100):save()

			time = 10
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = -100000
			schedule.update()
			assert(event:get_status() == "active", "Event should survive a clock rollback")

			time = 200
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete once time passes the end again")
		end)
	end)
end
