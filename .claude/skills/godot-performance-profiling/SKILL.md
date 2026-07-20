---
name: godot-performance-profiling
description: Use when investigating frame-rate, stutter, memory, or load-time issues in Spinny Slots, or before adding new animated/looping systems (reels, particles, tweens, VFX).
---

# Godot Performance & Profiling — Spinny Slots

## Goal

Keep the game smooth on modest Windows hardware, and catch performance regressions before
they reach a milestone build, not after.

## How to actually profile this project

- Use the Godot editor's Debugger → Profiler (CPU/GPU) and the Monitor tab (draw calls,
  object count, node count, orphan nodes) while playing a scene interactively. `--headless`
  runs (used by `tools/verify.ps1`) do not render or profile — profile from the editor or a
  debug export, not from the verify script.
- Watch **Orphan Nodes** specifically during a play session that spawns temporary visuals
  (floating reward labels, future particle bursts, reel-stop VFX). A rising count means
  something isn't calling `queue_free()`.
- For load-time issues, time `--headless --path <project> --quit-after N` runs before and
  after a change (this is exactly what `tools/verify.ps1`'s first step already does).

## Hot-path pitfalls to check for in review

- **String-based node lookups in loops or `_process`/`_physics_process`.** Every existing
  screen script (`machine_screen.gd`, `hud.gd`) caches its node references once via
  `@onready` and unique names (`%NodeName`). Any new script that calls `get_node()` or
  `find_child()` repeatedly instead of caching is a regression — flag it.
- **Creating new `Tween`s without killing the old one.** The existing pattern
  (`_active_tween`, `_call_tween`, `_highlight_tween`, etc. in `machine_screen.gd`) always
  checks `if _tween and _tween.is_valid(): _tween.kill()` before creating a replacement.
  Copy this pattern for any new animated system — an un-killed looping tween (like
  `_start_purchase_highlight`'s `set_loops()`) will keep running and stacking with new ones
  if you forget to kill it first.
- **Expensive work inside frequently-firing signal handlers.** `money_changed` can fire on
  every currency change; its handlers (`_on_money_changed`) should stay cheap — trigger a
  `refresh()` call, don't recompute derived state from scratch. Apply the same discipline
  to any new high-frequency signal.
- **Un-freed transient nodes.** `_spawn_floating_reward` chains `queue_free()` onto the tween
  that fades it out. Any new transient VFX (reel symbol pop, win celebration, particle burst)
  must follow the same "animate then free" chain, not just hide/reset for reuse unless it's
  genuinely pooled.

## Reel/animation-specific guidance (for future weighted-reel machines)

- Prefer a shared texture atlas for reel symbols over many individual textures — this cuts
  draw calls when several reels animate at once, which will matter more once machines have
  more than the Cardboard Spinner's fixed result.
- Benchmark frame time with the minimum and the maximum reel/symbol count you plan to ship
  before merging a new machine type — more simultaneous tweens and sprites is the most
  likely source of a new perf regression in this project.
- Keep per-frame reel-spin visuals (if ever driven by `_process` instead of `Tween`) doing
  the minimum possible work; prefer `Tween`/`AnimationPlayer` over manual `_process` easing
  where it's a straightforward substitute, matching the rest of the codebase.

## Memory and import settings

- `preload()` is used throughout for small config Resources and PackedScenes (see
  `economy.gd`, `machine_screen.gd`) — this is fine for small, always-needed data, but bakes
  the resource into the compiled script's memory footprint. Use `load()` instead for large,
  situational assets (music tracks, big splash art, per-area backgrounds) so they aren't
  paid for until actually needed.
- Check texture import settings (compression, mipmaps, size) for new machine cabinet art and
  symbol atlases — this project already ships `.ctex` compressed imports; don't import new
  art at a drastically different setting without a reason.

## Build-side performance signal

- `tools/export-windows.ps1` launch-checks the exported `.exe` with a `--quit-after 3`
  timeout. If that check starts failing or timing out after a change, suspect expensive
  `_ready()` work in an autoload (`Economy`, `GameState`) or the main scene, since those run
  on every single launch.
