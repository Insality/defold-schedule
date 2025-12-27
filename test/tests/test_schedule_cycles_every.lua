return function()
	describe("Schedule Cycles Every", function()
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

		it("Should cycle every N seconds", function()
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 120 })
				:save()

			set_time(60)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should be active at first trigger")

			set_time(61)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "completed", "Event should complete after duration")

			set_time(180)
			schedule.update()
			status = schedule.get_status(event_id)
			assert(status.status == "active", "Event should cycle and be active again")
		end)


		it("Should cycle with anchor start", function()
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100, anchor = "start" })
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active")

			set_time(90)
			schedule.update()
			assert(schedule.get_status(event_id).status == "completed")

			set_time(160)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active", "Should cycle from start anchor")
		end)


		it("Should cycle with anchor end", function()
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(30)
				:cycle("every", { seconds = 100, anchor = "end" })
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active")

			set_time(90)
			schedule.update()
			assert(schedule.get_status(event_id).status == "completed")

			set_time(190)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active", "Should cycle from end anchor")
		end)


		it("Should skip missed cycles when skip_missed is true", function()
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = true })
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active")

			set_time(1000)
			schedule.update()
			local status = schedule.get_status(event_id)
			assert(status.status == "active" or status.status == "completed", "Should skip to current cycle")
		end)


		it("Should catch up missed cycles when skip_missed is false", function()
			local trigger_count = 0
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(1)
				:cycle("every", { seconds = 100, skip_missed = false })
				:catch_up(true)
				:save()

			schedule.on_event:subscribe(function(event)
				if event.id == event_id then
					trigger_count = trigger_count + 1
				end
				return true
			end)

			set_time(60)
			schedule.update()
			assert(trigger_count == 1, "First trigger")

			set_time(1000)
			schedule.update()
			assert(trigger_count > 1, "Should catch up missed cycles")
		end)


		it("Should handle multiple cycles correctly", function()
			local event_id = schedule.event()
				:category("reward")
				:after(60)
				:duration(10)
				:cycle("every", { seconds = 100 })
				:save()

			set_time(60)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active")

			set_time(70)
			schedule.update()
			assert(schedule.get_status(event_id).status == "completed")

			set_time(160)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active", "Second cycle")

			set_time(170)
			schedule.update()
			assert(schedule.get_status(event_id).status == "completed", "Second cycle completed")

			set_time(260)
			schedule.update()
			assert(schedule.get_status(event_id).status == "active", "Third cycle")
		end)
	end)
end

