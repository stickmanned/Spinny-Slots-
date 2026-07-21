class_name PowerUpDefinition
extends Resource

## Authoritative behavior identifier. Presentation code should use the public
## identity fields below and leave effect resolution to JunkKingBattleEngine.
enum EffectKind {
	LUCK_BOOSTER,
	PAYOUT_DOUBLER,
	OVERCHARGE,
	FINAL_SURGE,
	INTERFERENCE_SHIELD,
	ODDS_DISRUPTOR,
	PAYOUT_SIPHON,
	SCRAP_REROLL,
	TRIPLE_WELDER,
	MIXED_LOAD_BONUS,
}

@export_group("Identity")
@export var power_up_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D

@export_group("Rules")
@export var effect_kind: EffectKind = EffectKind.LUCK_BOOSTER
## True only when a contestant deliberately arms this power-up for one spin.
## Reactive and charge-limited passive effects keep this false.
@export var is_active: bool = false
## -1 means the effect is available for the full battle. Non-negative values
## are tracked as charges by JunkKingBattleEngine.
@export_range(-1, 10, 1) var max_uses: int = -1
@export_range(0.0, 10.0, 0.01) var weight_multiplier: float = 1.0
@export_range(0.0, 10.0, 0.01) var payout_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.01) var failure_chance: float = 0.0
@export_range(0.0, 1.0, 0.01) var transfer_fraction: float = 0.0
@export_range(0, 100, 1) var regulation_start_round: int = 0
@export_range(0, 100, 1) var regulation_end_round: int = 0


func has_limited_uses() -> bool:
	return max_uses >= 0


func applies_during_regulation_round(round_number: int) -> bool:
	if regulation_start_round <= 0 and regulation_end_round <= 0:
		return true
	return round_number >= regulation_start_round and round_number <= regulation_end_round
