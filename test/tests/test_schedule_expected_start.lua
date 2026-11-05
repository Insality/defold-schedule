return function()
	describe("Schedule Expected Start", function()
		local schedule ---@type schedule
		local schedule_time
		local time = 0

		local log_levels = {}

		local function create_test_logger()
			local logger = {}
			for _, level in ipairs({ "trace", "debug", "info", "warn", "error" }) do
				logger[level] = function()
					log_levels[level] = (log_levels[level] or 0) + 1
				end
			end
			return logger
		end

		local function deep_equal(a, b)
			if type(a) ~= type(b) then
				return false
			end
			if type(a) ~= "table" then
				return a == b
			end
			for key, value in pairs(a) do
				if not deep_equal(value, b[key]) then
					return false
				end
			end
			for key in pairs(b) do
				if a[key] == nil then
					return false
				end
			end
			return true
		end

		local function deep_copy(value)
			if type(value) ~= "table" then
				return value
			end
			local result = {}
			for key, item in pairs(value) do
				result[key] = deep_copy(item)
			end
			return result
		end

		before(function()
			schedule = require("schedule.schedule")
			schedule_time = require("schedule.internal.schedule_time")

			schedule.reset_state()
			schedule.set_logger(nil)
			schedule_time.set_time_function(function() return time end)
			time = 0
			log_levels = {}
		end)

		after(function()
			schedule.set_logger(nil)
		end)


		it("Should return start_at in the future as is", function()
			time = 1000
			schedule.event("liveops")
				:start_at(5000)
				:duration(100)
				:save()
			schedule.update()

			assert(schedule.get_expected_start_time("liveops") == 5000)
			assert(schedule.get("liveops"):get_expected_start_time() == 5000)
		end)


		it("Should return save time plus after for a delayed event", function()
			time = 200
			schedule.event("delayed")
				:after(300)
				:duration(100)
				:save()

			time = 250
			schedule.update()

			assert(schedule.get_expected_start_time("delayed") == 500)
		end)


		it("Should return the next cycle occurrence after now", function()
			schedule.event("every")
				:cycle("every", { seconds = 100 })
				:duration(50)
				:save()

			schedule.update()
			assert(schedule.get("every"):get_status() == "active")
			assert(schedule.get_expected_start_time("every") == nil, "Active event has no expected start")

			time = 60
			schedule.update()
			assert(schedule.get("every"):get_status() == "pending")
			assert(schedule.get_expected_start_time("every") == 100)

			time = 160
			schedule.update()
			assert(schedule.get_expected_start_time("every") == 200)
		end)


		it("Should return nil for unknown and not pending events", function()
			assert(schedule.get_expected_start_time("missing") == nil)
			assert(schedule.get_failed_conditions("missing") == nil)

			local event = schedule.event("one_shot")
				:duration(10)
				:save()
			schedule.update()
			assert(event:get_status() == "active")
			assert(event:get_expected_start_time() == nil)

			time = 20
			schedule.update()
			assert(event:get_status() == "completed")
			assert(event:get_expected_start_time() == nil)
		end)


		it("Should return a past start time while conditions hold the event", function()
			local is_open = false
			schedule.register_condition("gate", function() return is_open end)

			schedule.event("gated")
				:after(100)
				:duration(1000)
				:condition("gate")
				:save()

			time = 150
			schedule.update()

			assert(schedule.get("gated"):get_status() == "pending")
			local start_time = schedule.get_expected_start_time("gated")
			assert(start_time == 100 and start_time <= schedule.get_time(), "Start time has come, waiting for conditions")

			local failed = schedule.get_failed_conditions("gated")
			assert(#failed == 1 and failed[1].name == "gate")

			is_open = true
			assert(#schedule.get_failed_conditions("gated") == 0)
			schedule.update()
			assert(schedule.get("gated"):get_status() == "active")
		end)


		it("Should list only the failed conditions in declaration order", function()
			local player = { level = 5, tokens = 0 }
			schedule.register_condition("min_level", function(data) return player.level >= data.level end)
			schedule.register_condition("has_tokens", function(data) return player.tokens >= data.amount end)
			schedule.register_condition("always", function() return true end)

			schedule.event("offer")
				:after(100)
				:condition("has_tokens", { amount = 10 })
				:condition("min_level", { level = 3 })
				:condition("always")
				:save()

			local failed = schedule.get_failed_conditions("offer")
			assert(#failed == 1)
			assert(failed[1].name == "has_tokens")
			assert(failed[1].data.amount == 10)

			player.level = 1
			failed = schedule.get("offer"):get_failed_conditions()
			assert(#failed == 2)
			assert(failed[1].name == "has_tokens")
			assert(failed[2].name == "min_level")

			player.level = 5
			player.tokens = 10
			assert(#schedule.get_failed_conditions("offer") == 0)
		end)


		it("Should return an empty list for an event without conditions", function()
			schedule.event("plain"):after(10):save()
			local failed = schedule.get_failed_conditions("plain")
			assert(type(failed) == "table" and #failed == 0)
		end)


		it("Should count an unregistered condition as failed without an error log", function()
			schedule.set_logger(create_test_logger())
			schedule.event("unknown_gate")
				:after(10)
				:condition("not_registered", { value = 1 })
				:save()
			log_levels = {}

			local failed = schedule.get_failed_conditions("unknown_gate")
			assert(#failed == 1 and failed[1].name == "not_registered")
			assert(schedule.get_expected_start_time("unknown_gate") == 10)

			assert(not log_levels.info and not log_levels.warn and not log_levels.error, "Nothing above debug is logged")
		end)


		it("Should return new entries that do not touch the event conditions", function()
			schedule.register_condition("never", function() return false end)
			local data = { value = 1 }
			schedule.event("entries")
				:after(10)
				:condition("never", data)
				:save()

			local failed = schedule.get_failed_conditions("entries")
			assert(failed[1].data == data, "Data is passed as declared")
			failed[1].name = "changed"
			table.remove(failed, 1)

			local conditions = schedule.get_event_state("entries").conditions
			assert(#conditions == 1 and conditions[1].name == "never")
		end)


		it("Should not abort, call callbacks or change the state", function()
			schedule.register_condition("never", function() return false end)
			local callback_count = 0
			local function count() callback_count = callback_count + 1 end

			schedule.event("strict")
				:after(100)
				:duration(50)
				:condition("never")
				:abort_on_fail()
				:on_start(count)
				:on_fail(count)
				:on_end(count)
				:save()
			schedule.event("every")
				:cycle("every", { seconds = 100 })
				:duration(50)
				:save()

			time = 60
			schedule.update()

			local snapshot = deep_copy(schedule.get_state())
			local queue_size = #schedule.on_event:get_events()
			callback_count = 0

			for _ = 1, 3 do
				schedule.get_expected_start_time("strict")
				schedule.get_failed_conditions("strict")
				schedule.get_expected_start_time("every")
				schedule.get_failed_conditions("every")
				schedule.get("strict"):get_expected_start_time()
				schedule.get("strict"):get_failed_conditions()
			end

			assert(deep_equal(snapshot, schedule.get_state()), "State should not change")
			assert(schedule.get("strict"):get_status() == "pending", "abort_on_fail should not trigger")
			assert(callback_count == 0, "No lifecycle callbacks")
			assert(#schedule.on_event:get_events() == queue_size, "No events in the global queue")
		end)
	end)
end
