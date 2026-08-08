return function()
	describe("Schedule Chaining", function()
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

		it("Should chain event after another event with default wait_online", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1)
				:duration(120)
				:save()

			time = 30
			schedule.update()
			assert(craft_1:get_status() == "pending")
			assert(craft_2:get_status() == "pending")

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")
			assert(craft_2:get_status() == "pending")

			time = 180
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "active", "Second event should start after first completes")
		end)

		it("Should chain event with wait_online false (default)", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = false })
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")

			time = 180
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "active", "Second event should start after first completes")

			time = 190
			schedule.update()
			assert(craft_2:get_time_left() == 110, "Second event should have 110 seconds left")
		end)


		it("Should calculate time when chained event starts after offline period", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id())
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")
			assert(craft_2:get_status() == "pending")

			time = 500
			schedule.update()
			assert(craft_1:get_status() == "completed")
			-- Both windows are over by now, the chained craft ran from 180 to 300 while offline
			assert(craft_2:get_status() == "completed", "Second event should be finished after the offline period")
			assert(craft_2:get_start_time() == 180, "Second event should start at first event end time")
		end)


		it("Should wait for update when wait_online is false and previous event completed offline", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = false })
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")

			time = 500
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "completed", "Second event should run through the offline period")
			assert(craft_2:get_start_time() == 180, "Second event should start at first event end time")
		end)


		it("Should handle chained events with different durations", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(60)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = true })
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")

			time = 120
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "active")

			time = 240
			schedule.update()
			assert(craft_2:get_status() == "completed")
		end)


		it("Should not spend the offline gap on the chained event with wait_online", function()
			local craft_1 = schedule.event()
				:category("craft")
				:duration(3600)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = true })
				:duration(3600)
				:save()

			schedule.update()
			assert(craft_1:get_status() == "active", "First craft should be active")

			-- Player is away for five hours, the first craft needed one
			time = 5 * 3600
			schedule.update()
			assert(craft_1:get_status() == "completed", "First craft should be completed")
			assert(craft_2:get_status() == "active", "Second craft should start when the player is back")
			assert(craft_2:get_start_time() == 5 * 3600, "Second craft should start now, not when the first ended")
			assert(craft_2:get_time_left() == 3600, "Second craft should still need a full hour, got " .. craft_2:get_time_left())
		end)


		it("Should spend the offline gap on the chained event without wait_online", function()
			local craft_1 = schedule.event()
				:category("craft")
				:duration(3600)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id())
				:duration(3600)
				:save()

			schedule.update()

			time = 5 * 3600
			schedule.update()
			assert(craft_1:get_status() == "completed", "First craft should be completed")
			assert(craft_2:get_start_time() == 3600, "Second craft should start when the first ended")
			assert(craft_2:get_time_left() == 0, "Second craft should already be done, got " .. craft_2:get_time_left())
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
				:after(craft_1:get_id(), { wait_online = true })
				:duration(60)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")

			time = 120
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "active")

			time = 180
			schedule.update()
			assert(craft_2:get_status() == "completed")

			time = 260
			schedule.update()
			assert(craft_1:get_status() == "active", "First event should cycle")
			assert(craft_2:get_status() == "pending", "Second event should wait for first again")
		end)


		it("Should handle chain interruption when first event is cancelled", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = true })
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")

			time = 90
			schedule.update()
			assert(craft_2:get_status() == "pending", "Second event should still be pending")
		end)


		it("Should handle multiple chained events", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(60)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = true })
				:duration(60)
				:save()

			local craft_3 = schedule.event()
				:category("craft")
				:after(craft_2:get_id(), { wait_online = true })
				:duration(60)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")
			assert(craft_2:get_status() == "pending")
			assert(craft_3:get_status() == "pending")

			time = 120
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "active")
			assert(craft_3:get_status() == "pending")

			time = 180
			schedule.update()
			assert(craft_2:get_status() == "completed")
			assert(craft_3:get_status() == "active")

			time = 240
			schedule.update()
			assert(craft_3:get_status() == "completed")
		end)


		it("Should handle chained events with wait_online true (immediate start)", function()
			local craft_1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local craft_2 = schedule.event()
				:category("craft")
				:after(craft_1:get_id(), { wait_online = true })
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_1:get_status() == "active")
			assert(craft_2:get_status() == "pending")

			time = 180
			schedule.update()
			assert(craft_1:get_status() == "completed")
			assert(craft_2:get_status() == "active", "Second event should start immediately when wait_online is true")
		end)
	end)
end

