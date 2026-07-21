class_name PowerUpSelectionPanel
extends PanelContainer

signal selection_confirmed(power_up_ids: Array[StringName])

const REQUIRED_SELECTIONS := 3
## Sized so the full ten-power-up catalog lays out as two rows of five without
## ever needing a scrollbar at the panel's authored width.
const CARD_COLUMNS := 5
const CARD_MINIMUM_SIZE := Vector2(184.0, 158.0)
const CARD_SEPARATION := 12.0
const CARD_ICON_MINIMUM_HEIGHT := 86.0
const REVIEW_CARD_SIZE := Vector2(300.0, 250.0)
const REVIEW_ICON_SIZE := Vector2(112.0, 112.0)
const ACTIVE_COLOR := Color(1.0, 0.84, 0.28, 1.0)
const PASSIVE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SELECTED_TINT := Color(1.0, 0.94, 0.5, 1.0)

@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var grid_area: Control = %Grid
@onready var grid: GridContainer = %PowerUpGrid
@onready var description_margin: MarginContainer = %DescriptionMargin
@onready var description_label: Label = %DescriptionLabel
@onready var selection_label: Label = %SelectionLabel
@onready var review_box: VBoxContainer = %ReviewBox
@onready var review_row: HBoxContainer = %ReviewRow
@onready var edit_button: Button = %EditButton
@onready var confirm_button: Button = %ConfirmButton

var _power_ups: Array[PowerUpDefinition] = []
var _selected_ids: Array[StringName] = []
var _buttons: Dictionary = {}
var _reviewing := false


func _ready() -> void:
	resized.connect(_update_columns)
	confirm_button.pressed.connect(_on_confirm_pressed)
	edit_button.pressed.connect(_leave_review)
	ButtonHover.attach(confirm_button)
	ButtonHover.attach(edit_button)
	_update_columns()


func configure(power_ups: Array[PowerUpDefinition]) -> void:
	_power_ups = power_ups.duplicate()
	_selected_ids.clear()
	_buttons.clear()
	_reviewing = false
	for child in grid.get_children():
		child.queue_free()
	for power_up in _power_ups:
		var button := _build_card(power_up)
		grid.add_child(button)
		_buttons[power_up.power_up_id] = button
	_update_columns()
	_refresh()


func get_selected_ids() -> Array[StringName]:
	return _selected_ids.duplicate()


func get_card_button(power_up_id: StringName) -> Button:
	return _buttons.get(power_up_id) as Button


## Builds a toggle card whose artwork fills most of the button while the name
## and type summary stay legible underneath it.
func _build_card(power_up: PowerUpDefinition) -> Button:
	var button := Button.new()
	button.name = "Select_%s" % power_up.power_up_id
	button.custom_minimum_size = CARD_MINIMUM_SIZE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.clip_contents = true
	button.text = ""
	button.tooltip_text = "%s\n%s" % [power_up.display_name, power_up.description]
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.toggled.connect(_on_power_up_toggled.bind(power_up))
	button.mouse_entered.connect(_show_description.bind(power_up))
	button.focus_entered.connect(_show_description.bind(power_up))
	ButtonHover.attach(button, Vector2(1.06, 1.06))

	var content := MarginContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("margin_left", 8)
	content.add_theme_constant_override("margin_top", 8)
	content.add_theme_constant_override("margin_right", 8)
	content.add_theme_constant_override("margin_bottom", 8)
	button.add_child(content)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	content.add_child(column)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = power_up.icon
	icon.custom_minimum_size = Vector2(0.0, CARD_ICON_MINIMUM_HEIGHT)
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)

	var name_label := Label.new()
	name_label.name = "CardName"
	name_label.text = power_up.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var type_label := Label.new()
	type_label.name = "CardType"
	type_label.text = _get_type_summary(power_up)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 13)
	type_label.add_theme_color_override(
		"font_color", ACTIVE_COLOR if power_up.is_active else PASSIVE_COLOR
	)
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(type_label)
	return button


## Builds the read-only loadout card shown on the review page so the player
## confirms artwork rather than a bare list of names.
func _build_review_card(power_up: PowerUpDefinition) -> Control:
	var card := VBoxContainer.new()
	card.name = "Review_%s" % power_up.power_up_id
	card.custom_minimum_size = REVIEW_CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.texture = power_up.icon
	icon.custom_minimum_size = REVIEW_ICON_SIZE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var name_label := Label.new()
	name_label.text = power_up.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 21)
	card.add_child(name_label)

	var type_label := Label.new()
	type_label.text = _get_type_summary(power_up)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 14)
	type_label.add_theme_color_override(
		"font_color", ACTIVE_COLOR if power_up.is_active else PASSIVE_COLOR
	)
	card.add_child(type_label)

	var description := Label.new()
	description.text = power_up.description
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 15)
	card.add_child(description)
	return card


func _on_power_up_toggled(enabled: bool, power_up: PowerUpDefinition) -> void:
	if _reviewing:
		var review_button := _buttons.get(power_up.power_up_id) as Button
		review_button.set_pressed_no_signal(power_up.power_up_id in _selected_ids)
		return
	if enabled:
		if _selected_ids.size() >= REQUIRED_SELECTIONS:
			var button := _buttons.get(power_up.power_up_id) as Button
			button.set_pressed_no_signal(false)
			description_label.text = (
				"Choose exactly three.\nDeselect one before adding %s." % power_up.display_name
			)
			return
		if power_up.power_up_id not in _selected_ids:
			_selected_ids.append(power_up.power_up_id)
	else:
		_selected_ids.erase(power_up.power_up_id)
	_refresh()


func _on_confirm_pressed() -> void:
	if _selected_ids.size() != REQUIRED_SELECTIONS:
		return
	if not _reviewing:
		_enter_review()
		return
	confirm_button.disabled = true
	selection_confirmed.emit(_selected_ids.duplicate())


func _enter_review() -> void:
	_reviewing = true
	grid_area.visible = false
	description_margin.visible = false
	selection_label.visible = false
	review_box.visible = true
	edit_button.visible = true
	for child in review_row.get_children():
		child.queue_free()
	for power_up_id in _selected_ids:
		var power_up := _find_power_up(power_up_id)
		if power_up != null:
			review_row.add_child(_build_review_card(power_up))
	confirm_button.text = "START BATTLE"


func _leave_review() -> void:
	_reviewing = false
	grid_area.visible = true
	description_margin.visible = true
	selection_label.visible = true
	review_box.visible = false
	edit_button.visible = false
	for child in review_row.get_children():
		child.queue_free()
	confirm_button.text = "REVIEW LOADOUT"
	_refresh()


func _refresh() -> void:
	selection_label.text = "Selected %d / %d" % [_selected_ids.size(), REQUIRED_SELECTIONS]
	confirm_button.disabled = _selected_ids.size() != REQUIRED_SELECTIONS
	confirm_button.text = "REVIEW LOADOUT"
	for power_up in _power_ups:
		var button := _buttons.get(power_up.power_up_id) as Button
		if button == null:
			continue
		var selected := power_up.power_up_id in _selected_ids
		button.set_pressed_no_signal(selected)
		button.modulate = SELECTED_TINT if selected else Color.WHITE


func _show_description(power_up: PowerUpDefinition) -> void:
	description_label.text = "%s — %s\n%s" % [
		power_up.display_name,
		_get_type_summary(power_up),
		power_up.description,
	]


func _get_type_summary(power_up: PowerUpDefinition) -> String:
	if not power_up.is_active:
		return "PASSIVE"
	return "ACTIVE • %d USE%s" % [power_up.max_uses, "" if power_up.max_uses == 1 else "S"]


func _find_power_up(power_up_id: StringName) -> PowerUpDefinition:
	for power_up in _power_ups:
		if power_up.power_up_id == power_up_id:
			return power_up
	return null


func _update_columns() -> void:
	if not is_instance_valid(grid):
		return
	# A row of N cards costs N * card + (N - 1) * separation, so the separation
	# has to be added back before dividing or the last column is lost.
	var available_width := maxf(size.x - 56.0, CARD_MINIMUM_SIZE.x * 2.0)
	var fitting_columns := floori(
		(available_width + CARD_SEPARATION) / (CARD_MINIMUM_SIZE.x + CARD_SEPARATION)
	)
	grid.columns = clampi(fitting_columns, 2, CARD_COLUMNS)
