class_name MetropolisMachineDefinition
extends Resource

## Metropolis counterpart to MachineDefinition. Reel count varies per
## machine (3 or 5) and payout is resolved by MetropolisEconomy from
## payout_tiers, not from a flat per-symbol value.

@export var machine_id: StringName
@export var display_name: String
@export_range(1, 1000000, 1) var ticket_price: int = 1
@export var ticket_texture: Texture2D
@export var cabinet_texture: Texture2D
@export var machine_scene_path: String = "res://scenes/metropolis_job.tscn"
@export_range(3, 5, 2) var reel_count: int = 3
@export var symbols: Array[MetropolisSymbol] = []
@export var payout_tiers: Array[MetropolisPayoutTier] = []
@export var screen_region: Rect2 = Rect2()
## Null means the machine has no special mechanic (Neon Arcade Cabinet).
@export var mechanic: MetropolisMechanicConfig


func get_payout_tier(tier: MetropolisSymbol.Tier) -> MetropolisPayoutTier:
	for entry in payout_tiers:
		if entry != null and entry.tier == tier:
			return entry
	return null


func get_payout(tier: MetropolisSymbol.Tier, match_count: int) -> int:
	var entry := get_payout_tier(tier)
	return entry.get_payout(match_count) if entry != null else 0


func get_mechanic_kind() -> int:
	return mechanic.kind if mechanic != null else MetropolisMechanicConfig.Kind.NONE
