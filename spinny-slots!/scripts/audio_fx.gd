extends Node
## Central sound-effect and click-feedback autoload.
##
## - Plays a click sound and a small pointer burst once per button press
##   (buttons are hooked globally through `node_added`, so bubbling can
##   never double-fire).
## - Plays the coin-drop sound whenever GameState reports money actually
##   spent.
## - Owns the slot-machine spin sound. The spin presentation duration is
##   derived from the stream length so animation and audio always match:
##   the audio is sped up with `pitch_scale`, never cut off early.

const CLICK_STREAM: AudioStream = preload("res://assets/sounds/CLICK.ogg")
const COIN_STREAM: AudioStream = preload("res://assets/sounds/coin-drop-1.mp3")
const SPIN_STREAM: AudioStream = preload("res://assets/sounds/slotmachine.mp3")
# Spins never present faster than this, so the reels stay readable.
const MIN_SPIN_DURATION := 0.9
const CLICK_BURST_DURATION := 0.3
const CLICK_BURST_RADIUS := 26.0

var _click_player: AudioStreamPlayer
var _coin_player: AudioStreamPlayer
var _spin_player: AudioStreamPlayer
var _burst_layer: CanvasLayer
var _audio_cleaned_up := false


class ClickBurst:
	extends Control

	var progress := 0.0:
		set(value):
			progress = value
			queue_redraw()

	func _draw() -> void:
		var radius := AudioFx.CLICK_BURST_RADIUS * (0.35 + 0.65 * progress)
		var alpha := 1.0 - progress
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(1.0, 0.9, 0.35, alpha), 3.0, true)


func _ready() -> void:
	_click_player = _create_player(CLICK_STREAM)
	_coin_player = _create_player(COIN_STREAM)
	_spin_player = _create_player(SPIN_STREAM)
	_burst_layer = CanvasLayer.new()
	_burst_layer.layer = 120
	add_child(_burst_layer)
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.tree_exiting.connect(_cleanup_audio)
	_hook_buttons(get_tree().root)
	GameState.money_spent.connect(_on_money_spent)
	GameState.sfx_enabled_changed.connect(_on_sfx_enabled_changed)


func get_spin_stream_length() -> float:
	return SPIN_STREAM.get_length()


## Presentation length of one spin at the current spin-speed upgrade level.
func get_spin_duration() -> float:
	return get_spin_duration_for_multiplier(Economy.get_spin_speed_multiplier())


func get_spin_duration_for_multiplier(speed_multiplier: float) -> float:
	return maxf(get_spin_stream_length() / maxf(speed_multiplier, 0.01), MIN_SPIN_DURATION)


## Pitch that makes the spin audio finish exactly in get_spin_duration().
func get_spin_pitch() -> float:
	return get_spin_pitch_for_multiplier(Economy.get_spin_speed_multiplier())


func get_spin_pitch_for_multiplier(speed_multiplier: float) -> float:
	return get_spin_stream_length() / get_spin_duration_for_multiplier(speed_multiplier)


func play_spin(speed_multiplier: float = -1.0) -> void:
	if not GameState.sfx_enabled or DisplayServer.get_name() == "headless":
		return
	# play() restarts the shared player, so rapid spins can never overlap.
	_spin_player.pitch_scale = (
		get_spin_pitch()
		if speed_multiplier < 0.0
		else get_spin_pitch_for_multiplier(speed_multiplier)
	)
	_spin_player.play()


func stop_spin() -> void:
	_spin_player.stop()


func play_click() -> void:
	if not GameState.sfx_enabled or DisplayServer.get_name() == "headless":
		return
	_click_player.play()


func play_coin_drop() -> void:
	if not GameState.sfx_enabled or DisplayServer.get_name() == "headless":
		return
	_coin_player.play()


func _create_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)


func _hook_buttons(root: Node) -> void:
	if root is BaseButton:
		_hook_button(root)
	for child in root.get_children():
		_hook_buttons(child)


func _hook_button(button: BaseButton) -> void:
	if button.button_down.is_connected(_on_button_down):
		return
	button.button_down.connect(_on_button_down)


func _on_button_down() -> void:
	play_click()
	if GameState.sfx_enabled:
		_spawn_click_burst(get_viewport().get_mouse_position())


func _spawn_click_burst(position: Vector2) -> void:
	var burst := ClickBurst.new()
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.position = position
	_burst_layer.add_child(burst)
	var tween := burst.create_tween()
	tween.tween_property(burst, "progress", 1.0, CLICK_BURST_DURATION)
	tween.tween_callback(burst.queue_free)


func _on_money_spent(_amount: int) -> void:
	play_coin_drop()


func _on_sfx_enabled_changed(_enabled: bool) -> void:
	if not _enabled:
		_spin_player.stop()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if GameState.money_spent.is_connected(_on_money_spent):
		GameState.money_spent.disconnect(_on_money_spent)
	if GameState.sfx_enabled_changed.is_connected(_on_sfx_enabled_changed):
		GameState.sfx_enabled_changed.disconnect(_on_sfx_enabled_changed)
	_cleanup_audio()


func _cleanup_audio() -> void:
	if _audio_cleaned_up:
		return
	_audio_cleaned_up = true
	for player in [_click_player, _coin_player, _spin_player]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
