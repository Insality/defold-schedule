return function()
	describe("Schedule Infinity", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule_time.set_time_function = function() return time end
			schedule.reset_state()
			time = 0
		end)

		it("Should create infinity event that never ends automatically", function()
			local event = schedule.event()
				:infinity()
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 1000
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active after long time")

			time = 10000
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active after very long time")
		end)


		it("Should create infinity event that stays active indefinitely", function()
			local event = schedule.event()
				:after(10)
				:infinity()
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			time = 10
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")
			assert(event:get_time_left() == -1, "Infinity event should have -1 time left")

			time = 1000
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active")
			assert(event:get_time_left() == -1, "Infinity event should still have -1 time left")
		end)


		it("Should allow manually finishing infinity event", function()
			local end_called = false
			local disabled_called = false

			local event = schedule.event()
				:infinity()
				:on_end(function(event_data)
					end_called = true
				end)
				:on_disabled(function(event_data)
					disabled_called = true
				end)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 100
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active")

			local success = event:finish()
			assert(success, "finish() should return true")
			assert(event:get_status() == "completed", "Event should be completed after finish()")
			assert(end_called, "on_end should be called")
			assert(disabled_called, "on_disabled should be called")
		end)


		it("Should handle infinity event with cycles", function()
			local event = schedule.event()
				:infinity()
				:cycle("every", { seconds = 100 })
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 100
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active after cycle time")

			local event_id = event:get_id()
			if event_id then
				local status = schedule.get_status(event_id)
				assert(status ~= nil, "Status should exist")
				if status then
					assert(status.cycle_count == 0, "Cycle count should be 0 for infinity events without end")
				end
			end
		end)


		it("Should save and restore infinity event state", function()
			local event = schedule.event()
				:id("infinity_test")
				:infinity()
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 100
			schedule.update()

			local saved_state = schedule.get_state()
			local serialized = sys.serialize(saved_state)
			local state_copy = sys.deserialize(serialized)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_event = schedule.get("infinity_test")
			assert(restored_event ~= nil, "Event should be restored")
			if restored_event then
				assert(restored_event:get_status() == "active", "Event should be active after restore")
			end
			local status = schedule.get_status("infinity_test")
			assert(status ~= nil, "Status should exist")
			if status then
				assert(status.infinity == true, "Infinity flag should be preserved")
			end
		end)


		it("Should handle infinity event with chaining", function()
			local event1 = schedule.event()
				:id("chain_start")
				:duration(10)
				:save()

			local event2 = schedule.event()
				:id("chain_infinity")
				:after("chain_start")
				:infinity()
				:save()

			time = 10
			schedule.update()
			assert(event1:get_status() == "completed", "First event should be completed")
			assert(event2:get_status() == "active", "Second event should be active")

			time = 1000
			schedule.update()
			assert(event2:get_status() == "active", "Infinity event should still be active")
		end)


		it("Should handle infinity event time calculations", function()
			local event = schedule.event()
				:after(10)
				:infinity()
				:save()

			assert(event:get_time_left() == -1, "Pending infinity event should have -1 time left")

			time = 10
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")
			assert(event:get_time_left() == -1, "Active infinity event should have -1 time left")

			time = 1000
			schedule.update()
			assert(event:get_time_left() == -1, "Infinity event should still have -1 time left")
		end)


		it("Should handle infinity event with category and payload", function()
			local payload = { buff_type = "permanent", effect = "double_damage" }
			local event = schedule.event()
				:category("buff")
				:infinity()
				:payload(payload)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")
			assert(event:get_category() == "buff", "Category should be preserved")
			local payload = event:get_payload()
			assert(payload ~= nil, "Payload should exist")
			if payload then
				assert(payload.buff_type == "permanent", "Payload should be preserved")
			end
		end)


		it("Should handle infinity event that can be cancelled", function()
			local event = schedule.event()
				:infinity()
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:cancel()
			assert(success, "cancel() should return true")
			assert(event:get_status() == "cancelled", "Event should be cancelled")
		end)


		it("Should handle infinity event that can be paused and resumed", function()
			local event = schedule.event()
				:infinity()
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:pause()
			assert(success, "pause() should return true")
			assert(event:get_status() == "paused", "Event should be paused")

			time = 1000
			schedule.update()
			assert(event:get_status() == "paused", "Event should remain paused")

			success = event:resume()
			assert(success, "resume() should return true")
			assert(event:get_status() == "active", "Event should be active again")
		end)
	end)
end

