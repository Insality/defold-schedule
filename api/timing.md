# Join window, run, clip and exceed

> Timing rules for `duration`, `end_at`, `cycle` and `min_time`.

Two clocks matter:

- **Join window** — when the event may still start.
- **Run** — how long it stays `active` after it starts.

With the default **clip** behaviour they are the same interval. With `:duration(n, { exceed_end_time = true })` they are not: the slot is the door, `duration` is the run from join.

`min_time` always looks at leftover **join** time, never at run length.


## Fields

| Field | Role |
| ----- | ---- |
| `start_at` | Calendar anchor / first occurrence |
| `cycle` | Repeating grid. The **slot** is `[occurrence, next occurrence)` |
| `duration` | Clip: length of join and run. Exceed: length of the run from `now` |
| `end_at` | Clip: hard stop for join and run. Exceed: hard stop for the join window only |
| `exceed_end_time` | Set via `:duration(n, { exceed_end_time = true })` |
| `min_time` | Refuse to start unless more than this many seconds remain in the join window |
| `infinity` | No join/run end. Incompatible with `duration` and `end_at` |


## Clip (default)

Join and run are `[occurrence, occurrence + duration)`, capped by `end_at` when both are set:

`end_time = min(start + duration, end_at)`

Late join keeps the occurrence as `start_time` and runs the leftover. Weekend sat–mon is `:cycle("weekly", { weekdays = { "sat" } })` + `:duration(2 * schedule.DAY)` with no flag.

`min_time = duration` means “only start if the full N still fits before the window ends”.


## Exceed

```lua
:duration(n, { exceed_end_time = true })
```

- **Run:** `start_time = now`, `end_time = now + n`. May pass `end_at` and the next occurrence.
- **Join window:**
  - with `end_at`: until `end_at`
  - with `cycle`: until the **next occurrence** (the slot)
  - with both: `min(next occurrence, end_at)` — no new joins after the season date; an already running run still finishes

While `active`, the next occurrence waits (one id, one run). After `completed`, if a join window is still open, that slot starts (`start_time = now` again). It is **not** burned because its occurrence start fell inside the previous run.

If `duration` is at least the cycle interval, runs can chain with no gap.


## Combinations

| Setup | Join window | Run | Late join |
| ----- | ----------- | --- | --------- |
| `duration` | `start` + duration | same | leftover |
| `end_at` | until `end_at` | until `end_at` | leftover |
| `duration` + `end_at` | until `min(start+duration, end_at)` | same | leftover |
| `cycle` + `duration` | `[occ, occ+duration)` | same | leftover (puzzle / weekend) |
| `cycle` + `duration` + exceed | `[occ, next occ)` | `now + duration` | full N from join |
| `end_at` + `duration` + exceed | until `end_at` | `now + duration` (may pass the date) | full N from join |
| `cycle` + `end_at` + `duration` + exceed | until `min(next occ, end_at)` | `now + duration` | full N from join |
| `infinity` | none | never ends | — |

Invalid:

- `infinity` with `duration` or `end_at`
- `exceed_end_time` without `duration`
- `start_at` with `after`

Pause still extends `end_time` only for relative duration when there is **no** `end_at`.


## Recipes

Timer:

```lua
:duration(schedule.HOUR)
```

Season until a date:

```lua
:start_at("2026-01-01T00:00:00")
:end_at("2026-03-01T00:00:00")
```

Cyclic leftover (puzzle day, weekend sat–mon):

```lua
:cycle("every", { seconds = 2 * schedule.DAY, skip_missed = true })
:duration(schedule.DAY)
```

Two-day slot, one day of play from join:

```lua
:cycle("every", { seconds = 2 * schedule.DAY, skip_missed = true })
:duration(schedule.DAY, { exceed_end_time = true })
```

Year window, one week from join:

```lua
:end_at("2026-12-31T00:00:00")
:duration(schedule.WEEK, { exceed_end_time = true })
```

Week that must not pass the date:

```lua
:duration(schedule.WEEK)
:end_at("2026-03-01T00:00:00")
```

Daily offer, 30 minutes whenever you join that day:

```lua
:cycle("every", { seconds = schedule.DAY, skip_missed = true })
:duration(30 * schedule.MINUTE, { exceed_end_time = true })
```

Join Monday 23:50 → run until Tuesday 00:20. Tuesday does not start while Monday is still active. At 00:20 Tuesday’s slot is still open, so a new 30 minutes start. If Monday’s run finished before midnight, Tuesday launches on the grid as usual.


## Out of scope

A **cyclic** short door plus a long run from join (enter only sat–mon, but a Sunday join still gets two full days, repeating every week) needs a third length. One-shot hybrid is already `start_at` + `end_at` + `duration` + exceed: the door is `end_at`, the run can pass that date.
