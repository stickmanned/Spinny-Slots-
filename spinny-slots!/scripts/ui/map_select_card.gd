extends Button

signal map_selected(map_id: String)

@onready var background_rect: TextureRect = $BackgroundRect
@onready var fallback_rect: ColorRect = $FallbackRect
@onready var name_label: Label = $NameLabel
@onready var lock_overlay: ColorRect = $LockOverlay
@onready var lock_label: Label = $LockOverlay/LockLabel
@onready var current_overlay: ColorRect = $CurrentOverlay

var _map_id: String
var _is_unlocked: bool
var _is_current: bool

func configure(config: Dictionary, current_map_id: String) -> void:
	_map_id = config["id"]
	_is_unlocked = config.get("is_unlocked", true)
	_is_current = (_map_id == current_map_id)
	
	name_label.text = config["name"]
	
	var bg_path: String = config.get("background_path", "")
	if bg_path != "":
		background_rect.texture = load(bg_path)
		background_rect.visible = true
		fallback_rect.visible = false
	else:
		background_rect.visible = false
		fallback_rect.visible = true
	
	if _is_current:
		current_overlay.visible = true
		lock_overlay.visible = false
		disabled = false # Needs to be focusable for keyboard nav, we handle block in _on_pressed
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	elif not _is_unlocked:
		lock_overlay.visible = true
		lock_label.text = "LOCKED\n" + config.get("unlock_requirement", "")
		current_overlay.visible = false
		disabled = false # We keep it enabled so we can catch clicks and show locked anim
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		lock_overlay.visible = false
		current_overlay.visible = false
		disabled = false
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _ready() -> void:
	pressed.connect(_on_pressed)
	ButtonHover.attach(self, Vector2(1.04, 1.04))

func _on_pressed() -> void:
	if _is_current:
		# Just jiggle or ignore
		return
		
	if not _is_unlocked:
		_play_locked_animation()
		return
		
	map_selected.emit(_map_id)

func _play_locked_animation() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var original_x = position.x
	tween.tween_property(self, "position:x", original_x + 10, 0.05)
	tween.tween_property(self, "position:x", original_x - 10, 0.1)
	tween.tween_property(self, "position:x", original_x, 0.05)
