return function()
	describe("Schedule Basic", function()
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

		it("Should create event with after and duration", function()
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			assert(event_id ~= nil, "Event ID should be generated")

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
			assert(status.status == "pending", "Event should be pending initially")

			set_time(30)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "pending", "Event should still be pending")

			set_time(60)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should be active")

			set_time(180)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "completed", "Event should be completed")
		end)


		it("Should create event with start_at and end_at", function()
			local event_id = schedule.event()
				:category("offer")
				:start_at(100)
				:end_at(200)
				:save()

			set_time(50)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status.status == "pending", "Event should be pending before start_at")

			set_time(100)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should be active at start_at")

			set_time(150)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should still be active")

			set_time(200)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "completed", "Event should be completed at end_at")
		end)


		it("Should create event with infinity", function()
			local event_id = schedule.event()
				:category("liveops")
				:after(60)
				:infinity()
				:save()

			set_time(30)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status.status == "pending", "Event should be pending")

			set_time(60)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should be active")

			set_time(1000)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should still be active with infinity")
		end)


		it("Should handle event with payload", function()
			local payload = { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 }
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:payload(payload)
				:save()

			local status = schedule.get_status(event_id)
			assert(status.payload ~= nil, "Payload should exist")
			assert(status.payload.building_id == "crafting_table", "Payload should contain building_id")
			assert(status.payload.item_id == "iron_shovel", "Payload should contain item_id")
			assert(status.payload.quantity == 1, "Payload should contain quantity")
		end)


		it("Should handle event with category", function()
			local event_id = schedule.event()
				:category("daily_reward")
				:after(60)
				:duration(120)
				:save()

			local status = schedule.get_status(event_id)
			assert(status.category == "daily_reward", "Category should be set")
		end)


		it("Should handle ISO date string for start_at", function()
			local event_id = schedule.event()
				:category("liveops")
				:start_at("2026-01-01T00:00:00")
				:duration(86400)
				:save()

			local status = schedule.get_status(event_id)
			assert(status ~= nil, "Status should exist")
		end)


		it("Should handle multiple events simultaneously", function()
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

			set_time(50)
			schedule.update()
			assert(schedule.get_status(event1).status == "pending")
			assert(schedule.get_status(event2).status == "pending")

			set_time(80)
			schedule.update()
			assert(schedule.get_status(event1).status == "active")
			assert(schedule.get_status(event2).status == "pending")

			set_time(150)
			schedule.update()
			assert(schedule.get_status(event1).status == "completed")
			assert(schedule.get_status(event2).status == "active")
		end)
	end)
end

