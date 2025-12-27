
# Use Cases

## Crafting Timers

```lua
local schedule = require("schedule.schedule")

--- 1 hour craft
local craft_id = schedule.event()
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
	:after(craft_1, { wait_online = true })
	:duration(schedule.HOUR)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()
```


## Handle Events

```lua
local schedule = require("schedule.schedule")

schedule.event()
	:category("craft")
	:after(60 * 60)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()

schedule.on_event:subscribe(function(event)
	if event.category ~= "craft" then
		return false
	end

	-- Handle event
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


## OFfers With Conditions

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

--- Daily rewards, trigger each day once, after 6:00 AM
schedule.event()
	:category("daily_reward")
	:cycle("every", { seconds = schedule.DAY, anchor = "start", skip_missed = true })
	:after(6 * schedule.HOUR) -- Start 6 hours from now (first occurrence)
	:duration(1) -- Instant reward
	:save()
```


## Weekly Events

Weekly cycles automatically calculate the next occurrence from the current time when `start_at` is not provided. This makes it easy to schedule recurring weekly events without specifying an exact start date.

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

schedule.event()
	:category("liveops")
	:id("event_new_year") -- Required for persistent event to set handlers for the same event
	:start_at("2026-01-01T00:00:00")
	:duration(7 * schedule.DAY)
	:catch_up(false) -- do not catch up if missed
	:payload({ event_id = "new_year" })
	:min_time(1 * schedule.DAY) -- do not start if not enough time left
	:on_start(function(event) -- Once per event activation
		print("Event started: " .. event.id)
	end)
	:on_enabled(function(event) -- When event is started or started at game start
		print("Event enabled: " .. event.id)
	end)
	:on_disabled(function(event) -- When event is disabled
		print("Event disabled: " .. event.id)
	end)
	:on_end(function(event) -- When event is ended
		print("Event ended: " .. event.id)
	end)
	:on_fail(function(event) -- When event fails condition
		print("Event failed: " .. event.id)
	end)
	:save()
```

## Using event ID

```lua
local schedule = require("schedule.schedule")

local event_id = schedule.event()
	:category("liveops")
	:id("event_first_week") -- Will find the stored event with this ID to keep event data
	:duration(7 * schedule.DAY)
	:save()
```
