class_name CoinCollectionEffect
extends Control

signal balance_progressed(value: int)
signal balance_pulse_requested
signal coin_sound_requested
signal coin_spawned(start_position: Vector2, target_position: Vector2)
signal collection_finished

const COIN_TEXTURE: Texture2D = preload("res://assets/art/ui/game_gui/coin_icon.png")
const MIN_VISUAL_COINS := 4
const MAX_VISUAL_COINS := 12
const BURST_DURATION := 0.16
const ARC_DURATION := 0.2
const ARRIVAL_DURATION := 0.24
const STAGGER_DURATION := 0.035
const REDUCED_MOTION_DURATION := 0.16

var _active_collection_id := 0
var _arrived_coin_ids: Dictionary = {}
var _arrival_count := 0
var _visual_coin_count := 0
var _start_balance := 0
var _payout := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func get_visual_coin_count(payout: int) -> int:
	if payout <= 0:
		return 0
	# Logarithmic growth keeps a small win lively without letting jackpots
	# create an unbounded number of Controls and Tweens.
	var proportional_count := 4 + floori(log(float(payout) + 1.0) / log(2.0))
	return clampi(proportional_count, MIN_VISUAL_COINS, MAX_VISUAL_COINS)


static func get_max_duration() -> float:
	return BURST_DURATION + ARC_DURATION + ARRIVAL_DURATION + STAGGER_DURATION * float(MAX_VISUAL_COINS - 1) + 0.02


func play(
	payout: int,
	start_balance: int,
	source: Control,
	target: Control,
	reduced_motion: bool
) -> void:
	_cancel_active_collection()
	if payout <= 0 or not is_instance_valid(source) or not is_instance_valid(target):
		return

	_active_collection_id += 1
	var collection_id := _active_collection_id
	_start_balance = start_balance
	_payout = payout
	_arrival_count = 0
	_arrived_coin_ids.clear()

	if reduced_motion:
		balance_progressed.emit(start_balance + payout)
		balance_pulse_requested.emit()
		coin_sound_requested.emit()
		await get_tree().create_timer(REDUCED_MOTION_DURATION).timeout
		if collection_id == _active_collection_id:
			collection_finished.emit()
			_arrived_coin_ids.clear()
			_visual_coin_count = 0
		return

	_visual_coin_count = get_visual_coin_count(payout)
	var source_center := source.get_global_rect().get_center()
	var target_center := target.get_global_rect().get_center()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ payout
	for coin_id in range(_visual_coin_count):
		_spawn_coin(coin_id, collection_id, source_center, target_center, rng)

	await collection_finished
	if collection_id == _active_collection_id:
		_arrived_coin_ids.clear()
		_visual_coin_count = 0


func _spawn_coin(
	coin_id: int,
	collection_id: int,
	source_center: Vector2,
	target_center: Vector2,
	rng: RandomNumberGenerator
) -> void:
	var coin := TextureRect.new()
	coin.name = "Coin%d" % coin_id
	coin.texture = COIN_TEXTURE
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.z_index = 1
	var coin_size := rng.randf_range(26.0, 38.0)
	coin.size = Vector2.ONE * coin_size
	coin.pivot_offset = coin.size * 0.5
	var start_center := source_center + Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-5.0, 7.0))
	coin.position = start_center - coin.size * 0.5
	coin.scale = Vector2.ONE * rng.randf_range(0.72, 1.02)
	coin.rotation = rng.randf_range(-0.45, 0.45)
	add_child(coin)
	coin_spawned.emit(start_center, target_center)

	var burst_angle := rng.randf_range(-PI * 0.88, -PI * 0.12)
	var burst_distance := rng.randf_range(42.0, 88.0)
	var burst_center := start_center + Vector2.from_angle(burst_angle) * burst_distance
	var direct_vector := target_center - burst_center
	var perpendicular := direct_vector.normalized().orthogonal()
	var arc_center := burst_center.lerp(target_center, rng.randf_range(0.4, 0.58))
	arc_center += perpendicular * rng.randf_range(-72.0, 72.0)
	var target_position := target_center - coin.size * 0.5
	var delay := float(coin_id) * STAGGER_DURATION + rng.randf_range(0.0, 0.018)
	var spin_rotation := coin.rotation + rng.randf_range(1.25, 2.25) * TAU

	var tween := coin.create_tween()
	tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(coin, "position", burst_center - coin.size * 0.5, BURST_DURATION)
	tween.tween_property(coin, "scale", Vector2.ONE * rng.randf_range(0.92, 1.16), BURST_DURATION)
	tween.tween_property(coin, "rotation", spin_rotation * 0.35, BURST_DURATION)
	tween.chain().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(coin, "position", arc_center - coin.size * 0.5, ARC_DURATION)
	tween.parallel().tween_property(coin, "rotation", spin_rotation * 0.72, ARC_DURATION)
	tween.chain().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(coin, "position", target_position, ARRIVAL_DURATION)
	tween.parallel().tween_property(coin, "scale", Vector2.ONE * 0.62, ARRIVAL_DURATION)
	tween.parallel().tween_property(coin, "rotation", spin_rotation, ARRIVAL_DURATION)
	tween.tween_callback(_on_coin_arrived.bind(coin_id, collection_id, coin))


func _on_coin_arrived(coin_id: int, collection_id: int, coin: TextureRect) -> void:
	if collection_id != _active_collection_id or _arrived_coin_ids.has(coin_id):
		return
	_arrived_coin_ids[coin_id] = true
	_arrival_count += 1
	if is_instance_valid(coin):
		coin.queue_free()

	var presented_balance := _start_balance + floori(float(_payout) * float(_arrival_count) / float(_visual_coin_count))
	if _arrival_count == _visual_coin_count:
		presented_balance = _start_balance + _payout
	balance_progressed.emit(presented_balance)
	balance_pulse_requested.emit()
	var sound_stride := maxi(1, ceili(float(_visual_coin_count) / 3.0))
	if _arrival_count == 1 or _arrival_count == _visual_coin_count or _arrival_count % sound_stride == 0:
		coin_sound_requested.emit()
	if _arrival_count == _visual_coin_count:
		collection_finished.emit()


func _cancel_active_collection() -> void:
	_active_collection_id += 1
	for child in get_children():
		child.queue_free()
	_arrived_coin_ids.clear()
	_arrival_count = 0
	_visual_coin_count = 0
