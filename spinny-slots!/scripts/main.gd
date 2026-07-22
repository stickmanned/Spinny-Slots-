extends Node

const JUNKYARD_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const JUNK_KING_BATTLE_SCENE: PackedScene = preload("res://scenes/junk_king_battle.tscn")
const METROPOLIS_JOB_SCENE: PackedScene = preload("res://scenes/metropolis_job.tscn")
const TRANSITION_DURATION := 0.24

@onready var scene_host: Node = $SceneHost
@onready var fade: ColorRect = %Fade

var _current_scene: Node = null
var _transitioning := false
var _transition_tween: Tween = null


func _ready() -> void:
	_swap_scene(JUNKYARD_SCENE)
	fade.color.a = 1.0
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(0.0, TRANSITION_DURATION)
	if is_inside_tree() and not _transitioning:
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _transition_to(scene: PackedScene) -> void:
	if _transitioning or scene == null:
		return
	_transitioning = true
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, 0.12 if GameState.reduced_motion else TRANSITION_DURATION)
	if not is_inside_tree():
		return
	_swap_scene(scene)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await _fade_to(0.0, 0.12 if GameState.reduced_motion else TRANSITION_DURATION)
	if not is_inside_tree():
		return
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false


func _fade_to(target_alpha: float, duration: float) -> Signal:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN if target_alpha > fade.color.a else Tween.EASE_OUT
	)
	_transition_tween.tween_property(fade, "color:a", target_alpha, duration)
	return _transition_tween.finished


func _swap_scene(scene: PackedScene) -> void:
	if is_instance_valid(_current_scene):
		scene_host.remove_child(_current_scene)
		_current_scene.queue_free()
	_current_scene = scene.instantiate()
	scene_host.add_child(_current_scene)
	_connect_navigation(_current_scene)


func _connect_navigation(scene: Node) -> void:
	if scene.has_signal("junk_king_challenge_confirmed"):
		scene.connect("junk_king_challenge_confirmed", _on_junk_king_challenge_confirmed)
	if scene.has_signal("map_requested"):
		scene.connect("map_requested", _on_map_requested)
	# The Junk King battle's victory/defeat popup navigates through its own
	# dedicated signals rather than map_requested; without these connections
	# the RETURN TO JUNKYARD / VISIT METROPOLIS buttons emit into the void.
	if scene.has_signal("return_to_junkyard_requested"):
		scene.connect("return_to_junkyard_requested", _on_return_to_junkyard_requested)
	if scene.has_signal("metropolis_requested"):
		scene.connect("metropolis_requested", _on_metropolis_requested)


func _on_junk_king_challenge_confirmed() -> void:
	_transition_to(JUNK_KING_BATTLE_SCENE)


func _on_return_to_junkyard_requested() -> void:
	_transition_to(JUNKYARD_SCENE)


func _on_metropolis_requested() -> void:
	_transition_to(METROPOLIS_JOB_SCENE)


func _on_map_requested(map_id: String) -> void:
	if map_id == "metropolis" and GameState.metropolis_unlocked:
		_transition_to(METROPOLIS_JOB_SCENE)
	elif map_id == "junkyard":
		_transition_to(JUNKYARD_SCENE)


func _exit_tree() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
