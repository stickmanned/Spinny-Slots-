extends CanvasLayer

signal activated
signal attention_pulse

const POP_UP_DURATION := 0.23
const POP_SETTLE_DURATION := 0.12
const WIGGLE_ANGLE := deg_to_rad(6.0)

@onready var phone_button: Button = %PhoneButton
@onready var badge: Label = %Badge

var _attention_tween: Tween
var _pop_tween: Tween
var _reduced_motion := false


func _ready() -> void:
	phone_button.pressed.connect(_activate)
	phone_button.visible = false
	phone_button.focus_mode = Control.FOCUS_ALL
	phone_button.resized.connect(_center_phone_pivot)
	_center_phone_pivot()


func show_notification(phone_texture: Texture2D, reduced_motion: bool, animate_pop: bool = true) -> void:
	_stop_tweens()
	_reduced_motion = reduced_motion
	phone_button.icon = phone_texture
	phone_button.disabled = false
	phone_button.visible = true
	phone_button.tooltip_text = "Answer phone"
	phone_button.rotation = 0.0
	badge.visible = true
	badge.modulate.a = 1.0
	badge.scale = Vector2.ONE
	_center_phone_pivot()
	if not animate_pop:
		phone_button.scale = Vector2.ONE
		_start_attention()
		return
	if _reduced_motion:
		phone_button.scale = Vector2.ONE
		badge.modulate.a = 0.0
		_pop_tween = create_tween()
		_pop_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_pop_tween.tween_property(badge, "modulate:a", 1.0, POP_SETTLE_DURATION)
		_pop_tween.tween_callback(_start_attention)
		return

	phone_button.scale = Vector2.ZERO
	_pop_tween = create_tween()
	_pop_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(phone_button, "scale", Vector2.ONE * 1.15, POP_UP_DURATION)
	_pop_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(phone_button, "scale", Vector2.ONE, POP_SETTLE_DURATION)
	_pop_tween.tween_callback(_start_attention)


func hide_notification() -> void:
	_stop_tweens()
	phone_button.disabled = true
	phone_button.visible = false
	phone_button.rotation = 0.0
	badge.visible = false


func show_idle(phone_texture: Texture2D) -> void:
	_stop_tweens()
	phone_button.icon = phone_texture
	phone_button.disabled = true
	phone_button.visible = true
	phone_button.scale = Vector2.ONE
	phone_button.rotation = 0.0
	phone_button.tooltip_text = "No new calls"
	badge.visible = false


func set_interactable(enabled: bool) -> void:
	phone_button.disabled = not enabled


func is_showing() -> bool:
	return phone_button.visible


func _unhandled_input(event: InputEvent) -> void:
	if (
		phone_button.visible
		and not phone_button.disabled
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_P
	):
		_activate()
		get_viewport().set_input_as_handled()


func _activate() -> void:
	if phone_button.disabled or not phone_button.visible:
		return
	phone_button.disabled = true
	_stop_tweens()
	badge.visible = false
	phone_button.rotation = 0.0
	activated.emit()

func _start_attention() -> void:
	if not phone_button.visible:
		return
	attention_pulse.emit()
	if _reduced_motion:
		_attention_tween = create_tween().set_loops()
		_attention_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_attention_tween.tween_property(badge, "scale", Vector2.ONE * 1.16, 0.22)
		_attention_tween.tween_property(badge, "scale", Vector2.ONE, 0.22)
		_attention_tween.tween_interval(0.65)
		return

	_attention_tween = create_tween().set_loops()
	_attention_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_attention_tween.tween_property(phone_button, "rotation", -WIGGLE_ANGLE, 0.1)
	_attention_tween.tween_property(phone_button, "rotation", WIGGLE_ANGLE, 0.2)
	_attention_tween.tween_property(phone_button, "rotation", 0.0, 0.1)
	_attention_tween.tween_interval(0.7)


func _stop_tweens() -> void:
	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()
	if _attention_tween and _attention_tween.is_valid():
		_attention_tween.kill()


func _center_phone_pivot() -> void:
	phone_button.pivot_offset = phone_button.size * 0.5
