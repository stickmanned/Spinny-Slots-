class_name UpgradeConfig
extends Resource

@export var upgrade_id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_range(1, 1000000, 1) var base_cost: int = 100
@export_range(1.0, 10.0, 0.01) var cost_growth: float = 1.55
@export_range(1, 100, 1) var max_level: int = 5
@export_range(0.0, 10.0, 0.001) var effect_per_level: float = 0.15
@export_multiline var tooltip: String = ""
## Metropolis-only: when > 0, the level-0 cost is this fraction of the owning
## machine's ticket price (then grown by cost_growth per level), so the same
## config scales sensibly across machines priced $10K to $2.5M. Junkyard leaves
## this 0 and uses the flat base_cost instead.
@export_range(0.0, 100.0, 0.001) var cost_fraction_of_ticket: float = 0.0
