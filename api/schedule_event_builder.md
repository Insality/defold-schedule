# schedule.event_builder API

> at /schedule/internal/schedule_event_builder.lua

## Functions

- [create](#create)
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
- [abort_on_fail](#abort_on_fail)
- [save](#save)
## Fields

- [config](#config)



### create

---
```lua
event_builder.create()
```

Create new event builder

- **Returns:**
	- `` *(schedule.event_builder)*:

### category

---
```lua
event_builder:category(category)
```

Set event category

- **Parameters:**
	- `category` *(string)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### after

---
```lua
event_builder:after(after, [options])
```

Set event to start after N seconds or after another event

- **Parameters:**
	- `after` *(string|number)*: Event ID or seconds
	- `[options]` *(table|nil)*: Options for chaining (wait_online, etc.)

- **Returns:**
	- `` *(schedule.event_builder)*:

### start_at

---
```lua
event_builder:start_at(start_at)
```

Set event to start at specific time

- **Parameters:**
	- `start_at` *(string|number)*: Timestamp or ISO date string

- **Returns:**
	- `` *(schedule.event_builder)*:

### end_at

---
```lua
event_builder:end_at(end_at)
```

Set event to end at specific time

- **Parameters:**
	- `end_at` *(string|number)*: Timestamp or ISO date string

- **Returns:**
	- `` *(schedule.event_builder)*:

### duration

---
```lua
event_builder:duration(duration)
```

Set event duration

- **Parameters:**
	- `duration` *(number)*: Duration in seconds

- **Returns:**
	- `` *(schedule.event_builder)*:

### infinity

---
```lua
event_builder:infinity()
```

Set event to never end

- **Returns:**
	- `` *(schedule.event_builder)*:

### cycle

---
```lua
event_builder:cycle(cycle_type, options)
```

Set event cycle
```lua
cycle_type:
    | "every"
    | "weekly"
    | "monthly"
    | "yearly"
```

- **Parameters:**
	- `cycle_type` *("every"|"monthly"|"weekly"|"yearly")*:
	- `options` *(table)*: Cycle options

- **Returns:**
	- `` *(schedule.event_builder)*:

### condition

---
```lua
event_builder:condition(name, [data])
```

Add condition

- **Parameters:**
	- `name` *(string)*: Condition name
	- `[data]` *(any)*: Condition data

- **Returns:**
	- `` *(schedule.event_builder)*:

### payload

---
```lua
event_builder:payload([payload])
```

Set event payload

- **Parameters:**
	- `[payload]` *(any)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### catch_up

---
```lua
event_builder:catch_up(catch_up)
```

Set catch up behavior

- **Parameters:**
	- `catch_up` *(boolean)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### min_time

---
```lua
event_builder:min_time(min_time)
```

Set minimum time required to start

- **Parameters:**
	- `min_time` *(number)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### on_start

---
```lua
event_builder:on_start(callback)
```

Set on_start callback

- **Parameters:**
	- `callback` *(function)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### on_enabled

---
```lua
event_builder:on_enabled(callback)
```

Set on_enabled callback

- **Parameters:**
	- `callback` *(function)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### on_disabled

---
```lua
event_builder:on_disabled(callback)
```

Set on_disabled callback

- **Parameters:**
	- `callback` *(function)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### on_end

---
```lua
event_builder:on_end(callback)
```

Set on_end callback

- **Parameters:**
	- `callback` *(function)*:

- **Returns:**
	- `` *(schedule.event_builder)*:

### abort_on_fail

---
```lua
event_builder:abort_on_fail()
```

Set flag to abort event when conditions fail. When conditions fail, event status will be set to "aborted" (will retry when conditions pass).

- **Returns:**
	- `` *(schedule.event_builder)*:

### save

---
```lua
event_builder:save()
```

Save event and return event ID

- **Returns:**
	- `event_id` *(string)*:


## Fields
<a name="config"></a>
- **config** (_schedule.event_config_)

