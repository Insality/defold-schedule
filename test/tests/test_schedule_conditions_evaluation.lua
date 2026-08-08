return function()
	describe("Schedule Conditions Evaluation", function()
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

		it("Should evaluate conditions when event is about to start", function()
			local condition_called = false

			schedule.register_condition("test_condition", function(data)
				condition_called = true
				return data.value == 100
			end)

			local event = schedule.event()
				:category("offer")
				:after(100)
				:duration(60)
				:condition("test_condition", { value = 100 })
				:save()

			assert(event:get_status() == "pending", "Event should be pending")

			time = 10
			schedule.update()
			assert(not condition_called, "Condition should not be evaluated before start_time")

			time = 100
			schedule.update()
			assert(condition_called, "Condition should be evaluated when event is about to start")
		end)


		it("Should keep retrying while conditions fail without abort_on_fail", function()
			local condition_value = false
			local evaluation_count = 0

			schedule.register_condition("dynamic_condition", function(data)
				evaluation_count = evaluation_count + 1
				return condition_value
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("dynamic_condition", {})
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "pending", "Event should stay pending while the condition fails")
			assert(evaluation_count >= 1, "Condition should be evaluated")

			local initial_count = evaluation_count
			condition_value = true
			schedule.update()
			assert(evaluation_count > initial_count, "Condition should be re-evaluated on the next update")
			assert(event:get_status() == "active", "Event should activate once the condition passes")
		end)


		it("Should not revive an aborted event when conditions pass later", function()
			local condition_value = false
			local fail_count = 0

			schedule.register_condition("count_condition", function(data)
				return condition_value
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("count_condition", {})
				:abort_on_fail()
				:on_fail(function() fail_count = fail_count + 1 end)
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Event should be aborted when the condition fails")
			assert(fail_count == 1, "on_fail should be called once")

			condition_value = true
			time = 70
			schedule.update()
			time = 80
			schedule.update()
			assert(event:get_status() == "aborted", "Aborted event should stay aborted, it does not retry")
			assert(fail_count == 1, "on_fail should not be called again, got " .. fail_count)

			assert(event:start(), "An aborted event can still be started explicitly")
			assert(event:get_status() == "active", "Explicit start should activate the event")
		end)


		it("Should set status to aborted when abort_on_fail is set", function()
			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted", "Status should be aborted when abort_on_fail is set")
		end)


		it("Should prevent activation until all conditions pass", function()
			local condition1_value = false
			local condition2_value = false

			schedule.register_condition("condition1", function(data)
				return condition1_value
			end)

			schedule.register_condition("condition2", function(data)
				return condition2_value
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("condition1", {})
				:condition("condition2", {})
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() ~= "active", "Event should not activate when conditions fail")

			condition1_value = true
			schedule.update()
			assert(event:get_status() ~= "active", "Event should not activate when only one condition passes")

			condition2_value = true
			schedule.update()
			assert(event:get_status() == "active", "Event should activate when all conditions pass")
		end)
	end)
end

