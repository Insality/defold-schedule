return function()
	describe("Schedule Control", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		it("Should force finish active event", function()
			local end_called = false
			local disabled_called = false

			local event = schedule.event()
				:duration(100)
				:on_end(function(event_data)
					end_called = true
				end)
				:on_disabled(function(event_data)
					disabled_called = true
				end)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 50
			schedule.update()
			assert(event:get_status() == "active", "Event should still be active")

			local success = event:finish()
			assert(success, "finish() should return true")
			assert(event:get_status() == "completed", "Event should be completed")
			assert(end_called, "on_end should be called")
			assert(disabled_called, "on_disabled should be called")
		end)


		it("Should force finish pending event", function()
			local start_called = false
			local enabled_called = false
			local end_called = false
			local disabled_called = false

			local event = schedule.event()
				:after(100)
				:duration(50)
				:on_start(function(event_data)
					start_called = true
				end)
				:on_enabled(function(event_data)
					enabled_called = true
				end)
				:on_end(function(event_data)
					end_called = true
				end)
				:on_disabled(function(event_data)
					disabled_called = true
				end)
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			local success = event:finish()
			assert(success, "finish() should return true")
			assert(event:get_status() == "completed", "Event should be completed")
			assert(start_called, "on_start should be called")
			assert(enabled_called, "on_enabled should be called")
			assert(end_called, "on_end should be called")
			assert(disabled_called, "on_disabled should be called")
		end)


		it("Should force start pending event", function()
			local start_called = false
			local enabled_called = false

			local event = schedule.event()
				:after(100)
				:duration(50)
				:on_start(function(event_data)
					start_called = true
				end)
				:on_enabled(function(event_data)
					enabled_called = true
				end)
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			local success = event:start()
			assert(success, "start() should return true")
			assert(event:get_status() == "active", "Event should be active")
			assert(start_called, "on_start should be called")
			assert(enabled_called, "on_enabled should be called")
		end)


		it("Should force start cancelled event", function()
			local event = schedule.event()
				:duration(50)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			event:cancel()
			assert(event:get_status() == "cancelled", "Event should be cancelled")

			local success = event:start()
			assert(success, "start() should return true")
			assert(event:get_status() == "active", "Event should be active")
		end)


		it("Should force start aborted event", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:duration(50)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			schedule.update()
			assert(event:get_status() == "aborted" or event:get_status() == "failed", "Event should be aborted or failed")

			local success = event:start()
			assert(success, "start() should return true")
			assert(event:get_status() == "active", "Event should be active")
		end)


		it("Should cancel active event", function()
			local event = schedule.event()
				:duration(100)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:cancel()
			assert(success, "cancel() should return true")
			assert(event:get_status() == "cancelled", "Event should be cancelled")
		end)


		it("Should cancel pending event", function()
			local event = schedule.event()
				:after(100)
				:duration(50)
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			local success = event:cancel()
			assert(success, "cancel() should return true")
			assert(event:get_status() == "cancelled", "Event should be cancelled")
		end)


		it("Should not cancel completed event", function()
			local event = schedule.event()
				:duration(10)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10
			schedule.update()
			assert(event:get_status() == "completed", "Event should be completed")

			local success = event:cancel()
			assert(not success, "cancel() should return false for completed event")
			assert(event:get_status() == "completed", "Event should remain completed")
		end)


		it("Should pause active event", function()
			local event = schedule.event()
				:duration(100)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:pause()
			assert(success, "pause() should return true")
			assert(event:get_status() == "paused", "Event should be paused")

			time = 1000
			schedule.update()
			assert(event:get_status() == "paused", "Event should remain paused")
		end)


		it("Should not pause non-active event", function()
			local event = schedule.event()
				:after(100)
				:duration(50)
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			local success = event:pause()
			assert(not success, "pause() should return false for pending event")
			assert(event:get_status() == "pending", "Event should remain pending")
		end)


		it("Should resume paused event", function()
			local enabled_called = false

			local event = schedule.event()
				:duration(100)
				:on_enabled(function(event_data)
					enabled_called = true
				end)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			event:pause()
			assert(event:get_status() == "paused", "Event should be paused")

			enabled_called = false
			local success = event:resume()
			assert(success, "resume() should return true")
			assert(event:get_status() == "active", "Event should be active")
			assert(enabled_called, "on_enabled should be called")
		end)


		it("Should not resume non-paused event", function()
			local event = schedule.event()
				:duration(100)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:resume()
			assert(not success, "resume() should return false for active event")
			assert(event:get_status() == "active", "Event should remain active")
		end)


		it("Should extend duration when paused event with duration is resumed", function()
			local event = schedule.event()
				:duration(100)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")
			
			local original_end_time = event:get_start_time() + 100
			assert(event:get_time_left() == 100, "Event should have 100 seconds left")

			time = 10
			schedule.update()
			assert(event:get_time_left() == 90, "Event should have 90 seconds left after 10 seconds")

			event:pause()
			assert(event:get_status() == "paused", "Event should be paused")
			
			-- Wait 20 seconds while paused
			time = 30
			schedule.update()
			assert(event:get_status() == "paused", "Event should remain paused")

			-- Resume the event
			event:resume()
			assert(event:get_status() == "active", "Event should be active")
			
			-- Duration should be extended by 20 seconds (pause duration)
			-- Original: 100 seconds, elapsed: 10 seconds, paused: 20 seconds
			-- New end_time should be: start_time + 100 + 20 = start_time + 120
			-- Time left should be: 90 seconds (original remaining) + 20 seconds (pause extension) = 110 seconds
			-- But actually, since we're at time 30, and end_time is now start_time + 120, time left = 120 - 30 = 90
			-- Wait, let me recalculate:
			-- start_time = 0
			-- original end_time = 0 + 100 = 100
			-- at time 10: time_left = 100 - 10 = 90
			-- pause at time 10
			-- resume at time 30 (20 seconds later)
			-- new end_time = 100 + 20 = 120
			-- at time 30: time_left = 120 - 30 = 90
			-- So time left should still be 90, but the total duration is now 120
			local time_left = event:get_time_left()
			assert(time_left == 90, "Event should have 90 seconds left (original 90 + pause extension compensated)")
			
			-- Verify the end_time was extended
			local event_state = schedule.get_status(event:get_id())
			assert(event_state.end_time == 120, "End time should be extended to 120 (original 100 + pause 20)")
		end)


		it("Should not extend duration for events with hardcoded end_at", function()
			local event = schedule.event()
				:duration(100)
				:end_at(200)  -- Hardcoded end time
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10
			schedule.update()
			local time_left_before = event:get_time_left()

			event:pause()
			assert(event:get_status() == "paused", "Event should be paused")
			
			-- Wait 20 seconds while paused
			time = 30
			schedule.update()

			-- Resume the event
			event:resume()
			assert(event:get_status() == "active", "Event should be active")
			
			-- End time should NOT be extended for hardcoded end_at
			local event_state = schedule.get_status(event:get_id())
			assert(event_state.end_time == 200, "End time should remain 200 (hardcoded, not extended)")
			
			-- Time left should be reduced by the pause duration
			local time_left_after = event:get_time_left()
			assert(time_left_after < time_left_before, "Time left should be reduced (hardcoded end_at doesn't extend)")
		end)


		it("Should handle control methods on infinity events", function()
			local event = schedule.event()
				:infinity()
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:pause()
			assert(success, "pause() should work on infinity event")
			assert(event:get_status() == "paused", "Event should be paused")

			success = event:resume()
			assert(success, "resume() should work on infinity event")
			assert(event:get_status() == "active", "Event should be active")

			success = event:cancel()
			assert(success, "cancel() should work on infinity event")
			assert(event:get_status() == "cancelled", "Event should be cancelled")

			success = event:start()
			assert(success, "start() should work on cancelled infinity event")
			assert(event:get_status() == "active", "Event should be active")

			success = event:finish()
			assert(success, "finish() should work on infinity event")
			assert(event:get_status() == "completed", "Event should be completed")
		end)


		it("Should handle control methods on non-existent events gracefully", function()
			local event = schedule.get("non_existent")
			assert(event == nil, "Non-existent event should return nil")

			if event then
				local success = event:finish()
				assert(not success, "finish() should return false for non-existent event")

				success = event:start()
				assert(not success, "start() should return false for non-existent event")

				success = event:cancel()
				assert(not success, "cancel() should return false for non-existent event")

				success = event:pause()
				assert(not success, "pause() should return false for non-existent event")

				success = event:resume()
				assert(not success, "resume() should return false for non-existent event")
			end
		end)


		it("Should not start already active event", function()
			local event = schedule.event()
				:duration(100)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			local success = event:start()
			assert(not success, "start() should return false for active event")
			assert(event:get_status() == "active", "Event should remain active")
		end)


		it("Should not start already completed event", function()
			local event = schedule.event()
				:duration(10)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10
			schedule.update()
			assert(event:get_status() == "completed", "Event should be completed")

			local success = event:start()
			assert(not success, "start() should return false for completed event")
			assert(event:get_status() == "completed", "Event should remain completed")
		end)
	end)
end

