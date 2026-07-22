# Metropolis Stabilization Pass - Implementation Prompt

You are working in `D:\Code\Spinny-Slots-`. The Godot project root is
`D:\Code\Spinny-Slots-\spinny-slots!`.

## Goal

Repair the existing Area 2: Metropolis implementation so map travel, ticket UI,
machine layout, spins, payouts, and all four defined Metropolis mechanics work
end to end and feel as consistent and polished as the current Junkyard UI.

This is a focused stabilization pass. Do not rebuild Metropolis, redesign the
whole game, add a Metropolis boss, or expand later-area content.

## Read first

Before editing:

1. Read the repository `AGENTS.md` and `docs/GAME_PLAN.md`. The plan limits the
   current shipped scope, so treat this work as repairing existing Metropolis
   code, not authorization to build more Area 2 story content.
2. Inspect the current Junkyard implementation and use it as the visual and
   interaction reference, especially:
   - `spinny-slots!/scenes/junkyard_job.tscn`
   - `spinny-slots!/scripts/junkyard_job.gd`
   - `spinny-slots!/scenes/ui/ticket_shop_panel.tscn`
   - `spinny-slots!/scenes/ui/odds_panel.tscn`
   - `spinny-slots!/scenes/ui/machine_selector_panel.tscn`
3. Inspect the current Metropolis implementation rather than assuming either
   prior implementation prompt was completed correctly:
   - `spinny-slots!/scenes/metropolis_job.tscn`
   - `spinny-slots!/scripts/metropolis_job.gd`
   - `spinny-slots!/scripts/metropolis_economy.gd`
   - `spinny-slots!/resources/machines/*.tres`
   - `spinny-slots!/scripts/dev/metropolis_milestone.gd`
   - `spinny-slots!/scripts/dev/metropolis_balance_sim.gd`
4. Review the three supplied screenshots. They show the map-current-state bug,
   overflowing ticket rows and redundant cash display, and the Firewall layout
   pushing Spin below the viewport.

The two older prompts are historical design context only. This prompt and the
current repository rules win wherever they conflict. In particular, the new
Skyline four-reel requirement below deliberately overrides the old five-reel
specification.

Do not stop after orientation to ask for confirmation. Inspect, make a short
plan, implement the smallest coherent fix, verify it, and then report.

## Known evidence to confirm, not blindly assume

Repository inspection already points to these likely causes:

- `scripts/ui/hud.gd::_populate_map_cards()` infers the active area from
  `get_tree().current_scene`, but `main.tscn` remains the current scene while
  Junkyard or Metropolis is instanced beneath its scene host. The fallback is
  therefore Junkyard even while Metropolis is active.
- `scenes/ui/ticket_shop_panel.tscn` has clipping disabled on both the panel and
  its `ScrollContainer`, allowing ticket rows to render outside the viewport.
- `scripts/ui/ticket_shop_panel.gd::set_extension_mode()` already hides the
  redundant balance label for Junkyard's embedded panel, but Metropolis does not
  currently enable that mode.
- `metropolis_job.tscn` copied Junkyard's vertically flowing center layout and
  inserted mechanic controls into the same `VBoxContainer`. Showing the Hack or
  Surge controls can therefore reflow the shared controls and push Spin down.
- `resources/machines/billboard_jackpot.tres` and the current Metropolis tests
  still define Skyline as five reels.
- Gameplay code exists, but the current integration test can pass a zero-payout
  spin because it only checks that money did not decrease. It also bypasses the
  real purchase/click flow and does not prove that each mechanic's UI changes
  gameplay state.

Trace each path and report the confirmed root cause. If the evidence above is
wrong or incomplete, fix the actual cause and explain the discrepancy.

## Priority 1 - Fix map state and two-way travel

Fix the Map Select flow so the active area is supplied from authoritative game
or host state rather than inferred from `SceneTree.current_scene` or a hardcoded
default.

Required behavior:

- In Junkyard, Map Select marks Junkyard as `CURRENT AREA` and lets the player
  choose unlocked Metropolis.
- After travelling to Metropolis, reopening Map Select marks Metropolis as
  `CURRENT AREA`.
- While in Metropolis, Junkyard is enabled and clicking it returns to Junkyard.
- Reopen Map Select after returning and confirm Junkyard is current again.
- The existing unlock rule remains intact: Metropolis cannot be entered before
  `GameState.metropolis_unlocked` is true.
- Repeated button presses during a transition do not duplicate scenes or leave
  the fade/input blocker stuck.

Add a deterministic integration test for the full round trip through the real
host/navigation signals. Do not validate this only by calling transition
methods directly.

## Priority 2 - Make the ticket and odds column match Junkyard quality

Use the current Junkyard left column as the layout and interaction reference,
while keeping Metropolis's five machine tickets and machine-specific data.

Required behavior:

- Reuse the existing ticket textures already assigned in the five machine
  resources. Do not search for or add replacement assets.
- Every ticket image preserves aspect ratio and remains completely inside its
  row button at all supported sizes.
- Every machine name and price remains inside its row button. Long names such as
  `Rideshare Drone Dispatch`, `Firewall Hacker Terminal`, and
  `Skyline Billboard Jackpot` must wrap, shrink, or use a deliberate text
  overrun policy without overlapping the price or leaving the button.
- The ticket list clips to the visible `ScrollContainer` viewport. Rows, ticket
  art, labels, hover scaling, and selection visuals must not draw above the
  header, below the panel, or over the odds panel while scrolling.
- Remove the redundant cash balance shown to the right of `TICKETS` in
  Metropolis. The global HUD remains the single cash display. Preserve any
  shared behavior Junkyard still needs.
- The lower-left panel title must read `ODDS`, not `PAYTABLE` or `PAY TABLE`.
  It must remain data-driven for the selected Metropolis machine and show useful
  symbol odds/payout information without truncated names.
- Ticket rows remain clickable after the clipping/layout changes; no decorative
  `Control` may intercept input.

Validate bounds using actual `global_rect` containment assertions after layout
settles, including after scrolling to the first, middle, and final rows. Also
capture and inspect screenshots at minimum at 1280x720 and 1920x1080.

## Priority 3 - Stabilize the machine layout across all five machines

The cabinet, left/right arrows, result/payout region, and Spin button must occupy
the same screen-space positions when cycling between machines. A machine's
special controls may change content, but must not reflow the common controls.

Use a fixed-size reserved mechanic region or an overlay anchored to a designated
region. Do not solve this by hardcoding unrelated per-machine offsets.

Required behavior:

- Cycle through all five machines and compare the `global_rect` of the cabinet,
  both arrows, payout region, and Spin button. The corresponding rectangles must
  remain equal within normal floating-point/layout tolerance.
- The full cabinet and reel display are visible and centered in their reserved
  area for every machine.
- The Spin button is fully inside the safe viewport and clickable for every
  machine, especially Firewall Hacker Terminal.
- Surge and Hack controls stay visible and usable without moving the shared
  controls.
- The layout remains valid at 1280x720 and the other aspect ratios exposed by
  the Settings resolution selector. At minimum, inspect one 16:10 mode in
  addition to 1280x720 and 1920x1080.

Keep this a shared layout fix. Do not create five separate hand-positioned
machine screens.

## Priority 4 - Change Skyline Billboard Jackpot to four reels

Skyline Billboard Jackpot must display and use exactly **four reels/icons** at
once. This is a gameplay-data change, not a cosmetic crop.

Update all affected layers together:

- Set Skyline's authoritative reel count to 4.
- Provide or generalize a four-reel presentation so exactly four evenly padded
  reel windows fit inside Skyline's configured screen region.
- Keep Quantum Vault at five reels and the first three machines at three reels.
- Update match evaluation and Skyline's paytable to support 3-of-4 and 4-of-4.
  Remove any Skyline-only 5-of-5 assumptions from display, tests, and simulation.
- Preserve independent per-reel rolls and preselect the complete result and all
  cascade refills before animation begins.
- Recalculate Skyline payouts after the probability change so its balance does
  not silently break. Do not change its symbol weights.

Add deterministic tests proving four results are rolled and rendered, 3-of-4
and 4-of-4 resolve correctly, 2-of-4 does not win, cascade caps still hold, and
Quantum still renders/resolves five reels.

## Priority 5 - Repair the complete ticket-to-payout gameplay loop

Test and fix the real user path for every machine:

1. Give the player enough cash.
2. Click that machine's visible ticket row.
3. Confirm the exact price is deducted and one ticket is added.
4. Confirm `SPIN (n)` immediately reflects the balance and is enabled.
5. Click the actual Spin button.
6. Confirm one ticket is consumed, reels visibly animate to the predetermined
   result, the result/payout UI updates, and the configured payout is credited
   after presentation.
7. Confirm a second spin without a ticket is blocked without consuming cash or
   awarding anything.

Final ticket prices remain:

| Machine | Ticket price |
|---|---:|
| Neon Arcade Cabinet | $10,000 |
| Rideshare Drone Dispatch | $100,000 |
| Firewall Hacker Terminal | $250,000 |
| Skyline Billboard Jackpot | $1,000,000 |
| Quantum Vault | $2,500,000 |

Payouts must come from machine/economy data, never from UI scripts. Add a
deterministic positive-win case for every machine that asserts the exact payout
credited, rather than merely asserting `money >= previous_money`.

Do not invent a special ability for Neon Arcade Cabinet; it is intentionally the
baseline machine. Verify the four defined mechanics end to end:

- **Rideshare Drone Dispatch - Surge Multiplier:** the visible dial/reroll/lock
  controls work; rerolls obey the cap and use a free token before cash; the
  locked value multiplies that exact spin's payout; a jackpot grants the free
  reroll token specified by current data.
- **Firewall Hacker Terminal - Hack Charge:** a Golden Key grants one charge up
  to the configured cap; selecting a visible reel and spinning consumes one
  charge; only that reel receives the configured higher-tier weight shift for
  that spin; selection resets afterward.
- **Skyline Billboard Jackpot - Cascade Match:** each winning tier clears and
  refills matched positions, pays its configured tier multiplier, respects the
  cap/bonus-tier rules, and awards the sum of all tiers. The entire cascade
  chain is computed before presentation.
- **Quantum Vault - Superposition:** only a reel whose predetermined result is
  the Superposition Symbol shows the double-exposure presentation, then
  collapses to the already-selected symbol. The animation never changes RNG or
  payout state.

For mechanics that are rare under normal RNG, use deterministic seeds or pure
calculation entry points in tests. Do not weaken production odds or add debug
cheats to make verification convenient.

## Priority 6 - Verify economy instead of guessing

Do not blindly rewrite payout values that are already correct. Run the existing
Metropolis balance simulation through the same production calculation path and
report its results for all five machines before and after any balance changes.

- Preserve every configured symbol weight.
- Verify baseline RTP is approximately 75-90% per ticket for each machine.
- Verify upgrades and mechanics affect returns as designed and that a fully
  invested machine can exceed 100% effective return.
- Because Skyline changes from five to four reels, retune its payout data as
  needed to return it to the target range.
- Change another machine's payout table only if the simulation or a confirmed
  data/wiring bug shows it is outside the target or not being awarded.
- Report spin count, fixed seed, average payout, RTP, best payout, and relevant
  upgraded/mechanic scenario for each machine. Do not report a simulated number
  you did not actually run.

## Architecture and change constraints

- Godot 4.7.1 standard edition and statically typed GDScript where practical.
- Select every base result and mechanic-dependent refill before reel animation.
  Reels present supplied results; they do not authoritatively roll or pay.
- Keep economy formulas and tunable machine values outside UI scripts, in the
  existing data/resource layer.
- Keep permanent bank/progression separate from temporary battle scores.
- Preserve Junkyard recovery and existing save compatibility.
- Make the smallest coherent change. Reuse existing shared UI where practical;
  do not broadly refactor unrelated systems.
- Do not add a dependency or third-party asset. Do not modify `addons/`.
- Do not delete or weaken tests. Update old five-reel Skyline expectations
  because the product requirement changed, and add coverage for the new result.
- Do not clear/rename `.godot`, restart the editor, or alter generated caches
  without asking the user to save and close Godot first.
- Preserve unrelated user changes in the worktree. Do not commit or push unless
  explicitly asked.

## Required acceptance tests

At minimum, the automated checks must cover these ten cases:

1. Junkyard -> Metropolis -> Junkyard round trip through real Map Select clicks,
   with the correct current-area overlay after each transition.
2. Metropolis remains locked before unlock and navigable afterward.
3. All five ticket rows keep art/name/price inside their buttons; scrolling
   clips the first and last rows to the viewport.
4. Metropolis has one global cash display, no ticket-header balance, and the
   lower-left title is `ODDS`.
5. Cabinet, arrows, payout region, and Spin button have stable rectangles across
   all five machine selections; every Spin button rect is inside the viewport.
6. Skyline produces/renders exactly four reels and evaluates 2-of-4, 3-of-4,
   4-of-4, and cascades correctly; Quantum remains five reels.
7. For each machine, clicking purchase then Spin consumes exactly one ticket and
   a forced positive result credits the exact configured payout.
8. Surge, Hack Charge, Cascade, and Superposition each change the intended real
   state/presentation and obey caps/reset rules.
9. A seeded result is unchanged before versus after presentation, proving
   outcome-before-animation.
10. Junkyard ticket/odds UI, spins, upgrades, map state, and save/load still
    pass after shared-component changes.

Extend `scripts/dev/metropolis_milestone.gd` or add a focused deterministic dev
test scene, and ensure `tools/verify.ps1` runs it on every verification pass.
Use the screenshot harness (updating it if necessary) to capture every machine,
not just one convenient selection.

## Required verification commands

Run from `D:\Code\Spinny-Slots-`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\export-windows.ps1
```

The second command is required because this pass touches area navigation and
main-scene wiring. Do not claim completion if either command fails.

Current diagnostic note: on 2026-07-21, the unmodified checkout's Godot 4.7.1
headless process crashed with signal 11 during the first main-scene load, and a
direct Metropolis milestone run crashed the same way. Re-run from your actual
environment. If the crash persists, report the exact command/output and keep the
task status honest; do not delete caches or weaken checks to get a green result.

## Final report contract

Return a concise implementation report containing:

1. Confirmed root cause for each issue.
2. Files changed and why.
3. Automated tests added/updated and what each proves.
4. Visual checks performed, including viewport sizes and all five machines.
5. Economy simulation table with real results and any payout changes.
6. Exact verification commands and pass/fail results.
7. Any remaining limitation or blocker, with no invented success claims.

Do not reply with only a plan or code excerpts. Complete the scoped repair,
verify it, and report evidence.
