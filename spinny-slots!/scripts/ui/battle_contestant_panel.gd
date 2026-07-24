class_name BattleContestantPanel
extends PanelContainer

signal power_up_requested(power_up_id: StringName)
signal power_up_focused(description: String)

const POWER_UP_ICON_SIZE := Vector2(58.0, 58.0)

@onready var avatar_frame: Control = %AvatarFrame
@onready var avatar: TextureRect = %Avatar
@onready var avatar_fallback: Label = %AvatarFallback
@onready var contestant_name: Label = %ContestantName
@onready var turn_marker: Label = %TurnMarker
@onready var total_label: Label = %TotalLabel
@onready var upgrade_summary: Label = %UpgradeSummary
@onready var power_up_row: HBoxContainer = %PowerUpRow
@onready var machine_name: Label = %MachineName
@onready var cabinet_art: TextureRect = %CabinetArt
@onready var reel_strip: Control = %ReelStrip
@onready var result_label: Label = %ResultLabel

var _machine: MachineDefinition
var _power_ups: Array[PowerUpDefinition] = []
var _power_up_buttons: Dictionary = {}
var _total_tween: Tween


func _ready() -> void:
	cabinet_art.resized.connect(_position_reel_strip)
	call_deferred("_position_reel_strip")


func configure_identity(display_name: String, portrait: Texture2D, fallback_text: String) -> void:
	contestant_name.text = display_name
	avatar.texture = portrait
	avatar.visible = portrait != null
	avatar_fallback.text = fallback_text
	# The name label already states who the contestant is, so the text fallback
	# would only repeat it. Reserve the avatar slot for real portrait art.
	avatar_fallback.visible = false
	avatar_frame.visible = portrait != null


func set_turn_active(active: bool) -> void:
	turn_marker.text = "YOUR TURN" if contestant_name.text == "YOU" and active else ("KING'S TURN" if active else "")
	turn_marker.modulate.a = 1.0 if active else 0.0
	self_modulate = Color(1.05, 1.05, 0.88, 1.0) if active else Color.WHITE


func set_upgrade_profile(profile: Dictionary, fixed_maximum: bool) -> void:
	var levels: Dictionary = profile.get("levels", {})
	var maximum_levels: Dictionary = profile.get("maximum_levels", {})
	var multipliers: Dictionary = profile.get("multipliers", {})
	var heading := "FIXED MAX UPGRADES" if fixed_maximum else "CURRENT UPGRADES"
	upgrade_summary.text = "%s\nLuck LV %d/%d x%.2f  ·  Coins LV %d/%d x%.2f  ·  Speed LV %d/%d x%.2f" % [
		heading,
		int(levels.get("luck", 0)),
		int(maximum_levels.get("luck", 0)),
		float(multipliers.get("luck", 1.0)),
		int(levels.get("coin_multiplier", 0)),
		int(maximum_levels.get("coin_multiplier", 0)),
		float(multipliers.get("coin_multiplier", 1.0)),
		int(levels.get("spin_speed", 0)),
		int(maximum_levels.get("spin_speed", 0)),
		float(multipliers.get("spin_speed", 1.0)),
	]


func get_upgrade_summary_text() -> String:
	return upgrade_summary.text


func set_power_ups(power_ups: Array[PowerUpDefinition], interactive: bool) -> void:
	_power_ups = power_ups.duplicate()
	_power_up_buttons.clear()
	for child in power_up_row.get_children():
		child.queue_free()
	for power_up in _power_ups:
		var button := TextureButton.new()
		button.name = "PowerUp_%s" % power_up.power_up_id
		button.custom_minimum_size = POWER_UP_ICON_SIZE
		button.texture_normal = power_up.icon
		button.texture_hover = power_up.icon
		button.texture_pressed = power_up.icon
		button.texture_disabled = power_up.icon
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = "%s\n%s" % [power_up.display_name, power_up.description]
		button.focus_mode = Control.FOCUS_ALL if interactive and power_up.is_active else Control.FOCUS_NONE
		button.disabled = not interactive or not power_up.is_active
		button.pressed.connect(_on_power_up_pressed.bind(power_up.power_up_id))
		button.mouse_entered.connect(power_up_focused.emit.bind("%s: %s" % [power_up.display_name, power_up.description]))
		ButtonHover.attach(button, Vector2(1.12, 1.12))
		power_up_row.add_child(button)
		var uses := Label.new()
		uses.name = "Uses"
		uses.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		uses.offset_left = -24.0
		uses.offset_top = -24.0
		uses.offset_right = 0.0
		uses.offset_bottom = 0.0
		uses.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		uses.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		uses.add_theme_font_size_override("font_size", 15)
		uses.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(uses)
		_power_up_buttons[power_up.power_up_id] = button


func set_power_up_states(states: Dictionary) -> void:
	for power_up in _power_ups:
		var button := _power_up_buttons.get(power_up.power_up_id) as TextureButton
		if button == null:
			continue
		var state: Dictionary = states.get(power_up.power_up_id, {})
		var uses_remaining := int(state.get("uses_remaining", power_up.max_uses))
		var armed := bool(state.get("armed", false))
		var can_activate := bool(state.get("can_activate", false))
		button.disabled = not can_activate
		button.modulate = Color(1.0, 0.9, 0.28, 1.0) if armed else (Color.WHITE if uses_remaining != 0 else Color(0.48, 0.52, 0.6, 0.72))
		var uses_label := button.get_node("Uses") as Label
		uses_label.text = "∞" if power_up.max_uses < 0 else str(maxi(uses_remaining, 0))


func configure_machine(machine: MachineDefinition) -> void:
	_machine = machine
	if machine == null:
		machine_name.text = "Waiting for machine..."
		cabinet_art.texture = null
		reel_strip.visible = false
		return
	machine_name.text = machine.display_name
	cabinet_art.texture = machine.cabinet_texture
	var icons: Array[Texture2D] = []
	for symbol in machine.symbols:
		icons.append(symbol.icon)
	reel_strip.call("set_idle_symbols", icons)
	call_deferred("_position_reel_strip")


func play_spin(outcome: Dictionary, duration: float, reduced_motion: bool) -> void:
	if _machine == null:
		return
	var result_icons: Array[Texture2D] = []
	var symbols: Array[SlotSymbol] = outcome.get("symbols", [] as Array[SlotSymbol])
	for symbol in symbols:
		result_icons.append(symbol.icon)
	var pool_icons: Array[Texture2D] = []
	for symbol in _machine.symbols:
		pool_icons.append(symbol.icon)
	reel_strip.call("play_spin", result_icons, pool_icons, duration, reduced_motion)
	if reduced_motion:
		return
	cabinet_art.pivot_offset = cabinet_art.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cabinet_art, "rotation", deg_to_rad(-1.8), duration * 0.28)
	tween.tween_property(cabinet_art, "rotation", deg_to_rad(1.8), duration * 0.44)
	tween.tween_property(cabinet_art, "rotation", 0.0, duration * 0.28)


func get_configured_machine() -> MachineDefinition:
	return _machine


func get_reel_blink_duration() -> float:
	return float(reel_strip.call("get_blink_duration"))


func set_result(text: String) -> void:
	result_label.text = text


func set_total(value: int, animate: bool = true) -> void:
	if _total_tween and _total_tween.is_valid():
		_total_tween.kill()
	var previous := _parse_total()
	if not animate or GameState.reduced_motion:
		total_label.text = NumberFormatter.currency(maxi(value, 0))
		return
	_total_tween = create_tween()
	_total_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_total_tween.tween_method(_set_presented_total, previous, maxi(value, 0), 0.34)


func get_power_up_button(power_up_id: StringName) -> TextureButton:
	return _power_up_buttons.get(power_up_id) as TextureButton


func _parse_total() -> int:
	return int(total_label.text.trim_prefix("$").replace(",", ""))


func _set_presented_total(value: int) -> void:
	total_label.text = NumberFormatter.currency(maxi(value, 0))


func _position_reel_strip() -> void:
	if _machine == null or cabinet_art.texture == null or not _machine.screen_region.has_area():
		reel_strip.visible = false
		return
	var texture_size := cabinet_art.texture.get_size()
	var control_size := cabinet_art.size
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or control_size.x <= 0.0 or control_size.y <= 0.0:
		return
	var draw_scale := minf(control_size.x / texture_size.x, control_size.y / texture_size.y)
	var draw_origin := (control_size - texture_size * draw_scale) * 0.5
	reel_strip.position = draw_origin + _machine.screen_region.position * draw_scale
	reel_strip.size = _machine.screen_region.size * draw_scale
	reel_strip.visible = true


func _on_power_up_pressed(power_up_id: StringName) -> void:
	power_up_requested.emit(power_up_id)
