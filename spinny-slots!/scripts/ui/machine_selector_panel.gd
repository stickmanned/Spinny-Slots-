extends PanelContainer

## Untyped so this panel works with either area's machine data — MachineDefinition
## (Junkyard) or MetropolisMachineDefinition (Metropolis). Both expose the same
## machine_id/display_name/cabinet_texture/screen_region field names; nothing
## here calls an area-specific method.
signal machine_selected(machine)
signal selection_changed(machine)

@onready var left_arrow: BaseButton = %LeftArrow
@onready var right_arrow: BaseButton = %RightArrow
@onready var cabinet_art: TextureRect = %CabinetArt
## The 3-window strip Junkyard always uses. Metropolis's 5-reel machines use
## reel_strip_5 instead; both live in the scene so ownership/unique-name
## registration happens through normal scene loading, not runtime swapping.
@onready var reel_strip: Control = %ReelStrip
@onready var reel_strip_5: Control = %ReelStrip5
@onready var machine_name: Label = %MachineName
@onready var select_button: Button = %SelectButton

var _machines: Array = []
var _selected_index := 0


func _ready() -> void:
	left_arrow.pressed.connect(func() -> void: _move_selection(-1))
	right_arrow.pressed.connect(func() -> void: _move_selection(1))
	_connect_arrow_feedback(left_arrow)
	_connect_arrow_feedback(right_arrow)
	select_button.pressed.connect(_select_current)
	cabinet_art.resized.connect(_center_cabinet_pivot)
	cabinet_art.resized.connect(_position_reel_strip)
	_center_cabinet_pivot()


## Whichever strip matches the currently selected machine's reel count.
## External callers (e.g. metropolis_job.gd) should use this instead of the
## %ReelStrip unique name, which stays reserved for Junkyard's always-3-reel
## direct lookup so its existing behavior never changes.
func get_active_reel_strip() -> Control:
	return reel_strip_5 if _get_reel_count(get_selected_machine()) == 5 else reel_strip


func configure(machines: Array, selected_machine_id: StringName = &"") -> void:
	_machines = machines.duplicate()
	_selected_index = 0
	if not selected_machine_id.is_empty():
		for index in range(_machines.size()):
			if _machines[index].machine_id == selected_machine_id:
				_selected_index = index
				break
	_refresh()


func set_select_button_visible(is_visible: bool) -> void:
	select_button.visible = is_visible


func get_selected_machine():
	if _machines.is_empty():
		return null
	return _machines[_selected_index]


func play_spin_flourish(duration: float = 0.72) -> Signal:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(cabinet_art, "scale", Vector2(0.92, 1.08), duration * 0.28)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cabinet_art, "rotation", deg_to_rad(-3.0), duration * 0.18)
	tween.tween_property(cabinet_art, "rotation", deg_to_rad(3.0), duration * 0.18)
	tween.tween_property(cabinet_art, "rotation", 0.0, duration * 0.18)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(cabinet_art, "scale", Vector2.ONE, duration * 0.18)
	return tween.finished


func _move_selection(direction: int) -> void:
	if _machines.size() <= 1:
		return
	_selected_index = wrapi(_selected_index + direction, 0, _machines.size())
	_refresh()
	selection_changed.emit(get_selected_machine())


func _select_current() -> void:
	var machine = get_selected_machine()
	if machine != null:
		machine_selected.emit(machine)


func _refresh() -> void:
	var has_multiple := _machines.size() > 1
	left_arrow.disabled = not has_multiple
	right_arrow.disabled = not has_multiple
	left_arrow.modulate.a = 1.0 if has_multiple else 0.72
	right_arrow.modulate.a = 1.0 if has_multiple else 0.72
	select_button.disabled = _machines.is_empty()
	var machine = get_selected_machine()
	if machine == null:
		cabinet_art.texture = null
		machine_name.text = "No machines"
		reel_strip.visible = false
		reel_strip_5.visible = false
		return
	cabinet_art.texture = machine.cabinet_texture
	machine_name.text = machine.display_name
	_position_reel_strip()


## Duck-typed: MachineDefinition (Junkyard) never declares reel_count, so this
## always resolves to 3 for Junkyard machines and their strip never changes.
func _get_reel_count(machine) -> int:
	if machine == null:
		return 3
	var value = machine.get("reel_count")
	return int(value) if value != null else 3


func _position_reel_strip() -> void:
	var machine = get_selected_machine()
	var active_strip := get_active_reel_strip()
	var inactive_strip := reel_strip_5 if active_strip == reel_strip else reel_strip
	inactive_strip.visible = false
	if machine == null or cabinet_art.texture == null or not machine.screen_region.has_area():
		active_strip.visible = false
		return
	active_strip.visible = true
	var texture_size := cabinet_art.texture.get_size()
	var control_size := cabinet_art.size
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or control_size.x <= 0.0 or control_size.y <= 0.0:
		return
	var draw_scale := minf(control_size.x / texture_size.x, control_size.y / texture_size.y)
	var draw_origin := (control_size - texture_size * draw_scale) * 0.5
	active_strip.position = draw_origin + machine.screen_region.position * draw_scale
	active_strip.size = machine.screen_region.size * draw_scale


func _connect_arrow_feedback(arrow: BaseButton) -> void:
	arrow.mouse_entered.connect(func() -> void: _set_arrow_feedback(arrow, Vector2.ONE * 1.1, Color(0.82, 0.95, 1.0, arrow.modulate.a)))
	arrow.mouse_exited.connect(func() -> void: _set_arrow_feedback(arrow, Vector2.ONE, Color(1.0, 1.0, 1.0, arrow.modulate.a)))
	arrow.button_down.connect(func() -> void: _set_arrow_feedback(arrow, Vector2.ONE * 0.92, Color(0.68, 0.86, 0.96, arrow.modulate.a)))
	arrow.button_up.connect(func() -> void: _set_arrow_feedback(arrow, Vector2.ONE, Color(1.0, 1.0, 1.0, arrow.modulate.a)))
	arrow.resized.connect(func() -> void: arrow.pivot_offset = arrow.size * 0.5)
	arrow.pivot_offset = arrow.size * 0.5


func _set_arrow_feedback(arrow: BaseButton, target_scale: Vector2, tint: Color) -> void:
	if arrow.disabled:
		return
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(arrow, "scale", target_scale, 0.1)
	tween.tween_property(arrow, "modulate", tint, 0.1)


func _center_cabinet_pivot() -> void:
	cabinet_art.pivot_offset = cabinet_art.size * 0.5
