# Spinny Slots agent guide

## Before changing the project

- Read `docs/GAME_PLAN.md` and keep work inside its current milestone.
- The Godot project root is `spinny-slots!`; do not assume the repository root contains `project.godot`.
- Use Godot 4.7.1 standard edition and GDScript unless the product plan is explicitly changed.
- Make the smallest coherent change. Do not build later areas before the Junkyard chapter is validated.

## Architecture boundaries

- Select slot outcomes before reel animation. Reels present a supplied result and never authoritatively calculate payouts.
- Keep economy formulas and machine values out of UI scripts. Put tunable values in Godot Resources under `resources/`.
- Keep permanent bank/progression separate from boss-battle scores.
- Preserve the recovery job so a save cannot become permanently bankrupt.
- Keep the game offline and free of real-money gambling, purchases, cash-out, accounts, and cloud services.

## Files and assets

- Use snake_case file names and statically typed GDScript where practical.
- Keep generated `.godot/` and `builds/` output untracked.
- Do not put API keys or other secrets in the repository.
- Record every third-party art, audio, font, or code asset in `spinny-slots!/ASSET_LICENSES.md`.
- Treat `spinny-slots!/addons/` as vendored code. Do not modify it except for an intentional, documented upgrade or compatibility fix.

## Required verification

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify.ps1
```

For release-affecting changes, also run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\export-windows.ps1
```

When gameplay logic is introduced, add deterministic tests alongside it and include those tests in `tools/verify.ps1`.

## Agent skills

On-demand skill packages live in `.claude/skills/` (Claude Code) and `.agents/skills/`
(Codex CLI, Antigravity) — same content, duplicated for each tool's discovery path. Reach
for them by name or let the agent auto-trigger on a matching task:

- `godot-architecture-review` — outcome-before-animation, data/UI separation, autoload and
  signal conventions, static typing.
- `godot-performance-profiling` — profiling workflow, hot-path/tween/signal-handler
  pitfalls, reel/VFX and memory guidance.
- `slot-systems-design` — the outcome pipeline, paytable/RNG design, boss-battle fairness,
  story/dialogue state-machine conventions.
- `godot-build-pipeline` — `tools/verify.ps1` / `tools/export-windows.ps1` usage, adding a
  new deterministic test, asset licensing, vendored `addons/` handling.

These restate and expand this file's rules with concrete, code-level detail; this file
remains the source of truth if the two ever disagree.
