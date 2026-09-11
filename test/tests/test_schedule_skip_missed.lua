return function()
	describe("Schedule skip_missed LiveOps windows", function()
		local schedule ---@type schedule
		local schedule_time
		local time = 0

		local JAN_1 = 1767225600 -- 2026-01-01T00:00:00 UTC, Thursday
		local DAY
		local HOUR

		local function subscribe_starts(event_id)
			local starts = {}
			schedule.on_event:subscribe(function(event)
				if event.event_id == event_id and event.callback_type == "start" then
					table.insert(starts, event.start_time)
				end
				return true
			end)
			return starts
		end

		before(function()
			schedule = require("schedule.schedule")
			schedule_time = require("schedule.internal.schedule_time")
			DAY = schedule.DAY
			HOUR = schedule.HOUR

			schedule.reset_state()
			schedule_time.set_time_function(function() return time end)
			time = 0
		end)

		local function declare_puzzle()
			return schedule.event("puzzle")
				:start_at("2026-01-01T00:00:00")
				:duration(DAY)
				:cycle("every", { seconds = 2 * DAY, skip_missed = true })
				:catch_up(false)
				:save()
		end

		it("Should start only the current window after a long offline jump", function()
			local starts = subscribe_starts("puzzle")
			time = JAN_1 + 12 * HOUR
			local event = declare_puzzle()
			schedule.update()
			assert(event:get_status() == "active", "First window should be running at Jan 1 12:00")
			assert(event:get_start_time() == JAN_1, "First window starts at Jan 1 00:00")

			for i = #starts, 1, -1 do
				starts[i] = nil
			end

			time = JAN_1 + 14 * DAY + 12 * HOUR -- 2026-01-15 12:00
			schedule.update()

			assert(#starts == 1, "One update after the gap must emit one start, got " .. #starts
				.. " times=" .. table.concat(starts, ","))
			assert(event:get_status() == "active", "Should stay on the current window, got " .. event:get_status())
			assert(event:get_start_time() == JAN_1 + 14 * DAY,
				"Should land on Jan 15 00:00, got " .. tostring(event:get_start_time()))
			assert(event:get_end_time() == JAN_1 + 15 * DAY,
				"Current window should last one day, got " .. tostring(event:get_end_time()))
			assert(event:get_cycle_count() == 7,
				"Jan 15 is occurrence 7 on the Jan 1 grid, got " .. event:get_cycle_count())
		end)


		it("Should start only the current window on first launch inside it", function()
			time = JAN_1 + 14 * DAY + 12 * HOUR -- 2026-01-15 12:00
			local event = declare_puzzle()
			local starts = subscribe_starts("puzzle")
			schedule.update()

			assert(#starts == 1, "First launch must not replay Jan 1..13, starts=" .. #starts)
			assert(event:get_status() == "active", "Should start the Jan 15 window, got " .. event:get_status())
			assert(event:get_start_time() == JAN_1 + 14 * DAY,
				"Should land on Jan 15 00:00, got " .. tostring(event:get_start_time()))
			assert(event:get_cycle_count() == 7,
				"Jan 15 is occurrence 7, got " .. event:get_cycle_count())
		end)


		it("Should park pending in a gap without starting missed windows", function()
			time = JAN_1 + 13 * DAY + 12 * HOUR -- 2026-01-14 12:00, gap after Jan 13 window
			local event = declare_puzzle()
			local starts = subscribe_starts("puzzle")
			schedule.update()

			assert(#starts == 0, "Gap must not start missed windows, starts=" .. #starts)
			assert(event:get_status() == "pending", "Jan 14 is a gap, got " .. event:get_status())
			assert(event:get_start_time() == JAN_1 + 14 * DAY,
				"Should wait for Jan 15, got " .. tostring(event:get_start_time()))
		end)


		it("Should start the current weekly week once, not every Monday since start_at", function()
			-- Friday Sep 11 2026 12:00. Monday week with duration WEEK is still open.
			time = JAN_1 + 253 * DAY + 12 * HOUR
			local event = schedule.event("weekly_puzzle")
				:start_at("2026-01-05T00:00:00")
				:duration(schedule.WEEK)
				:cycle("weekly", { weekdays = { "mon" }, skip_missed = true })
				:catch_up(false)
				:save()

			local starts = subscribe_starts("weekly_puzzle")
			schedule.update()

			assert(#starts == 1, "Must not walk every Monday, starts=" .. #starts)
			assert(event:get_status() == "active", "Friday is inside the Monday week, got " .. event:get_status())
			assert(event:get_start_time() == JAN_1 + 249 * DAY,
				"Should land on Monday Sep 7, got " .. tostring(event:get_start_time()))
		end)
	end)
end
