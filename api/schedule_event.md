# schedule.event API

> at /schedule/internal/schedule_event.lua

## Functions

- [create](#create)
- [is_event](#is_event)
- [get_id](#get_id)
- [get_status](#get_status)
- [get_time_left](#get_time_left)
- [get_time_to_start](#get_time_to_start)
- [get_progress](#get_progress)
- [get_payload](#get_payload)
- [get_category](#get_category)
- [get_start_time](#get_start_time)
- [finish](#finish)
- [start](#start)
- [cancel](#cancel)
- [pause](#pause)
- [resume](#resume)
## Fields

- [state](#state)



### create

---
```lua
event.create(event_state)
```

Create event instance

- **Parameters:**
	- `event_state` *(schedule.event.state)*:

- **Returns:**
	- `event` *(schedule.event)*: Event instance

### is_event

---
```lua
event.is_event([value])
```

Check if value is an event

- **Parameters:**
	- `[value]` *(any)*:

- **Returns:**
	- `is_event` *(boolean)*: True if value is an schedule event

### get_id

---
```lua
event:get_id()
```

Get event ID

- **Returns:**
	- `id` *(string)*: Event ID

### get_status

---
```lua
event:get_status()
```

Get event status

- **Returns:**
	- `status` *(string)*: Event status ("pending", "active", "completed", etc.)

### get_time_left

---
```lua
event:get_time_left()
```

Get time left until event ends

- **Returns:**
	- `time_left` *(number)*: Returns -1 for infinity events, 0 for completed events, or remaining seconds

### get_time_to_start

---
```lua
event:get_time_to_start()
```

Get time until event starts

- **Returns:**
	- `time_to_start` *(number)*: Time in seconds until event starts

### get_progress

---
```lua
event:get_progress()
```

Get event progress

- **Returns:**
	- `progress` *(number)*: Progress value between 0 and 1

### get_payload

---
```lua
event:get_payload()
```

Get event payload

- **Returns:**
	- `payload` *(any)*: Event payload data

### get_category

---
```lua
event:get_category()
```

Get event category

- **Returns:**
	- `category` *(string|nil)*: Event category or nil

### get_start_time

---
```lua
event:get_start_time()
```

Get event start time

- **Returns:**
	- `start_time` *(number|nil)*: Event start time in seconds or nil

### finish

---
```lua
event:finish()
```

Force finish this event. Sets status to "completed" and triggers lifecycle callbacks.
Works on active, pending, paused, or any other status. If event is pending, it will be started first.

- **Returns:**
	- `success` *(boolean)*: True if event was finished

### start

---
```lua
event:start()
```

Force start this event. Sets status to "active" and triggers lifecycle callbacks.
Works on pending, cancelled, aborted, failed, or paused events.

- **Returns:**
	- `success` *(boolean)*: True if event was started

### cancel

---
```lua
event:cancel()
```

Cancel this event. Sets status to "cancelled".
Works on any status except "completed".

- **Returns:**
	- `success` *(boolean)*: True if event was cancelled

### pause

---
```lua
event:pause()
```

Pause this event. Sets status to "paused" and preserves current state.
Only works on active events.

- **Returns:**
	- `success` *(boolean)*: True if event was paused

### resume

---
```lua
event:resume()
```

Resume this paused event. Sets status back to "active".
Only works on paused events.
For events with duration (not end_at), extends end_time by the pause duration.

- **Returns:**
	- `success` *(boolean)*: True if event was resumed


## Fields
<a name="state"></a>
- **state** (_schedule.event.state_)

