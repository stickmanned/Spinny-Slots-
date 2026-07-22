class_name MetropolisSymbol
extends Resource

## Metropolis payouts are looked up by (tier, match count) on the owning
## machine's payout_tiers, not by a flat per-symbol value like Junkyard's
## SlotSymbol. Tier is the only economic property a symbol carries.
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
