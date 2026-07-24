extends VBoxContainer

## Two-line paytable row: the symbol's full name (tinted by tier) and its match
## odds on top, its per-count payout curve underneath. Splitting onto two lines
## keeps the full name legible even on 5-reel machines, whose value string
## ("3x .. 4x .. 5x ..") is far too wide to share one line with the name.

const TIER_COLORS := {
	MetropolisSymbol.Tier.COMMON: Color(0.85, 0.9, 0.95),
	MetropolisSymbol.Tier.UNCOMMON: Color(0.55, 0.95, 0.55),
	MetropolisSymbol.Tier.RARE: Color(0.45, 0.7, 1.0),
	MetropolisSymbol.Tier.JACKPOT: Color(1.0, 0.85, 0.2),
}

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %NameLabel
@onready var percent_label: Label = %PercentLabel
@onready var value_label: Label = %ValueLabel


func configure(symbol: MetropolisSymbol, payout_tier: MetropolisPayoutTier, probability: float) -> void:
	icon.texture = symbol.icon
	name_label.text = symbol.display_name
	name_label.add_theme_color_override(
		"font_color", TIER_COLORS.get(symbol.tier, Color.WHITE)
	)
	percent_label.text = "%d%%" % roundi(probability * 100.0)
	value_label.text = "%s EACH" % NumberFormatter.currency(symbol.payout)
	var match_text := _format_payouts(payout_tier)
	if not match_text.is_empty():
		value_label.text += "   BONUS " + match_text


func _format_payouts(payout_tier: MetropolisPayoutTier) -> String:
	if payout_tier == null:
		return ""
	var counts := payout_tier.payouts_by_count.keys()
	counts.sort()
	var parts: Array[String] = []
	for count in counts:
		parts.append("%sx %s" % [count, NumberFormatter.currency(int(payout_tier.payouts_by_count[count]))])
	return "   ".join(parts)
