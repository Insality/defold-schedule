# schedule API

> at /schedule/schedule.lua

## Functions

- [reset_state](#reset_state)
- [get_state](#get_state)
- [set_state](#set_state)
- [event](#event)
- [get](#get)
- [get_status](#get_status)
- [register_condition](#register_condition)
- [update](#update)
- [filter](#filter)
- [set_logger](#set_logger)
## Fields

- [SECOND](#SECOND)
- [MINUTE](#MINUTE)
- [HOUR](#HOUR)
- [DAY](#DAY)
- [WEEK](#WEEK)
- [on_event](#on_event)



### reset_state

---
```lua
schedule.reset_state()
```

Reset all schedule state. Clears all events, callbacks, conditions, subscriptions, and resets time tracking.
Use for testing or implementing a "reset game" feature.

### get_state

---
```lua
schedule.get_state()
```

Get the complete schedule state for serialization. Call when saving your game to persist events.
Critical for offline progression. Save to your save file system and restore with `set_state()` on load.

- **Returns:**
	- `state` *(schedule.state)*: Complete state object suitable for serialization

### set_state

---
```lua
schedule.set_state(new_state)
```

Restore schedule state from serialization. Call immediately after loading saved game data.
Restores all events to their previous state. The system calculates catch-up time from saved time to current time.

- **Parameters:**
	- `new_state` *(schedule.state)*: State object previously obtained from `get_state()`

### event

---
```lua
schedule.event([id])
```

Create a new event builder for scheduling timed events. Returns a builder with fluent API.
Chain methods like `:category()`, `:after()`, `:duration()`, then call `:save()` to finalize.
Nothing happens until `:save()` is called.

- **Parameters:**
	- `[id]` *(string|nil)*: Unique identifier for the event for persistence, or nil to generate a random one

- **Returns:**
	- `builder` *(schedule.event_builder)*: Builder instance for configuring and saving the event

### get

---
```lua
schedule.get(event_id)
```

Get an event object by ID. Returns a rich event object with methods like `get_time_left()`, `get_status()`, `get_payload()`.
Use this for convenience methods and type-safe access. Use `get_status()` for raw state table access.

- **Parameters:**
	- `event_id` *(string)*: The event ID returned from `event():save()` or set via `event():id()`

- **Returns:**
	- `event` *(schedule.event|nil)*: Event object with query methods, or nil if event doesn't exist

### get_status

---
```lua
schedule.get_status(event_id)
```

Get the raw event state table by ID. Use for direct state access or legacy compatibility.
Prefer `get()` for new code unless you specifically need raw state access.

- **Parameters:**
	- `event_id` *(string)*: The event ID to query

- **Returns:**
	- `status` *(schedule.event.state|nil)*: Raw event state table, or nil if event doesn't exist

### register_condition

---
```lua
schedule.register_condition(name, [evaluator])
```

Register a condition evaluator function. Call before creating events that use `:condition()`.
Conditions check game state (tokens, progression, inventory) before activation. Multiple conditions
use AND logic - all must pass. If any fails and `abort_on_fail()` is set, event status becomes "aborted" and will not retry.

- **Parameters:**
	- `name` *(string)*: Condition name to use in `event():condition(name, data)`
	- `[evaluator]` *(fun(data: any):boolean)*: Function that returns true if condition passes

### update

---
```lua
schedule.update()
```

Update the schedule system. Call this at your desired refresh rate (e.g., in your game loop or timer callback).
Processes all events, handles time progression, and triggers lifecycle callbacks. Initializes time tracking on first call.

### filter

---
```lua
schedule.filter([category], [status])
```

Filter events by category and/or status. Returns events matching the criteria.
Iterates all events, so consider caching results for large event counts.

- **Parameters:**
	- `[category]` *(string|nil)*: Category to filter by (e.g., "craft", "offer"), nil for any category
	- `[status]` *(string|nil)*: Status to filter by ("pending", "active", "completed", etc.), nil for any status

- **Returns:**
	- `events` *(table<string, schedule.event>)*: Table mapping event_id -> event object

### set_logger

---
```lua
schedule.set_logger([logger_instance])
```

Set a custom logger instance. Integrates schedule logging with your game's logging system.
Useful for debugging, production tracking, or analytics integration. Pass nil to disable logging.

- **Parameters:**
	- `[logger_instance]` *(table|schedule.logger|nil)*: Logger object with `info`, `debug`, `error` methods, or nil to disable


## Fields
<a name="SECOND"></a>
- **SECOND** (_integer_): Time constants. Prefer these over raw numbers (e.g., `schedule.HOUR` instead of `3600`) for readability.

<a name="MINUTE"></a>
- **MINUTE** (_integer_)

<a name="HOUR"></a>
- **HOUR** (_integer_)

<a name="DAY"></a>
- **DAY** (_integer_)

<a name="WEEK"></a>
- **WEEK** (_integer_)

<a name="on_event"></a>
- **on_event** (_unknown_): Global event subscription queue. Subscribe for centralized event handling across multiple categories.

