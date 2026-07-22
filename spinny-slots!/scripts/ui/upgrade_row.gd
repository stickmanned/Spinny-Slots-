extends Button

signal upgrade_requested(upgrade_id: StringName)

@onready var upgrade_icon: TextureRect = %UpgradeIcon
@onready var upgrade_name: Label = %UpgradeName
@onready var upgrade_status: Label = %UpgradeStatus
@onready var cost_label: Label = %CostLabel

var _config: UpgradeConfig
var _hover_tween: Tween
## Upgrade data source. Defaults to Economy (Junkyard's global tracks); the
## Metropolis screen swaps in a per-machine provider. Any object exposing the
## same get_upgrade_level/multiplier/cost, is_upgrade_maxed, and can_afford
## methods works, so this row never needs to know which area it serves.
var _provider: Object = Economy


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


func set_provider(provider: Object) -> void:
	if provider != null:
		_provider = provider


func configure(config: UpgradeConfig) -> void:
	_config = config
	upgrade_name.text = config.display_name
	upgrade_icon.texture = config.icon
	tooltip_text = config.tooltip
	refresh(true)


func refresh(purchases_enabled: bool) -> void:
	if _config == null:
		return
	var level: int = _provider.get_upgrade_level(_config.upgrade_id)
	var multiplier: float = _provider.get_upgrade_multiplier(_config.upgrade_id)
	upgrade_status.text = "LV %d  •  %s" % [level, _format_multiplier(multiplier)]
	if _provider.is_upgrade_maxed(_config.upgrade_id):
		cost_label.text = "MAX"
		disabled = true
		return
	var cost: int = _provider.get_upgrade_cost(_config.upgrade_id)
	cost_label.text = "$%s" % _format_cost(cost)
	disabled = not purchases_enabled or not _provider.can_afford(cost)


## Metropolis upgrade costs reach the millions; abbreviate so they fit the row.
func _format_cost(amount: int) -> String:
	if amount >= 1_000_000:
		return ("%.2f" % (float(amount) / 1_000_000.0)).trim_suffix("0").trim_suffix("0").trim_suffix(".") + "M"
	if amount >= 10_000:
		return "%dK" % roundi(float(amount) / 1_000.0)
	return str(amount)


func _on_pressed() -> void:
	if _config != null:
		upgrade_requested.emit(_config.upgrade_id)


func _format_multiplier(multiplier: float) -> String:
	if is_equal_approx(multiplier, roundf(multiplier)):
		return "%dx" % roundi(multiplier)
	return ("%.2f" % multiplier).trim_suffix("0") + "x"
