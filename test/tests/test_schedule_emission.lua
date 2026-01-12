return function()
	describe("Schedule Emission", function()
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

		it("Should prevent duplicate event emissions", function()
			local emission_count = 0

			schedule.on_event:subscribe(function(event)
				if event.callback_type == "enabled" then
					emission_count = emission_count + 1
				end
				return true
			end)

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(emission_count == 1, "Event should be emitted once")

			schedule.update()
			assert(emission_count == 1, "Event should not be emitted again on same update cycle")

			time = 100
			schedule.update()
			assert(emission_count == 1, "Event should not be emitted again while still active")
		end)


		it("Should emit events on each cycle activation", function()
			local emission_count = 0

			schedule.on_event:subscribe(function(event)
				if event.callback_type == "enabled" then
					emission_count = emission_count + 1
				end
				return true
			end)

			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100 })
				:save()

			time = 60
			schedule.update()
			assert(emission_count == 1, "First cycle should emit")

			time = 70
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete")

			time = 160
			schedule.update()
			assert(emission_count == 2, "Second cycle should emit when event becomes active again")
		end)


		it("Should emit events when reactivated after completion", function()
			local emission_count = 0

			schedule.on_event:subscribe(function(event)
				if event.callback_type == "enabled" then
					emission_count = emission_count + 1
				end
				return true
			end)

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100 })
				:save()

			time = 60
			schedule.update()
			assert(emission_count == 1, "Event should be emitted when becoming active")

			time = 70
			schedule.update()
			assert(event:get_status() == "completed", "Event should be completed")
			assert(emission_count == 1, "Emission count should not increase on completion")

			time = 160
			schedule.update()
			assert(event:get_status() == "active", "Event should cycle and become active again")
			assert(emission_count == 2, "Event should emit again when reactivated with new start_time (new cycle)")
		end)


		it("Should emit multiple events when they become active", function()
			local emissions = {}

			schedule.on_event:subscribe(function(event)
				if event.callback_type == "enabled" then
					table.insert(emissions, {
						event_id = event.event_id,
						start_time = event.start_time
					})
				end
				return true
			end)

			local event1 = schedule.event()
				:category("craft")
				:after(60)
				:duration(10)
				:save()

			local event2 = schedule.event()
				:category("craft")
				:after(60)
				:duration(10)
				:save()

			time = 60
			schedule.update()
			assert(#emissions == 2, "Both events should emit")
			assert(emissions[1].event_id ~= emissions[2].event_id, "Different events should have different IDs")
		end)


		it("Should emit events after processor completes", function()
			local processor_order = {}
			local emission_order = {}

			schedule.on_event:subscribe(function(event)
				if event.callback_type == "enabled" then
					table.insert(emission_order, "emission")
				end
				return true
			end)

			local event = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:on_start(function()
					table.insert(processor_order, "on_start")
				end)
				:save()

			time = 60
			schedule.update()

			assert(processor_order[1] == "on_start", "Processor callbacks should run first")
			assert(emission_order[1] == "emission", "Emission should happen after processor")
		end)
	end)
end

