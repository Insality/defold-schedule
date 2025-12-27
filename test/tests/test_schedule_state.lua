return function()
	describe("Schedule State", function()
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

		it("Should get and set state", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			set_time(60)
			schedule.update()

			local state = schedule.get_state()
			assert(state ~= nil, "State should exist")

			schedule.reset_state()
			schedule.init()

			schedule.set_state(state)
			schedule.init()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist after state restore")
		end)


		it("Should reset state", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			schedule.reset_state()
			schedule.init()

			local status = schedule.get_status(event_id)
			assert(status == nil, "Status should not exist after reset")
		end)


		it("Should persist state across game restarts", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			set_time(60)
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

				local status = schedule.get_status(event_id)
				assert(status ~= nil, "Status should exist after state restore")
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

			set_time(60)
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

				local status1 = schedule.get_status(event1)
				local status2 = schedule.get_status(event2)
				assert(status1 ~= nil, "First event status should exist")
				assert(status2 ~= nil, "Second event status should exist")
			end
		end)


		it("Should handle state with multiple events", function()
			local event_ids = {}
			for i = 1, 5 do
				local event_id = schedule.event()
					:category("craft")
					:after(60 * i)
					:duration(120)
					:save()
				table.insert(event_ids, event_id)
			end

			set_time(300)
			schedule.update()

			local state = schedule.get_state()
			schedule.reset_state()
			schedule.init()
			schedule.set_state(state)
			schedule.init()

			for _, event_id in ipairs(event_ids) do
				local status = schedule.get_status(event_id)
				assert(status ~= nil, "Status should exist for event " .. event_id)
			end
		end)
	end)
end

