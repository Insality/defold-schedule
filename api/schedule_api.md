# schedule API

> at /schedule/schedule.lua

## Functions

- [init](#init)
- [reset_state](#reset_state)
- [get_state](#get_state)
- [set_state](#set_state)
- [event](#event)
- [get_status](#get_status)
- [register_condition](#register_condition)
- [update](#update)
- [set_logger](#set_logger)
## Fields

- [SECOND](#SECOND)
- [MINUTE](#MINUTE)
- [HOUR](#HOUR)
- [DAY](#DAY)
- [WEEK](#WEEK)
- [on_event](#on_event)
- [timer_id](#timer_id)



### init

---
```lua
schedule.init()
```

Initialize schedule system

### reset_state

---
```lua
schedule.reset_state()
```

Reset schedule state

### get_state

---
```lua
schedule.get_state()
```

Get state for serialization

- **Returns:**
	- `` *(schedule.state)*:

### set_state

---
```lua
schedule.set_state(new_state)
```

Set state from serialization

- **Parameters:**
	- `new_state` *(schedule.state)*:

### event

---
```lua
schedule.event()
```

Create new event builder

- **Returns:**
	- `` *(schedule.event_builder)*:

### get_status

---
```lua
schedule.get_status(event_id)
```

Get event status

- **Parameters:**
	- `event_id` *(string)*:

- **Returns:**
	- `` *(schedule.event_status|nil)*:

### register_condition

---
```lua
schedule.register_condition(name, [evaluator])
```

Register condition evaluator

- **Parameters:**
	- `name` *(string)*: Condition name
	- `[evaluator]` *(fun(data: any):boolean)*:

### update

---
```lua
schedule.update()
```

Update schedule system

### set_logger

---
```lua
schedule.set_logger([logger_instance])
```

Set logger

- **Parameters:**
	- `[logger_instance]` *(table|schedule.logger|nil)*:


## Fields
<a name="SECOND"></a>
- **SECOND** (_integer_): Time constants

<a name="MINUTE"></a>
- **MINUTE** (_integer_)

<a name="HOUR"></a>
- **HOUR** (_integer_)

<a name="DAY"></a>
- **DAY** (_integer_)

<a name="WEEK"></a>
- **WEEK** (_integer_)

<a name="on_event"></a>
- **on_event** (_unknown_): Global event subscription queue

<a name="timer_id"></a>
- **timer_id** (_nil_): Timer handle for update loop

