return function()
	describe("Schedule State", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		local function deep_copy_state(state)
			local serialized = sys.serialize(state)
			return sys.deserialize(serialized)
		end

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should get and set state", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()

			local state = schedule.get_state()
			assert(state ~= nil, "State should exist")

			schedule.reset_state()

			schedule.set_state(state)

			local restored_event = schedule.get(event:get_id())
			assert(restored_event ~= nil, "Status should exist after state restore")
		end)


		it("Should reset state", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			schedule.reset_state()

			local restored_event = schedule.get(event:get_id())
			assert(restored_event == nil, "Status should not exist after reset")
		end)


		it("Should persist state across game restarts", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()

			local state = schedule.get_state()
			local is_ok, encoded = pcall(json.encode, state)
			local saved_state = nil
			if is_ok and encoded then
				saved_state = json.decode(encoded)
			end

			schedule.reset_state()

			if saved_state then
				schedule.set_state(saved_state)

				local restored_event = schedule.get(event:get_id())
				assert(restored_event ~= nil, "Status should exist after state restore")
			end
		end)


		it("Should handle state serialization and deserialization", function()
			local event1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local event2 = schedule.event()
				:category("offer")
				:after(100)
				:duration(200)
				:save()

			time = 60
			schedule.update()

			local state = schedule.get_state()
			local is_ok, encoded = pcall(json.encode, state)
			local saved_state = nil
			if is_ok and encoded then
				saved_state = json.decode(encoded)
			end

			schedule.reset_state()

			if saved_state then
				schedule.set_state(saved_state)

				local restored_event1 = schedule.get(event1:get_id())
				local restored_event2 = schedule.get(event2:get_id())
				assert(restored_event1 ~= nil, "First event status should exist")
				assert(restored_event2 ~= nil, "Second event status should exist")
			end
		end)


		it("Should handle state with multiple events", function()
			local events = {}
			for i = 1, 5 do
				local event = schedule.event()
					:category("craft")
					:after(60 * i)
					:duration(120)
					:save()
				table.insert(events, event)
			end

			time = 300
			schedule.update()

			local state = schedule.get_state()
			schedule.reset_state()
			schedule.set_state(state)

			for _, event in ipairs(events) do
				local restored_event = schedule.get(event:get_id())
				assert(restored_event ~= nil, "Status should exist for event " .. event:get_id())
			end
		end)


		it("Should save and restore infinity events", function()
			local event = schedule.event("infinity_state_test")
				:infinity()
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 100
			schedule.update()

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_event = schedule.get("infinity_state_test")
			assert(restored_event ~= nil, "Event should be restored")
			assert(restored_event:get_status() == "active", "Event should be active after restore")
			local status = schedule.get_status("infinity_state_test")
			assert(status ~= nil, "Status should exist")
			assert(status.infinity == true, "Infinity flag should be preserved")
		end)


		it("Should save and restore events in all statuses", function()
			local pending_event = schedule.event("pending_test")
				:after(100)
				:duration(50)
				:save()

			local active_event = schedule.event("active_test")
				:duration(50)
				:save()

			schedule.update()
			assert(active_event:get_status() == "active", "Event should be active")

			local cancelled_event = schedule.event("cancelled_test")
				:duration(50)
				:save()

			schedule.update()
			cancelled_event:cancel()
			assert(cancelled_event:get_status() == "cancelled", "Event should be cancelled before save")

			local paused_event = schedule.event("paused_test")
				:duration(50)
				:save()
			schedule.update()
			paused_event:pause()
			assert(paused_event:get_status() == "paused", "Event should be paused before save")

			time = 10
			schedule.update()
			local completed_event = schedule.event("completed_test")
				:duration(10)
				:save()
			schedule.update()
			time = 20
			schedule.update()
			assert(completed_event:get_status() == "completed", "Event should be completed before save")

			local state = schedule.get_state()
			local cancelled_status_before = state.events["cancelled_test"]
			assert(cancelled_status_before ~= nil, "Cancelled event should be in state")
			assert(cancelled_status_before.status == "cancelled", "Cancelled event status should be cancelled in state, got: " .. tostring(cancelled_status_before.status))
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_state = schedule.get_state()
			local cancelled_status_after_restore = restored_state.events["cancelled_test"]
			assert(cancelled_status_after_restore ~= nil, "Cancelled event should be in restored state")
			assert(cancelled_status_after_restore.status == "cancelled", "Cancelled event status should be cancelled in restored state")

			local pending_restored = schedule.get("pending_test")
			assert(pending_restored ~= nil, "Pending event should be restored")
			assert(pending_restored:get_status() == "pending", "Pending event should be restored")
			local active_restored = schedule.get("active_test")
			assert(active_restored ~= nil, "Active event should be restored")
			assert(active_restored:get_status() == "active", "Active event should be restored")
			local cancelled_restored = schedule.get("cancelled_test")
			assert(cancelled_restored ~= nil, "Cancelled event should be restored")
			assert(cancelled_restored:get_status() == "cancelled", "Cancelled event should be restored")
			local paused_restored = schedule.get("paused_test")
			assert(paused_restored ~= nil, "Paused event should be restored")
			assert(paused_restored:get_status() == "paused", "Paused event should be restored")
			local completed_restored = schedule.get("completed_test")
			assert(completed_restored ~= nil, "Completed event should be restored")
			assert(completed_restored:get_status() == "completed", "Completed event should be restored")

			time = 20
			schedule.update()

			assert(cancelled_restored:get_status() == "cancelled", "Cancelled event should remain cancelled after update")
			assert(paused_restored:get_status() == "paused", "Paused event should remain paused after update")
		end)


		it("Should save and restore events with cycles", function()
			local event = schedule.event("cycle_test")
				:duration(10)
				:cycle("every", { seconds = 20 })
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10
			schedule.update()
			assert(event:get_status() == "completed", "Event should be completed")

			time = 30
			schedule.update()
			assert(event:get_status() == "active", "Event should be active again after cycle")

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_event = schedule.get("cycle_test")
			assert(restored_event ~= nil, "Event should be restored")
			local status = schedule.get_status("cycle_test")
			assert(status ~= nil, "Status should exist")
			assert(status.cycle ~= nil, "Cycle config should be preserved")
			assert(status.cycle_count ~= nil, "Cycle count should be preserved")
		end)


		it("Should save and restore events with chaining", function()
			local event1 = schedule.event("chain1")
				:duration(10)
				:save()

			local event2 = schedule.event("chain2")
				:after("chain1")
				:duration(20)
				:save()

			schedule.update()
			assert(event1:get_status() == "active", "First event should be active at start")

			time = 10
			schedule.update()
			assert(event1:get_status() == "completed", "First event should be completed")
			assert(event2:get_status() == "active", "Second event should be active")

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_event1 = schedule.get("chain1")
			local restored_event2 = schedule.get("chain2")
			assert(restored_event1 ~= nil, "First event should be restored")
			assert(restored_event2 ~= nil, "Second event should be restored")
			local status2 = schedule.get_status("chain2")
			assert(status2 ~= nil, "Status2 should exist")
			assert(status2.after == "chain1", "Chaining should be preserved")
		end)


		it("Should override config when event with same ID is created", function()
			local event1 = schedule.event("override_test")
				:category("old_category")
				:duration(100)
				:payload({ old = "data" })
				:save()

			schedule.update()
			assert(event1:get_status() == "active", "Event should be active")

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local event2 = schedule.event("override_test")
				:category("new_category")
				:duration(200)
				:payload({ new = "data" })
				:save()

			local status = schedule.get_status("override_test")
			assert(status ~= nil, "Status should exist")
			assert(status.category == "new_category", "Category should be overridden")
			assert(status.duration == 200, "Duration should be overridden")
			assert(status.payload ~= nil, "Payload should exist")
			assert(status.payload.new == "data", "Payload should be overridden")
		end)


		it("Should override all config fields when event with same ID is created", function()
			local event1 = schedule.event("full_override_test")
				:category("category1")
				:duration(100)
				:payload({ key1 = "value1" })
				:after(10)
				:save()

			schedule.update()

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local event2 = schedule.event("full_override_test")
				:category("category2")
				:duration(200)
				:payload({ key2 = "value2" })
				:after(20)
				:save()

			local status = schedule.get_status("full_override_test")
			assert(status ~= nil, "Status should exist")
			assert(status.category == "category2", "Category should be overridden")
			assert(status.duration == 200, "Duration should be overridden")
			assert(status.payload ~= nil, "Payload should exist")
			assert(status.payload.key2 == "value2", "Payload should be overridden")
			assert(status.after == 20, "After should be overridden")
		end)


		it("Should use table-based save and restore", function()
			local event = schedule.event("table_test")
				:category("test")
				:duration(50)
				:save()

			schedule.update()

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_event = schedule.get("table_test")
			assert(restored_event ~= nil, "Event should be restored using table copy")
			assert(restored_event:get_category() == "test", "Category should be preserved")
		end)


		it("Should preserve last_update_time when restoring state", function()
			local event = schedule.event("time_test")
				:duration(50)
				:save()

			time = 100
			schedule.update()

			local state = schedule.get_state()
			local saved_time = state.last_update_time
			assert(saved_time == 100, "last_update_time should be saved")

			local state_copy = deep_copy_state(state)

			schedule.reset_state()

			schedule.set_state(state_copy)

			local restored_state = schedule.get_state()
			assert(restored_state.last_update_time == 100, "last_update_time should be preserved")
		end)


		it("Should restore events after simulated game restart", function()
			local event1 = schedule.event("restart_test1")
				:after(50)
				:duration(100)
				:save()

			local event2 = schedule.event("restart_test2")
				:duration(200)
				:save()

			time = 50
			schedule.update()
			assert(event1:get_status() == "active", "Event1 should be active")
			assert(event2:get_status() == "active", "Event2 should be active")

			time = 100
			schedule.update()

			local state = schedule.get_state()
			local state_copy = deep_copy_state(state)

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 150

			schedule.set_state(state_copy)
			schedule.update()

			local restored_event1 = schedule.get("restart_test1")
			local restored_event2 = schedule.get("restart_test2")
			assert(restored_event1 ~= nil, "Event1 should be restored")
			assert(restored_event2 ~= nil, "Event2 should be restored")
			assert(restored_event1:get_status() == "active" or restored_event1:get_status() == "completed", "Event1 should be active or completed")
			assert(restored_event2:get_status() == "active" or restored_event2:get_status() == "completed", "Event2 should be active or completed")
		end)
	end)
end

