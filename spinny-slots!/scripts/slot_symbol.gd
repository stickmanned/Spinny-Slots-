class_name SlotSymbol
extends Resource

@export var symbol_id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_range(1, 1000000, 1) var payout: int = 1
@export_range(0.0, 100.0, 0.01) var weight: float = 1.0
