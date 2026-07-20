class_name ConfettiEffect
extends Control
## Celebrates landing a machine's rarest symbol: simple rectangles rain down
## in alternating rainbow colors, then fade out and clean themselves up.

signal finished

const PIECE_COUNT := 46
const RAINBOW_COLORS: Array[Color] = [
	Color(0.95, 0.25, 0.25),
	Color(0.98, 0.55, 0.15),
	Color(0.98, 0.85, 0.15),
	Color(0.30, 0.80, 0.35),
	Color(0.25, 0.55, 0.95),
	Color(0.60, 0.35, 0.90),
]
const PIECE_MIN_SIZE := Vector2(6.0, 12.0)
const PIECE_MAX_SIZE := Vector2(11.0, 20.0)
const FALL_DURATION_MIN := 1.05
const FALL_DURATION_MAX := 1.75
const FADE_DURATION := 0.18
const SPAWN_WINDOW := 0.45
const REDUCED_MOTION_DURATION := 0.5

var _active_burst_id := 0
var _pieces_remaining := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func get_max_duration() -> float:
	return SPAWN_WINDOW + FALL_DURATION_MAX + FADE_DURATION + 0.02


## Rains PIECE_COUNT rectangles across the full width of this Control, each
## colored from a cycling rainbow palette, then frees them once they land.
func play(reduced_motion: bool = false) -> void:
	_active_burst_id += 1
	var burst_id := _active_burst_id
	for child in get_children():
		child.queue_free()

	if reduced_motion:
		await get_tree().create_timer(REDUCED_MOTION_DURATION).timeout
		if burst_id == _active_burst_id:
			finished.emit()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	_pieces_remaining = PIECE_COUNT
	for index in range(PIECE_COUNT):
		_spawn_piece(index, burst_id, rng)


func _spawn_piece(index: int, burst_id: int, rng: RandomNumberGenerator) -> void:
	var piece := ColorRect.new()
	piece.name = "Confetti%d" % index
	# Adjacent pieces cycle through the palette so the rain reads as
	# alternating rainbow colors rather than random noise.
	piece.color = RAINBOW_COLORS[index % RAINBOW_COLORS.size()]
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var piece_size := Vector2(
		rng.randf_range(PIECE_MIN_SIZE.x, PIECE_MAX_SIZE.x),
		rng.randf_range(PIECE_MIN_SIZE.y, PIECE_MAX_SIZE.y)
	)
	piece.size = piece_size
	piece.pivot_offset = piece_size * 0.5
	var start_x := rng.randf_range(0.0, maxf(size.x - piece_size.x, 0.0))
	piece.position = Vector2(start_x, -piece_size.y - rng.randf_range(0.0, 60.0))
	piece.rotation = rng.randf_range(0.0, TAU)
	add_child(piece)

	var fall_duration := rng.randf_range(FALL_DURATION_MIN, FALL_DURATION_MAX)
	var drift := rng.randf_range(-70.0, 70.0)
	var spawn_delay := rng.randf_range(0.0, SPAWN_WINDOW)
	var spin_amount := rng.randf_range(2.0, 5.0) * TAU * (1.0 if rng.randf() < 0.5 else -1.0)
	var target_y := size.y + piece_size.y + 40.0

	var tween := piece.create_tween()
	tween.tween_interval(spawn_delay)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(piece, "position:y", target_y, fall_duration)
	tween.tween_property(piece, "position:x", piece.position.x + drift, fall_duration)
	tween.tween_property(piece, "rotation", piece.rotation + spin_amount, fall_duration)
	tween.chain().tween_property(piece, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(_on_piece_landed.bind(burst_id, piece))


func _on_piece_landed(burst_id: int, piece: ColorRect) -> void:
	if is_instance_valid(piece):
		piece.queue_free()
	if burst_id != _active_burst_id:
		return
	_pieces_remaining -= 1
	if _pieces_remaining <= 0:
		finished.emit()
