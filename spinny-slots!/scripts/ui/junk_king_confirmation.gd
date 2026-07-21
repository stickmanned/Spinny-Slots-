extends CanvasLayer

signal accepted
signal declined

@onready var modal_root: Control = %ModalRoot
@onready var prompt_panel: PanelContainer = %PromptPanel
@onready var yes_button: Button = %YesButton
@onready var no_button: Button = %NoButton

var _is_open := false
var _choice_locked := false
var _tween: Tween


func _ready() -> void:
	yes_button.pressed.connect(_accept)
	no_button.pressed.connect(_decline)
	ButtonHover.attach(yes_button)
	ButtonHover.attach(no_button)
	modal_root.visible = false


func open() -> bool:
	if _is_open:
		return false
	_is_open = true
	_choice_locked = false
	modal_root.visible = true
	yes_button.disabled = false
	no_button.disabled = false
	prompt_panel.pivot_offset = prompt_panel.size * 0.5
	if _tween and _tween.is_valid():
		_tween.kill()
	if GameState.reduced_motion:
		prompt_panel.scale = Vector2.ONE
		prompt_panel.modulate.a = 1.0
	else:
		prompt_panel.scale = Vector2.ONE * 0.94
		prompt_panel.modulate.a = 0.0
		_tween = create_tween().set_parallel()
		_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(prompt_panel, "scale", Vector2.ONE, 0.2)
		_tween.set_trans(Tween.TRANS_QUAD)
		_tween.tween_property(prompt_panel, "modulate:a", 1.0, 0.16)
	yes_button.grab_focus()
	return true


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_choice_locked = true
	if _tween and _tween.is_valid():
		_tween.kill()
	modal_root.visible = false


func is_open() -> bool:
	return _is_open


func _accept() -> void:
	if not _lock_choice():
		return
	accepted.emit()


func _decline() -> void:
	if not _lock_choice():
		return
	declined.emit()


func _lock_choice() -> bool:
	if not _is_open or _choice_locked:
		return false
	_choice_locked = true
	yes_button.disabled = true
	no_button.disabled = true
	return true
