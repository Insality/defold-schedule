# Test Requirements Analysis

Based on `tech_doc.md`, here are the required tests for the schedule library:

## ✅ Currently Covered Tests

### Schedule Core
- ✅ Basic event creation and lifecycle (test_schedule_basic.lua)
- ✅ Event emission to global queue (test_schedule_events.lua)
- ✅ Filtering by category and status (test_schedule_basic.lua)

### Start Time
- ✅ `after(seconds)` - relative delay (test_schedule_basic.lua)
- ✅ `after(event_id)` - event chaining (test_schedule_chaining.lua)
- ✅ `wait_online` option behavior (test_schedule_chaining.lua)
- ✅ `start_at(timestamp)` - absolute time (test_schedule_basic.lua)
- ✅ `start_at` with ISO date strings (implicitly tested)

### End Time
- ✅ `duration(seconds)` (test_schedule_basic.lua)
- ✅ `end_at(timestamp)` (test_schedule_basic.lua)
- ✅ `infinity()` (test_schedule_infinity.lua)
- ✅ End time priority: infinity > end_at > duration (implicitly tested)

### Cycling
- ✅ "every" cycle with anchor "start" and "end" (test_schedule_cycles_every.lua)
- ✅ "weekly" cycle (test_schedule_cycles_weekly.lua)
- ✅ "monthly" cycle (test_schedule_cycles_monthly.lua)
- ✅ "yearly" cycle (test_schedule_cycles_yearly.lua)
- ✅ `skip_missed` behavior (all cycle tests)
- ✅ `max_catches` limit (needs explicit test)

### Chaining
- ✅ Basic chaining (test_schedule_chaining.lua)
- ✅ Chained events with cycles (test_schedule_chaining.lua)
- ✅ Multiple chained events (test_schedule_chaining.lua)
- ✅ Chain interruption on cancellation (test_schedule_chaining.lua)
- ✅ Chained events reset start_time when parent reactivates (needs explicit test)

### Infinity
- ✅ Never ends automatically (test_schedule_infinity.lua)
- ✅ Manual control (test_schedule_infinity.lua, test_schedule_control.lua)
- ✅ Time calculations (test_schedule_infinity.lua)
- ✅ With cycles (test_schedule_infinity.lua)
- ✅ With chaining (test_schedule_infinity.lua)

### Payload
- ✅ Payload storage and retrieval (test_schedule_basic.lua)
- ✅ Payload in event queue (test_schedule_events.lua)

### Manual Control
- ✅ `start()` - all statuses (test_schedule_control.lua)
- ✅ `finish()` - all statuses (test_schedule_control.lua)
- ✅ `cancel()` - all statuses (test_schedule_control.lua)
- ✅ `pause()` - active events only (test_schedule_control.lua)
- ✅ `resume()` - paused events only (test_schedule_control.lua)
- ✅ Error handling for non-existent events (test_schedule_control.lua)

### Persistence ID
- ✅ Explicit IDs (test_schedule_basic.lua)
- ✅ Auto-generated IDs (implicitly tested)
- ✅ Updating events with same ID (test_schedule_state.lua)

### Catch-up
- ✅ Basic catch-up (test_schedule_catchup.lua)
- ✅ Catch-up with duration events (test_schedule_catchup.lua)
- ✅ Catch-up with cycle events (test_schedule_catchup.lua)
- ✅ Default catch_up behavior (test_schedule_catchup.lua)
- ✅ Catch-up only when `last_update_time` exists (needs explicit test)

### Conditions
- ✅ Condition registration (test_schedule_conditions.lua)
- ✅ Single and multiple conditions (test_schedule_conditions.lua)
- ✅ `on_fail` with "cancel" and "abort" (test_schedule_conditions.lua)
- ✅ Condition re-evaluation (test_schedule_conditions.lua)
- ✅ Status change from failed/aborted to pending when conditions pass (needs explicit test)

### Lifecycle Callbacks
- ✅ All callbacks individually (test_schedule_lifecycle.lua)
- ✅ Callback order (test_schedule_lifecycle.lua)
- ✅ Callbacks during catch-up (needs explicit test)
- ✅ Callback error handling (needs explicit test)

### Min Time
- ✅ Basic min_time check (test_schedule_mintime.lua)
- ✅ Min_time with cycles (test_schedule_mintime.lua)
- ✅ Min_time with infinity events (test_schedule_mintime.lua)

### State Management
- ✅ Get/set state (test_schedule_state.lua)
- ✅ Reset state (test_schedule_state.lua)
- ✅ State serialization (test_schedule_state.lua)
- ✅ State with all event types (test_schedule_state.lua)
- ✅ Callbacks not serialized (implicitly tested)

## ❌ Missing Critical Tests

### Schedule Core
1. **Event emission tracking** - Test that emit keys prevent duplicate emissions
2. **Emit key clearing** - Test that emit keys are cleared when status changes away from "active"
3. **Processing order** - Test that processor.update_all() runs before event emission
4. **Time initialization** - Test that time tracking initializes on first update()

### Start Time
5. **start_at precedence** - Test that `start_at` takes precedence over `after()` when both specified
6. **ISO date parsing** - Explicit test for ISO date string parsing (YYYY-MM-DDTHH:MM:SS)
7. **Chained event start_time reset** - Test that chained events reset start_time to nil when parent reactivates (for cycling)

### End Time
8. **end_at without start_at/after** - Test that event can start immediately if current_time < end_time when only end_at is set
9. **End time calculation priority** - Explicit test verifying: infinity (nil) > end_at > duration

### Cycling
10. **max_catches limit** - Test that max_catches limits catch-up cycles during offline period
11. **Cycle immediate activation** - Test that cycles can immediately activate if next_cycle_time <= current_time
12. **Cycle count increment** - Test that cycle_count increments on each cycle activation

### Chaining
13. **Chain loop termination** - Test that chain updates continue until no more events can start
14. **Parent reactivation reset** - Test that chained events reset start_time when parent reactivates (for cycling events)

### Catch-up
15. **Catch-up requires last_update_time** - Test that catch-up only processes if `catch_up = true` AND `last_update_time` exists
16. **Non-cycling immediate completion** - Test that non-cycling events are marked completed immediately if offline period spans entire duration
17. **Catch-up lifecycle callbacks** - Test that catch-up triggers on_start, on_enabled, on_end, on_disabled for missed activations

### Conditions
18. **Condition evaluation before start_time** - Test that conditions are evaluated for pending events even before start_time is reached
19. **Status change on condition pass** - Test that status automatically changes to "pending" when conditions pass after failure
20. **on_fail custom function** - Test that custom function in on_fail sets status to "failed"

### Lifecycle Callbacks
21. **Catch-up callback order** - Test that `_trigger_event_cycle` calls: on_start → on_enabled → on_end → on_disabled during catch-up
22. **Callback error handling** - Test that callbacks wrapped in pcall don't crash system, errors are logged
23. **on_start during catch-up** - Test that on_start IS called during catch-up cycles (not skipped)

### Event Status
24. **All seven statuses** - Test all status transitions: pending, active, completed, cancelled, aborted, failed, paused
25. **Startable statuses** - Test that pending, cancelled, aborted, failed can transition to active

### Event Query Methods
26. **get_time_left() edge cases** - Test get_time_left() for all statuses and infinity events
27. **get_time_to_start() edge cases** - Test get_time_to_start() for all statuses

### State Management
28. **State structure validation** - Test that state structure is exactly: { events = {[event_id] = event_state}, last_update_time = number|nil }
29. **Callbacks not in state** - Explicit test that callbacks are not serialized

## 📋 Recommended Test File Structure

### New Test Files Needed:
1. **test_schedule_emission.lua** - Event emission tracking and duplicate prevention
2. **test_schedule_processing_order.lua** - Processing order and time initialization
3. **test_schedule_start_at_precedence.lua** - start_at precedence over after()
4. **test_schedule_iso_dates.lua** - ISO date string parsing
5. **test_schedule_cycle_max_catches.lua** - max_catches limit testing
6. **test_schedule_chain_reset.lua** - Chained event start_time reset on parent reactivation
7. **test_schedule_catchup_requirements.lua** - Catch-up requirements (last_update_time)
8. **test_schedule_conditions_evaluation.lua** - Condition evaluation timing and status changes
9. **test_schedule_lifecycle_catchup.lua** - Lifecycle callbacks during catch-up
10. **test_schedule_status_transitions.lua** - All status transitions

### Enhancements to Existing Tests:
- **test_schedule_cycles_every.lua** - Add explicit max_catches test
- **test_schedule_catchup.lua** - Add explicit last_update_time requirement test
- **test_schedule_conditions.lua** - Add status change test when conditions pass
- **test_schedule_lifecycle.lua** - Add catch-up callback order test, error handling test
- **test_schedule_state.lua** - Add explicit callback serialization test

## 🎯 Priority Tests (Critical for Library Reliability)

**High Priority:**
1. Event emission tracking and duplicate prevention
2. Catch-up requirements (last_update_time check)
3. Condition evaluation timing
4. Status transitions (all seven statuses)
5. Chained event reset on parent reactivation

**Medium Priority:**
6. max_catches limit
7. ISO date parsing
8. start_at precedence
9. Lifecycle callbacks during catch-up
10. Callback error handling

**Low Priority:**
11. Processing order verification
12. Time initialization
13. State structure validation
14. Edge cases for query methods

