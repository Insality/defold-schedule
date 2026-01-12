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
	end)
end

