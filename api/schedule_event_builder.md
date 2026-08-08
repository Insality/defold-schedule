# schedule.event_builder API

> at /schedule/internal/schedule_event_builder.lua

## Functions

- [category](#category)
- [after](#after)
- [start_at](#start_at)
- [end_at](#end_at)
- [duration](#duration)
- [infinity](#infinity)
- [cycle](#cycle)
- [condition](#condition)
- [payload](#payload)
- [catch_up](#catch_up)
- [min_time](#min_time)
- [on_start](#on_start)
- [on_enabled](#on_enabled)
- [on_disabled](#on_disabled)
- [on_end](#on_end)
- [on_fail](#on_fail)
- [abort_on_fail](#abort_on_fail)
- [save](#save)
## Fields

- [config](#config)



### category

---
```lua
event_builder:category(category)
```

Set the event category for grouping and filtering. Enables filtering with `schedule.filter()`.
Use consistent lowercase names (e.g., "craft", "offer", "liveops", "cooldown").

- **Parameters:**
	- `category` *(string)*: Category name

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### after

---
```lua
event_builder:after(after, [options])
```

Set event to start after a relative delay or after another event completes (event chaining).
Use for relative timing or sequential events. Use `start_at()` for absolute calendar-based timing.
Set `wait_online = true` in options to start counting when the player is back online, so an offline gap
between the two events is not spent by this one. Without it the event starts right when the parent ended,
which means it can already be finished when the player returns.

- **Parameters:**
	- `after` *(string|number|schedule.event)*: Seconds to wait (number) or event ID to chain after (string)
	- `[options]` *(table|nil)*: Options table with `wait_online` (boolean) for chaining behavior

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### start_at

---
```lua
event_builder:start_at(start_at)
```

Set event to start at an absolute time (calendar-based scheduling). Use for LiveOps events or scheduled promotions.
ISO date strings (e.g., "2026-01-01T00:00:00") are more readable; use timestamps for programmatic calculation.

- **Parameters:**
	- `start_at` *(string|number)*: Unix timestamp (seconds) or ISO date string (YYYY-MM-DDTHH:MM:SS)

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### end_at

---
```lua
event_builder:end_at(end_at)
```

Set event to end at an absolute time (calendar-based end date). Use for fixed-date events like LiveOps.
Use `duration()` for relative durations calculated from start time.

- **Parameters:**
	- `end_at` *(string|number)*: Unix timestamp (seconds) or ISO date string (YYYY-MM-DDTHH:MM:SS)

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### duration

---
```lua
event_builder:duration(duration)
```

Set the event duration. Use for crafting timers, cooldowns, temporary buffs, or any relative-duration event.
End time is calculated as start_time + duration. For recurring events, each cycle uses the same duration.

- **Parameters:**
	- `duration` *(number)*: Duration in seconds (use `schedule.HOUR`, `schedule.DAY`, etc. for clarity)

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### infinity

---
```lua
event_builder:infinity()
```

Set event to never end automatically (runs until manually cancelled). Use for permanent buffs,
continuous effects, or events that end based on game state rather than time.

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### cycle

---
```lua
event_builder:cycle(cycle_type, options)
```

Set the event to repeat on a cycle. Types: `"every"` (interval-based), `"weekly"` (calendar-based),
`"monthly"`, `"yearly"`. Set `skip_missed = true` for LiveOps (skip missed cycles), `false` for
daily rewards (catch-up). `anchor = "start"` (default) or `"end"` (gaps between cycles).
`max_catches` limits catch-up cycles during offline time.
```lua
cycle_type:
    | "every"
    | "weekly"
    | "monthly"
    | "yearly"
```

- **Parameters:**
	- `cycle_type` *("every"|"monthly"|"weekly"|"yearly")*: Type of cycle repetition
	- `options` *(table)*: Cycle options: `seconds` (for "every"), `weekdays`, `day`, `month`, `time`, `anchor`, `skip_missed`, `max_catches`

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### condition

---
```lua
event_builder:condition(name, [data])
```

Add a condition that must pass for the event to activate. Register evaluator with `schedule.register_condition()` first.
Multiple conditions use AND logic - all must pass. If any fails and `abort_on_fail()` is set, event status becomes "aborted" and will not retry.

- **Parameters:**
	- `name` *(string)*: Condition name (must be registered via `schedule.register_condition()`)
	- `[data]` *(any)*: Data passed to the condition evaluator function

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### payload

---
```lua
event_builder:payload([payload])
```

Set custom data payload passed to event handlers and callbacks. Included in all event notifications.
Store lightweight data (IDs, configuration objects). Avoid large objects or functions.

- **Parameters:**
	- `[payload]` *(any)*: Custom data object to attach to the event

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### catch_up

---
```lua
event_builder:catch_up(catch_up)
```

Set whether the event should catch up on missed time when the game resumes after being offline.
Enable for offline progression (crafting, daily rewards). Disable for LiveOps or time-sensitive events.
Events with a duration (or an `end_at`) default to `false`, events without one default to `true`.

- **Parameters:**
	- `catch_up` *(boolean)*: true to enable offline catch-up, false to disable

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### min_time

---
```lua
event_builder:min_time(min_time)
```

Set the minimum time remaining required for the event to start. If less time remains, the event is cancelled.
Use for LiveOps events or limited-time offers to prevent wasted activations.

- **Parameters:**
	- `min_time` *(number)*: Minimum seconds remaining required to start (use `schedule.DAY`, etc.)

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### on_start

---
```lua
event_builder:on_start(callback)
```

Set callback called once when the event activates. Use for one-time activation logic (notifications, achievements).
Called once per activation cycle. Use `on_enabled` for state changes that should happen during catch-up.

- **Parameters:**
	- `callback` *(function)*: Callback receives event data: `{id, category, payload, status, start_time, end_time}`

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### on_enabled

---
```lua
event_builder:on_enabled(callback)
```

Set callback called whenever the event becomes active, including during offline catch-up.
Use for UI updates, state changes, or effects that should apply whenever the event is active.
Use `on_start` for one-time activation actions.

- **Parameters:**
	- `callback` *(function)*: Callback receives event data: `{id, category, payload, status, start_time, end_time}`

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### on_disabled

---
```lua
event_builder:on_disabled(callback)
```

Set callback called when the event becomes inactive. Use for cleanup, UI updates, or state changes.
Paired with `on_enabled` to manage active state. Use to toggle UI elements or enable/disable features.

- **Parameters:**
	- `callback` *(function)*: Callback receives event data: `{id, category, payload, status, start_time, end_time}`

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### on_end

---
```lua
event_builder:on_end(callback)
```

Set callback called when the event completes naturally. Use for completion rewards, notifications, or achievements.
Called when duration expires or end time is reached. Use `on_disabled` for general cleanup on any deactivation.

- **Parameters:**
	- `callback` *(function)*: Callback receives event data: `{id, category, payload, status, start_time, end_time}`

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### on_fail

---
```lua
event_builder:on_fail(callback)
```

Set callback called when the event fails (aborted due to condition failure). Use for handling failure cases.

- **Parameters:**
	- `callback` *(function)*: Callback receives event data: `{id, category, payload, status, start_time, end_time}`

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### abort_on_fail

---
```lua
event_builder:abort_on_fail()
```

Set flag to abort event when conditions fail. When conditions fail, event status will be set to "aborted" and will not retry.

- **Returns:**
	- `Self` *(schedule.event_builder)*: for method chaining

### save

---
```lua
event_builder:save()
```

Save the event to the schedule system and return the event instance. Call as the final step after configuration.
Nothing happens until `save()` is called. The event is validated, times are calculated, state is stored,
and callbacks are registered. If an existing event with the same ID exists, its state is merged.
Returns the created event object, with methods like `get_time_left()` and `get_status()`.

- **Returns:**
	- `event` *(schedule.event)*: Created event instance


## Fields
<a name="config"></a>
- **config** (_table_)

