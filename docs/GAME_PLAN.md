# Slot Machine Story Game - Product and Development Plan

Status: Draft 1  
Platform: Windows desktop  
Engine: Godot 4 with GDScript  
Mode: Single-player, offline  
Working title: To be decided

## 1. Product vision

A story-driven progression game in which an underpaid worker is drawn into an increasingly strange world of improvised slot-machine competitions. The player begins by dragging trash bags into a dumpster for $1 each, discovers a cardboard slot machine through an arrogant rich kid, upgrades machines and gadgets, and defeats each area's owner in a fixed-spin money battle.

The game should combine:

- A clear narrative and memorable rivals.
- Short, tactile interactions.
- Satisfying slot reveals and reward presentation.
- Understandable upgrade decisions.
- Meaningful boss battles with limited player-controlled advantages.
- A visible journey from a junkyard to increasingly extravagant areas.

This is an entertainment game using fictional in-game money only. It will not contain real-money wagering, purchasable currency, cash-out systems, or real-world prizes.

## 2. Target player experience

The intended player should feel:

1. Poor but capable during the opening job.
2. Curious when the phone call interrupts the routine.
3. Excited by the first machine's reveal.
4. Clever when selecting upgrades and gadgets.
5. Tense during a close boss battle.
6. Satisfied when defeating a rival and entering a new area.

The tone is comedic and slightly satirical. The game can make fun of wealth, hustle culture, luck, and the absurdity of chasing larger numbers without treating real gambling as financial advice.

## 3. Product goals and success criteria

### Initial goal

Ship one polished, downloadable Windows chapter containing the complete Junkyard progression loop.

### Playtest success criteria

The first chapter is successful when:

- At least four of five playtesters reach the phone call without instructions.
- At least four of five understand how a spin, payout, and upgrade work.
- The first slot spin occurs within three minutes of starting.
- Playtesters can reach and attempt the boss without becoming permanently bankrupt.
- At least three of five playtesters voluntarily ask what happens in the next area or choose to replay the boss.
- No playtester encounters a progress-blocking save, economy, or UI bug.
- A clean Windows build runs on a second computer without Godot installed.

These are playtest targets, not promises. Results should determine what is improved or removed before more areas are built.

## 4. Design pillars

### Story gives progression meaning

Every new machine, gadget, and area should be introduced through the world or its characters. Menus should support the story instead of replacing it.

### Every interaction has physical feedback

Dragging a bag, pressing Spin, stopping a reel, buying an upgrade, and winning a battle must each have clear animation and sound feedback.

### New machines change the rules

A later machine cannot be only a more expensive version of an earlier machine. Each machine needs one understandable mechanical difference.

### Failure costs time, not the entire save

Players may lose spins and boss attempts, but they must always retain permanent unlocks and have access to the day job as a recovery path.

### Luck creates tension; decisions create ownership

Results are random, but upgrades, gadget loadouts, reel holds, and machine selection give players influence over outcomes.

## 5. Core game loop

```text
Perform area job or activity
        |
Earn starting money
        |
Pay to spin a machine
        |
Receive a result and payout
        |
Buy upgrades and gadgets
        |
Unlock and master new machines
        |
Challenge the area boss
        |
Win the prize purse and unlock the next area
```

The day job remains available after slots unlock. It acts as a narrative reminder, an optional interaction, and bankruptcy protection.

## 6. Opening sequence

### Junkyard job

- The game opens directly in the junkyard without a long menu or cutscene.
- Trash bags appear around the work area.
- The player drags each bag into the dumpster using the mouse.
- A valid drop pays $1 and spawns a floating `+$1` indicator.
- An invalid drop returns the bag without removing money.
- The dumpster highlights when a dragged bag enters its valid drop zone.
- Bag weight, scale, and sound can vary slightly for tactile variety.
- A click-select/click-destination accessibility option should be added after the primary drag interaction works.

### Phone call

- The phone rings after the player reaches the configured Junkyard threshold (currently $30).
- The world dims and a phone panel slides in from the right.
- The rich kid delivers a short conversation, no more than several lines at once.
- The player learns that a cardboard machine is hidden nearby.
- Dialogue establishes the rich kid as confident, condescending, and suspiciously interested in the player.
- The player can continue, skip previously seen dialogue, and review the immediate objective.

### First spin

- Each machine spin consumes one machine-specific ticket. Cardboard Cash tickets currently cost $30.
- The first few results are protected from causing immediate bankruptcy.
- The machine displays its possible symbols and payout rules.
- The first win introduces the upgrade panel.

All initial economy numbers are provisional and must be balanced through simulation and playtesting.

## 7. Slot-machine system

Every machine definition contains:

- Machine identifier and display name.
- Area and unlock conditions.
- Spin price.
- Symbol list.
- Base symbol weights.
- Match and combination payouts.
- Special mechanic.
- Mastery requirements.
- Associated art, sounds, and animation timings.

The result is chosen before the animation begins. Reels animate toward that predetermined result. The visual reel position never independently determines the payout.

### Standard spin flow

1. Confirm that the machine is unlocked and the player can afford the spin.
2. Subtract the spin price.
3. Apply luck and active gadget modifiers to the result table.
4. Select the result.
5. Disable additional spin requests.
6. Animate reels stopping from left to right.
7. Evaluate the combination.
8. Present the payout and update money.
9. Update mastery and collection progress.
10. Re-enable the machine or let Auto Spinner continue.

### Required feedback

- Distinct click when each reel stops.
- Clear anticipation before the final reel.
- Short payout count-up animation.
- Stronger lighting, particles, and sound for rare outcomes.
- Fast or skip animation option after it is unlocked.
- No deceptive near-miss system that changes visuals after the result is selected.

## 8. Junkyard area

The first shipped chapter should ultimately contain five machines. Development begins with only Cardboard Cash.

| Machine | Theme | Special mechanic |
|---|---|---|
| Cardboard Cash | Cardboard, tape, marker symbols | Standard three-reel rules; teaches the game |
| Can Crusher | Crushed cans and a hydraulic press | Matching cans collapse and reroll once |
| Scrap Sorter | Conveyor belts and mechanical claws | Player can hold one reel before the next spin |
| Magnet Machine | Coils, batteries, and an electromagnet | A charged magnet can pull one symbol toward a match |
| Golden Dumpster | A suspicious luxury machine hidden in trash | High-cost, high-variance rewards and final mastery challenge |

### Machine unlocking

Machines unlock through a combination of:

- Money earned.
- Previous-machine mastery.
- Short story events.

Mastery may include total spins, discovering symbols, and completing one machine-specific challenge. Mastery must not require waiting for an extremely rare result with no alternate route.

## 9. Upgrades

### Primary upgrades

| Upgrade | Effect | Design constraint |
|---|---|---|
| Luck | Shifts probability toward rarer symbols | Updated odds must be visible to the player |
| Spin Speed | Shortens reel and cooldown duration | Affects farming speed, not the number of boss spins |
| Money Multiplier | Multiplies eligible payouts | Curve must be capped and balanced against machine costs |

Upgrade costs increase by level. A provisional curve is:

```text
cost = base_cost * 1.55 ^ current_level
```

The exact formula should live in configuration data so it can be balanced without rewriting gameplay code.

### Upgrade scopes

- Machine upgrades provide strong bonuses for one machine.
- Area upgrades provide moderate bonuses within the current area.
- Future global upgrades provide small permanent bonuses across areas.

The first chapter only needs machine upgrades. Global prestige is out of scope until the main loop has been validated.

## 10. Gadgets

Players eventually equip a limited number of gadgets. A limited loadout creates decisions and keeps the interface readable.

Initial gadget candidates:

- **Auto Spinner:** Automatically spins while sufficient money remains.
- **Reel Lock:** Preserves one selected reel for a future spin.
- **Lucky Magnet:** Nudges one eligible symbol toward a match after charging.
- **Scrap Collector:** Occasionally refunds part of a losing spin.
- **Overclocker:** Temporarily increases spin speed.
- **Payout Scanner:** Shows detailed machine odds and possible combinations.

The first playable prototype needs only Auto Spinner. The first complete Junkyard chapter should have two or three gadgets, not all six.

Auto Spinner must support:

- Start and stop.
- Stop when balance drops below a chosen reserve.
- Stop after a chosen number of spins.
- Stop after a rare result.
- Clear visual indication while active.

## 11. Boss battle

### Rules

- The player and boss each receive 10 spins.
- Both begin with a separate battle score of $0.
- Battle spins do not spend the player's banked money.
- The player selects a machine and gadget loadout before beginning.
- Player and boss statistics are displayed before the battle.
- Highest total payout after 10 spins wins.
- A tie triggers one sudden-death spin for each competitor.
- Winning grants the prize purse and unlocks the next area.
- Losing discards only the player's battle score; banked money and permanent progression remain intact.
- The boss can be challenged again.

### Player agency

Boss outcomes cannot depend entirely on passive randomness. During the battle, the player may:

- Choose when to use a gadget.
- Hold a reel when the equipped machine supports it.
- Choose a safer or riskier machine before the battle.

Boss odds and special abilities are fixed and testable. The game does not secretly improve the boss because the player is ahead.

### Junkyard boss: the rich kid

- Uses an expensive polished machine that contrasts with the junkyard.
- Taunts the player early in the battle.
- Becomes visibly nervous if the player takes the lead.
- Activates one clearly explained boss gadget.
- On defeat, pays the promised prize and reveals the next location.
- On victory, delivers a short taunt and allows an immediate retry or return to upgrading.

## 12. Story structure

### Chapter pattern

Each area follows this narrative structure:

1. Arrival and introduction to the local job or activity.
2. Meeting or hearing from the area's rival.
3. Discovering the first themed machine.
4. Short dialogue events at progression milestones.
5. Unlocking the rival challenge.
6. Boss battle and aftermath.
7. Transition to the next area.

### Full-game area ideas

Only the Junkyard is committed. Later areas are provisional:

1. **Junkyard:** improvised machines; rich kid rival.
2. **Arcade Backroom:** tickets, CRTs, and skill-versus-luck themes.
3. **Boardwalk:** carnival machinery and showman rival.
4. **Neon District:** high-speed electronic machines and corporate rival.
5. **Penthouse Casino:** extravagant final area and resolution of the rich kid's motive.

No later area should enter production until the Junkyard chapter meets the playtest success criteria.

## 13. UI plan

### Global HUD

- Current bank balance.
- Current area and objective.
- Phone access when messages are available.
- Settings and pause controls.

### Slot screen hierarchy

1. Reels and machine cabinet.
2. Spin button with visible price.
3. Current payout or result.
4. Money balance.
5. Upgrades.
6. Equipped gadgets.
7. Mastery and odds/details.

### Boss screen hierarchy

- Player and boss scores shown side by side.
- Remaining spins centered at the top.
- Current leader communicated through restrained animation and color.
- Player gadgets remain accessible.
- Dialogue never blocks the reels during an active result.

### Accessibility baseline

- UI scales across common 16:9 Windows resolutions.
- Text remains readable at 1280x720.
- Keyboard alternatives for important mouse actions.
- Reduced screen shake and reduced flashing settings.
- Separate music and sound volumes.
- Text does not rely on color alone.
- Dialogue can be advanced and previously seen dialogue can be skipped.

## 14. Art direction and asset plan

The recommended style is a stylized, hand-drawn industrial cartoon:

- Heavy imperfect outlines.
- Cardboard, marker, tape, rust, and scratched-metal textures.
- Muted environmental colors with bright reward highlights.
- Exaggerated silhouettes for machines and characters.
- Portrait-based dialogue.

### Initial art kit

- One layered junkyard background.
- One dumpster and three trash-bag variants.
- Player and rich-kid portraits with a few expressions.
- One layered cardboard machine cabinet.
- Six transparent reel symbols.
- One reusable button and panel set.
- Currency, upgrade, and gadget icons.
- Basic spark, coin, glow, and jackpot effects.

Prototype with shapes and text before producing final art. All third-party assets must be recorded in `ASSET_LICENSES.md` with creator, source, license, modifications, and usage.

## 15. Audio plan

Minimum audio for the first machine:

- Trash pickup and dumpster impact.
- Money tick.
- Phone ring and dialogue advance.
- Spin button press.
- Reel loop and three stop clicks.
- Common, uncommon, and rare win stingers.
- Upgrade purchase sound.
- Boss lead-change and victory/defeat stingers.

Audio must reinforce timing. Reel stop sounds should occur at the exact visual stop, not merely during the general animation.

## 16. Technical plan

### Proposed project structure

```text
project.godot
scenes/
  main.tscn
  junkyard_job.tscn
  machine_screen.tscn
  boss_battle.tscn
  machines/
    slot_machine.tscn
    reel.tscn
  ui/
    hud.tscn
    phone_call.tscn
    upgrade_panel.tscn
    gadget_panel.tscn
scripts/
  game_state.gd
  save_manager.gd
  economy.gd
  slot_machine.gd
  reel.gd
  boss_battle.gd
resources/
  machines/
  symbols/
  upgrades/
  gadgets/
assets/
  art/
  audio/
  fonts/
builds/
```

### Core responsibilities

- `GameState`: current money, story progress, unlocks, upgrades, gadgets, and collections.
- `SaveManager`: versioned local save files, safe loading, and recovery from invalid data.
- `Economy`: prices, payouts, multipliers, and affordability checks.
- `SlotMachine`: validates a spin, selects results, awards payouts, and emits animation events.
- `Reel`: presentation only; animates to a provided symbol.
- `BossBattle`: turn count, separate scores, boss behavior, tie handling, and rewards.

Machine, symbol, upgrade, and gadget values should use Godot Resources or other configuration data. UI code must not contain authoritative economy formulas.

### Save data

Save at minimum:

- Save format version.
- Bank balance.
- Current area and story checkpoint.
- Unlocked machines.
- Upgrade levels.
- Owned and equipped gadgets.
- Machine mastery.
- Settings.

Autosave after purchases, unlocks, boss outcomes, and area transitions. Use atomic replacement or a backup save to reduce corruption risk.

## 17. Delivery roadmap

Complexity uses relative sizes rather than hour estimates.

### Milestone 0 - Project foundation (Small)

- Godot project and Git repository.
- Hackatime configured.
- Base resolution and stretch settings.
- Folder structure and README.
- Debug scene and Windows export preset.

**Done when:** a placeholder Windows build runs outside Godot.

### Milestone 1 - Spin toy (Medium)

- Three text-based reels.
- Weighted result selection.
- Spin cost and payout.
- Reel timing and basic sounds.
- Repeatable 50-spin test without state errors.

**Done when:** spinning alone is understandable and satisfying enough for a short playtest.

### Milestone 2 - Opening loop (Medium)

- Trash drag interaction.
- $1 rewards.
- Phone call and objective.
- Transition to Cardboard Spinner.
- One upgrade.

**Done when:** a new player reaches and uses the machine without explanation.

### Milestone 3 - Progression slice (Large)

- Three primary upgrades.
- Auto Spinner.
- Machine mastery.
- Save/load.
- Bankruptcy recovery through the day job.

**Done when:** a 10-15 minute progression session survives closing and reopening the game.

### Milestone 4 - Boss slice (Large)

- Rich kid presentation and dialogue.
- Ten-spin battle.
- Gadget use.
- Victory, loss, tie, and retry flows.
- Prize and chapter-complete state.

**Done when:** every battle outcome is testable and cannot damage permanent progression.

### Milestone 5 - Junkyard chapter (Large)

- Remaining machines and their distinct mechanics.
- Final art and audio pass.
- Settings and accessibility baseline.
- Economy balancing.
- Windows packaging and release page.

**Done when:** the success criteria in Section 3 have been tested and critical issues resolved.

## 18. Explicitly out of scope for the first ship

- Multiplayer.
- Online leaderboards.
- Accounts or cloud saves.
- Real-money purchases.
- Trading.
- Pets.
- Daily rewards or live-service events.
- Prestige or rebirth systems.
- Procedural areas.
- More than one completed story area.
- Full voice acting.
- Mobile, console, macOS, or Linux releases.

These can be reconsidered only after the Junkyard chapter is playable and tested.

## 19. Major risks and mitigations

| Risk | Mitigation |
|---|---|
| Repetition becomes boring | Validate one polished spin before building content; give machines distinct mechanics |
| Pure randomness makes bosses feel unfair | Use gadget choices, reel holds, visible statistics, and protected permanent progress |
| Player becomes bankrupt | Keep day job available and protect the opening spins |
| Upgrade economy grows uncontrollably | Store values in data and run simulations before adding areas |
| Art workload delays the game | Use layered reusable assets and placeholder art until the loop works |
| Scope expands beyond a shippable Horizons project | Commit only to the Junkyard chapter and keep later areas provisional |
| Auto Spinner removes all interaction | Add configurable stop rules and make boss battles require decisions |
| Save corruption blocks progress | Version saves, save at clear checkpoints, and retain a backup |

## 20. Immediate next build

The first development target is not the full Junkyard. It is a gray-box interaction containing:

1. A balance starting at $10.
2. One Cardboard Spinner costing $2.
3. Three reels using text symbols.
4. Weighted results selected before animation.
5. A payout added to the balance.
6. One Money Multiplier upgrade.
7. A Windows export that runs outside the editor.

After this is playable, add the trash-job opening and phone call. This order tests the riskiest assumption - the slot interaction - before investing in story art or multiple machines.
