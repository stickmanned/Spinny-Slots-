class_name MetropolisSymbol
extends Resource

## Every landed symbol pays this flat amount, just like Junkyard. The owning
## machine's payout tiers remain optional match/cascade bonuses layered on top.
enum Tier {
	COMMON,
	UNCOMMON,
	RARE,
	JACKPOT,
}

@export var symbol_id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var tier: Tier = Tier.COMMON
@export_range(0.0, 100.0, 0.01) var weight: float = 1.0
@export_range(0, 2147483647, 1) var payout: int = 0


static func tier_name(value: Tier) -> String:
	match value:
		Tier.COMMON:
			return "Common"
		Tier.UNCOMMON:
			return "Uncommon"
		Tier.RARE:
			return "Rare"
		Tier.JACKPOT:
			return "Jackpot"
	return "Unknown"
