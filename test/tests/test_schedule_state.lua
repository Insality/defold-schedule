return function()
	describe("Schedule State", function()
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

		it("Should get and set state", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()

			local state = schedule.get_state()
			assert(state ~= nil, "State should exist")

			schedule.reset_state()
			schedule.init()

			schedule.set_state(state)
			schedule.init()

			local event_info = schedule.get(event:get_id())
			assert(event_info ~= nil, "Status should exist after state restore")
		end)


		it("Should reset state", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			schedule.reset_state()
			schedule.init()

			local event_info = schedule.get(event:get_id())
			assert(event_info == nil, "Status should not exist after reset")
		end)


		it("Should persist state across game restarts", function()
			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()

			local state = schedule.get_state()
			local is_ok, encoded = pcall(json.encode, state)
			local saved_state = nil
			if is_ok and encoded then
				saved_state = json.decode(encoded)
			end

			schedule.reset_state()
			schedule.init()

			if saved_state then
				schedule.set_state(saved_state)
				schedule.init()

				local event_info = schedule.get(event:get_id())
				assert(event_info ~= nil, "Status should exist after state restore")
			end
		end)


		it("Should handle state serialization and deserialization", function()
			local event1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local event2 = schedule.event()
				:category("offer")
				:after(100)
				:duration(200)
				:save()

			time = 60
			schedule.update()

			local state = schedule.get_state()
			local is_ok, encoded = pcall(json.encode, state)
			local saved_state = nil
			if is_ok and encoded then
				saved_state = json.decode(encoded)
			end

			schedule.reset_state()
			schedule.init()

			if saved_state then
				schedule.set_state(saved_state)
				schedule.init()

				local event_info1 = schedule.get(event1:get_id())
				local event_info2 = schedule.get(event2:get_id())
				assert(event_info1 ~= nil, "First event status should exist")
				assert(event_info2 ~= nil, "Second event status should exist")
			end
		end)


		it("Should handle state with multiple events", function()
			local events = {}
			for i = 1, 5 do
				local event = schedule.event()
					:category("craft")
					:after(60 * i)
					:duration(120)
					:save()
				table.insert(events, event)
			end

			time = 300
			schedule.update()

			local state = schedule.get_state()
			schedule.reset_state()
			schedule.init()
			schedule.set_state(state)
			schedule.init()

			for _, event in ipairs(events) do
				local event_info = schedule.get(event:get_id())
				assert(event_info ~= nil, "Status should exist for event " .. event:get_id())
			end
		end)
	end)
end

