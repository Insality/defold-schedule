return function()
	describe("Schedule Control", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule_time.set_time_function = function() return time end
			schedule.reset_state()
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
				:on_fail("abort")
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

			local success = schedule.cancel(event:get_id())
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

			local success = schedule.pause(event:get_id())
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

			local success = schedule.resume(event:get_id())
			assert(not success, "resume() should return false for active event")
			assert(event:get_status() == "active", "Event should remain active")
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
			local success = schedule.finish("non_existent")
			assert(not success, "finish() should return false for non-existent event")

			success = schedule.start("non_existent")
			assert(not success, "start() should return false for non-existent event")

			success = schedule.cancel("non_existent")
			assert(not success, "cancel() should return false for non-existent event")

			success = schedule.pause("non_existent")
			assert(not success, "pause() should return false for non-existent event")

			success = schedule.resume("non_existent")
			assert(not success, "resume() should return false for non-existent event")
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

