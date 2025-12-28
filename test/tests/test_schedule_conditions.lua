return function()
	describe("Schedule Conditions", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule_time.set_time_function = function() return time end
			schedule.reset_state()
			schedule.init()
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

			schedule.update()
			assert(condition_called, "Condition should be called")
		end)


		it("Should handle event with single condition", function()
			schedule.register_condition("has_level", function(data)
				return data.level >= 5
			end)

			local event_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("has_level", { level = 5 })
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should handle event with multiple conditions", function()
			schedule.register_condition("has_token", function(data)
				return data.amount >= 100
			end)

			local event_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("has_token", { token_id = "gems", amount = 100 })
				:condition("has_token", { token_id = "level", amount = 4 })
				:save()

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Status should exist")
		end)


		it("Should cancel event when condition fails with on_fail cancel", function()
			local fail_called = false
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("always_false", {})
				:on_fail("cancel")
				:on_fail(function(event)
					fail_called = true
				end)
				:save()

			time = 60
			schedule.update()
			assert(fail_called, "on_fail callback should be called")

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Event info should exist")
			assert(event_info:get_status() == "cancelled" or event_info:get_status() == "failed", "Event should be cancelled or failed")
		end)


		it("Should abort event when condition fails with on_fail abort", function()
			local fail_called = false
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("always_false", {})
				:on_fail("abort")
				:on_fail(function(event)
					fail_called = true
				end)
				:save()

			time = 60
			schedule.update()
			assert(fail_called, "on_fail callback should be called")

			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Event info should exist")
			assert(event_info:get_status() == "aborted" or event_info:get_status() == "failed", "Event should be aborted or failed")
		end)


		it("Should re-evaluate conditions on update", function()
			local condition_value = false
			schedule.register_condition("dynamic_condition", function(data)
				return condition_value
			end)

			local event_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(3600)
				:condition("dynamic_condition", {})
				:save()

			time = 60
			schedule.update()
			local event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Event info should exist")
			local initial_status = event_info:get_status()

			condition_value = true
			schedule.update()
			event_info = schedule.get(event_id)
			assert(event_info ~= nil, "Event info should exist")
			assert(event_info:get_status() ~= initial_status or event_info:get_status() == "active", "Status should change when condition becomes true")
		end)
	end)
end

