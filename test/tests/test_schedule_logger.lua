return function()
	describe("Schedule Logger", function()
		local schedule ---@type schedule

		local debug_called = false
		local warn_called = false
		local error_called = false

		local EMPTY_FUNCTION = function(_, message, context) end

		local function reset_logger_state()
			debug_called = false
			warn_called = false
			error_called = false
		end

		local function create_test_logger()
			return {
				trace = EMPTY_FUNCTION,
				debug = function(_, message, context)
					debug_called = true
				end,
				info = EMPTY_FUNCTION,
				warn = function(_, message, context)
					warn_called = true
				end,
				error = function(_, message, context)
					error_called = true
				end,
		}
	end

		before(function()
			schedule = require("schedule.schedule")
			schedule.reset_state()
			reset_logger_state()
			schedule.init()
		end)

		it("Should call debug when creating event", function()
			schedule.set_logger(create_test_logger())
			schedule.init()

			assert(not debug_called, "Debug should not be called yet")

			schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			assert(debug_called, "Debug should be called when creating event")
		end)


		it("Should call warn when getting status of non-existing event", function()
			schedule.set_logger(create_test_logger())
			schedule.init()

			assert(not warn_called, "Warn should not be called yet")

			local event_info = schedule.get("non_existing_event")
			assert(event_info == nil, "Status should be nil for non-existing event")
		end)


		it("Should call error when using non-existing condition", function()
			schedule.set_logger(create_test_logger())
			schedule.init()

			reset_logger_state()
			assert(not error_called, "Error should not be called yet")

			schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("non_existing_condition", {})
				:save()

			schedule.update()
			assert(error_called, "Error should be called for non-existing condition")
		end)


		it("Should work without logger set", function()
			schedule.set_logger(nil)
			schedule.init()

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			assert(event ~= nil, "Status should exist even without logger")
		end)


		it("Should allow changing logger at runtime", function()
			local logger1 = create_test_logger()
			local logger2 = create_test_logger()

			schedule.set_logger(logger1)
			schedule.init()

			reset_logger_state()
			schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()
			assert(debug_called, "First logger should be called")

			reset_logger_state()
			schedule.set_logger(logger2)
			schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()
			assert(debug_called, "Second logger should be called")
		end)
	end)
end

