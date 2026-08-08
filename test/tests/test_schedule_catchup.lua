return function()
	describe("Schedule Catchup", function()
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

		it("Should catch up missed events when catch_up is true", function()
			local count = 0

			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = false })
				:on_start(function()
					count = count + 1
				end)
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(count == 1, "on_start should be called")
			assert(event:get_status() == "active", "Event should be active")

			time = 1000
			schedule.update()
			assert(count > 5, "on_start should be called multiple times")
			assert(event:get_status() == "completed", "Event should be completed after catch up")
		end)


		it("Should skip missed events when catch_up is false", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" and event.callback_type == "enabled" then
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

			time = 60
			schedule.update()
			local initial_count = trigger_count

			time = 1000
			schedule.update()
			assert(trigger_count == initial_count, "Should not catch up missed events")
		end)


		it("Should catch up with duration events", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			time = 1000
			schedule.update()

			-- FIX
			-- TODO: here is double due the last update time logic, it's not calling a catchup to finish first time
			schedule.update()

			assert(event:get_status() == "completed", "Event should be completed after catch up")
		end)


		it("Should catch up with cycle events", function()
			local trigger_count = 0
			schedule.on_event:subscribe(function(event)
				if event.category == "reward" and event.callback_type == "enabled" then
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

			time = 60
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			time = 1000
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed cycles")
		end)


		it("Should simulate offline progression", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:catch_up(true)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active")

			time = 10000
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete after offline period")
		end)


		it("Should handle catch_up default behavior with duration", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 1000
			schedule.update()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle catch_up default behavior without duration", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:save()

			time = 1000
			schedule.update()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should replay every missed cycle exactly once", function()
			local runs = {}

			schedule.event("daily")
				:after(10)
				:duration(1)
				:cycle("every", { seconds = 100 })
				:catch_up(true)
				:on_end(function(event_data) table.insert(runs, event_data.start_time) end)
				:save()

			schedule.update()

			-- Player is away until 1000, occurrences are 10, 110, ... 910
			time = 1000
			schedule.update()

			assert(#runs == 10, "Should replay 10 cycles, got " .. #runs)
			assert(runs[1] == 10, "First replayed cycle should start at 10, got " .. tostring(runs[1]))
			assert(runs[#runs] == 910, "Last replayed cycle should start at 910, got " .. tostring(runs[#runs]))
			assert(schedule.get_event_state("daily").next_cycle_time == 1010, "Next cycle should stay on the grid")
		end)


		it("Should limit replayed cycles to max_catches per update", function()
			local runs = 0

			schedule.event("daily")
				:after(10)
				:duration(1)
				:cycle("every", { seconds = 100, max_catches = 3 })
				:catch_up(true)
				:on_end(function() runs = runs + 1 end)
				:save()

			schedule.update()

			time = 10000
			schedule.update()
			assert(runs == 3, "Should replay at most max_catches cycles per update, got " .. runs)
		end)


		it("Should replay only the last cycle with skip_missed", function()
			local runs = {}

			schedule.event("daily")
				:after(10)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = true })
				:catch_up(true)
				:on_end(function(event_data) table.insert(runs, event_data.start_time) end)
				:save()

			schedule.update()

			time = 1000
			schedule.update()
			assert(#runs == 1, "Should replay a single cycle, got " .. #runs)
			assert(runs[1] == 910, "Should replay the most recent cycle, got " .. tostring(runs[1]))
		end)


		it("Should replay missed calendar cycles", function()
			-- 2026-01-01T00:00:00 UTC is a Thursday
			local THURSDAY = 1767225600
			local runs = 0
			time = THURSDAY

			schedule.event("weekly")
				:cycle("weekly", { weekdays = { "sun" }, time = "10:00" })
				:duration(3600)
				:catch_up(true)
				:on_end(function() runs = runs + 1 end)
				:save()

			schedule.update()

			-- Four Sundays pass while the game is closed
			time = THURSDAY + 28 * 86400
			schedule.update()
			assert(runs == 4, "Should replay the four missed Sundays, got " .. runs)
		end)


		it("Should not replay anything when catch_up is off", function()
			local runs = 0

			schedule.event("daily")
				:after(10)
				:duration(1)
				:cycle("every", { seconds = 100 })
				:catch_up(false)
				:on_end(function() runs = runs + 1 end)
				:save()

			schedule.update()

			time = 1000
			schedule.update()
			assert(runs <= 1, "Only the running occurrence may finish, got " .. runs)
			assert(schedule.get_event_state("daily").next_cycle_time == 1010, "Should land back on the cycle grid")
		end)


		it("Should activate the occurrence that is running when the player returns", function()
			local runs = 0

			-- Occurrences every 100 seconds, each running for 50 seconds
			local event = schedule.event("window")
				:duration(50)
				:cycle("every", { seconds = 100 })
				:catch_up(true)
				:on_end(function() runs = runs + 1 end)
				:save()

			schedule.update()

			-- Back at 520, inside the occurrence that started at 500
			time = 520
			schedule.update()

			assert(runs == 5, "Should replay the five finished occurrences, got " .. runs)
			assert(event:get_status() == "active", "The running occurrence should be active")
			assert(event:get_start_time() == 500, "Should be on the occurrence that started at 500, got " .. tostring(event:get_start_time()))
		end)


		it("Should show a calendar event that is running, even without catch_up", function()
			-- 2026-01-01T00:00:00 UTC is a Thursday, the first Sunday is the 4th
			local THURSDAY = 1767225600
			time = THURSDAY

			local event = schedule.event("weekend")
				:cycle("weekly", { weekdays = { "sun" }, time = "00:00" })
				:duration(2 * 86400)
				:catch_up(false)
				:save()

			schedule.update()
			assert(event:get_status() == "pending", "Should wait for Sunday")

			-- The player opens the game on Monday noon, the event runs until Tuesday
			time = THURSDAY + 4 * 86400 + 12 * 3600
			schedule.update()
			assert(event:get_status() == "active", "The running weekend event should be active")
			assert(event:get_time_left() == 12 * 3600, "Should have 12 hours left, got " .. event:get_time_left())
		end)


		it("Should default catch_up by the presence of a duration", function()
			schedule.event("with_duration"):after(10):duration(10):save()
			schedule.event("without_duration"):after(10):save()

			assert(schedule.get_event_state("with_duration").catch_up == false,
				"Events with a duration should not catch up by default")
			assert(schedule.get_event_state("without_duration").catch_up == true,
				"Events without a duration should catch up by default")

			schedule.event("with_duration"):after(10):duration(10):catch_up(true):save()
			assert(schedule.get_event_state("with_duration").catch_up == true, "Explicit catch_up should win")

			schedule.event("with_duration"):after(10):duration(10):catch_up(false):save()
			assert(schedule.get_event_state("with_duration").catch_up == false,
				"catch_up(false) should override the stored value")
		end)
	end)
end
