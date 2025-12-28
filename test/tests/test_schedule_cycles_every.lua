return function()
	describe("Schedule Cycles Every", function()
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

		it("Should cycle every N seconds", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 120 })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active", "Event should be active at first trigger")

			time = 61
			schedule.update()
			assert(event:get_status() == "completed", "Event should complete after duration")

			time = 180
			schedule.update()
			assert(event:get_status() == "active", "Event should cycle and be active again")
		end)


		it("Should cycle with anchor start", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100, anchor = "start" })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 90
			schedule.update()
			assert(event:get_status() == "completed")

			time = 160
			schedule.update()
			assert(event:get_status() == "active", "Should cycle from start anchor")
		end)


		it("Should cycle with anchor end", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100, anchor = "end" })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 90
			schedule.update()
			assert(event:get_status() == "completed")

			time = 190
			schedule.update()
			assert(event:get_status() == "active", "Should cycle from end anchor")
		end)


		it("Should skip missed cycles when skip_missed is true", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = true })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 1000
			schedule.update()
			assert(event:get_status() == "active" or event:get_status() == "completed", "Should skip to current cycle")
		end)


		it("Should catch up missed cycles when skip_missed is false", function()
			local trigger_count = 0
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = false })
				:catch_up(true)
				:save()

			schedule.on_event:subscribe(function(event_data)
				if event_data.id == event:get_id() then
					trigger_count = trigger_count + 1
				end
				return true
			end)

			time = 60
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			time = 1000
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed cycles")
		end)


		it("Should handle multiple cycles correctly", function()
			local event = schedule.event()
				:category("reward")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100 })
				:save()

			time = 60
			schedule.update()
			assert(event:get_status() == "active")

			time = 70
			schedule.update()
			assert(event:get_status() == "completed")

			time = 160
			schedule.update()
			assert(event:get_status() == "active", "Second cycle")

			time = 170
			schedule.update()
			assert(event:get_status() == "completed", "Second cycle completed")

			time = 260
			schedule.update()
			assert(event:get_status() == "active", "Third cycle")
		end)
	end)
end

