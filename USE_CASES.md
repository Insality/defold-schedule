
# Use Cases

## Crafting Timers

```lua
local schedule = require("schedule.schedule")

--- 1 hour craft
local craft = schedule.event()
	:category("craft")
	:duration(60 * 60)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()
```


## Crafting Timers Chaining

```lua
local schedule = require("schedule.schedule")

local craft_1 = schedule.event()
	:category("craft")
	:duration(schedule.HOUR)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()

local craft_2 = schedule.event()
	:category("craft")
	:after(craft_1:get_id(), { wait_online = true })
	:duration(schedule.HOUR)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()
```


## Handle Events

The `callback_type` is one of `"start"`, `"enabled"`, `"disabled"`, `"end"` or `"fail"`.

Return `true` from a subscriber to mark the event as handled and remove it from the queue.
Return `nil` to leave it for other subscribers. Note that `return false` also counts as handled.

```lua
local schedule = require("schedule.schedule")

schedule.event()
	:category("craft")
	:after(60 * 60)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()

schedule.on_event:subscribe(function(event)
	if event.category ~= "craft" or event.callback_type ~= "end" then
		return nil -- Not ours, leave it in the queue
	end

	give_item(event.payload.item_id, event.payload.quantity)
	return true
end)
```


## Declare LiveOps Events

```lua
local schedule = require("schedule.schedule")

--- New year week
schedule.event()
	:category("liveops")
	:start_at("2026-01-01T00:00:00")
	:duration(7 * schedule.DAY)
	:cycle("every", { seconds = 4 * schedule.HOUR, anchor = "start", skip_missed = true })
	:catch_up(false) -- do not catch up if missed
	:payload({ event_id = "new_year" })
	:min_time(1 * schedule.DAY) -- do not start if not enough time left
	:save()
```


## Offers

```lua
local schedule = require("schedule.schedule")

schedule.event()
	:category("offer")
	:after(60) -- 1 minute after setup
	:duration(4 * schedule.HOUR) -- 4 hours duration
	:payload({ offer_id = "100_coins" })
	:save()
```


## Offers With Conditions

```lua
local schedule = require("schedule.schedule")

schedule.register_condition("has_token", function(data)
	return token.container("wallet"):is_enough(data.token_id, data.amount)
end)

schedule.event()
	:category("offer")
	:after(60) -- 1 minute after setup
	:duration(4 * schedule.HOUR) -- 4 hours duration
	:payload({ offer_id = "100_coins" })
	:condition("has_token", { token_id = "gems", amount = 100 })
	:condition("has_token", { token_id = "level", amount = 4 })
	:save()
```


## Declare Daily Rewards

```lua
local schedule = require("schedule.schedule")

--- Daily rewards, trigger each day once, starting 6 hours from now
--- catch_up(true) makes the player receive the rewards missed while offline,
--- skip_missed = true would grant only the most recent one instead
schedule.event("daily_reward")
	:category("daily_reward")
	:cycle("every", { seconds = schedule.DAY, anchor = "start" })
	:after(6 * schedule.HOUR) -- Start 6 hours from now (first occurrence)
	:duration(1) -- Instant reward
	:catch_up(true)
	:on_end(function(event_data)
		give_daily_reward()
	end)
	:save()
```


## Weekly Events

Weekly, monthly and yearly cycles automatically calculate the next occurrence from the current time when `start_at` is not provided. This makes it easy to schedule recurring events without specifying an exact start date.

All calendar times are UTC: `time = "14:00"` means 14:00 UTC, not the player's local time.

### Every Sunday (No start_at needed)

```lua
local schedule = require("schedule.schedule")

--- Weekly event every Sunday at midnight
--- Automatically starts on the next Sunday, no start_at required
schedule.event()
	:category("weekly_event")
	:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
	:duration(schedule.DAY)
	:payload({ event_type = "sunday_event" })
	:save()
```

### Every Sunday at Specific Time

```lua
local schedule = require("schedule.schedule")

--- Weekly event every Sunday at 14:00 (2 PM)
schedule.event()
	:category("weekly_event")
	:cycle("weekly", { weekdays = { "sun" }, time = "14:00", skip_missed = true })
	:duration(6 * schedule.HOUR) -- Active from 14:00 to 20:00
	:payload({ event_type = "sunday_afternoon" })
	:save()
```

### Multiple Days of Week

```lua
local schedule = require("schedule.schedule")

--- Weekend events on Saturday and Sunday
schedule.event()
	:category("weekend_event")
	:cycle("weekly", { weekdays = { "sat", "sun" }, time = "09:00", skip_missed = true })
	:duration(schedule.DAY)
	:payload({ event_type = "weekend" })
	:save()
```

### Weekly Event with start_at Anchor

```lua
local schedule = require("schedule.schedule")

--- Weekly event anchored to a specific date
schedule.event()
	:category("weekly_event")
	:start_at("2026-01-05T00:00:00") -- First Sunday of 2026
	:cycle("weekly", { weekdays = { "sun" }, time = "00:00", skip_missed = true })
	:duration(schedule.DAY)
	:payload({ event_type = "sunday_event" })
	:save()
```


## Handle lifecycle events

```lua
local schedule = require("schedule.schedule")

schedule.event("event_new_year")
	:category("liveops")
	:start_at("2026-01-01T00:00:00")
	:duration(7 * schedule.DAY)
	:catch_up(false) -- do not catch up if missed
	:payload({ event_id = "new_year" })
	:min_time(1 * schedule.DAY) -- do not start if not enough time left
	:on_start(function(event) -- Once per event activation
		print("Event started: " .. event.event_id)
	end)
	:on_enabled(function(event) -- When event is started or started at game start
		print("Event enabled: " .. event.event_id)
	end)
	:on_disabled(function(event) -- When event is disabled
		print("Event disabled: " .. event.event_id)
	end)
	:on_end(function(event) -- When event is ended
		print("Event ended: " .. event.event_id)
	end)
	:abort_on_fail() -- When event fails condition, set status to "aborted"
	:save()
```

## Using event ID

```lua
local schedule = require("schedule.schedule")

local event = schedule.event("event_first_week")
	:category("liveops")
	:duration(7 * schedule.DAY)
	:save()

local event_id = event:get_id()
```


## Save and Restore

```lua
local saver = require("saver.saver")
local schedule = require("schedule.schedule")

function init(self)
	saver.init()
	saver.bind_save_state("schedule", schedule.get_state())

	-- Declare events after the state is restored. Timings are kept, callbacks are re-attached
	declare_game_events()

	timer.delay(1, true, function()
		schedule.update()
	end)
end
```


## Clean Up Finished Events

Completed events stay in the state until they are removed.

```lua
local schedule = require("schedule.schedule")

-- Drop a single event
schedule.remove("craft_sword")

-- Drop every finished craft, for example before saving
schedule.clear("craft", "completed")
```


## Use Server Time

The device clock can be changed by the player. Drive the schedule from your server time
to make LiveOps events and offers tamper resistant.

```lua
local schedule = require("schedule.schedule")

schedule.set_time_function(function()
	return backend.get_server_time() -- Unix seconds
end)
```


## Show a Craft Timer

```lua
local schedule = require("schedule.schedule")

local function update_craft_ui(self)
	local craft = schedule.get("craft_sword")
	if not craft then
		return
	end

	if craft:is_active() then
		self.progress:set_to(craft:get_progress())
		self.timer_text:set_text(format_time(craft:get_time_left()))
	end
end
```
