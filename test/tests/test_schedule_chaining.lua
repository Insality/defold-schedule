return function()
	describe("Schedule Chaining", function()
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

		it("Should chain event after another event", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1, { wait_online = true })
				:duration(120)
				:save()

			set_time(30)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "pending")
			assert(schedule.get_status(craft_2).status == "pending")

			set_time(60)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active")
			assert(schedule.get_status(craft_2).status == "pending")

			set_time(180)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "completed")
			assert(schedule.get_status(craft_2).status == "active", "Second event should start after first completes")
		end)


		it("Should chain event with wait_online false", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1, { wait_online = false })
				:duration(120)
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active")

			set_time(180)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "completed")
			assert(schedule.get_status(craft_2).status == "active", "Second event should start after first completes")
		end)


		it("Should handle chained events with different durations", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(60)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1, { wait_online = true })
				:duration(120)
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active")

			set_time(120)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "completed")
			assert(schedule.get_status(craft_2).status == "active")

			set_time(240)
			schedule.update()
			assert(schedule.get_status(craft_2).status == "completed")
		end)


		it("Should handle chained events with cycles", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(60)
				:cycle("every", { seconds = 200 })
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1, { wait_online = true })
				:duration(60)
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active")

			set_time(120)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "completed")
			assert(schedule.get_status(craft_2).status == "active")

			set_time(180)
			schedule.update()
			assert(schedule.get_status(craft_2).status == "completed")

			set_time(260)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active", "First event should cycle")
			assert(schedule.get_status(craft_2).status == "pending", "Second event should wait for first again")
		end)


		it("Should handle chain interruption when first event is cancelled", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1, { wait_online = true })
				:duration(120)
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active")

			set_time(90)
			schedule.update()
			assert(schedule.get_status(craft_2).status == "pending", "Second event should still be pending")
		end)


		it("Should handle multiple chained events", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(60)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1, { wait_online = true })
				:duration(60)
				:save()

			local craft_3 = schedule.event()
				:category("craft")
				:after(craft_2, { wait_online = true })
				:duration(60)
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "active")
			assert(schedule.get_status(craft_2).status == "pending")
			assert(schedule.get_status(craft_3).status == "pending")

			set_time(120)
			schedule.update()
			assert(schedule.get_status(craft_1).status == "completed")
			assert(schedule.get_status(craft_2).status == "active")
			assert(schedule.get_status(craft_3).status == "pending")

			set_time(180)
			schedule.update()
			assert(schedule.get_status(craft_2).status == "completed")
			assert(schedule.get_status(craft_3).status == "active")

			set_time(240)
			schedule.update()
			assert(schedule.get_status(craft_3).status == "completed")
		end)
	end)
end

