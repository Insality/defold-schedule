return function()
	describe("Schedule Emission", function()
		local schedule ---@type schedule
		local schedule_time = require("schedule.internal.schedule_time")
		local time = 0

		before(function()
			schedule = require("schedule.schedule")
			schedule_time.set_time_function = function() return time end
			schedule.reset_state()
			time = 0
		end)

		it("Should prevent duplicate event emissions", function()
			local emission_count = 0

			schedule.on_event:subscribe(function(event)
				emission_count = emission_count + 1
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


		it("Should emit events with unique emit keys based on cycle_count", function()
			local emission_count = 0

			schedule.on_event:subscribe(function(event)
				emission_count = emission_count + 1
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
			assert(emission_count == 2, "Second cycle should emit with new cycle_count")
		end)


		it("Should clear emit keys when event status changes away from active", function()
			local emission_count = 0

			schedule.on_event:subscribe(function(event)
				emission_count = emission_count + 1
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


		it("Should use emit key with event_id, start_time, and cycle_count", function()
			local emissions = {}

			schedule.on_event:subscribe(function(event)
				table.insert(emissions, {
					id = event.id,
					start_time = event.start_time,
					cycle_count = event.cycle_count
				})
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
			assert(emissions[1].id ~= emissions[2].id, "Different events should have different IDs")
		end)


		it("Should emit events after processor completes", function()
			local processor_order = {}
			local emission_order = {}

			schedule.on_event:subscribe(function(event)
				table.insert(emission_order, "emission")
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

