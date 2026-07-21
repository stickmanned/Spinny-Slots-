extends CanvasLayer

const UPGRADE_ROW_SCENE: PackedScene = preload("res://scenes/ui/upgrade_row.tscn")
const MAP_SELECT_CARD_SCENE: PackedScene = preload("res://scenes/ui/map_select_card.tscn")
const MapConfig = preload("res://scripts/map_config.gd")

signal map_requested(map_id: String)


@onready var coin_value: Label = %CoinValue
@onready var gem_value: Label = %GemValue
@onready var upgrade_rows: VBoxContainer = %UpgradeRows
@onready var currency_panel: PanelContainer = %CurrencyPanel
@onready var upgrade_panel: PanelContainer = %UpgradePanel
@onready var settings_button: Button = %SettingsButton
@onready var settings_layer: CanvasLayer = %SettingsLayer
@onready var volume_slider: HSlider = %VolumeSlider
@onready var close_button: Button = %CloseButton
@onready var resolution_dropdown: OptionButton = %ResolutionDropdown
@onready var reduced_motion_button: Button = %ReducedMotionButton
@onready var sfx_button: Button = %SfxButton
@onready var map_button: Button = %MapButton
@onready var map_select_layer: CanvasLayer = %MapSelectLayer
@onready var map_cards_container: HBoxContainer = %MapCardsContainer
@onready var close_map_button: Button = %CloseMapButton

var _currency_tween: Tween
var _upgrade_tween: Tween
var _coin_pulse_tween: Tween
var _upgrades_enabled := true


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.gems_changed.connect(_on_gems_changed)
	GameState.upgrade_levels_changed.connect(_on_upgrade_levels_changed)
	_on_money_changed(GameState.money)
	_on_gems_changed(GameState.gems)
	_build_upgrade_rows()

	settings_button.pressed.connect(_on_settings_pressed)
	close_button.pressed.connect(_on_close_pressed)
	volume_slider.value = GameState.music_volume
	volume_slider.value_changed.connect(_on_volume_value_changed)
	reduced_motion_button.button_pressed = GameState.reduced_motion
	reduced_motion_button.toggled.connect(_on_reduced_motion_toggled)
	_update_reduced_motion_text()
	sfx_button.button_pressed = not GameState.sfx_enabled
	sfx_button.toggled.connect(_on_sfx_toggled)
	_update_sfx_text()
	settings_button.visible = GameState.day_job_tutorial_completed
	map_button.visible = GameState.metropolis_unlocked
	map_button.pressed.connect(_on_map_pressed)
	close_map_button.pressed.connect(_on_close_map_pressed)
	ButtonHover.attach(map_button)
	ButtonHover.attach(settings_button)
	ButtonHover.attach(close_map_button)

	# Populate and select screen resolution options
	resolution_dropdown.clear()
	resolution_dropdown.add_item("1280x720 (720p)", 0)
	resolution_dropdown.add_item("1920x1080 (1080p)", 1)
	resolution_dropdown.add_item("1920x1200 (1200p)", 2)
	resolution_dropdown.add_item("2560x1440 (1440p)", 3)
	resolution_dropdown.add_item("2560x1600 (1600p)", 4)
	resolution_dropdown.add_item("3840x2160 (4K)", 5)

	var current_size = DisplayServer.window_get_size()
	if current_size.x == 1280:
		resolution_dropdown.selected = 0
	elif current_size.x == 1920 and current_size.y == 1080:
		resolution_dropdown.selected = 1
	elif current_size.x == 1920 and current_size.y == 1200:
		resolution_dropdown.selected = 2
	elif current_size.x == 2560 and current_size.y == 1440:
		resolution_dropdown.selected = 3
	elif current_size.x == 2560 and current_size.y == 1600:
		resolution_dropdown.selected = 4
	elif current_size.x == 3840:
		resolution_dropdown.selected = 5
	else:
		resolution_dropdown.selected = 0
	resolution_dropdown.item_selected.connect(_on_resolution_selected)


func hide_all() -> void:
	_stop_visibility_tweens()
	currency_panel.modulate.a = 0.0
	upgrade_panel.modulate.a = 0.0
	settings_button.visible = false
	map_button.visible = false


func show_currency(duration: float) -> void:
	currency_panel.visible = true
	if _currency_tween and _currency_tween.is_valid():
		_currency_tween.kill()
	_currency_tween = create_tween()
	_currency_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_currency_tween.tween_property(currency_panel, "modulate:a", 1.0, duration)


func enter_machine_mode(duration: float) -> void:
	currency_panel.visible = true
	upgrade_panel.visible = true
	settings_button.visible = true
	map_button.visible = GameState.metropolis_unlocked
	if _currency_tween and _currency_tween.is_valid():
		_currency_tween.kill()
	if duration <= 0.0:
		currency_panel.modulate.a = 1.0
	else:
		_currency_tween = create_tween()
		_currency_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_currency_tween.tween_property(currency_panel, "modulate:a", 1.0, duration)
	if _upgrade_tween and _upgrade_tween.is_valid():
		_upgrade_tween.kill()
	upgrade_panel.modulate.a = 0.0
	if duration <= 0.0:
		upgrade_panel.modulate.a = 1.0
		return
	_upgrade_tween = create_tween()
	_upgrade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_upgrade_tween.tween_property(upgrade_panel, "modulate:a", 1.0, duration)


func _stop_visibility_tweens() -> void:
	if _currency_tween and _currency_tween.is_valid():
		_currency_tween.kill()
	if _upgrade_tween and _upgrade_tween.is_valid():
		_upgrade_tween.kill()


func _build_upgrade_rows() -> void:
	for child in upgrade_rows.get_children():
		child.queue_free()
	for config in Economy.get_upgrade_configs():
		var row := UPGRADE_ROW_SCENE.instantiate()
		upgrade_rows.add_child(row)
		row.configure(config)
		row.connect("upgrade_requested", _on_upgrade_requested)
	_refresh_upgrade_rows()


func set_upgrades_enabled(enabled: bool) -> void:
	_upgrades_enabled = enabled
	_refresh_upgrade_rows()


func get_coin_balance_target() -> Control:
	return coin_value


func set_presented_money(value: int) -> void:
	coin_value.text = str(value)


func pulse_coin_balance() -> void:
	if _coin_pulse_tween and _coin_pulse_tween.is_valid():
		_coin_pulse_tween.kill()
	coin_value.pivot_offset = coin_value.size * 0.5
	coin_value.scale = Vector2.ONE * 1.08
	_coin_pulse_tween = create_tween()
	_coin_pulse_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_coin_pulse_tween.tween_property(coin_value, "scale", Vector2.ONE, 0.14)


func _refresh_upgrade_rows() -> void:
	for row in upgrade_rows.get_children():
		if row.has_method("refresh"):
			row.refresh(_upgrades_enabled)


func _on_upgrade_requested(upgrade_id: StringName) -> void:
	if not _upgrades_enabled:
		return
	Economy.purchase_upgrade(upgrade_id)


func _on_upgrade_levels_changed(_upgrade_id: StringName, _level: int) -> void:
	_refresh_upgrade_rows()


func _on_money_changed(value: int) -> void:
	set_presented_money(value)
	_refresh_upgrade_rows()


func _on_gems_changed(value: int) -> void:
	gem_value.text = str(value)


func _on_settings_pressed() -> void:
	settings_layer.visible = true


func _on_close_pressed() -> void:
	settings_layer.visible = false


func _on_volume_value_changed(value: float) -> void:
	GameState.music_volume = value


func _on_reduced_motion_toggled(enabled: bool) -> void:
	GameState.reduced_motion = enabled
	_update_reduced_motion_text()


func _update_reduced_motion_text() -> void:
	reduced_motion_button.text = "REDUCED MOTION: %s" % ("ON" if GameState.reduced_motion else "OFF")


func _on_sfx_toggled(pressed: bool) -> void:
	GameState.sfx_enabled = not pressed
	_update_sfx_text()


func _update_sfx_text() -> void:
	sfx_button.text = "SOUND EFFECTS: %s" % ("ON" if GameState.sfx_enabled else "OFF")


func show_settings_button() -> void:
	settings_button.visible = true
	map_button.visible = GameState.metropolis_unlocked


func set_controls_enabled(enabled: bool) -> void:
	settings_button.disabled = not enabled
	map_button.disabled = not enabled
	volume_slider.editable = enabled
	resolution_dropdown.disabled = not enabled
	close_button.disabled = not enabled
	reduced_motion_button.disabled = not enabled
	sfx_button.disabled = not enabled
	if not enabled:
		settings_layer.visible = false


func _on_resolution_selected(index: int) -> void:
	var target_size = Vector2i(1280, 720)
	match index:
		0:
			target_size = Vector2i(1280, 720)
		1:
			target_size = Vector2i(1920, 1080)
		2:
			target_size = Vector2i(1920, 1200)
		3:
			target_size = Vector2i(2560, 1440)
		4:
			target_size = Vector2i(2560, 1600)
		5:
			target_size = Vector2i(3840, 2160)
	var screen = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen)

	if target_size.x >= screen_size.x and target_size.y >= screen_size.y:
		# Selected resolution matches or exceeds the monitor - fill it edge-to-edge.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(target_size)
		DisplayServer.window_set_position((screen_size - target_size) / 2)


func _on_map_pressed() -> void:
	map_select_layer.visible = true
	_populate_map_cards()
	close_map_button.grab_focus()


func _on_close_map_pressed() -> void:
	map_select_layer.visible = false
	map_button.grab_focus()


func _populate_map_cards() -> void:
	for child in map_cards_container.get_children():
		child.queue_free()
	
	var current_scene_name = get_tree().current_scene.scene_file_path.get_file().get_basename()
	var current_map_id = "junkyard" # default
	if current_scene_name == "metropolis_preview":
		current_map_id = "metropolis"
	elif current_scene_name == "junkyard_job":
		current_map_id = "junkyard"
	
	for map_config in MapConfig.get_maps():
		var card = MAP_SELECT_CARD_SCENE.instantiate()
		map_cards_container.add_child(card)
		card.configure(map_config, current_map_id)
		card.map_selected.connect(_on_map_selected)
		
	# Focus the first enabled map card that is unlocked and not current, if any. Otherwise close button has focus
	for card in map_cards_container.get_children():
		if card.disabled == false and card.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND:
			card.grab_focus()
			break


func _on_map_selected(map_id: String) -> void:
	map_select_layer.visible = false
	map_requested.emit(map_id)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if map_select_layer.visible:
			_on_close_map_pressed()
			get_viewport().set_input_as_handled()
		elif settings_layer.visible:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
