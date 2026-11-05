return function()
	describe("Schedule Conditions", function()
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

		it("Should register condition", function()
			local condition_called = false
			schedule.register_condition("test_condition", function(data)
				condition_called = true
				return data.value == 100
			end)

			local event_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("test_condition", { value = 100 })
				:save()

			time = 60
			schedule.update()
			assert(condition_called, "Condition should be called when event is about to start")
		end)


		it("Should handle event with single condition", function()
			schedule.register_condition("has_level", function(data)
				return data.level >= 5
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("has_level", { level = 5 })
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should handle event with multiple conditions", function()
			schedule.register_condition("has_token", function(data)
				return data.amount >= 100
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("has_token", { token_id = "gems", amount = 100 })
				:condition("has_token", { token_id = "level", amount = 4 })
				:save()

			assert(event ~= nil, "Status should exist")
		end)


		it("Should abort event when condition fails with abort_on_fail", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Event should be aborted")
		end)


		it("Should abort event when condition fails with abort_on_fail", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Event should be aborted")
		end)


		it("Should re-evaluate conditions on update", function()
			local condition_value = false
			schedule.register_condition("dynamic_condition", function(data)
				return condition_value
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("dynamic_condition", {})
				:save()

			time = 60
			schedule.update()
			local initial_status = event:get_status()

			condition_value = true
			schedule.update()
			assert(event:get_status() ~= initial_status or event:get_status() == "active", "Status should change when condition becomes true")
		end)


		it("Should not start a cyclic leftover window when conditions fail after min_time skip", function()
			-- weekly Monday + duration week: always inside a leftover window.
			-- The first start_at is long dead, so min_time skips it and process_cycle
			-- lands on this week. Conditions must still gate that start.
			local JAN_1 = 1767225600
			local player_level = 1
			schedule.register_condition("min_level", function(min_level)
				return player_level >= min_level
			end)

			time = JAN_1 + 253 * schedule.DAY + 12 * schedule.HOUR -- Friday Sep 11 2026
			local event = schedule.event("puzzle_event")
				:start_at("2026-01-05T00:00:00")
				:duration(schedule.WEEK)
				:min_time(schedule.HOUR)
				:cycle("weekly", { weekdays = { "mon" }, skip_missed = true })
				:condition("min_level", 6)
				:catch_up(false)
				:save()

			schedule.update()
			assert(event:get_status() == "pending",
				"Level 1 must not start the leftover week, got " .. event:get_status())

			player_level = 6
			schedule.update()
			assert(event:get_status() == "active",
				"Should start the current week once the condition passes, got " .. event:get_status())
			assert(event:get_start_time() == JAN_1 + 249 * schedule.DAY,
				"Should keep Monday Sep 7 as the occurrence, got " .. tostring(event:get_start_time()))
		end)


		it("Should check a single condition without an event", function()
			local current_scene = "main"
			schedule.register_condition("scene", function(scene_name)
				return current_scene == scene_name
			end)

			assert(schedule.check_condition("scene", "main"), "Should pass on the current scene")
			assert(not schedule.check_condition("scene", "battle"), "Should fail on another scene")

			current_scene = "battle"
			assert(schedule.check_condition("scene", "battle"), "Should follow the game state")
		end)


		it("Should assert on an unregistered condition", function()
			local is_ok = pcall(schedule.check_condition, "unknown_condition", nil)
			assert(not is_ok, "Unknown condition should assert")
		end)


		it("Should return a boolean from check_condition", function()
			schedule.register_condition("truthy", function()
				return "yes" ---@diagnostic disable-line: return-type-mismatch
			end)
			schedule.register_condition("nil_result", function()
				return nil ---@diagnostic disable-line: return-type-mismatch
			end)

			assert(schedule.check_condition("truthy", nil) == true, "Truthy result should be true")
			assert(schedule.check_condition("nil_result", nil) == false, "Nil result should be false")
		end)
	end)
end
