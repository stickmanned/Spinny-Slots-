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
