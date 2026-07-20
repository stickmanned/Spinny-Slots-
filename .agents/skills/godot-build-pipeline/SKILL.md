---
name: godot-build-pipeline
description: Use when running verification, adding a new test, exporting a Windows build, or adding third-party assets/addons to Spinny Slots. Wraps tools/verify.ps1 and tools/export-windows.ps1.
---

# Build & Verification Pipeline — Spinny Slots

## Goal

Make sure every change is actually verified the way this project expects, and that new
gameplay logic ships with the deterministic tests `AGENTS.md` requires.

## Standard verification (run before considering any change done)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify.ps1
```

Run from the **repository root**, not `spinny-slots!/`. This:

1. Headlessly loads and validates the main scene (`godot --headless --path <project>
   --quit-after 2`).
2. Runs each dev smoke-test scene headlessly (currently `res://scenes/dev/smoke_test.tscn`
   and `res://scenes/dev/milestone_2c_test.tscn`), each of which calls `get_tree().quit(1)`
   and `push_error()` per failure if any assertion fails — a non-zero exit fails the whole
   script.

## Release verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify.ps1 -Export
```

Additionally runs `--export-release "Windows Desktop"` to
`spinny-slots!/builds/SpinnySlots.exe` and launch-checks the exported binary headlessly for
3 seconds. Run this — not just the base verify — for anything touching export settings,
autoloads, or main-scene wiring, not only for gameplay-content tweaks.

## Adding a new deterministic test

Follow the exact pattern already used in `scripts/dev/smoke_test.gd` and
`scripts/dev/milestone_2c_test.gd`:

1. A `Node` script whose `_ready()` calls `call_deferred("_run")`.
2. `_run()` awaits `process_frame`/timers as needed, and calls small `_assert_true` /
   `_assert_equal` / `_assert_string_equal` / `_assert_float_close` / `_assert_vector_close`
   helpers that append human-readable messages to a `_failures: Array[String]`.
3. At the end: if `_failures` is empty, `print(...)` a summary and `get_tree().quit(0)`;
   otherwise `push_error()` each failure and `get_tree().quit(1)`.
4. Wrap the test in a minimal scene (`res://scenes/dev/<name>.tscn`) and add another
   `Invoke-Checked` block to `tools/verify.ps1` with
   `--headless --path <project> res://scenes/dev/<name>.tscn`, so it runs on every future
   verify pass.

**This is a hard requirement, not a suggestion:** `AGENTS.md` states "When gameplay logic is
introduced, add deterministic tests alongside it and include those tests in
`tools/verify.ps1`." Don't merge new economy, RNG, or progression logic without this.

## Third-party assets and vendored code

- Before adding any art, audio, font, or code asset you didn't originally author, record it
  in `spinny-slots!/ASSET_LICENSES.md` (license, source, attribution requirement) **in the
  same change** that introduces the asset — don't defer it to a follow-up.
- `spinny-slots!/addons/` (e.g. `godot_super-wakatime`) is vendored code. Treat it as
  read-only except for a deliberate, documented upgrade or compatibility fix — don't edit a
  vendored script incidentally while fixing something unrelated.

## Project layout gotcha

The Godot project root is `spinny-slots!/`, **not** the repository root — `project.godot`
lives there, and all `res://` paths are relative to it. `tools/verify.ps1` and
`tools/export-windows.ps1` already account for this (`$projectRoot = Join-Path
$repositoryRoot 'spinny-slots!'`); don't assume a new script can find `project.godot` at the
repo root.

## Untracked output

`.godot/` (import cache) and `spinny-slots!/builds/` (exported binaries) must stay
untracked — never commit generated import data or the exported `.exe`.
