
# Use Cases

- [Two ways to use the schedule](#two-ways-to-use-the-schedule)
- [Pull style](#pull-style)
	- [Crafting timer](#crafting-timer)
	- [A building with a craft queue](#a-building-with-a-craft-queue)
	- [Cooldowns](#cooldowns)
	- [Energy regeneration](#energy-regeneration)
- [Push style](#push-style)
	- [LiveOps event window](#liveops-event-window)
	- [Daily rewards](#daily-rewards)
	- [Weekend event](#weekend-event)
	- [Limited time offer with conditions](#limited-time-offer-with-conditions)
	- [One global handler](#one-global-handler)
- [Chaining events](#chaining-events)
- [Save and restore](#save-and-restore)
- [Server time](#server-time)
- [Cleaning up](#cleaning-up)
- [Things to keep in mind](#things-to-keep-in-mind)


## Two ways to use the schedule

There are two ways to work with an event, and most games use both.

**Pull** - you keep the event id and ask the schedule about it when you need to.
**Push** - you attach callbacks (or subscribe to `schedule.on_event`) and the schedule calls you.

|                          | Pull                                          | Push                                  |
| ------------------------ | --------------------------------------------- | ------------------------------------- |
| Good for                 | crafting, cooldowns, anything created in game  | LiveOps, daily rewards, global events |
| Event id                 | generated, you store it in your own data       | a fixed id written in code            |
| Re-declare on game start | not needed                                     | needed, to attach the callbacks again |
| Who cleans up            | you, with `schedule.remove()`                  | usually nobody, the event repeats     |

Rule of thumb: if the event is created by the player, use pull. If the event is part of your game
design and always exists, use push.

Both styles need `schedule.update()` running, it is what moves events between statuses:

```lua
timer.delay(1, true, function()
	schedule.update()
end)
```


## Pull style

### Crafting timer

Create the event, keep its id, ask for status and time when you draw the UI.

```lua
local schedule = require("schedule.schedule")

function start_craft(building, item_id, duration)
	local event = schedule.event()
		:category("craft")
		:duration(duration)
		:payload({ item = item_id })
		:save()

	building.craft_id = event:get_id() -- Store it with your building data
end


function update_craft_ui(self, building)
	local craft = building.craft_id and schedule.get(building.craft_id)
	if not craft then
		return self.panel:set_empty()
	end

	if craft:is_active() then
		self.progress:set_to(craft:get_progress())
		self.timer_text:set_text(format_time(craft:get_time_left()))
	end

	self.claim_button:set_enabled(craft:get_status() == "completed")
end


function claim_craft(building)
	local craft = building.craft_id and schedule.get(building.craft_id)
	if not craft or craft:get_status() ~= "completed" then
		return false
	end

	give_item(craft:get_payload().item)
	schedule.remove(building.craft_id) -- Otherwise it stays in the save file
	building.craft_id = nil
	return true
end
```

Events created without an id get a generated one (`schedule_1`, `schedule_2`, ...). The counter is
part of the state, so ids stay unique across sessions.

Offline works out of the box: a craft that finished while the game was closed is `completed` on the
first `update()` after launch, no configuration needed.


### A building with a craft queue

Keep the queue in your own data and let the schedule track only the craft that is running. One event
per building keeps the save file small and the queue easy to reorder or cancel.

```lua
local schedule = require("schedule.schedule")

function update_building(building)
	if building.craft_id then
		if schedule.get(building.craft_id):get_status() == "completed" then
			claim_craft(building)
		end
		return
	end

	local next_craft = table.remove(building.queue, 1)
	if next_craft then
		start_craft(building, next_craft.item, next_craft.duration)
	end
end
```

You can also chain the whole queue with [`:after()`](#chaining-events), but then the events depend on
each other and you can not remove one until the chain is done.


### Cooldowns

A cooldown is an event that is active while the cooldown lasts.

```lua
local schedule = require("schedule.schedule")

function start_cooldown(cooldown_id, duration)
	schedule.event(cooldown_id):category("cooldown"):duration(duration):save()
end


function is_on_cooldown(cooldown_id)
	local cooldown = schedule.get(cooldown_id)
	return cooldown ~= nil and cooldown:is_active()
end


function get_cooldown_left(cooldown_id)
	local cooldown = schedule.get(cooldown_id)
	return cooldown and cooldown:get_time_left() or 0
end
```

```lua
start_cooldown("free_chest", 4 * schedule.HOUR)

if is_on_cooldown("free_chest") then
	print("Ready in " .. get_cooldown_left("free_chest") .. " seconds")
end
```


### Energy regeneration

A short repeating event, one unit of energy per cycle. `catch_up(true)` gives the player the energy
that regenerated while the game was closed, `max_catches` caps how much a single update may grant.

```lua
local schedule = require("schedule.schedule")

schedule.event("energy_regen")
	:category("resource")
	:cycle("every", { seconds = 5 * schedule.MINUTE, max_catches = 60 })
	:duration(1)
	:catch_up(true)
	:on_end(function()
		add_energy(1)
	end)
	:save()
```

This one mixes both styles: a fixed id and a callback, so declare it on every game start.


## Push style

### LiveOps event window

A fixed window in the calendar. `on_enabled` and `on_disabled` are the pair that toggles content:
they also fire when the game starts inside an active window, so the UI is always in sync.

```lua
local schedule = require("schedule.schedule")

schedule.event("new_year")
	:category("liveops")
	:start_at("2026-01-01T00:00:00") -- UTC
	:end_at("2026-01-08T00:00:00")
	:on_enabled(function() enable_new_year_content() end)
	:on_disabled(function() disable_new_year_content() end)
	:save()
```

Query it anywhere for the UI:

```lua
local event = schedule.get("new_year")
if event:is_active() then
	self.banner:set_text(format_time(event:get_time_left()) .. " left")
else
	self.banner:set_text("Starts in " .. format_time(event:get_time_to_start()))
end
```


### Daily rewards

One reward per day, starting six hours from now. With `catch_up(true)` every day the player missed
is granted on return, with `skip_missed = true` only the most recent one is.

```lua
local schedule = require("schedule.schedule")

schedule.event("daily_reward")
	:category("daily_reward")
	:cycle("every", { seconds = schedule.DAY })
	:after(6 * schedule.HOUR)
	:duration(1) -- Instant reward
	:catch_up(true)
	:on_end(function()
		give_daily_reward()
	end)
	:save()
```


### Weekend event

Calendar cycles find their next occurrence on their own, no `start_at` needed. A player who opens
the game in the middle of the window sees it as active.

```lua
local schedule = require("schedule.schedule")

schedule.event("weekend_event")
	:category("liveops")
	:cycle("weekly", { weekdays = { "sat" }, time = "00:00" }) -- UTC
	:duration(2 * schedule.DAY)
	:on_enabled(function() enable_weekend_bonus() end)
	:on_disabled(function() disable_weekend_bonus() end)
	:save()
```

`monthly` and `yearly` work the same way:

```lua
	:cycle("monthly", { day = 1, time = "12:00" })
	:cycle("yearly", { month = 12, day = 25, time = "00:00" })
```


### Limited time offer with conditions

Conditions are checked right before the event starts. Without `abort_on_fail()` the event keeps
waiting and starts as soon as the condition passes.

```lua
local schedule = require("schedule.schedule")

schedule.register_condition("min_level", function(data)
	return get_player_level() >= data.level
end)

schedule.event("starter_offer")
	:category("offer")
	:after(5 * schedule.MINUTE)
	:duration(4 * schedule.HOUR)
	:condition("min_level", { level = 5 })
	:payload({ offer_id = "starter_pack" })
	:on_start(function(event) show_offer(event.payload.offer_id) end)
	:on_end(function(event) hide_offer(event.payload.offer_id) end)
	:save()
```

Add `:abort_on_fail()` when a missed condition means the offer is gone for good. The event becomes
`aborted`, `on_fail` is called once, and the schedule never retries it.

Use `:min_time()` to avoid starting something that is about to expire:

```lua
schedule.event("season_sale")
	:end_at("2026-03-01T00:00:00")
	:min_time(schedule.DAY) -- Do not show a sale that lasts less than a day
	:save()
```


### One global handler

Instead of per event callbacks you can handle everything in one place. Useful for analytics,
logging, or a single content router.

```lua
local schedule = require("schedule.schedule")

schedule.on_event:subscribe(function(event)
	if event.category ~= "liveops" then
		return nil -- Not ours, leave it for other subscribers
	end

	if event.callback_type == "enabled" then
		enable_content(event.event_id)
	elseif event.callback_type == "disabled" then
		disable_content(event.event_id)
	end

	return true -- Handled, remove it from the queue
end)
```

`callback_type` is one of `"start"`, `"enabled"`, `"disabled"`, `"end"`, `"fail"`.
Unhandled events wait in the queue (the last 128 are kept), so a UI that subscribes later still
catches up. Return `nil` when the event is not yours, note that returning `false` counts as handled.


## Chaining events

An event can start when another one completes.

```lua
local schedule = require("schedule.schedule")

local craft_1 = schedule.event():category("craft"):duration(schedule.HOUR):save()

local craft_2 = schedule.event()
	:category("craft")
	:after(craft_1:get_id(), { wait_online = true })
	:duration(schedule.HOUR)
	:save()
```

`wait_online = true` makes the second craft start counting when the player is back, so an offline
gap is not spent on it. Without the option the second craft starts the moment the first one ended,
which means it can already be finished when the player returns.

Two things to know about chains:

- The parent has to stay in the state. Removing it while the child is still `pending` leaves the
  child waiting forever.
- A chained event has no `start_time` until its parent completes, so `get_time_to_start()` returns
  `0` for it. Sum up the durations yourself to show an ETA for a queue.


## Save and restore

The whole schedule is one serializable table. Restore it **before** declaring your events:

```lua
local saver = require("saver.saver")
local schedule = require("schedule.schedule")

function init(self)
	saver.init()
	saver.bind_save_state("schedule", schedule.get_state())

	declare_game_events() -- Push style events with their callbacks

	timer.delay(1, true, function()
		schedule.update()
	end)
end
```

Callbacks are functions, so they can not be saved. Declaring your push style events on every game
start is the intended flow: stored timings, status and cycle counters are kept, only the callbacks
are attached again. Pull style events need nothing, their ids live in your own data.


## Server time

The device clock can be changed by the player. Drive the schedule from your backend to make LiveOps
events, offers and crafts tamper resistant.

```lua
local schedule = require("schedule.schedule")

schedule.set_time_function(function()
	return backend.get_server_time() -- Unix seconds
end)
```


## Cleaning up

Completed events stay in the state until they are removed.

```lua
schedule.remove("craft_sword") -- A single event

schedule.clear("craft", "completed") -- Every finished craft

schedule.clear() -- Everything
```


## Things to keep in mind

- **Call `update()`.** Statuses only change there. Once per second is plenty, the schedule works on
  absolute time and does not need frequent updates.
- **All times are UTC.** `"2026-01-01T00:00:00"` and `time = "14:00"` are UTC, there is no local time
  zone conversion.
- **`catch_up` only matters for cycles.** A single event that ran out while the game was closed is
  always completed on the next update. Default: `false` for events with a duration, `true` without.
- **`cancelled` and `aborted` are final.** The update loop never revives them, call `event:start()`
  to run such an event anyway.
- **A new event is `pending`** until the first `update()`, which is where conditions and `min_time`
  are checked.
