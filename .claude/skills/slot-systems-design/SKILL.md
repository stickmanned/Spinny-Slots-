---
name: slot-systems-design
description: Use when designing or implementing slot outcomes, paytables, economy balance, boss battles, or story/dialogue progression for Spinny Slots. Covers RNG fairness and fixed-spin boss constraints.
---

# Slot Systems Design — Spinny Slots

## Goal

Keep "the math" (economy, RNG, boss fairness) correct, data-driven, and testable. Even with
fictional currency, the player's sense of fairness in spins and boss fights is the core trust
mechanic of this game — treat it with the same rigor a real slot/economy system would need.

## The outcome pipeline (every machine must follow this order)

1. Resolve inputs — does the player have a ticket, can they afford it
   (`Economy.can_afford`, `GameState.consume_machine_ticket`)?
2. Compute the **complete** result from data — symbols and payout — before any
   presentation starts. `Economy.prepare_machine_spin` is the reference implementation.
3. Hand the finished result to the presentation layer. Reels/animation only *play back* a
   result that already exists; they never decide or adjust it mid-animation.
4. Only after presentation finishes does the award get applied to `GameState`
   (`Economy.award_machine_spin`, called after the spin flourish `await`s in
   `machine_screen._on_spin_pressed`).

Never split this — e.g. don't compute symbols up front but decide the payout after watching
where reels visually "land." That reintroduces exactly the coupling `AGENTS.md` forbids.

## Current state vs. what's coming

- Today, `MachineDefinition` models a **fixed/guaranteed** payout and a fixed
  `result_symbols` array — intentionally simple for the Cardboard Spinner milestone. Don't
  over-engineer weighted RNG before the plan calls for it (see `docs/GAME_PLAN.md` and stay
  inside the current milestone per `AGENTS.md`).
- When a later machine needs real weighted-random reels:
  - Model each reel as a `Resource` holding a symbol list plus integer/float weights —
    data, not inline math in a script.
  - Add an explicit, seedable RNG helper (Godot's `RandomNumberGenerator` with a settable
    `seed`) so any given spin is reproducible from a seed, for tests and for reproducing a
    player-reported bug.
  - Compute the entire grid/result before any reel animation starts — same rule as above.

## Paytable and balance hygiene

- Keep payout tables as data (Resources or exported arrays/dictionaries), not math scattered
  across multiple scripts, so they can be unit-tested and rebalanced without touching
  gameplay code.
- For any weighted/random machine, add a headless simulation test (same style as
  `scripts/dev/smoke_test.gd`) that runs N simulated spins and asserts the observed average
  payout stays within an expected band. This catches an accidental balance-breaking change
  (e.g. a weight typo) before it reaches a milestone build, and belongs in
  `tools/verify.ps1` alongside the other dev smoke tests.
- Guard rails from `AGENTS.md` apply here directly: economy formulas and machine values stay
  out of UI scripts, and every new machine needs "one understandable mechanical difference"
  from earlier machines (per `docs/GAME_PLAN.md`'s design pillars) — not just bigger numbers.

## Boss battles ("fixed-spin money battle")

Per `docs/GAME_PLAN.md`'s design pillars — "Luck creates tension; decisions create
ownership" — a boss encounter should be a **predetermined/scripted spin sequence**, not the
same weighted-random path as a regular machine, unless the product plan explicitly changes.
Player agency in a boss fight comes from upgrades, gadget loadouts, and machine/reel-hold
choices going in — not from the boss's own RNG. Keep boss-battle score/state separate from
permanent bank/progression (`AGENTS.md`), so a lost boss attempt costs time, not the save.

## Story and dialogue state machines

Persisted one-shot story flags live on `GameState` (`day_job_intro_seen`,
`phone_call_completed`, `ticket_purchase_tutorial_completed`, etc.), each paired with a
`mark_*()` method that no-ops if already set and emits `story_progress_changed` — see
`mark_phone_notification_received`, `mark_ticket_purchase_tutorial_completed`. New story
beats should follow this exact pattern (flag + guarded mark method + signal), not ad hoc
booleans checked independently in multiple scripts. Scene-level phase enums (`JobPhase`)
consume these flags to decide which screen/dialogue state to restore into on load — see
`machine_screen._restore_story_phase`.

## Economy/bank safety

- Every new spend path must go through `Economy`'s guarded methods
  (`can_afford`/`spend_money`-style checks) — never subtract `GameState.money` directly from
  a scene script.
- Every new way to lose money or get stuck needs a recovery path back to positive income
  (the day job today). This is a hard requirement in `AGENTS.md`: "Preserve the recovery job
  so a save cannot become permanently bankrupt."
