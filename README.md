# Spinny Slots

Spinny Slots is a story-driven, single-player slot-machine progression game made with Godot 4 and GDScript. It uses fictional in-game money only; there is no real-money wagering, purchasable currency, cash-out system, or real-world prize.

The first target is a polished Windows chapter set in the Junkyard. The immediate development target is the gray-box Cardboard Spinner described in [the game plan](docs/GAME_PLAN.md).

## Requirements

- Godot 4.7.1 standard edition
- Windows PowerShell 5.1 or newer
- Godot 4.7.1 export templates for Windows builds
- A configured Hackatime account

The Godot project is in `spinny-slots!`. Open `spinny-slots!/project.godot` in Godot.

## Hackatime

The project includes the MIT-licensed Godot Super Wakatime 2.0.1 editor plugin, pinned to the revision published in Godot's Asset Library. It is enabled in `project.godot` and uses the existing user-level `.wakatime.cfg`; API keys are never stored in this repository.

After opening the project, edit or save a scene/script and check the WakaTime panel at the bottom of the editor. Hackatime may take a short time to display the heartbeat.

## Verification and export

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\export-windows.ps1
```

The verification script imports the project headlessly and runs a dependency-free foundation smoke test. The export script also creates `spinny-slots!/builds/SpinnySlots.exe`; build output is intentionally ignored by Git.

Third-party assets must be recorded in [ASSET_LICENSES.md](spinny-slots!/ASSET_LICENSES.md) before use.
