class_name JunkKingPresence
extends Control

signal activated
signal arrival_completed

const ART_ASPECT_RATIO := 1354.0 / 1133.0
const MIN_SAFE_MARGIN := 10.0
const MAX_SAFE_MARGIN := 18.0
const MIN_DESIRED_WIDTH := 132.0
const MAX_DESIRED_WIDTH := 218.0
const ARRIVAL_DURATION := 0.78
const ARRIVAL_SETTLE_DURATION := 0.13
const REDUCED_ARRIVAL_DURATION := 0.28
const ROCK_ANGLE := deg_to_rad(2.0)
const GLOW_SCALE := Vector2(1.055, 1.055)
const STANDARD_GLOW_MIN_ALPHA := 0.08
const STANDARD_GLOW_MAX_ALPHA := 0.24
const REDUCED_GLOW_MIN_ALPHA := 0.07
const REDUCED_GLOW_MAX_ALPHA := 0.2

@onready var layout_slot: Control = %LayoutSlot
@onready var visual_root: Control = %VisualRoot
@onready var glow: TextureRect = %Glow
@onready var presence_button: Button = %PresenceButton

var _left_boundary_control: Control = null
var _cabinet_control: Control = null
var _left_arrow_control: Control = null
var _arrival_tween: Tween = null
var _idle_tween: Tween = null
var _glow_tween: Tween = null
var _layout_queued := false
var _activation_locked := true
var _reduced_motion := false
var _animation_generation := 0


func _ready() -> void:
	presence_button.pressed.connect(_activate)
	presence_button.focus_mode = Control.FOCUS_ALL
	presence_button.tooltip_text = "Challenge the Junk King"
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	visible = false
	_reset_visual_transform()


func configure_layout(
	left_boundary_control: Control,
	cabinet_control: Control,
	left_arrow_control: Control
) -> void:
	_disconnect_layout_sources()
	_left_boundary_control = left_boundary_control
	_cabinet_control = cabinet_control
	_left_arrow_control = left_arrow_control
	_connect_layout_source(_left_boundary_control)
	_connect_layout_source(_cabinet_control)
	_connect_layout_source(_left_arrow_control)
	_queue_layout()


func show_arrival(reduced_motion: bool, animate: bool = true) -> void:
	_animation_generation += 1
	var generation := _animation_generation
	_stop_tweens()
	_reduced_motion = reduced_motion
	visible = true
	_activation_locked = true
	presence_button.disabled = true
	_apply_responsive_layout()
	_reset_visual_transform()

	if not animate:
		_finish_arrival(generation)
		return

	if _reduced_motion:
		visual_root.modulate.a = 0.0
		glow.modulate.a = 0.0
		_arrival_tween = create_tween().set_parallel(true)
		_arrival_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_arrival_tween.tween_property(visual_root, "modulate:a", 1.0, REDUCED_ARRIVAL_DURATION)
		_arrival_tween.tween_property(glow, "modulate:a", REDUCED_GLOW_MIN_ALPHA, REDUCED_ARRIVAL_DURATION)
		_arrival_tween.chain().tween_callback(_finish_arrival.bind(generation))
		return

	var viewport_size := get_viewport_rect().size
	var flight_distance := maxf(viewport_size.x * 0.22, layout_slot.size.x * 1.6)
	var flight_lift := maxf(viewport_size.y * 0.2, layout_slot.size.y * 1.25)
	visual_root.position = Vector2(-flight_distance, -flight_lift)
	visual_root.scale = Vector2.ONE * 0.82
	visual_root.rotation = deg_to_rad(-8.0)
	visual_root.modulate.a = 0.12
	_arrival_tween = create_tween().set_parallel(true)
	_arrival_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_arrival_tween.tween_property(visual_root, "position", Vector2.ZERO, ARRIVAL_DURATION)
	_arrival_tween.tween_property(visual_root, "scale", Vector2.ONE, ARRIVAL_DURATION)
	_arrival_tween.tween_property(visual_root, "rotation", 0.0, ARRIVAL_DURATION)
	_arrival_tween.tween_property(visual_root, "modulate:a", 1.0, ARRIVAL_DURATION * 0.72)
	_arrival_tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_arrival_tween.tween_property(visual_root, "scale", Vector2.ONE * 1.035, ARRIVAL_SETTLE_DURATION)
	_arrival_tween.chain().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_arrival_tween.tween_property(visual_root, "scale", Vector2.ONE, ARRIVAL_SETTLE_DURATION)
	_arrival_tween.chain().tween_callback(_finish_arrival.bind(generation))


func show_idle(reduced_motion: bool) -> void:
	_animation_generation += 1
	_stop_tweens()
	_reduced_motion = reduced_motion
	visible = true
	_apply_responsive_layout()
	_reset_visual_transform()
	set_interactable(true)
	_start_idle_animation()


func hide_presence() -> void:
	_animation_generation += 1
	_stop_tweens()
	_activation_locked = true
	presence_button.disabled = true
	presence_button.release_focus()
	visible = false
	_reset_visual_transform()


func disable_presence() -> void:
	set_interactable(false)


func set_interactable(enabled: bool) -> void:
	var can_interact := enabled and visible
	presence_button.disabled = not can_interact
	_activation_locked = not can_interact
	if not can_interact:
		presence_button.release_focus()


func grab_keyboard_focus() -> void:
	if visible and not presence_button.disabled:
		presence_button.grab_focus()


func is_showing() -> bool:
	return visible


func get_presence_global_rect() -> Rect2:
	return layout_slot.get_global_rect()


func _activate() -> void:
	if _activation_locked or presence_button.disabled or not visible:
		return
	_activation_locked = true
	presence_button.disabled = true
	presence_button.release_focus()
	activated.emit()


func _finish_arrival(generation: int) -> void:
	if generation != _animation_generation or not visible:
		return
	_arrival_tween = null
	_reset_visual_transform()
	set_interactable(true)
	_start_idle_animation()
	arrival_completed.emit()


func _start_idle_animation() -> void:
	_stop_idle_tweens()
	visual_root.position = Vector2.ZERO
	visual_root.scale = Vector2.ONE
	visual_root.rotation = 0.0
	visual_root.modulate.a = 1.0
	glow.scale = GLOW_SCALE

	if not _reduced_motion:
		_idle_tween = create_tween().set_loops()
		_idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_idle_tween.tween_property(visual_root, "rotation", ROCK_ANGLE, 1.25)
		_idle_tween.tween_property(visual_root, "rotation", -ROCK_ANGLE, 2.5)
		_idle_tween.tween_property(visual_root, "rotation", 0.0, 1.25)
		_idle_tween.tween_interval(0.35)

	var minimum_alpha := REDUCED_GLOW_MIN_ALPHA if _reduced_motion else STANDARD_GLOW_MIN_ALPHA
	var maximum_alpha := REDUCED_GLOW_MAX_ALPHA if _reduced_motion else STANDARD_GLOW_MAX_ALPHA
	var pulse_duration := 1.65 if _reduced_motion else 1.15
	glow.modulate.a = minimum_alpha
	_glow_tween = create_tween().set_loops()
	_glow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(glow, "modulate:a", maximum_alpha, pulse_duration)
	_glow_tween.parallel().tween_property(glow, "scale", GLOW_SCALE * 1.025, pulse_duration)
	_glow_tween.tween_property(glow, "modulate:a", minimum_alpha, pulse_duration)
	_glow_tween.parallel().tween_property(glow, "scale", GLOW_SCALE, pulse_duration)
	_glow_tween.tween_interval(0.4 if _reduced_motion else 0.2)


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_queued = false
	if not is_node_ready():
		return
	var target_rect := _calculate_final_global_rect()
	var inverse_transform := get_global_transform().affine_inverse()
	var local_top_left: Vector2 = inverse_transform * target_rect.position
	var local_bottom_right: Vector2 = inverse_transform * target_rect.end
	layout_slot.position = local_top_left
	layout_slot.size = Vector2(
		absf(local_bottom_right.x - local_top_left.x),
		absf(local_bottom_right.y - local_top_left.y)
	)
	visual_root.pivot_offset = layout_slot.size * 0.5
	glow.pivot_offset = glow.size * 0.5
	presence_button.pivot_offset = presence_button.size * 0.5


func _calculate_final_global_rect() -> Rect2:
	var root_rect := get_global_rect()
	var viewport_size := get_viewport_rect().size
	var viewport_rect := Rect2(root_rect.position, viewport_size)
	if root_rect.size.x > 0.0 and root_rect.size.y > 0.0:
		viewport_rect.size = root_rect.size

	var short_side := minf(viewport_rect.size.x, viewport_rect.size.y)
	var margin := clampf(short_side * 0.018, MIN_SAFE_MARGIN, MAX_SAFE_MARGIN)
	var desired_width := clampf(viewport_rect.size.x * 0.14, MIN_DESIRED_WIDTH, MAX_DESIRED_WIDTH)

	if not _has_valid_layout_sources():
		var fallback_height := desired_width / ART_ASPECT_RATIO
		return Rect2(
			viewport_rect.position + Vector2(margin, margin),
			Vector2(desired_width, fallback_height)
		)

	var boundary_rect := _left_boundary_control.get_global_rect()
	var cabinet_rect := _cabinet_control.get_global_rect()
	var arrow_rect := _left_arrow_control.get_global_rect()
	var safe_left := viewport_rect.position.x + margin
	var safe_right := viewport_rect.end.x - margin
	var safe_top := viewport_rect.position.y + margin
	var corridor_left := maxf(safe_left, boundary_rect.end.x + margin)
	var corridor_right := minf(safe_right, cabinet_rect.position.x - margin)
	var available_width := maxf(corridor_right - corridor_left, 0.0)
	var target_bottom := minf(arrow_rect.position.y - margin, viewport_rect.end.y - margin)
	var available_height := maxf(target_bottom - safe_top, 0.0)
	var width := minf(desired_width, available_width)
	width = minf(width, available_height * ART_ASPECT_RATIO)

	if width <= 0.0:
		return Rect2(Vector2(corridor_left, safe_top), Vector2.ZERO)

	var height := width / ART_ASPECT_RATIO
	var desired_x := arrow_rect.get_center().x - width * 0.5
	var maximum_x := corridor_right - width
	var target_x := clampf(desired_x, corridor_left, maximum_x)
	var target_y := maxf(target_bottom - height, safe_top)
	var result := Rect2(Vector2(target_x, target_y), Vector2(width, height))

	# The arrow may be scaled briefly for hover feedback. The shared margin is
	# intentionally larger than that transform, and this final guard keeps its
	# input rectangle clear even if a caller supplies a differently sized arrow.
	if result.intersects(arrow_rect):
		result.position.y = arrow_rect.position.y - margin - result.size.y
	return result


func _has_valid_layout_sources() -> bool:
	return (
		is_instance_valid(_left_boundary_control)
		and is_instance_valid(_cabinet_control)
		and is_instance_valid(_left_arrow_control)
	)


func _connect_layout_source(control: Control) -> void:
	if not is_instance_valid(control):
		return
	if not control.resized.is_connected(_queue_layout):
		control.resized.connect(_queue_layout)


func _disconnect_layout_sources() -> void:
	var controls: Array[Control] = []
	if is_instance_valid(_left_boundary_control):
		controls.append(_left_boundary_control)
	if is_instance_valid(_cabinet_control):
		controls.append(_cabinet_control)
	if is_instance_valid(_left_arrow_control):
		controls.append(_left_arrow_control)
	for control in controls:
		if control.resized.is_connected(_queue_layout):
			control.resized.disconnect(_queue_layout)


func _reset_visual_transform() -> void:
	if not is_node_ready():
		return
	visual_root.position = Vector2.ZERO
	visual_root.scale = Vector2.ONE
	visual_root.rotation = 0.0
	visual_root.modulate = Color.WHITE
	glow.scale = GLOW_SCALE
	glow.modulate = Color(1.0, 0.82, 0.28, STANDARD_GLOW_MIN_ALPHA)


func _stop_idle_tweens() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_idle_tween = null
	_glow_tween = null


func _stop_tweens() -> void:
	if _arrival_tween != null and _arrival_tween.is_valid():
		_arrival_tween.kill()
	_arrival_tween = null
	_stop_idle_tweens()


func _exit_tree() -> void:
	_stop_tweens()
	_disconnect_layout_sources()
