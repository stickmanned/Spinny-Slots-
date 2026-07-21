# Junk King battle rules

This document records the implementation assumptions for the first-area boss.
The current feature request overrides the older prototype rule that preserved the
wallet after a loss; permanent progression is still protected.

## Encounter and persistence

- The first successful purchase that unlocks the Magnet Machine checkpoints the
  save and starts the one-time phone introduction.
- A failed purchase or a later ticket purchase cannot start it.
- Interrupted introductions resume from the safe post-purchase call state.
- Interrupted battles restore the last pre-battle checkpoint. Battle scores,
  RNG state, and pending effects are intentionally transient.
- A loss keeps the boss available. A win closes the encounter and unlocks the
  Metropolis preview permanently.

## Regulation and machine schedule

- Regulation is 10 rounds. The player spins first, then the Junk King, once per
  round.
- Battle scores are separate from the wallet and tickets are never consumed.
- One machine is chosen as the battle's extra machine. One shared schedule gets
  three appearances of every Junkyard machine plus that extra appearance, then
  is shuffled once. The schedule's current entry is stored as round state and
  used by both contestants; each contestant still rolls an independent result.
- If regulation is tied, sudden-death pairs repeat. Both contestants use the same
  newly randomized Junkyard machine within each pair.

## Power-up operation order

Every result is fully calculated before its reel animation. Player and Junk King
upgrade profiles are value-only snapshots created at battle setup. The player
uses current levels; the Junk King always uses the configured Junkyard maxima:
Luck 5 (1.75x), Coin Multiplier 10 (2.50x), and Spin Speed 5 (2.25x).

The calculation order is:

1. Resolve or shield incoming hostile effects.
2. Apply that contestant's Luck upgrade, then Luck Booster and Odds Disruptor,
   to non-common symbol weights.
3. Independently roll three symbols from the shared round machine's real data.
4. Apply Scrap Reroll when its exact trigger is met.
5. Sum configured symbol payouts.
6. Apply that contestant's Coin Multiplier upgrade.
7. Apply either Triple Welder or Mixed Load Bonus when eligible.
8. Apply Final Surge during regulation rounds 8 through 10.
9. Apply one armed manual effect: Payout Doubler, Overcharge, Odds Disruptor, or Payout Siphon.
10. Floor once to whole dollars and clamp to a non-negative score.
11. Transfer Payout Siphon's 20 percent share, if applicable.
12. Commit the score, charges, and log once using the prepared spin token.

The player's loadout is exactly three unique choices from the 10-item catalog.
The Junk King uses Odds Disruptor, Payout Siphon, and Final Surge; his deterministic
AI activates the disruptor on round 4 and the siphon on round 8.

## Outcome transaction

- Victory adds only the Junk King's final battle score to the wallet. The
  player's temporary score is not paid again. The payout and Metropolis unlock
  share one idempotent resolution token.
- Defeat changes the wallet to exactly $30 once. It does not remove machines,
  tickets, upgrades, gems, story progress, or the Magnet Machine unlock.
