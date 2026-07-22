class_name MetropolisMechanicConfig
extends Resource

## Mirrors the PowerUpDefinition pattern used by the Junk King battle: one
## flat Resource with a kind enum and generic fields reused per kind,
## resolved by the spin engine rather than by per-kind subclasses.
enum Kind {
	NONE,
	SURGE_MULTIPLIER,
	HACK_CHARGE,
	CASCADE_MATCH,
	SUPERPOSITION,
}

@export var kind: Kind = Kind.NONE

@export_group("Surge Multiplier (Rideshare Drone Dispatch)")
## Fixed cycle the dial steps through; the player locks whichever value it is
## showing when they stop it.
@export var surge_multiplier_sequence: Array[float] = [1.0, 1.5, 2.0, 3.0, 5.0]
@export_range(0, 1000000, 1) var surge_reroll_cost: int = 5
@export_range(0, 10, 1) var surge_max_rerolls_per_spin: int = 3

@export_group("Hack Charge (Firewall Hacker Terminal)")
@export_range(0, 10, 1) var hack_max_charges: int = 3
## Multiplies the chosen reel's non-common tier weights for one spin only.
@export_range(1.0, 20.0, 0.01) var hack_weight_shift_multiplier: float = 3.0

@export_group("Cascade Match (Skyline Billboard Jackpot)")
@export_range(1, 10, 1) var cascade_max_tiers: int = 4
## Payout multiplier applied to each successive cascade tier in one spin.
@export var cascade_tier_multipliers: Array[float] = [1.0, 1.25, 1.5, 2.0]
## Landing the jackpot symbol seeds one guaranteed tier beyond the cap.
@export var cascade_jackpot_grants_bonus_tier: bool = true

@export_group("Superposition (Quantum Vault)")
## Presentation-only: how long the collapse animation plays once a reel
## carrying a predetermined jackpot symbol stops. No economy fields — the
## outcome is already fixed before this ever plays.
@export_range(0.0, 2.0, 0.01) var superposition_collapse_duration: float = 0.32
