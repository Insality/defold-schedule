# schedule API

> at /schedule/schedule.lua

## Functions

- [reset_state](#reset_state)
- [get_state](#get_state)
- [set_state](#set_state)
- [event](#event)
- [get](#get)
- [get_event_state](#get_event_state)
- [remove](#remove)
- [clear](#clear)
- [set_time_function](#set_time_function)
- [get_time](#get_time)
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

Reset all schedule state. Clears all events, callbacks, conditions, subscriptions and time tracking.
The custom time function set with `set_time_function()` is kept, it is a system setting and not game state.
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

Restore schedule state from serialization. Call immediately after loading saved game data,
before declaring your events. Restores all events to their previous state, the next `update()` catches up
the time that passed since the state was saved. Lifecycle callbacks are not serializable: re-declare your
events with `schedule.event(id)` after restoring to attach them again, it keeps the stored timings.

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
	- `[id]` *(string|nil)*: Unique identifier for the event for persistence, or nil to generate one

- **Returns:**
	- `builder` *(schedule.event_builder)*: Builder instance for configuring and saving the event

### get

---
```lua
schedule.get(event_id)
```

Get an event object by ID. Returns a rich event object with methods like `get_time_left()`, `get_status()`, `get_payload()`.
Use this for convenience methods and type-safe access. Use `get_event_state()` for raw state table access.

- **Parameters:**
	- `event_id` *(string)*: The event ID returned from `event():save()` or passed to `schedule.event(id)`

- **Returns:**
	- `event` *(schedule.event|nil)*: Event object with query methods, or nil if event doesn't exist

### get_event_state

---
```lua
schedule.get_event_state(event_id)
```

Get the raw event state table by ID. Use for direct state access.
The returned table is the live internal state, changing it changes the event.
Prefer `get()` unless you specifically need raw state access.

- **Parameters:**
	- `event_id` *(string)*: The event ID to query

- **Returns:**
	- `event_state` *(schedule.event.state|nil)*: Raw event state table, or nil if event doesn't exist

### remove

---
```lua
schedule.remove(event_id)
```

Remove an event completely, dropping its state and its lifecycle callbacks.
Completed events stay in the state until removed, so clean up one-shot events you no longer need
to keep the save file small.

- **Parameters:**
	- `event_id` *(string)*: The event ID to remove

- **Returns:**
	- `is_removed` *(boolean)*: True if the event existed and was removed

### clear

---
```lua
schedule.clear([category], [status])
```

Remove every event matching the given category and/or status. Both arguments are optional,
`clear()` removes all events. Useful to drop completed one-shot events on save.

- **Parameters:**
	- `[category]` *(string|nil)*: Category to match, nil for any category
	- `[status]` *(string|nil)*: Status to match ("completed", "cancelled", ...), nil for any status

- **Returns:**
	- `removed_count` *(number)*: Number of removed events

### set_time_function

---
```lua
schedule.set_time_function([callback])
```

Set the function used to read the current time. Return Unix time in seconds.
Use it to drive the schedule from server time instead of the device clock, which is the
recommended setup for LiveOps events and anything a player could cheat by changing the clock.
Pass nil to go back to the device clock (`socket.gettime`).

- **Parameters:**
	- `[callback]` *(fun():number|nil)*: Function returning the current Unix time in seconds

### get_time

---
```lua
schedule.get_time()
```

Get the current time used by the schedule, as returned by the time function.

- **Returns:**
	- `time` *(number)*: Current Unix time in seconds

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
	- `[evaluator]` *(fun(data: any):boolean|nil)*: Function that returns true if condition passes, nil to unregister

### update

---
```lua
schedule.update()
```

Update the schedule system. Call this at your desired refresh rate (e.g., in your game loop or timer callback).
Processes all events, handles time progression, and triggers lifecycle callbacks. Initializes time tracking on first call.
Once per second is enough for most games, the schedule works on absolute time and does not need frequent updates.

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
Logging is disabled by default. Pass any object with `trace`, `debug`, `info`, `warn` and `error`
methods (a defold-log logger fits), or nil to turn logging off again.

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
Unhandled events are kept for late subscribers, ideal for UI that needs to catch up (the last 128 are kept).
Use it for cross-cutting concerns (logging, analytics), use lifecycle callbacks for event-specific logic.
Callback: `fun(event: table): boolean|nil`. Return `true` to mark the event as handled and drop it from
the queue, return `nil` to leave it for other subscribers. Note that returning `false` also marks it handled.
Event table contains: `callback_type`, `event_id`, `category`, `payload`, `status`, `start_time`, `end_time`
`callback_type` is one of `"start"`, `"enabled"`, `"disabled"`, `"end"`, `"fail"`
