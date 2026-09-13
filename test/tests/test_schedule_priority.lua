return function()
	local function deep_copy_state(state)
		local serialized = sys.serialize(state)
		return sys.deserialize(serialized)
	end

	describe("Schedule Priority", function()
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

		it("Should start higher priority events first in the same update", function()
			local started = {}
			for _, event_id in ipairs({ "a_low", "b_high", "c_mid" }) do
				schedule.event(event_id)
					:after(60)
					:duration(60)
					:priority(event_id == "b_high" and 10 or (event_id == "c_mid" and 5 or 0))
					:on_start(function() table.insert(started, event_id) end)
					:save()
			end

			time = 60
			schedule.update()

			assert(#started == 3, "All three events should start, got " .. #started)
			assert(started[1] == "b_high", "Highest priority should start first, got " .. started[1])
			assert(started[2] == "c_mid", "Middle priority should start second, got " .. started[2])
			assert(started[3] == "a_low", "Lowest priority should start last, got " .. started[3])
		end)


		it("Should order events with the same priority by event id", function()
			local started = {}
			for _, event_id in ipairs({ "zzz", "aaa", "mmm" }) do
				schedule.event(event_id)
					:after(60)
					:on_start(function() table.insert(started, event_id) end)
					:save()
			end

			time = 60
			schedule.update()

			assert(started[1] == "aaa", "Should start by id, got " .. tostring(started[1]))
			assert(started[2] == "mmm", "Should start by id, got " .. tostring(started[2]))
			assert(started[3] == "zzz", "Should start by id, got " .. tostring(started[3]))
		end)


		it("Should let a condition see a higher priority event started in the same update", function()
			schedule.register_condition("no_active_in_category", function(data)
				return next(schedule.filter(data.category, "active")) == nil
			end)

			-- The gated event sorts before the offer by id, so only priority can save it
			schedule.event("a_gated_liveops")
				:category("liveops")
				:after(60)
				:duration(3 * schedule.HOUR)
				:condition("no_active_in_category", { category = "offer" })
				:save()

			schedule.event("b_offer")
				:category("offer")
				:after(60)
				:duration(schedule.HOUR)
				:priority(20)
				:save()

			time = 60
			schedule.update()

			assert(schedule.get("b_offer"):get_status() == "active",
				"Offer should start, got " .. schedule.get("b_offer"):get_status())
			assert(schedule.get("a_gated_liveops"):get_status() == "pending",
				"Gated event should wait, got " .. schedule.get("a_gated_liveops"):get_status())

			-- The offer window is over, the gate opens and the leftover window is joined
			time = 60 + schedule.HOUR
			schedule.update()
			assert(schedule.get("a_gated_liveops"):get_status() == "active",
				"Gated event should start once the offer is over, got " .. schedule.get("a_gated_liveops"):get_status())
		end)


		it("Should keep priority through save and restore", function()
			schedule.event("important"):after(60):priority(7):save()

			local saved_state = deep_copy_state(schedule.get_state())
			schedule.reset_state()
			schedule.set_state(saved_state)

			assert(schedule.get_event_state("important").priority == 7, "Priority should survive the restore")
		end)


		it("Should treat an unset priority as the default 10", function()
			local started = {}
			schedule.event("a_above"):after(60):priority(20):on_start(function() table.insert(started, "a_above") end):save()
			schedule.event("b_default"):after(60):on_start(function() table.insert(started, "b_default") end):save()
			schedule.event("c_below"):after(60):priority(5):on_start(function() table.insert(started, "c_below") end):save()

			time = 60
			schedule.update()

			assert(started[1] == "a_above", "20 should go first, got " .. tostring(started[1]))
			assert(started[2] == "b_default", "Unset should sit in the middle, got " .. tostring(started[2]))
			assert(started[3] == "c_below", "5 should go last, got " .. tostring(started[3]))

			-- The default is not written into the state, a save file keeps only deliberate priorities
			assert(schedule.get_event_state("b_default").priority == nil, "Default priority should not be stored")
		end)


		it("Should keep the declared priority on re-declare", function()
			schedule.event("with_priority"):after(60):priority(3):save()
			schedule.event("with_priority"):after(60):save()
			assert(schedule.get_event_state("with_priority").priority == 3, "Re-declare should keep the stored priority")
		end)


		it("Should pick up events added and removed between updates", function()
			local started = {}
			schedule.event("first"):after(60):priority(20):on_start(function() table.insert(started, "first") end):save()

			time = 60
			schedule.update()
			assert(#started == 1, "Only the declared event should start, got " .. #started)

			-- Both change the event set, so the cached update order has to be rebuilt
			schedule.remove("first")
			schedule.event("second"):after(60):on_start(function() table.insert(started, "second") end):save()

			time = 120
			schedule.update()
			assert(started[2] == "second", "A newly added event should be updated, got " .. tostring(started[2]))
			assert(schedule.get("first") == nil, "The removed event should stay removed")
		end)


		it("Should follow a priority changed by re-declaring the event", function()
			local started = {}
			schedule.event("a_first"):after(60):duration(60):on_start(function() table.insert(started, "a_first") end):save()
			schedule.event("b_second"):after(60):duration(60):on_start(function() table.insert(started, "b_second") end):save()

			-- Builds and caches the update order while both events sit at the default priority
			schedule.update()
			assert(#started == 0, "Nothing should start yet")

			-- Re-declaring is how a declared value is changed, and it rebuilds the order
			schedule.event("b_second"):priority(20):save()

			time = 60
			schedule.update()
			assert(started[1] == "b_second", "The raised priority should start first, got " .. tostring(started[1]))
			assert(started[2] == "a_first", "The default priority should start second, got " .. tostring(started[2]))
		end)


		it("Should survive an event removed from a callback of another event", function()
			schedule.event("a_remover")
				:after(60)
				:duration(schedule.HOUR)
				:priority(20)
				:on_start(function() schedule.remove("b_victim") end)
				:save()

			local is_victim_started = false
			schedule.event("b_victim")
				:after(60)
				:on_start(function() is_victim_started = true end)
				:save()

			time = 60
			schedule.update()

			assert(not is_victim_started, "The removed event should not start")
			assert(schedule.get("a_remover"):get_status() == "active", "The remover should be active")
		end)
	end)
end
