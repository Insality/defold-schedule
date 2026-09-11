return function()
	describe("Schedule duration, end_at and exceed_end_time", function()
		local schedule ---@type schedule
		local schedule_time
		local builder
		local time = 0

		-- 2026-01-01T00:00:00 UTC is Thursday
		local JAN_1 = 1767225600
		local SUN = JAN_1 + 3 * 86400 -- Jan 4 Sunday
		local MON = JAN_1 + 4 * 86400 -- Jan 5 Monday
		local DAY
		local MINUTE

		before(function()
			schedule = require("schedule.schedule")
			schedule_time = require("schedule.internal.schedule_time")
			builder = require("schedule.internal.schedule_event_builder")

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			DAY = schedule.DAY
			MINUTE = schedule.MINUTE
			time = 0
		end)

		it("Should clip duration + end_at so the run ends at end_at", function()
			local event = schedule.event("sale")
				:start_at(100)
				:duration(200)
				:end_at(180)
				:save()

			time = 100
			schedule.update()

			assert(event:get_status() == "active", "Should start at start_at, got " .. event:get_status())
			assert(event:get_end_time() == 180, "Clip end should be min(start+duration, end_at), got " .. tostring(event:get_end_time()))
		end)


		it("Should clip duration + end_at so a short duration wins", function()
			local event = schedule.event("sale")
				:start_at(100)
				:duration(50)
				:end_at(200)
				:save()

			time = 100
			schedule.update()

			assert(event:get_status() == "active", "Should start at start_at")
			assert(event:get_end_time() == 150, "Clip end should be start+duration when it is before end_at, got " .. tostring(event:get_end_time()))
		end)


		it("Should cancel a one-shot when min_time equals duration but end_at clips the window", function()
			local event = schedule.event("sale")
				:start_at(100)
				:duration(100)
				:end_at(150)
				:min_time(100)
				:save()

			time = 100
			schedule.update()

			assert(event:get_status() == "cancelled",
				"Leftover 50 is not enough for min_time 100, got " .. event:get_status())
		end)


		it("Should run a full duration past end_at when exceed_end_time is set", function()
			local event = schedule.event("season_week")
				:start_at(100)
				:end_at(200)
				:duration(80, { exceed_end_time = true })
				:save()

			time = 190
			schedule.update()

			assert(event:get_status() == "active", "Should join until end_at, got " .. event:get_status())
			assert(event:get_start_time() == 190, "Exceed should start at now, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == 270, "Exceed run should pass end_at, got " .. tostring(event:get_end_time()))

			time = 200
			schedule.update()
			assert(event:get_status() == "active", "Run should continue past end_at")

			time = 270
			schedule.update()
			assert(event:get_status() == "completed", "Run should end at now+duration")
		end)


		it("Should keep cyclic leftover without exceed_end_time", function()
			time = JAN_1 + 12 * 3600
			local event = schedule.event("puzzle")
				:start_at("2026-01-01T00:00:00")
				:duration(DAY)
				:cycle("every", { seconds = 2 * DAY, skip_missed = true })
				:catch_up(false)
				:save()

			schedule.update()

			assert(event:get_status() == "active", "Late join should still start the leftover window")
			assert(event:get_start_time() == JAN_1, "Clip start stays the occurrence, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == JAN_1 + DAY, "Clip end stays occurrence+duration, got " .. tostring(event:get_end_time()))
			assert(event:get_time_left() == 12 * 3600, "Leftover should be 12 hours, got " .. tostring(event:get_time_left()))
		end)


		it("Should last two days from a Sunday join on a weekly Saturday exceed event", function()
			time = SUN
			local event = schedule.event("weekend")
				:start_at("2026-01-03T00:00:00")
				:duration(2 * DAY, { exceed_end_time = true })
				:cycle("weekly", { weekdays = { "sat" }, skip_missed = true })
				:catch_up(false)
				:save()

			schedule.update()

			assert(event:get_status() == "active", "Sunday is still inside the Saturday slot, got " .. event:get_status())
			assert(event:get_start_time() == SUN, "Exceed should start at now, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == SUN + 2 * DAY, "Run should be two days from join, got " .. tostring(event:get_end_time()))
		end)


		it("Should start a one-day exceed run on day two of a two-day slot", function()
			time = JAN_1 + DAY + 12 * 3600
			local event = schedule.event("slot")
				:start_at("2026-01-01T00:00:00")
				:duration(DAY, { exceed_end_time = true })
				:cycle("every", { seconds = 2 * DAY, skip_missed = true })
				:catch_up(false)
				:save()

			schedule.update()

			assert(event:get_status() == "active", "Day two of the slot should still be joinable, got " .. event:get_status())
			assert(event:get_start_time() == time, "Exceed should start at now")
			assert(event:get_end_time() == time + DAY, "Run should be one day from join, got " .. tostring(event:get_end_time()))
		end)


		it("Should start Tuesday when a late Monday exceed run ends after midnight", function()
			time = MON + DAY - 10 * MINUTE
			local event = schedule.event("offer")
				:start_at("2026-01-05T00:00:00")
				:duration(30 * MINUTE, { exceed_end_time = true })
				:cycle("every", { seconds = DAY, skip_missed = true })
				:catch_up(false)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Monday 23:50 should start the offer")
			assert(event:get_start_time() == time, "Exceed should start at join time")
			assert(event:get_end_time() == MON + DAY + 20 * MINUTE, "Run should cross midnight")

			time = MON + DAY
			schedule.update()
			assert(event:get_status() == "active", "Tuesday occurrence waits while Monday is still active")
			assert(event:get_start_time() == MON + DAY - 10 * MINUTE, "Should still be Monday's run")

			time = MON + DAY + 20 * MINUTE
			schedule.update()
			assert(event:get_status() == "active", "Tuesday should start when Monday's run ends, got " .. event:get_status())
			assert(event:get_start_time() == MON + DAY + 20 * MINUTE,
				"Tuesday should start at 00:20, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == MON + DAY + 50 * MINUTE,
				"Tuesday run should be 30 minutes, got " .. tostring(event:get_end_time()))
		end)


		it("Should launch the next day on the grid when the exceed run finished before it", function()
			time = MON
			local event = schedule.event("offer")
				:start_at("2026-01-05T00:00:00")
				:duration(30 * MINUTE, { exceed_end_time = true })
				:cycle("every", { seconds = DAY, skip_missed = true })
				:catch_up(false)
				:save()

			schedule.update()
			assert(event:get_status() == "active", "Should start at Monday midnight")

			time = MON + 30 * MINUTE
			schedule.update()
			assert(event:get_status() == "pending", "Should wait for Tuesday after Monday's run, got " .. event:get_status())
			assert(event:get_start_time() == MON + DAY, "Next start should be Tuesday 00:00, got " .. tostring(event:get_start_time()))

			time = MON + DAY
			schedule.update()
			assert(event:get_status() == "active", "Tuesday should launch on the grid")
			assert(event:get_start_time() == MON + DAY, "Tuesday start should be midnight, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == MON + DAY + 30 * MINUTE, "Tuesday run should be 30 minutes")
		end)


		it("Should reject exceed_end_time without duration", function()
			assert(not pcall(function()
				builder._validate_config({ exceed_end_time = true })
			end), "exceed_end_time requires duration()")
		end)


		it("Should keep an active exceed run across re-declare", function()
			time = 50
			schedule.event("season_week")
				:start_at(0)
				:end_at(200)
				:duration(80, { exceed_end_time = true })
				:save()

			schedule.update()
			local start_time = schedule.get("season_week"):get_start_time()
			local end_time = schedule.get("season_week"):get_end_time()
			assert(start_time == 50, "Should have started at now")
			assert(end_time == 130, "Should run 80 seconds from join")

			schedule.event("season_week")
				:start_at(0)
				:end_at(200)
				:duration(80, { exceed_end_time = true })
				:save()

			assert(schedule.get("season_week"):get_start_time() == start_time, "Re-declare must keep start_time")
			assert(schedule.get("season_week"):get_end_time() == end_time, "Re-declare must keep end_time")
			assert(schedule.get_event_state("season_week").exceed_end_time == true, "Flag should stay on the state")
		end)
	end)
end
