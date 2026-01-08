return function()
	describe("Schedule Lifecycle", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should call on_start callback", function()
			local start_called = false
			local start_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function(event_data)
					start_called = true
					start_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_called, "on_start should be called")
			assert(start_event ~= nil, "Event should be passed to callback")
			assert(start_event.event_id == event:get_id(), "Event ID should match")
		end)


		it("Should call on_enabled callback", function()
			local enabled_called = false
			local enabled_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_enabled(function(event_data)
					enabled_called = true
					enabled_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(enabled_called, "on_enabled should be called")
			assert(enabled_event ~= nil, "Event should be passed to callback")
		end)


		it("Should call on_disabled callback", function()
			local disabled_called = false
			local disabled_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_disabled(function(event_data)
					disabled_called = true
					disabled_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(not disabled_called, "on_disabled should not be called yet")

			time = 180
			schedule.update()
			assert(disabled_called, "on_disabled should be called when event ends")
			assert(disabled_event ~= nil, "Event should be passed to callback")
		end)


		it("Should call on_end callback", function()
			local end_called = false
			local end_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_end(function(event_data)
					end_called = true
					end_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(not end_called, "on_end should not be called yet")

			time = 180
			schedule.update()
			assert(end_called, "on_end should be called when event ends")
			assert(end_event ~= nil, "Event should be passed to callback")
		end)


		it("Should abort event when condition fails with abort_on_fail", function()
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
			assert(event:get_status() == "aborted", "abort_on_fail should set status to aborted when condition fails")
		end)


		it("Should call callbacks in correct order", function()
			local callback_order = {}

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function(event_data)
					table.insert(callback_order, "start")
				end)
				:on_enabled(function(event_data)
					table.insert(callback_order, "enabled")
				end)
				:on_end(function(event_data)
					table.insert(callback_order, "end")
				end)
				:on_disabled(function(event_data)
					table.insert(callback_order, "disabled")
				end)
				:save()

			time = 60
			schedule.update()
			assert(callback_order[1] == "start" or callback_order[1] == "enabled", "Start or enabled should be called first")
			assert(callback_order[2] == "start" or callback_order[2] == "enabled", "Start or enabled should be called second")

			time = 180
			schedule.update()
			assert(callback_order[3] == "end" or callback_order[3] == "disabled", "End or disabled should be called third")
			assert(callback_order[4] == "end" or callback_order[4] == "disabled", "End or disabled should be called fourth")
		end)


		it("Should call callbacks with persistent events using id", function()
			local start_called = false
			local event_id = "persistent_event"

			schedule.event(event_id)
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function(event)
					start_called = true
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_called, "on_start should be called for persistent event")

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)

			schedule.event(event_id)
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function(event)
					start_called = true
				end)
				:save()

			time = 120
			schedule.update()
			assert(start_called, "on_start should be called for same persistent event")
		end)


		it("Should push events to queue for all callback types", function()
			local events = {}
			schedule.on_event:subscribe(function(event)
				table.insert(events, event)
			end)

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function() end)
				:on_enabled(function() end)
				:on_end(function() end)
				:on_disabled(function() end)
				:save()

			time = 60
			schedule.update()

			local event_types = {}
			for _, e in ipairs(events) do
				table.insert(event_types, e.callback_type)
			end

			assert(table.concat(event_types, ","):find("start"), "Should have start event")
			assert(table.concat(event_types, ","):find("enabled"), "Should have enabled event")

			time = 180
			schedule.update()

			event_types = {}
			for _, e in ipairs(events) do
				table.insert(event_types, e.callback_type)
			end

			assert(table.concat(event_types, ","):find("end"), "Should have end event")
			assert(table.concat(event_types, ","):find("disabled"), "Should have disabled event")
		end)


		it("Should push disabled event to queue when paused", function()
			local events = {}
			schedule.on_event:subscribe(function(event)
				table.insert(events, event)
			end)

			local disabled_called = false
			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_disabled(function(event_data)
					disabled_called = true
				end)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			event:pause()
			assert(event:get_status() == "paused", "Event should be paused")
			assert(disabled_called, "on_disabled callback should be called when paused")

			local has_disabled_event = false
			for _, e in ipairs(events) do
				if e.callback_type == "disabled" then
					has_disabled_event = true
					assert(e.event_id == event:get_id(), "Disabled event should have correct ID")
					break
				end
			end
			assert(has_disabled_event, "Should have disabled event in queue")
		end)


		it("Should push enabled event to queue when resumed", function()
			local events = {}
			schedule.on_event:subscribe(function(event)
				table.insert(events, event)
			end)

			local enabled_called = false
			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_enabled(function(event_data)
					enabled_called = true
				end)
				:save()

			time = 60
			schedule.update()
			event:pause()

			event:resume()
			assert(event:get_status() == "active", "Event should be active")
			assert(enabled_called, "on_enabled callback should be called when resumed")

			local has_enabled_event = false
			for _, e in ipairs(events) do
				if e.callback_type == "enabled" then
					has_enabled_event = true
					assert(e.event_id == event:get_id(), "Enabled event should have correct ID")
					break
				end
			end
			assert(has_enabled_event, "Should have enabled event in queue")
		end)


		it("Should push fail event to queue when abort_on_fail triggers", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local events = {}
			schedule.on_event:subscribe(function(event)
				table.insert(events, event)
			end)

			local fail_called = false
			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:abort_on_fail()
				:on_fail(function(event_data)
					fail_called = true
				end)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Event should be aborted")
			assert(fail_called, "on_fail callback should be called")

			local has_fail_event = false
			for _, e in ipairs(events) do
				if e.callback_type == "fail" then
					has_fail_event = true
					assert(e.event_id == event:get_id(), "Fail event should have correct ID")
					break
				end
			end
			assert(has_fail_event, "Should have fail event in queue")
		end)


		it("Should only emit active events on state restore, not start events", function()
			local event1 = schedule.event("event1")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			local event2 = schedule.event("event2")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()

			assert(event1:get_status() == "active", "Event1 should be active")
			assert(event2:get_status() == "active", "Event2 should be active")

			local saved_state = sys.deserialize(sys.serialize(schedule.get_state()))

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)

			local events = {}
			schedule.on_event:subscribe(function(event)
				table.insert(events, event)
			end)

			schedule.set_state(saved_state)

			schedule.event("event1")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			schedule.event("event2")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			schedule.update()

			local event_types = {}
			for _, e in ipairs(events) do
				table.insert(event_types, e.callback_type)
			end

			local has_start = false
			local has_enabled = false
			for _, etype in ipairs(event_types) do
				if etype == "start" then
					has_start = true
				end
				if etype == "enabled" then
					has_enabled = true
				end
			end

			assert(not has_start, "Should not have start events on state restore")
			assert(has_enabled, "Should have enabled events on state restore")
		end)


		it("Should emit active events for all active events on state restore", function()
			local event1 = schedule.event("restore_event1")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			local event2 = schedule.event("restore_event2")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			local event3 = schedule.event("restore_event3")
				:category("liveops")
				:after(200)
				:duration(120)
				:save()

			time = 60
			schedule.update()

			assert(event1:get_status() == "active", "Event1 should be active")
			assert(event2:get_status() == "active", "Event2 should be active")
			assert(event3:get_status() == "pending", "Event3 should be pending")

			local saved_state = sys.deserialize(sys.serialize(schedule.get_state()))
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)

			local events = {}
			schedule.on_event:subscribe(function(event)
				table.insert(events, event)
			end)

			schedule.set_state(saved_state)

			schedule.event("restore_event1")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			schedule.event("restore_event2")
				:category("liveops")
				:after(60)
				:duration(120)
				:save()

			schedule.event("restore_event3")
				:category("liveops")
				:after(200)
				:duration(120)
				:save()

			schedule.update()

			local enabled_count = 0
			for _, e in ipairs(events) do
				if e.callback_type == "enabled" then
					enabled_count = enabled_count + 1
				end
			end

			assert(enabled_count == 2, "Should have 2 enabled events on restore")
		end)
	end)
end

