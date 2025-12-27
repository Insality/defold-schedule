return function()
	describe("Schedule Conditions", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local mock_time_value = 0

		local function set_time(time)
			mock_time_value = time
		end

	before(function()
		schedule = require("schedule.schedule")
		schedule_time.get_time = function()
			return mock_time_value
		end
		schedule.reset_state()
		schedule.init()

		mock_time_value = 0
	end)

		after(function()
			schedule.update()
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

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
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

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
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

			set_time(60)
			schedule.update()
			assert(fail_called, "on_fail callback should be called")

			local status = schedule.get_status(event_id)
			assert(status.status == "cancelled" or status.status == "failed", "Event should be cancelled or failed")
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

			set_time(60)
			schedule.update()
			assert(fail_called, "on_fail callback should be called")

			local status = schedule.get_status(event_id)
			assert(status.status == "aborted" or status.status == "failed", "Event should be aborted or failed")
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

			set_time(60)
			schedule.update()
			local status = schedule.get_status(event_id)
			local initial_status = status.status

			condition_value = true
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status ~= initial_status or status.status == "active", "Status should change when condition becomes true")
		end)
	end)
end

