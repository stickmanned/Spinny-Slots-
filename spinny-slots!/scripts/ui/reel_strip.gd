extends Control

const SHUFFLE_INTERVAL := 0.06
const BLINK_INTERVAL := 0.09
const BLINK_COUNT := 3
const ICON_OVERSCAN_SCALE := 1.55
const SUPERPOSITION_SHIMMER_INTERVAL := 0.12

var _windows: Array[Control] = []
var _icons: Array[TextureRect] = []
## One faint offset copy per reel, used only for the Quantum Vault
## Superposition collapse; stays fully transparent on every other machine.
var _ghosts: Array[TextureRect] = []
var _superposition_tweens: Array[Tween] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		if child is Control and child.get_child_count() == 1 and child.get_child(0) is TextureRect:
			_windows.append(child)
			_icons.append(child.get_child(0) as TextureRect)
	for window in _windows:
		var ghost := TextureRect.new()
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ghost.modulate.a = 0.0
		window.add_child(ghost)
		_ghosts.append(ghost)
	resized.connect(_layout_windows)
	_layout_windows()


func get_spin_total_duration(duration: float) -> float:
	return duration + get_blink_duration()


func get_blink_duration() -> float:
	return BLINK_COUNT * 2.0 * BLINK_INTERVAL


func set_static_icon(icon: Texture2D) -> void:
	for reel_icon in _icons:
		reel_icon.texture = icon


func set_idle_symbols(icons: Array[Texture2D]) -> void:
	if icons.is_empty():
		return
	for index in range(_icons.size()):
		_icons[index].texture = icons[index % icons.size()]
		_icons[index].modulate.a = 1.0


## superposition_flags marks reels whose predetermined result is the
## Superposition Symbol (Quantum Vault). Those reels render a shimmering
## double-exposure during the spin and collapse onto the single settled symbol
## when they stop. The result itself is fixed before this is ever called — this
## is presentation only and never chooses or alters a symbol.
func play_spin(
	result_icons: Array[Texture2D],
	pool_icons: Array[Texture2D],
	duration: float,
	reduced_motion: bool = false,
	superposition_flags: Array = []
) -> void:
	if result_icons.is_empty():
		return
	_clear_superposition()
	if reduced_motion:
		for index in range(_icons.size()):
			_icons[index].texture = result_icons[index % result_icons.size()]
			_icons[index].modulate.a = 1.0
		return
	if pool_icons.is_empty() or _icons.is_empty():
		for index in range(_icons.size()):
			_icons[index].texture = result_icons[index % result_icons.size()]
		return
	var last_index := maxi(_icons.size() - 1, 1)
	for index in range(_icons.size()):
		var reel_icon := _icons[index]
		var result_icon: Texture2D = result_icons[index % result_icons.size()]
		reel_icon.modulate.a = 1.0
		# Staggers each reel's stop between 50% and 100% of duration, same
		# spread regardless of how many reels this strip has.
		var stop_time := duration * (0.5 + 0.5 * (float(index) / float(last_index)))
		var shuffle_count := maxi(int(stop_time / SHUFFLE_INTERVAL), 1)
		var tween := create_tween()
		for shuffle_index in range(shuffle_count):
			var is_last := shuffle_index == shuffle_count - 1
			var icon: Texture2D = result_icon if is_last else pool_icons[randi() % pool_icons.size()]
			tween.tween_callback(reel_icon.set.bind("texture", icon))
			tween.tween_interval(SHUFFLE_INTERVAL)
		if index < superposition_flags.size() and bool(superposition_flags[index]):
			_play_superposition(index, result_icon, pool_icons, stop_time)
	var blink_tween := create_tween()
	blink_tween.tween_interval(duration)
	for _blink_index in range(BLINK_COUNT):
		blink_tween.tween_callback(_set_windows_alpha.bind(0.25))
		blink_tween.tween_interval(BLINK_INTERVAL)
		blink_tween.tween_callback(_set_windows_alpha.bind(1.0))
		blink_tween.tween_interval(BLINK_INTERVAL)


## Shimmers a second offset candidate over the reel until stop_time, then
## collapses it into the settled symbol.
func _play_superposition(
	index: int, result_icon: Texture2D, pool_icons: Array[Texture2D], stop_time: float
) -> void:
	var ghost := _ghosts[index]
	var reel_icon := _icons[index]
	var offset := reel_icon.size.x * 0.12
	ghost.size = reel_icon.size
	ghost.texture = pool_icons[randi() % pool_icons.size()] if not pool_icons.is_empty() else result_icon
	ghost.modulate.a = 0.55
	var shimmer := create_tween().set_loops()
	shimmer.tween_callback(func() -> void:
		if not pool_icons.is_empty():
			ghost.texture = pool_icons[randi() % pool_icons.size()]
	)
	shimmer.tween_property(ghost, "position:x", reel_icon.position.x + offset, SUPERPOSITION_SHIMMER_INTERVAL)
	shimmer.parallel().tween_property(ghost, "modulate:a", 0.3, SUPERPOSITION_SHIMMER_INTERVAL)
	shimmer.tween_property(ghost, "position:x", reel_icon.position.x - offset, SUPERPOSITION_SHIMMER_INTERVAL)
	shimmer.parallel().tween_property(ghost, "modulate:a", 0.55, SUPERPOSITION_SHIMMER_INTERVAL)
	_superposition_tweens.append(shimmer)

	# Collapse: at the reel's stop, converge the ghost onto the settled symbol
	# and fade it out, leaving the single actually-rolled icon.
	var collapse := create_tween()
	collapse.tween_interval(stop_time)
	collapse.tween_callback(func() -> void:
		if shimmer.is_valid():
			shimmer.kill()
		ghost.texture = result_icon
	)
	collapse.tween_property(ghost, "position:x", reel_icon.position.x, 0.18)
	collapse.parallel().tween_property(ghost, "modulate:a", 0.0, 0.18)
	_superposition_tweens.append(collapse)


func _clear_superposition() -> void:
	for tween in _superposition_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_superposition_tweens.clear()
	for index in range(_ghosts.size()):
		_ghosts[index].modulate.a = 0.0
		_ghosts[index].position = Vector2.ZERO


func _set_windows_alpha(alpha: float) -> void:
	for reel_icon in _icons:
		reel_icon.modulate.a = alpha


func _layout_windows() -> void:
	if _windows.is_empty():
		return
	var count := _windows.size()
	# Inset the reels from all four edges of the screen region so no icon ever
	# sits flush against (or past) the cabinet screen border, on both the
	# 3-reel and 5-reel strips.
	var side_pad := size.x * 0.05
	var vertical_pad := size.y * 0.08
	var usable_width := maxf(size.x - side_pad * 2.0, 0.0)
	var usable_height := maxf(size.y - vertical_pad * 2.0, 0.0)
	var gap := usable_width * 0.06
	var window_width := (usable_width - gap * float(count - 1)) / float(count)
	var window_height := minf(usable_height, window_width)
	var y := (size.y - window_height) * 0.5
	for index in range(count):
		var window := _windows[index]
		window.position = Vector2(side_pad + index * (window_width + gap), y)
		window.size = Vector2(window_width, window_height)
		var reel_icon := _icons[index]
		reel_icon.size = window.size * ICON_OVERSCAN_SCALE
		reel_icon.position = (window.size - reel_icon.size) * 0.5
