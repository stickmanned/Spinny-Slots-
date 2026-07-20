extends Control

signal ticket_purchase_confirmed(machine_id: StringName)
signal spin_started(machine_id: StringName)
signal spin_completed(machine_id: StringName, payout: int)

const JUNKYARD_PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")

@onready var ticket_shop: PanelContainer = %TicketShopPanel
@onready var selector: PanelContainer = %MachineSelectorPanel
@onready var balance_label: Label = %BalanceLabel
@onready var spin_ticket_label: Label = %SpinTicketLabel
@onready var spin_button: Button = %SpinButton
@onready var result_label: Label = %ResultLabel
@onready var payout_label: Label = %PayoutLabel
@onready var coin_collection_effect: CoinCollectionEffect = %CoinCollectionEffect

var _selected_machine: MachineDefinition
var _spin_in_progress := false
var _balance_pulse_tween: Tween


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.machine_tickets_changed.connect(_on_machine_tickets_changed)
	ticket_shop.connect("purchase_requested", _on_purchase_requested)
	selector.connect("selection_changed", _on_selection_changed)
	spin_button.pressed.connect(_on_spin_pressed)
	coin_collection_effect.balance_progressed.connect(_set_presented_balance)
	coin_collection_effect.balance_pulse_requested.connect(_pulse_balance)
	coin_collection_effect.coin_sound_requested.connect(AudioFx.play_coin_drop)
	selector.call("configure", JUNKYARD_PROGRESSION.machines, GameState.selected_machine_id)
	selector.call("set_select_button_visible", false)
	_selected_machine = selector.call("get_selected_machine") as MachineDefinition
	if _selected_machine != null:
		GameState.selected_machine_id = _selected_machine.machine_id
		ticket_shop.call("configure", _selected_machine)
	_refresh()


func _on_money_changed(_value: int) -> void:
	_refresh()


func _on_machine_tickets_changed(_machine_id: StringName, _count: int) -> void:
	_refresh()


func _on_selection_changed(machine: MachineDefinition) -> void:
	_selected_machine = machine
	GameState.selected_machine_id = machine.machine_id
	ticket_shop.call("configure", machine)
	result_label.text = ""
	payout_label.text = ""
	_refresh()


func _on_purchase_requested(machine: MachineDefinition) -> void:
	if not Economy.purchase_ticket(machine):
		_refresh()
		return
	ticket_purchase_confirmed.emit(machine.machine_id)
	var flourish := create_tween()
	flourish.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flourish.tween_property(ticket_shop, "scale", Vector2.ONE * 1.025, 0.12)
	flourish.tween_property(ticket_shop, "scale", Vector2.ONE, 0.16)
	_refresh()


func _on_spin_pressed() -> void:
	if _spin_in_progress or _selected_machine == null:
		return
	var outcome := Economy.prepare_machine_spin(_selected_machine)
	if outcome.is_empty():
		_refresh()
		return

	_spin_in_progress = true
	spin_started.emit(_selected_machine.machine_id)
	result_label.text = "SPINNING..."
	payout_label.text = ""
	_refresh()
	await selector.call("play_spin_flourish", 0.72)
	var names: Array[String] = []
	for symbol in outcome.get("symbols", []):
		names.append((symbol as SlotSymbol).display_name)
	result_label.text = "  •  ".join(names)
	var pending_payout := maxi(int(outcome.get("payout", 0)), 0)
	payout_label.text = "+%d COINS" % pending_payout
	await coin_collection_effect.play(
		pending_payout,
		GameState.money,
		payout_label,
		balance_label,
		GameState.reduced_motion
	)
	if not is_inside_tree():
		return
	var payout := Economy.award_machine_spin(outcome)
	spin_completed.emit(_selected_machine.machine_id, payout)
	_spin_in_progress = false
	_refresh()


func _refresh() -> void:
	balance_label.text = "Balance: $%d" % GameState.money
	if _selected_machine == null:
		spin_ticket_label.text = "No machine selected"
		spin_button.disabled = true
		return
	var ticket_count := GameState.get_machine_ticket_count(_selected_machine.machine_id)
	spin_ticket_label.text = "%s tickets: %d" % [_selected_machine.display_name, ticket_count]
	spin_button.text = "SPIN"
	spin_button.disabled = _spin_in_progress or ticket_count <= 0
	ticket_shop.call("refresh")


func _set_presented_balance(value: int) -> void:
	balance_label.text = "Balance: $%d" % value


func _pulse_balance() -> void:
	if _balance_pulse_tween and _balance_pulse_tween.is_valid():
		_balance_pulse_tween.kill()
	balance_label.pivot_offset = balance_label.size * 0.5
	balance_label.scale = Vector2.ONE * 1.08
	_balance_pulse_tween = create_tween()
	_balance_pulse_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_balance_pulse_tween.tween_property(balance_label, "scale", Vector2.ONE, 0.14)
