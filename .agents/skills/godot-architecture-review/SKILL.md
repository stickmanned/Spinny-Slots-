---
name: godot-architecture-review
description: Use when writing or reviewing Spinny Slots gameplay code (scripts, autoloads, Resources, scenes). Enforces outcome-before-animation, data/UI separation, signal conventions, and static typing.
---

# Godot Architecture Review — Spinny Slots

## Goal

Keep gameplay logic correct, decoupled, and consistent with the architecture already
established in `spinny-slots!/scripts/`, so the codebase stays coherent as it grows past
the Junkyard chapter into more machines, gadgets, and areas.

## Non-negotiable invariants

1. **Outcome-before-animation.** A result (payout, symbols) must be fully computed before
   any reel/animation code runs. `machine_screen._on_spin_pressed` is the reference: it
   calls `Economy.prepare_machine_spin(...)` to get a complete outcome, *then* awaits the
   spin flourish, *then* calls `Economy.award_machine_spin(outcome)`. Any new machine,
   minigame, or boss battle must follow the same compute → animate → reveal → award order.
   Reels and UI never authoritatively calculate payouts themselves — see `AGENTS.md`.

2. **Data/UI separation.** Scene scripts (`machine_screen.gd`, `hud.gd`, panel scripts under
   `scripts/ui/`) never hardcode prices, payouts, weights, or thresholds. Those values live
   in autoload logic (`Economy`) or `Resource` subclasses (`MachineDefinition`,
   `EconomyConfig`, `JunkyardProgressionConfig`) under `resources/`. If you find yourself
   writing a numeric literal that represents a game-balance value inside a `scripts/ui/*.gd`
   file, stop and move it into a Resource or the relevant autoload.

3. **Autoloads own persistent state.** `Economy` and `GameState` are the only places mutable,
   persisted game state lives. Scene scripts read from them and react to their signals
   (`money_changed`, `gems_changed`, `machine_tickets_changed`, `machine_unlocked`,
   `story_progress_changed`) instead of caching a parallel copy of that state locally.

4. **Phase-based state machines are exhaustive.** Screens like `machine_screen.gd` drive
   branching off an enum (`JobPhase`). Before adding a new phase, `grep` every place that
   matches on the enum (guard checks in `_input`, `_on_dialogue_finished`,
   `_restore_story_phase`, etc.) and update all of them — a phase that's only handled in
   some switches is a bug waiting to happen.

5. **Bankruptcy recovery must survive new features.** Any new spend path must preserve the
   day job (or an equivalent) as a way to recover from $0. Never ship a path that can leave
   a save permanently unable to earn money.

6. **No real-money mechanics, ever.** No IAP, cash-out, accounts, or cloud services — this
   is an offline, fictional-currency game by design (`AGENTS.md`, `docs/GAME_PLAN.md`).

## Established coding conventions to match

- snake_case for files, functions, and variables; PascalCase for `class_name` Resource
  types (`MachineDefinition`, `EconomyConfig`, `JunkyardProgressionConfig`).
- Statically typed GDScript everywhere practical: explicit `-> ReturnType`, typed `var`,
  typed arrays (`Array[String]`, `Array[StringName]`).
- Cache node lookups once with `@onready` and unique-name syntax (`%NodeName`) instead of
  repeated string-based `get_node()` calls, especially in anything that runs often.
- Communicate across scripts with signals connected once in `_ready()`, not direct calls
  into sibling nodes. Emit from the method that actually changes state (see `GameState`'s
  property setters, which validate/clamp, then emit).
- Setters validate before mutating (`money` setter uses `maxi(value, 0)`). Apply the same
  defensive pattern — clamp, then emit — to any new numeric or persisted state.
- Anything a designer should be able to tune without touching code (new machines,
  paytables, boss stats, dialogue) belongs in a `Resource` under `resources/`, following
  the existing `@export`-field pattern, not hardcoded in a script.

## Review checklist

- [ ] Is the outcome fully computed before any animation/tween starts?
- [ ] Are all tunable numbers in a Resource or `Economy`, not in a UI/scene script?
- [ ] Does new state route through `GameState`/`Economy` and their signals?
- [ ] If a new `JobPhase`-style enum value was added, were *all* matches on that enum updated?
- [ ] Is there still a way to recover from a $0 balance?
- [ ] Are new persisted flags one-shot (`if already_set: return`) like `mark_phone_call_started`?
- [ ] Does the change avoid touching `spinny-slots!/addons/` (vendored code)?

## Anti-patterns seen in practice — reject these in review

- Computing a payout inline inside a `_on_spin_pressed`-style UI handler instead of asking
  `Economy` for a complete outcome first.
- Reading or writing `GameState` fields directly from more than one unrelated script instead
  of going through a documented `Economy`/`GameState` method.
- Adding a new phase to a state-machine enum without updating every existing switch/guard
  that matches on that enum.
- A new spend/loss path with no recovery mechanism back to positive income.
