return function()
	describe("Schedule Events", function()
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

		it("Should subscribe to events", function()
			local event_received = false
			local received_event = nil

			schedule.on_event:subscribe(function(event)
				event_received = true
				received_event = event
				return true
			end)

			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(event_received, "Event should be received")
			assert(received_event ~= nil, "Event should be passed to subscriber")
			assert(received_event.id == event_id, "Event ID should match")
		end)


		it("Should filter events by category", function()
			local craft_count = 0
			local offer_count = 0

			schedule.on_event:subscribe(function(event)
				if event.category == "craft" then
					craft_count = craft_count + 1
					return true
				end
				if event.category == "offer" then
					offer_count = offer_count + 1
					return true
				end
				return false
			end)

			local craft_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			local offer_id = schedule.event()
				:category("offer")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(craft_count == 1, "Craft event should be received")
			assert(offer_count == 1, "Offer event should be received")
		end)


		it("Should handle event payload", function()
			local received_payload = nil

			schedule.on_event:subscribe(function(event)
				received_payload = event.payload
				return true
			end)

			local payload = { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 }
			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:payload(payload)
				:save()

			time = 60
			schedule.update()
			assert(received_payload ~= nil, "Payload should be received")
			assert(received_payload.building_id == "crafting_table", "Payload should contain building_id")
			assert(received_payload.item_id == "iron_shovel", "Payload should contain item_id")
		end)


		it("Should handle multiple subscribers", function()
			local subscriber1_called = false
			local subscriber2_called = false

			schedule.on_event:subscribe(function(event)
				subscriber1_called = true
				return true
			end)

			schedule.on_event:subscribe(function(event)
				subscriber2_called = true
				return true
			end)

			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(subscriber1_called, "First subscriber should be called")
			assert(subscriber2_called, "Second subscriber should be called")
		end)


		it("Should unsubscribe from events", function()
			local call_count = 0
			local subscription = schedule.on_event:subscribe(function(event)
				call_count = call_count + 1
				return true
			end)

			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(call_count == 1, "Subscriber should be called once")

			schedule.on_event:unsubscribe(subscription)

			local event_id2 = schedule.event()
				:category("craft")
				:after(120)
				:duration(120)
				:save()

			time = 120
			schedule.update()
			assert(call_count == 1, "Subscriber should not be called after unsubscribe")
		end)


		it("Should handle subscriber returning false", function()
			local subscriber1_called = false
			local subscriber2_called = false

			schedule.on_event:subscribe(function(event)
				subscriber1_called = true
				return false
			end)

			schedule.on_event:subscribe(function(event)
				subscriber2_called = true
				return true
			end)

			local event_id = schedule.event()
				:category("craft")
				:after(60)
				:duration(120)
				:save()

			time = 60
			schedule.update()
			assert(subscriber1_called, "First subscriber should be called")
			assert(subscriber2_called, "Second subscriber should still be called")
		end)
	end)
end

