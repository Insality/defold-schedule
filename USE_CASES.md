
# Use Cases

## Crafting Timers

```lua
local schedule = require("schedule.schedule")

--- 1 hour craft
local craft_id = schedule.event()
	:category("craft")
	:after(60 * 60)
	:payload( { building_id = "crafting_table", item_id = "iron_shovel", quantity = 1 } )
	:save()
```


## Crafting Timers Chaining


## Declare LiveOps Events

```lua
local schedule = require("schedule.schedule")

--- New year week
schedule.event()
	:category("liveops")
	:start_at("2026-01-01T00:00:00")
	:duration(7 * schedule.DAY)
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
	:save()
```


## Declare Daily Rewards

```lua
local schedule = require("schedule.schedule")

--- Daily rewards, trigger each day once, after 6:00 AM
schedule.event()
	:category("daily_reward")
```
