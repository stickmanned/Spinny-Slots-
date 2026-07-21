extends Control

signal map_requested(map_id: String)

@onready var content: Control = %Content
@onready var back_button: Button = %BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	content.pivot_offset = content.size * 0.5
	if GameState.reduced_motion:
		content.modulate.a = 1.0
		return
	content.modulate.a = 0.0
	content.scale = Vector2.ONE * 0.96
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(content, "modulate:a", 1.0, 0.28)
	tween.tween_property(content, "scale", Vector2.ONE, 0.34)


func _on_back_pressed() -> void:
	back_button.disabled = true
	map_requested.emit("junkyard")
