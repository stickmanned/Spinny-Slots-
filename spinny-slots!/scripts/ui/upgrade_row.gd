extends Button

signal upgrade_requested(upgrade_id: StringName)

@onready var upgrade_icon: TextureRect = %UpgradeIcon
@onready var upgrade_name: Label = %UpgradeName
@onready var upgrade_status: Label = %UpgradeStatus
@onready var cost_label: Label = %CostLabel

var _config: UpgradeConfig
var _hover_tween: Tween


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_update_pivot)
	_update_pivot()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	z_index = 10
	_animate_scale(Vector2(1.025, 1.025))


func _on_mouse_exited() -> void:
	z_index = 0
	_animate_scale(Vector2.ONE)


func _animate_scale(target_scale: Vector2) -> void:
	_update_pivot()
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target_scale, 0.12)


func configure(config: UpgradeConfig) -> void:
	_config = config
	upgrade_name.text = config.display_name
	upgrade_icon.texture = config.icon
	tooltip_text = config.tooltip
	refresh(true)


func refresh(purchases_enabled: bool) -> void:
	if _config == null:
		return
	var level := Economy.get_upgrade_level(_config.upgrade_id)
	var multiplier := Economy.get_upgrade_multiplier(_config.upgrade_id)
	upgrade_status.text = "LV %d  •  %s" % [level, _format_multiplier(multiplier)]
	if Economy.is_upgrade_maxed(_config.upgrade_id):
		cost_label.text = "MAX"
		disabled = true
		return
	var cost := Economy.get_upgrade_cost(_config.upgrade_id)
	cost_label.text = "$%d" % cost
	disabled = not purchases_enabled or not Economy.can_afford(cost)


func _on_pressed() -> void:
	if _config != null:
		upgrade_requested.emit(_config.upgrade_id)


func _format_multiplier(multiplier: float) -> String:
	if is_equal_approx(multiplier, roundf(multiplier)):
		return "%dx" % roundi(multiplier)
	return ("%.2f" % multiplier).trim_suffix("0") + "x"
