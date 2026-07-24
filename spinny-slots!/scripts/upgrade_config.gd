class_name UpgradeConfig
extends Resource

@export var upgrade_id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_range(1, 1000000, 1) var base_cost: int = 100
@export_range(1.0, 10.0, 0.01) var cost_growth: float = 1.55
@export_range(1, 100, 1) var max_level: int = 5
## The cap before Area 2 is unlocked. A value <= 0 uses max_level. This lets
## one persistent upgrade track continue growing in Metropolis without
## showing later-area levels during the Junkyard chapter.
@export_range(0, 100, 1) var max_level_before_metropolis: int = 0
## Optional cost for the first level beyond the Junkyard cap. Later extended
## levels grow from this value using cost_growth, independent of machine choice.
@export_range(0, 2147483647, 1) var metropolis_base_cost: int = 0
@export_range(0.0, 10.0, 0.001) var effect_per_level: float = 0.15
@export_multiline var tooltip: String = ""
## Legacy Metropolis per-machine pricing field retained for save/resource
## compatibility. Global upgrades now use base_cost and cost_growth everywhere.
@export_range(0.0, 100.0, 0.001) var cost_fraction_of_ticket: float = 0.0
