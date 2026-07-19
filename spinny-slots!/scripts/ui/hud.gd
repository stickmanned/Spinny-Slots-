extends CanvasLayer

const UPGRADE_ROW_SCENE: PackedScene = preload("res://scenes/ui/upgrade_row.tscn")
const PLACEHOLDER_UPGRADES: Array[Dictionary] = [
	{"name": "Luck", "disabled": true},
	{"name": "Spin Speed", "disabled": true},
	{"name": "Money Multiplier", "disabled": true},
]

@onready var coin_value: Label = %CoinValue
@onready var gem_value: Label = %GemValue
@onready var upgrade_rows: VBoxContainer = %UpgradeRows
@onready var currency_panel: PanelContainer = %CurrencyPanel
@onready var upgrade_panel: PanelContainer = %UpgradePanel
@onready var settings_button: Button = %SettingsButton
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var close_button: Button = %CloseButton

var _currency_tween: Tween


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.gems_changed.connect(_on_gems_changed)
	_on_money_changed(GameState.money)
	_on_gems_changed(GameState.gems)
	populate(PLACEHOLDER_UPGRADES)
	
	settings_button.pressed.connect(_on_settings_pressed)
	close_button.pressed.connect(_on_close_pressed)
	volume_slider.value = GameState.music_volume
	volume_slider.value_changed.connect(_on_volume_value_changed)
	settings_button.visible = GameState.day_job_tutorial_completed


func hide_all() -> void:
	_stop_visibility_tweens()
	currency_panel.modulate.a = 0.0
	upgrade_panel.modulate.a = 0.0
	settings_button.visible = false


func show_currency(duration: float) -> void:
	if _currency_tween and _currency_tween.is_valid():
		_currency_tween.kill()
	_currency_tween = create_tween()
	_currency_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_currency_tween.tween_property(currency_panel, "modulate:a", 1.0, duration)


func _stop_visibility_tweens() -> void:
	if _currency_tween and _currency_tween.is_valid():
		_currency_tween.kill()


func populate(upgrades: Array) -> void:
	for child in upgrade_rows.get_children():
		child.queue_free()

	for upgrade_value in upgrades:
		var row := UPGRADE_ROW_SCENE.instantiate()
		upgrade_rows.add_child(row)
		var upgrade: Dictionary = upgrade_value if upgrade_value is Dictionary else {"name": str(upgrade_value)}
		row.configure(upgrade)


func _on_money_changed(value: int) -> void:
	coin_value.text = str(value)


func _on_gems_changed(value: int) -> void:
	gem_value.text = str(value)


func _on_settings_pressed() -> void:
	settings_panel.visible = true


func _on_close_pressed() -> void:
	settings_panel.visible = false


func _on_volume_value_changed(value: float) -> void:
	GameState.music_volume = value


func show_settings_button() -> void:
	settings_button.visible = true
