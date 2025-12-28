return function()
	describe("Schedule Conditions Evaluation", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
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


		it("Should automatically change status to pending when conditions pass after failure", function()
			local condition_value = false

			schedule.register_condition("dynamic_condition", function(data)
				return condition_value
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("dynamic_condition", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "aborted" or event:get_status() == "failed", "Event should be aborted when condition fails")

			condition_value = true
			schedule.update()
			local status = event:get_status()
			assert(status == "pending" or status == "active", "Status should change to pending or active when conditions pass")
		end)


		it("Should re-evaluate conditions when status changes back to startable", function()
			local condition_value = false
			local evaluation_count = 0

			schedule.register_condition("count_condition", function(data)
				evaluation_count = evaluation_count + 1
				return condition_value
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("count_condition", {})
				:abort_on_fail()
				:save()

			time = 60
			schedule.update()
			assert(evaluation_count >= 1, "Condition should be evaluated")

			local initial_count = evaluation_count
			condition_value = true
			schedule.update()
			assert(evaluation_count > initial_count, "Condition should be re-evaluated when status changes")
			assert(event:get_status() == "pending" or event:get_status() == "active", "Event should become startable")
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

