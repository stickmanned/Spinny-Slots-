extends Control

signal bag_deposited(payout: int)
signal hud_hide_requested
signal hud_currency_show_requested(duration: float)

enum JobPhase {
	INTRO,
	TUTORIAL,
	PLAYING,
}

const BASE_VIEWPORT_HEIGHT := 720.0
const BAG_HIT_SIZE := Vector2(150.0, 190.0)
const DRAG_LIFT_SCALE := 1.06
const DRAG_LIFT_ROTATION := deg_to_rad(-2.0)
const DROP_DURATION := 0.22
const RETURN_DURATION := 0.24
const INTRO_FADE_DURATION := 0.26
const HUD_FADE_DURATION := 0.32
const TUTORIAL_FADE_IN_DURATION := 0.24
const TUTORIAL_FADE_OUT_DURATION := 0.4
const DAY_JOB_INTRO: Resource = preload("res://resources/dialogue/day_job_intro.tres")

@onready var dumpster: Node2D = $World/Dumpster
@onready var dumpster_sprite: Sprite2D = $World/Dumpster/DumpsterSprite
@onready var dumpster_highlight: Sprite2D = $World/Dumpster/DumpsterHighlight
@onready var drop_zone: Area2D = $World/Dumpster/DropZone
@onready var drop_shape: CollisionShape2D = $World/Dumpster/DropZone/DropShape
@onready var bag: Area2D = $World/TrashBag
@onready var bag_sprite: Sprite2D = $World/TrashBag/BagSprite
@onready var bag_shape: CollisionShape2D = $World/TrashBag/BagShape
@onready var hud: CanvasLayer = $Hud
@onready var tutorial_prompt: PanelContainer = %TutorialPrompt
@onready var dialogue_box: CanvasLayer = $DialogueBox

var _is_dragging := false
var _interaction_locked := false
var _bag_active := true
var _drag_enabled := false
var _grab_offset := Vector2.ZERO
var _ground_position := Vector2.ZERO
var _world_scale := 1.0
var _active_tween: Tween
var _tutorial_tween: Tween
var _phase := JobPhase.INTRO
var _music_player: AudioStreamPlayer = null


func _ready() -> void:
	set_process_input(true)
	resized.connect(_layout_world)
	drop_zone.area_entered.connect(_on_drop_zone_area_entered)
	drop_zone.area_exited.connect(_on_drop_zone_area_exited)
	dialogue_box.connect("finished", _on_intro_finished)
	bag_deposited.connect(_on_bag_deposited)
	hud_hide_requested.connect(Callable(hud, "hide_all"))
	hud_currency_show_requested.connect(Callable(hud, "show_currency"))
	_layout_world()
	_start_opening_sequence()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT and _is_dragging:
		_finish_drag(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _try_begin_drag(event.position):
				get_viewport().set_input_as_handled()
		elif _is_dragging:
			_finish_drag(_is_bag_in_drop_zone())
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_dragging:
		bag.global_position = event.position + _grab_offset
		_set_drop_highlight(_is_bag_in_drop_zone())
		get_viewport().set_input_as_handled()


func _try_begin_drag(mouse_position: Vector2) -> bool:
	if not _drag_enabled or _interaction_locked or not _bag_active or _is_dragging:
		return false

	var local_mouse := bag.to_local(mouse_position)
	var hit_rect := Rect2(-BAG_HIT_SIZE * 0.5, BAG_HIT_SIZE)
	if not hit_rect.has_point(local_mouse):
		return false

	_is_dragging = true
	_grab_offset = bag.global_position - mouse_position
	bag.z_index = 20
	bag.scale = Vector2.ONE * _world_scale * DRAG_LIFT_SCALE
	bag.rotation = DRAG_LIFT_ROTATION
	return true


func _finish_drag(valid_drop: bool) -> void:
	if not _is_dragging or _interaction_locked:
		return

	_is_dragging = false
	_interaction_locked = true
	_set_drop_highlight(false)
	if valid_drop:
		_complete_valid_drop()
	else:
		_return_bag_to_ground()


func _complete_valid_drop() -> void:
	_bag_active = false
	bag_shape.set_deferred("disabled", true)
	var payout := Economy.award_day_job_bag()
	_spawn_floating_reward(payout)
	bag_deposited.emit(payout)

	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(bag, "global_position", drop_zone.global_position, DROP_DURATION)
	_active_tween.tween_property(bag, "scale", Vector2.ONE * _world_scale * 0.58, DROP_DURATION)
	_active_tween.tween_property(bag, "rotation", deg_to_rad(8.0), DROP_DURATION)
	_active_tween.tween_property(bag_sprite, "modulate:a", 0.0, DROP_DURATION)
	await _active_tween.finished
	_spawn_next_bag()


func _return_bag_to_ground() -> void:
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(bag, "position", _ground_position, RETURN_DURATION)
	_active_tween.tween_property(bag, "scale", Vector2.ONE * _world_scale, RETURN_DURATION)
	_active_tween.tween_property(bag, "rotation", 0.0, RETURN_DURATION)
	await _active_tween.finished
	bag.z_index = 2
	_interaction_locked = false


func _spawn_next_bag() -> void:
	bag.position = _ground_position
	bag.scale = Vector2.ONE * _world_scale
	bag.rotation = 0.0
	bag.z_index = 2
	bag_sprite.modulate.a = 1.0
	bag_shape.set_deferred("disabled", false)
	_bag_active = true
	_interaction_locked = false


func _spawn_floating_reward(payout: int) -> void:
	var reward := Label.new()
	reward.text = "+$%d" % payout
	reward.custom_minimum_size = Vector2(160.0, 60.0)
	reward.position = dumpster.position + Vector2(-80.0, -155.0) * _world_scale
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_font_size_override("font_size", 38)
	reward.add_theme_color_override("font_color", Color(1.0, 0.88, 0.22))
	reward.add_theme_color_override("font_outline_color", Color.BLACK)
	reward.add_theme_constant_override("outline_size", 8)
	reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward.z_index = 8
	add_child(reward)

	var reward_tween := reward.create_tween().set_parallel(true)
	reward_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reward_tween.tween_property(reward, "position:y", reward.position.y - 78.0, 0.72)
	reward_tween.tween_property(reward, "modulate:a", 0.0, 0.72).set_delay(0.18)
	reward_tween.chain().tween_callback(reward.queue_free)


func _layout_world() -> void:
	if not is_node_ready():
		return

	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	_world_scale = clampf(viewport_size.y / BASE_VIEWPORT_HEIGHT, 1.0, 1.35)
	dumpster.position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.53)
	dumpster.scale = Vector2.ONE * _world_scale
	_ground_position = Vector2(viewport_size.x * 0.22, viewport_size.y * 0.78)
	if not _is_dragging and not _interaction_locked:
		bag.position = _ground_position
		bag.scale = Vector2.ONE * _world_scale


func _is_bag_in_drop_zone() -> bool:
	if not _bag_active:
		return false
	var bag_size := BAG_HIT_SIZE * bag.global_transform.get_scale().abs()
	var zone_shape := drop_shape.shape as RectangleShape2D
	var zone_size := zone_shape.size * drop_shape.global_transform.get_scale().abs()
	var bag_bounds := Rect2(bag_shape.global_position - bag_size * 0.5, bag_size)
	var zone_bounds := Rect2(drop_shape.global_position - zone_size * 0.5, zone_size)
	return bag_bounds.intersects(zone_bounds)


func _on_drop_zone_area_entered(area: Area2D) -> void:
	if area == bag and _is_dragging:
		_set_drop_highlight(true)


func _on_drop_zone_area_exited(area: Area2D) -> void:
	if area == bag:
		_set_drop_highlight(false)


func _set_drop_highlight(is_highlighted: bool) -> void:
	dumpster_highlight.visible = is_highlighted and _is_dragging
	dumpster_sprite.modulate = Color(1.08, 1.08, 0.92) if is_highlighted and _is_dragging else Color.WHITE


func _start_opening_sequence() -> void:
	hud_hide_requested.emit()
	if GameState.day_job_tutorial_completed:
		_enter_playing()
	elif GameState.day_job_intro_seen:
		_enter_tutorial()
	else:
		_enter_intro()


func _enter_intro() -> void:
	_phase = JobPhase.INTRO
	_drag_enabled = false
	dialogue_box.call("play", DAY_JOB_INTRO.get("lines"))


func _enter_tutorial() -> void:
	_phase = JobPhase.TUTORIAL
	_drag_enabled = true
	hud_currency_show_requested.emit(HUD_FADE_DURATION)
	_fade_tutorial_prompt(1.0, TUTORIAL_FADE_IN_DURATION)


func _enter_playing() -> void:
	_phase = JobPhase.PLAYING
	_drag_enabled = true
	hud_currency_show_requested.emit(HUD_FADE_DURATION)
	tutorial_prompt.modulate.a = 0.0
	_play_music()
	hud.show_settings_button()


func _on_intro_finished() -> void:
	if _phase != JobPhase.INTRO:
		return
	GameState.day_job_intro_seen = true
	dialogue_box.call("fade_out", INTRO_FADE_DURATION)
	_enter_tutorial()


func _on_bag_deposited(_payout: int) -> void:
	if _phase != JobPhase.TUTORIAL:
		return
	GameState.day_job_tutorial_completed = true
	_phase = JobPhase.PLAYING
	_fade_tutorial_prompt(0.0, TUTORIAL_FADE_OUT_DURATION)
	_play_music()
	hud.show_settings_button()


func _fade_tutorial_prompt(target_alpha: float, duration: float) -> void:
	if _tutorial_tween and _tutorial_tween.is_valid():
		_tutorial_tween.kill()
	_tutorial_tween = create_tween()
	_tutorial_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tutorial_tween.tween_property(tutorial_prompt, "modulate:a", target_alpha, duration)


func _play_music() -> void:
	if _music_player and _music_player.playing:
		return
	if not _music_player:
		_music_player = AudioStreamPlayer.new()
		var stream = load("res://music/Spinny Slots! Music - 001 - (Official) Tower Defense Simulator OST - Never Broke Again.mp3") as AudioStreamMP3
		if stream:
			stream.loop = true
			_music_player.stream = stream
		_music_player.volume_db = linear_to_db(GameState.music_volume)
		add_child(_music_player)
		
		GameState.music_volume_changed.connect(func(vol: float) -> void:
			if _music_player:
				_music_player.volume_db = linear_to_db(vol)
		)
	_music_player.play()
