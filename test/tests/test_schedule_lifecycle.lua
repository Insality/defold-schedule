return function()
	describe("Schedule Lifecycle", function()
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

		it("Should call on_start callback", function()
			local start_called = false
			local start_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function(event_data)
					start_called = true
					start_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_called, "on_start should be called")
			assert(start_event ~= nil, "Event should be passed to callback")
			assert(start_event.id == event:get_id(), "Event ID should match")
		end)


		it("Should call on_enabled callback", function()
			local enabled_called = false
			local enabled_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_enabled(function(event_data)
					enabled_called = true
					enabled_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(enabled_called, "on_enabled should be called")
			assert(enabled_event ~= nil, "Event should be passed to callback")
		end)


		it("Should call on_disabled callback", function()
			local disabled_called = false
			local disabled_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_disabled(function(event_data)
					disabled_called = true
					disabled_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(not disabled_called, "on_disabled should not be called yet")

			time = 180
			schedule.update()
			assert(disabled_called, "on_disabled should be called when event ends")
			assert(disabled_event ~= nil, "Event should be passed to callback")
		end)


		it("Should call on_end callback", function()
			local end_called = false
			local end_event = nil

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_end(function(event_data)
					end_called = true
					end_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(not end_called, "on_end should not be called yet")

			time = 180
			schedule.update()
			assert(end_called, "on_end should be called when event ends")
			assert(end_event ~= nil, "Event should be passed to callback")
		end)


		it("Should call on_fail callback", function()
			local fail_called = false
			local fail_event = nil

			schedule.register_condition("always_false", function(data)
				return false
			end)

			local event = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:condition("always_false", {})
				:on_fail(function(event_data)
					fail_called = true
					fail_event = event_data
				end)
				:save()

			time = 60
			schedule.update()
			assert(fail_called, "on_fail should be called when condition fails")
			assert(fail_event ~= nil, "Event should be passed to callback")
		end)


		it("Should call callbacks in correct order", function()
			local callback_order = {}

			local event = schedule.event()
				:category("liveops")
				:after(60)
				:duration(120)
				:on_start(function(event_data)
					table.insert(callback_order, "start")
				end)
				:on_enabled(function(event_data)
					table.insert(callback_order, "enabled")
				end)
				:on_end(function(event_data)
					table.insert(callback_order, "end")
				end)
				:on_disabled(function(event_data)
					table.insert(callback_order, "disabled")
				end)
				:save()

			time = 60
			schedule.update()
			assert(callback_order[1] == "start" or callback_order[1] == "enabled", "Start or enabled should be called first")
			assert(callback_order[2] == "start" or callback_order[2] == "enabled", "Start or enabled should be called second")

			time = 180
			schedule.update()
			assert(callback_order[3] == "end" or callback_order[3] == "disabled", "End or disabled should be called third")
			assert(callback_order[4] == "end" or callback_order[4] == "disabled", "End or disabled should be called fourth")
		end)


		it("Should call callbacks with persistent events using id", function()
			local start_called = false
			local event_id = "persistent_event"

			schedule.event()
				:category("liveops")
				:id(event_id)
				:after(60)
				:duration(120)
				:on_start(function(event)
					start_called = true
				end)
				:save()

			time = 60
			schedule.update()
			assert(start_called, "on_start should be called for persistent event")

			schedule.reset_state()
			schedule.init()

			schedule.event()
				:category("liveops")
				:id(event_id)
				:after(60)
				:duration(120)
				:on_start(function(event)
					start_called = true
				end)
				:save()

			time = 120
			schedule.update()
			assert(start_called, "on_start should be called for same persistent event")
		end)
	end)
end

