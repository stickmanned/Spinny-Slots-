class_name MachineDefinition
extends Resource

@export var machine_id: StringName
@export var display_name: String
@export_range(1, 1000000, 1) var ticket_price: int = 1
@export var ticket_texture: Texture2D
@export var cabinet_texture: Texture2D
@export var machine_scene_path: String = "res://scenes/machine_screen.tscn"
@export var symbols: Array[SlotSymbol] = []
@export var screen_region: Rect2 = Rect2()
## Gems awarded per landed copy of this machine's rarest (lowest-weight)
## symbol. Higher-tier machines should award more.
@export_range(0, 1000, 1) var rarest_symbol_gem_reward: int = 0
