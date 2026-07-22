extends Button

## Untyped machine param — see machine_selector_panel.gd for why.
signal purchase_requested(machine)
signal selected(machine)

@onready var ticket_art: TextureRect = %TicketArt
@onready var machine_name: Label = %MachineName
@onready var price_label: Label = %PriceLabel

var _machine
var _purchase_enabled := true
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


func configure(machine, is_selected: bool) -> void:
	_machine = machine
	button_pressed = is_selected
	refresh()


func refresh() -> void:
	if _machine == null:
		disabled = true
		return
	ticket_art.texture = _machine.ticket_texture
	machine_name.text = _machine.display_name
	_update_name_font_size()
	var shortfall := Economy.get_shortfall(_machine.ticket_price)
	disabled = not _purchase_enabled or shortfall > 0
	price_label.text = "$%d" % _machine.ticket_price


func _update_name_font_size() -> void:
	if machine_name == null or _machine == null:
		return
	var text_len: int = _machine.display_name.length()
	var font_size := 15
	if text_len > 16:
		font_size = 11
	elif text_len > 11:
		font_size = 13
	machine_name.add_theme_font_size_override("font_size", font_size)


func set_selected(is_selected: bool) -> void:
	button_pressed = is_selected


func set_purchase_enabled(enabled: bool) -> void:
	_purchase_enabled = enabled
	refresh()


func get_machine():
	return _machine


func get_buy_button() -> Button:
	return self


func _on_pressed() -> void:
	if _machine != null and not disabled:
		selected.emit(_machine)
		purchase_requested.emit(_machine)
