extends Node
## Debug admin panel toggled with Shift+A.
## Self-disables in release builds so it never ships to players.

const JUNKYARD_PROGRESSION: JunkyardProgressionConfig = preload(
	"res://resources/story/junkyard_progression.tres"
)
const MAIN_THEME: Theme = preload("res://resources/ui/main_theme.tres")

# ── Cached node references ──────────────────────────────────────────────
var _canvas: CanvasLayer
var _dim: ColorRect
var _panel_root: Control
var _money_input: LineEdit
var _fps_label: Label
var _show_fps := false


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_input(false)
		return
	_build_ui()
	_canvas.visible = false


# ── Toggle ───────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A and event.shift_pressed:
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_canvas.visible = not _canvas.visible
	if _canvas.visible:
		_money_input.text = str(GameState.money)


func _close() -> void:
	_canvas.visible = false


# ── FPS counter ──────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _show_fps and is_instance_valid(_fps_label):
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


# ── UI construction ─────────────────────────────────────────────────────
func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100
	add_child(_canvas)

	# Full-screen dim backdrop (matches settings modal pattern)
	var modal_root := Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_root.theme = MAIN_THEME
	_canvas.add_child(modal_root)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.015, 0.025, 0.055, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_root.add_child(_dim)

	# Centered panel with explicit size so themed buttons can't push it off-screen
	_panel_root = PanelContainer.new()
	_panel_root.anchor_left = 0.5
	_panel_root.anchor_right = 0.5
	_panel_root.anchor_top = 0.5
	_panel_root.anchor_bottom = 0.5
	_panel_root.offset_left = -230.0
	_panel_root.offset_right = 230.0
	_panel_root.offset_top = -270.0
	_panel_root.offset_bottom = 270.0
	_panel_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	modal_root.add_child(_panel_root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_root.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	# ── Header row with title + close button ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)

	var title := Label.new()
	title.text = "ADMIN PANEL"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := _make_close_button()
	header.add_child(close_btn)

	var subtitle := Label.new()
	subtitle.text = "Shift+A to toggle  •  Debug only"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.7))
	content.add_child(subtitle)

	_add_separator(content)

	# ── Money section ──
	_add_section_label(content, "MONEY")

	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	content.add_child(money_row)
	_add_button(money_row, "$100", _set_money.bind(100))
	_add_button(money_row, "$1K", _set_money.bind(1000))
	_add_button(money_row, "$10K", _set_money.bind(10000))
	_add_button(money_row, "$100K", _set_money.bind(100000))

	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 6)
	content.add_child(custom_row)

	_money_input = LineEdit.new()
	_money_input.placeholder_text = "Custom $"
	_money_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_input.custom_minimum_size = Vector2(120, 40)
	_money_input.add_theme_font_size_override("font_size", 18)
	custom_row.add_child(_money_input)

	_add_button(custom_row, "SET", _set_custom_money)

	_add_separator(content)

	# ── Story Progress section ──
	_add_section_label(content, "STORY PROGRESS")

	var story_row1 := HBoxContainer.new()
	story_row1.add_theme_constant_override("separation", 6)
	content.add_child(story_row1)
	_add_button(story_row1, "Skip Tutorial", _skip_tutorial)
	_add_button(story_row1, "Skip Phone Call", _skip_phone_call)

	var story_row2 := HBoxContainer.new()
	story_row2.add_theme_constant_override("separation", 6)
	content.add_child(story_row2)
	_add_button(story_row2, "Complete All Story", _complete_all_story)
	_add_button(story_row2, "Reset Progress", _reset_progress)

	_add_separator(content)

	# ── Tickets section ──
	_add_section_label(content, "TICKETS")

	var ticket_row := HBoxContainer.new()
	ticket_row.add_theme_constant_override("separation", 6)
	content.add_child(ticket_row)
	_add_button(ticket_row, "+10 All", _give_tickets.bind(10))
	_add_button(ticket_row, "+50 All", _give_tickets.bind(50))

	_add_separator(content)

	# ── Upgrades section ──
	_add_section_label(content, "UPGRADES")

	var upgrade_row := HBoxContainer.new()
	upgrade_row.add_theme_constant_override("separation", 6)
	content.add_child(upgrade_row)
	_add_button(upgrade_row, "Max All", _max_all_upgrades)
	_add_button(upgrade_row, "Reset All", _reset_all_upgrades)

	_add_separator(content)

	# ── Scene / Display section ──
	_add_section_label(content, "SCENE & DISPLAY")

	var scene_row := HBoxContainer.new()
	scene_row.add_theme_constant_override("separation", 6)
	content.add_child(scene_row)
	_add_button(scene_row, "Reload Scene", _reload_scene)
	_add_button(scene_row, "Toggle FPS", _toggle_fps)

	# FPS label (anchored to top-center, always above admin panel)
	_fps_label = Label.new()
	_fps_label.text = ""
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_fps_label.offset_top = 4.0
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Add to a separate always-visible layer so FPS persists when panel is closed
	var fps_canvas := CanvasLayer.new()
	fps_canvas.layer = 99
	add_child(fps_canvas)
	var fps_root := Control.new()
	fps_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fps_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_root.theme = MAIN_THEME
	fps_canvas.add_child(fps_root)
	fps_root.add_child(_fps_label)


# ── Builder helpers ──────────────────────────────────────────────────────
func _add_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.91, 0.28))
	parent.add_child(lbl)


func _add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	parent.add_child(sep)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 40)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _make_close_button() -> Button:
	# Red X button matching the settings panel style from hud.tscn
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = Vector2(42, 42)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 20)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.82, 0.13, 0.13)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.95, 0.25, 0.25)
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.65, 0.08, 0.08)
	pressed.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.pressed.connect(_close)
	return btn


# ── Action callbacks ─────────────────────────────────────────────────────
func _set_money(amount: int) -> void:
	GameState.money = amount


func _set_custom_money() -> void:
	var value := _money_input.text.strip_edges().replace("$", "").replace(",", "")
	if value.is_valid_int():
		GameState.money = maxi(int(value), 0)
		_money_input.text = str(GameState.money)


func _skip_tutorial() -> void:
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	_close_and_reload()


func _skip_phone_call() -> void:
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	_close_and_reload()


func _complete_all_story() -> void:
	# Set every story flag so the scene jumps straight to the machine selector.
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	for machine in JUNKYARD_PROGRESSION.machines:
		GameState.unlock_machine(machine.machine_id)
		if GameState.selected_machine_id == &"":
			GameState.selected_machine_id = machine.machine_id
	# Ensure the player has enough money and tickets to actually play.
	if GameState.money < 100:
		GameState.money = 100
	for machine in JUNKYARD_PROGRESSION.machines:
		if GameState.get_machine_ticket_count(machine.machine_id) < 5:
			GameState.add_machine_ticket(machine.machine_id, 10)
	_close_and_reload()


func _reset_progress() -> void:
	GameState.reset_for_new_game()
	_close_and_reload()


func _give_tickets(amount: int) -> void:
	for machine in JUNKYARD_PROGRESSION.machines:
		GameState.add_machine_ticket(machine.machine_id, amount)


func _max_all_upgrades() -> void:
	for config in Economy.get_upgrade_configs():
		var current := GameState.get_upgrade_level(config.upgrade_id)
		for _i in range(config.max_level - current):
			GameState.increment_upgrade_level(config.upgrade_id)


func _reset_all_upgrades() -> void:
	var ids: Array[StringName] = []
	for config in Economy.get_upgrade_configs():
		ids.append(config.upgrade_id)
	GameState.upgrade_levels.clear()
	for uid in ids:
		GameState.upgrade_levels_changed.emit(uid, 0)


func _reload_scene() -> void:
	_close_and_reload()


func _toggle_fps() -> void:
	_show_fps = not _show_fps
	if not _show_fps:
		_fps_label.text = ""


func _close_and_reload() -> void:
	_close()
	get_tree().reload_current_scene()
