class_name MetropolisPayoutTier
extends Resource

## One symbol tier's payout curve for a Metropolis machine. 3-reel machines
## only ever populate the "3" entry (3-of-a-kind is the only win shape);
## Wider machines populate each paying count through their configured reel
## count. Keeping this sparse lets one resource type serve all machine shapes.

@export var tier: MetropolisSymbol.Tier = MetropolisSymbol.Tier.COMMON
## Keys are match counts as strings ("3", "4", "5"); values are the coin
## payout for landing that many matching symbols of this tier in one spin.
@export var payouts_by_count: Dictionary = {}


func get_payout(match_count: int) -> int:
	return int(payouts_by_count.get(str(match_count), 0))
