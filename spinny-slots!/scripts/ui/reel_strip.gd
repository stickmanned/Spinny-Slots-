extends Control

const SHUFFLE_INTERVAL := 0.06
const BLINK_INTERVAL := 0.09
const BLINK_COUNT := 3
const ICON_OVERSCAN_SCALE := 1.55

var _windows: Array[Control] = []
var _icons: Array[TextureRect] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		if child is Control and child.get_child_count() == 1 and child.get_child(0) is TextureRect:
			_windows.append(child)
			_icons.append(child.get_child(0) as TextureRect)
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


func play_spin(
	result_icons: Array[Texture2D],
	pool_icons: Array[Texture2D],
	duration: float,
	reduced_motion: bool = false
) -> void:
	if result_icons.is_empty():
		return
	if reduced_motion:
		for index in range(_icons.size()):
			_icons[index].texture = result_icons[index % result_icons.size()]
			_icons[index].modulate.a = 1.0
		return
	if pool_icons.is_empty() or _icons.is_empty():
		for index in range(_icons.size()):
			_icons[index].texture = result_icons[index % result_icons.size()]
		return
	for index in range(_icons.size()):
		var reel_icon := _icons[index]
		var result_icon: Texture2D = result_icons[index % result_icons.size()]
		reel_icon.modulate.a = 1.0
		var stop_time := duration * (0.5 + 0.25 * index)
		var shuffle_count := maxi(int(stop_time / SHUFFLE_INTERVAL), 1)
		var tween := create_tween()
		for shuffle_index in range(shuffle_count):
			var is_last := shuffle_index == shuffle_count - 1
			var icon: Texture2D = result_icon if is_last else pool_icons[randi() % pool_icons.size()]
			tween.tween_callback(reel_icon.set.bind("texture", icon))
			tween.tween_interval(SHUFFLE_INTERVAL)
	var blink_tween := create_tween()
	blink_tween.tween_interval(duration)
	for _blink_index in range(BLINK_COUNT):
		blink_tween.tween_callback(_set_windows_alpha.bind(0.25))
		blink_tween.tween_interval(BLINK_INTERVAL)
		blink_tween.tween_callback(_set_windows_alpha.bind(1.0))
		blink_tween.tween_interval(BLINK_INTERVAL)


func _set_windows_alpha(alpha: float) -> void:
	for reel_icon in _icons:
		reel_icon.modulate.a = alpha


func _layout_windows() -> void:
	if _windows.is_empty():
		return
	var gap := size.x * 0.06
	var window_width := (size.x - gap * 2.0) / 3.0
	var window_height := minf(size.y, window_width)
	var y := (size.y - window_height) * 0.5
	for index in range(_windows.size()):
		var window := _windows[index]
		window.position = Vector2(index * (window_width + gap), y)
		window.size = Vector2(window_width, window_height)
		var reel_icon := _icons[index]
		reel_icon.size = window.size * ICON_OVERSCAN_SCALE
		reel_icon.position = (window.size - reel_icon.size) * 0.5
