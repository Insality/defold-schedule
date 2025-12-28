# Schedule Technical Documentation

## Schedule

- Central update loop processes all events each frame via `update()`
- Processing order: processor.update_all() → event emission to global queue
- Processor order per event: catch-up → start time calculation → activation checks → completion checks → cycle processing → chaining updates
- Maintains global event queue (`on_event`) for cross-cutting concerns
- Events emitted to global queue when status changes to "active" (pushed during activation in processor)
- On game restart: all active events are emitted to queue and `on_enabled` is called (but NOT `on_start`) on first update after `set_state()`
- On game restart: all active events are emitted to queue and `on_enabled` is called (but NOT `on_start`) on first update after `set_state()`
- Tracks last update time for catch-up calculations
- State is fully serializable for save/load
- Events are stored in memory and processed on each `update()` call
- Time tracking initialized on first `update()` call

## Event

- Core unit with start time, end time, and status
- Seven possible statuses: "pending", "active", "completed", "cancelled", "aborted", "failed", "paused"
- Status transitions: pending → active → completed (normal flow)
- Can have duration (end_time = start_time + duration)
- Triggers lifecycle callbacks on start/end
- Stores category, payload, and configuration
- Each event has unique ID for persistence
- Events can be queried by ID at any time
- Status "startable" includes: pending, cancelled, aborted, failed (can transition to active)

## Start Time

### After

- Relative delay: `after(seconds)` calculates start_time = current_time + seconds
- Event chaining: `after(event_id)` waits for referenced event to complete
- Chained events start when parent event's end_time is reached
- Chain validation checks parent event exists and status = "completed"
- `wait_online` option: if true, waits for first `update()` call after parent completes (starts counting after player is online, don't include offline time); if false/nil, starts immediately when parent completes
- Start time recalculated when parent event completes
- Processor updates all chained events in a loop until no more updates occur
- Chained events reset start_time to nil when parent reactivates (for cycling events)

### Start At

- Absolute time: `start_at(timestamp)` or `start_at(iso_string)` sets fixed start time
- ISO date strings parsed to Unix timestamps (YYYY-MM-DDTHH:MM:SS)
- Event activates when current_time >= start_time
- Used for calendar-based scheduling (LiveOps, promotions)
- Takes precedence over `after()` if both specified (

## End Time

- Duration: `duration(seconds)` calculates end_time = start_time + duration
- End At: `end_at(timestamp)` sets absolute end time
- Infinity: `infinity()` sets end_time = nil, event never ends automatically
- If end_at set without start_at/after: start_time defaults to current_time, event can start immediately if current_time < end_time
- End time checked each update cycle
- When current_time >= end_time, event transitions to completed
- Infinity events remain active until manually cancelled
- End time calculation priority: infinity (nil) > end_at > duration

## Cycling

- Recurring events that repeat after completion
- Four cycle types: "every", "weekly", "monthly", "yearly"
- "every": Fixed interval in seconds, anchor to "start" or "end"
  - Anchor "start": next cycle = original start_time + (interval * cycle_count)
  - Anchor "end": next cycle = previous cycle's end_time + interval
- "weekly": Specific weekdays at specific time (e.g., {"sun", "mon"} at "14:00")
- "monthly": Specific day of month at specific time (e.g., day 1 at "00:00")
- "yearly": Specific month/day at specific time (e.g., month 1, day 1 at "00:00")
- `skip_missed`: If true, skips missed cycles; if false, catches up on offline time
- `max_catches`: Limits number of cycles to catch up during offline period
- Next cycle time calculated from last cycle end time (for "every" with anchor "end") or anchor time (for calendar-based)
- Cycle count tracked for each event, increments on each cycle activation
- When event completes, next cycle time is calculated and event status reset to pending
- Cycles processed after event completion, can immediately activate if next_cycle_time <= current_time

## Chaining

- Events can depend on other events completing
- `after(event_id)` creates dependency chain
- Chained event waits until parent event status = "completed"
- Start time set to parent's end_time when parent completes
- Processor iterates through all events to update chained events
- Chain updates continue until no more events can start
- Chained events reset start_time when parent event reactivates (for cycles)

## Infinity

- Events with `infinity()` never end automatically
- end_time remains nil throughout event lifecycle
- Status stays "active" until manually cancelled or finished
- Used for permanent buffs, continuous effects
- `get_time_left()` returns -1 for infinity events
- Must be manually controlled via `finish()` or `cancel()`

## Payload

- Custom data attached to event via `payload(data)`
- Included in all event notifications and callbacks
- Passed to lifecycle callbacks (on_start, on_enabled, etc.)
- Included in global event queue messages
- Stored in event state, serialized with state
- Use for lightweight data (IDs, config objects)

## Manual Control

- `start()`: Force activate pending/cancelled/aborted/failed/paused event
  - Cannot start already active or completed events
  - Sets start_time to current_time if not set
  - Calculates end_time if not infinity
  - Triggers on_start and on_enabled callbacks
- `finish()`: Force complete any event, triggers on_end and on_disabled callbacks
  - Works on any status, even if pending (triggers on_start first)
  - Sets end_time to current_time if not set
- `cancel()`: Cancel event (status = "cancelled"), cannot cancel completed events
  - Permanent cancellation, event won't activate
- `pause()`: Pause active event (status = "paused"), preserves current state
  - Only works on active events
  - Event stops progressing while paused
- `resume()`: Resume paused event back to active, triggers on_enabled
  - Only works on paused events
- Manual control bypasses normal timing constraints and condition checks
- Lifecycle callbacks still triggered appropriately

## Persistence ID

- Events can have explicit ID via `event(id)` - pass ID as parameter to `event()` function
- ID required for finding events with `schedule.get(id)`
- IDs must be unique across all events
- Without ID, auto-generated ID created (schedule_1, schedule_2, etc.)
- IDs used as keys in state.events table
- Same ID can update existing event (merges configuration)
- Critical for save/load: events identified by ID in serialized state

## Catch-up

- Handles offline progression when game resumes
- Enabled via `catch_up(true)`, default depends on event type
- Events with duration default to `catch_up = false`
- Events without duration default to `catch_up = true`
- On resume, calculates time difference from last_update_time to current_time
- For pending events: checks if should have started/completed during offline period
- For active events: checks if should have completed during offline period
- For cycling events: processes missed cycles (respects skip_missed and max_catches)
- Catch-up triggers lifecycle callbacks for missed activations (on_start, on_enabled, on_end, on_disabled)
- Events emitted to global queue for missed periods
- Catch-up only processes if `catch_up = true` AND `last_update_time` exists
- For non-cycling events: if offline period spans entire duration, event marked completed immediately

## Conditions

- Pre-activation validation system
- Conditions registered via `schedule.register_condition(name, evaluator)`
- Events can have multiple conditions via `condition(name, data)`
- All conditions must pass (AND logic) for event to activate
- Evaluated in `should_start_event` before activation
- If condition fails and `abort_on_fail()` is set, event status becomes "aborted" and will not retry
- Failed conditions prevent activation until conditions pass
- Conditions re-evaluated when event status changes back to startable (cancelled/aborted/failed → pending)
- If conditions pass after failure, status automatically changes to "pending"

## Lifecycle Callbacks

- `on_start`: Called when event activates (status changes to "active") - only on actual activation, not on game restart
- `on_enabled`: Called whenever the event becomes active, including:
  - When event first activates (after on_start)
  - During catch-up cycles
  - On game restart if event was already active (called for all active events on first update after `set_state()`)
- `on_disabled`: Called when event becomes inactive
- `on_end`: Called when event completes naturally
- Callbacks stored in memory only (not serialized with state)
- Callbacks receive event data: {id, category, payload, status, start_time, end_time}
- Callbacks wrapped in pcall for error handling (errors logged, don't crash system)
- During catch-up cycles, `_trigger_event_cycle` calls: on_start → on_enabled → on_end → on_disabled
- Normal activation calls: on_start → on_enabled; completion calls: on_end → on_disabled
- On game restart: active events get on_enabled (but NOT on_start) and are emitted to queue on first update
- Use on_start for one-time actions, on_enabled for state changes that should apply whenever event is active

## Min Time

- Minimum time remaining required for event to start
- Set via `min_time(seconds)`
- Checked before activation: if (end_time - current_time) <= min_time, event cancelled
- Used for LiveOps to prevent wasted activations
- Also checked during cycle processing to skip cycles with insufficient time
- If min_time check fails, event status set to "cancelled" (permanent, won't retry)
- Checked both in `should_start_event` and during cycle processing

## State Management

- Complete state serializable via `get_state()`
- State includes: events table, last_update_time
- `set_state(new_state)` restores from serialization
- State.events maps event_id → event_state
- Event state includes all configuration and runtime data (status, times, cycle info, etc.)
- Callbacks not serialized (stored separately in memory via lifecycle module)
- State used for save/load to persist events across sessions
- On restore, catch-up time calculated from saved last_update_time to current_time
- `reset_state()` clears all events, callbacks, conditions, subscriptions, and time tracking
- State structure: { events = {[event_id] = event_state}, last_update_time = number|nil }

