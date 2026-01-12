return function()
	describe("Schedule Cycles Every", function()
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

		it("Should cycle every N seconds", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 120 })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active at first trigger")

			time = 61
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete after duration")

			time = 180
			schedule.update()
			assert(event:get_status() == "active", "Event should cycle and be active again")
		end)


		it("Should cycle with anchor start", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100, anchor = "start" })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 90
			schedule.update()
			assert(event:get_status() == "completed")

			time = 160
			schedule.update()
			assert(event:get_status() == "active", "Should cycle from start anchor")
		end)


		it("Should cycle with anchor end", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100, anchor = "end" })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 90
			schedule.update()
			assert(event:get_status() == "completed")

			time = 190
			schedule.update()
			assert(event:get_status() == "active", "Should cycle from end anchor")
		end)


		it("Should skip missed cycles when skip_missed is true", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = true })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 1000
			schedule.update()
			assert(event:get_status() == "active" or event:get_status() == "completed", "Should skip to current cycle")
		end)


		it("Should catch up missed cycles when skip_missed is false", function()
			local trigger_count = 0
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = false })
				:catch_up(true)
				:save()

			schedule.on_event:subscribe(function(event_data)
				if event_data.event_id == event:get_id() and event_data.callback_type == "enabled" then
					trigger_count = trigger_count + 1
				end
				return true
			end)

			time = 60
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			time = 1000
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed cycles")
		end)


		it("Should handle multiple cycles correctly", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100 })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 70
			schedule.update()
			assert(event:get_status() == "completed")

			time = 160
			schedule.update()
			assert(event:get_status() == "active", "Second cycle")

			time = 170
			schedule.update()
			assert(event:get_status() == "completed", "Second cycle completed")

			time = 260
			schedule.update()
			assert(event:get_status() == "active", "Third cycle")
		end)


		it("Should limit catch-up cycles with max_catches", function()
			local cycle_count = 0
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100, skip_missed = false, max_catches = 3 })
				:catch_up(true)
				:on_start(function()
					cycle_count = cycle_count + 1
				end)
				:save()

			time = 60
			schedule.update()
			assert(cycle_count == 1, "First cycle should trigger")
			assert(event:get_status() == "active", "Event should be active")

			time = 70
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete")

			time = 1000
			schedule.update()
			assert(cycle_count <= 4, "Should only catch up max_catches cycles (1 initial + 3 catch-up = 4 max)")
			assert(cycle_count >= 3, "Should catch up at least some cycles")
		end)


		it("Should increment cycle_count on each cycle activation", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100 })
				:save()

			time = 60
			schedule.update()
			local status1 = schedule.get_status(event:get_id())
			assert(status1 ~= nil, "Status should exist")
			assert(status1.cycle_count == 0 or status1.cycle_count == nil, "Initial cycle_count should be 0 or nil")

			time = 70
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete")

			time = 160
			schedule.update()
			local status2 = schedule.get_status(event:get_id())
			assert(status2 ~= nil, "Status should exist")
			assert(status2.cycle_count == 1, "cycle_count should increment to 1 after second cycle")

			time = 170
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete again")

			time = 260
			schedule.update()
			local status3 = schedule.get_status(event:get_id())
			assert(status3 ~= nil, "Status should exist")
			assert(status3.cycle_count == 2, "cycle_count should increment to 2 after third cycle")
		end)
	end)
end

