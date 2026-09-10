return function()
	describe("Schedule LiveOps control scenario", function()
		local schedule ---@type schedule
		local schedule_time
		local time = 0
		local player_level = 1

		-- 2026-01-01T00:00:00 UTC. Puzzle/diamond alternate from this anchor.
		local JAN_1 = 1767225600
		local DAY
		local HOUR

		local function deep_copy_state(state)
			return sys.deserialize(sys.serialize(state))
		end

		local function count_active(category)
			local count = 0
			local active_id
			for event_id, event in pairs(schedule.filter(category, "active")) do
				count = count + 1
				active_id = event_id
			end
			return count, active_id
		end

		local function declare_calendar()
			schedule.event("puzzle")
				:category("liveops")
				:start_at("2026-01-01T00:00:00")
				:duration(DAY)
				:cycle("every", { seconds = 2 * DAY, skip_missed = true })
				:min_time(HOUR)
				:catch_up(false)
				:save()

			schedule.event("diamond")
				:category("liveops")
				:start_at("2026-01-02T00:00:00")
				:duration(DAY)
				:cycle("every", { seconds = 2 * DAY, skip_missed = true })
				:min_time(HOUR)
				:catch_up(false)
				:save()

			schedule.event("fortune")
				:category("liveops")
				:infinity()
				:condition("min_level", 7)
				:save()
		end

		before(function()
			schedule = require("schedule.schedule")
			schedule_time = require("schedule.internal.schedule_time")
			DAY = schedule.DAY
			HOUR = schedule.HOUR

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			player_level = 1
			schedule.register_condition("min_level", function(min_level)
				return player_level >= min_level
			end)

			-- Sep 10 2026 12:00 UTC: puzzle window (Jan 1 + 252 days)
			time = JAN_1 + 252 * DAY + 12 * HOUR
		end)

		it("Should run the liveops calendar control scenario", function()
			declare_calendar()
			schedule.update()

			-- 1. First update: exactly one of puzzle/diamond is active, min_time killed nobody
			assert(schedule.get("puzzle"):get_status() ~= "cancelled", "min_time must not cancel puzzle")
			assert(schedule.get("diamond"):get_status() ~= "cancelled", "min_time must not cancel diamond")
			local active_count, active_id = count_active("liveops")
			assert(active_count == 1, "Exactly one liveops event should be active, got " .. active_count)
			assert(active_id == "puzzle", "Sep 10 is a puzzle day, got " .. tostring(active_id))
			assert(schedule.get("puzzle"):get_cycle_count() == 126,
				"Puzzle should be occurrence 126 on the Jan 1 grid, got " .. schedule.get("puzzle"):get_cycle_count())
			assert(schedule.get_event_state("diamond").next_cycle_time == JAN_1 + 253 * DAY,
				"Diamond should already be scheduled for Sep 11, got " ..
					tostring(schedule.get_event_state("diamond").next_cycle_time))

			-- 3. fortune waits on level 1
			assert(schedule.get("fortune"):get_status() == "pending", "fortune should wait for level 7")

			-- 2. Next day the active event swaps
			time = time + DAY
			schedule.update()
			active_count, active_id = count_active("liveops")
			assert(active_count == 1, "Still exactly one active after a day, got " .. active_count)
			assert(active_id == "diamond", "Sep 11 is a diamond day, got " .. tostring(active_id))
			assert(schedule.get("diamond"):get_cycle_count() == 126,
				"Diamond should be occurrence 126 on the Jan 2 grid, got " .. schedule.get("diamond"):get_cycle_count())

			-- 3. fortune opens at level 7 without a restart
			player_level = 7
			schedule.update()
			assert(schedule.get("fortune"):get_status() == "active", "fortune should start at level 7")

			-- 4. get_state → set_state → re-declare keeps the running occurrence
			local puzzle_start = schedule.get("puzzle"):get_start_time()
			local puzzle_end = schedule.get("puzzle"):get_end_time()
			local diamond_start = schedule.get("diamond"):get_start_time()
			local diamond_end = schedule.get("diamond"):get_end_time()
			local saved = deep_copy_state(schedule.get_state())

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			schedule.register_condition("min_level", function(min_level)
				return player_level >= min_level
			end)
			schedule.set_state(saved)
			declare_calendar()

			assert(schedule.get("puzzle"):get_start_time() == puzzle_start, "puzzle start_time should survive re-declare")
			assert(schedule.get("puzzle"):get_end_time() == puzzle_end, "puzzle end_time should survive re-declare")
			assert(schedule.get("diamond"):get_start_time() == diamond_start, "diamond start_time should survive re-declare")
			assert(schedule.get("diamond"):get_end_time() == diamond_end, "diamond end_time should survive re-declare")

			-- 5. Restart mid-event does not replay the occurrence
			local starts = 0
			schedule.on_event:subscribe(function(event)
				if event.callback_type == "start" and (event.event_id == "puzzle" or event.event_id == "diamond") then
					starts = starts + 1
				end
				return true
			end)
			schedule.update()
			assert(starts == 0, "Restored occurrence must not fire on_start again, got " .. starts)
			active_count, active_id = count_active("liveops")
			assert(active_count == 2, "diamond + fortune should be active after restore, got " .. active_count)
			assert(schedule.get("diamond"):get_status() == "active", "diamond should still be active")
			assert(schedule.get("fortune"):get_status() == "active", "fortune should still be active")

			-- 6. A week offline with catch_up(false) does not replay missed windows
			local lifecycle = {}
			schedule.on_event:subscribe(function(event)
				if event.event_id == "puzzle" or event.event_id == "diamond" then
					table.insert(lifecycle, event.event_id .. ":" .. event.callback_type)
				end
				return true
			end)
			time = time + 7 * DAY
			schedule.update()
			local replayed = 0
			for _, item in ipairs(lifecycle) do
				if item:find(":start$", 1) then
					replayed = replayed + 1
				end
			end
			assert(replayed <= 1, "Missed windows must not be replayed, starts=" .. replayed .. " events=" .. table.concat(lifecycle, ","))
			active_count = count_active("liveops")
			-- fortune is infinite and still active; exactly one of puzzle/diamond
			local liveops_window = 0
			if schedule.get("puzzle"):get_status() == "active" then
				liveops_window = liveops_window + 1
			end
			if schedule.get("diamond"):get_status() == "active" then
				liveops_window = liveops_window + 1
			end
			assert(liveops_window == 1, "After a week, exactly one of puzzle/diamond should be active, got " .. liveops_window)
			assert(schedule.get("fortune"):get_status() == "active", "fortune should stay active")
		end)


		it("Should recover a pending calendar event whose start_time is still in the future", function()
			declare_calendar()

			local st = schedule.get_event_state("puzzle")
			st.status = "pending"
			st.start_time = time + 10 * 365 * DAY
			st.end_time = nil
			st.cycle_count = 126

			schedule.update()

			local event = schedule.get("puzzle")
			assert(event:get_status() == "active", "Should start the current window, got " .. event:get_status())
			assert(event:get_start_time() == JAN_1 + 252 * DAY,
				"Should land on the Sep 10 occurrence, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == JAN_1 + 253 * DAY,
				"Should set end_time for the current window, got " .. tostring(event:get_end_time()))
			assert(event:get_cycle_count() == 126, "Should be occurrence 126, got " .. event:get_cycle_count())
		end)


		it("Should recover a pending calendar event in a gap without starting a finished window", function()
			-- Sep 11 12:00 UTC: puzzle gap until Sep 12
			time = JAN_1 + 253 * DAY + 12 * HOUR
			declare_calendar()

			local st = schedule.get_event_state("puzzle")
			st.status = "pending"
			st.start_time = time + 10 * 365 * DAY
			st.end_time = nil

			schedule.update()

			assert(schedule.get("puzzle"):get_status() == "pending",
				"Gap day should stay pending, got " .. schedule.get("puzzle"):get_status())
			assert(schedule.get("puzzle"):get_start_time() == JAN_1 + 254 * DAY,
				"Should wait for the Sep 12 occurrence, got " .. tostring(schedule.get("puzzle"):get_start_time()))

			time = JAN_1 + 254 * DAY
			schedule.update()
			assert(schedule.get("puzzle"):get_status() == "active",
				"Should start the next window, got " .. schedule.get("puzzle"):get_status())
			assert(schedule.get("puzzle"):get_start_time() == JAN_1 + 254 * DAY,
				"Next window should start on Sep 12, got " .. tostring(schedule.get("puzzle"):get_start_time()))
		end)
	end)
end
