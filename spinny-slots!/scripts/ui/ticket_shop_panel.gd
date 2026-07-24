extends PanelContainer

## Untyped machine params so this panel serves both Junkyard (MachineDefinition)
## and Metropolis (MetropolisMachineDefinition) — see machine_selector_panel.gd.
signal purchase_requested(machine)
signal machine_selected(machine)

const TICKET_ROW_SCENE: PackedScene = preload("res://scenes/ui/ticket_list_row.tscn")
const REVEAL_STAGGER := 0.1
const REVEAL_SCALE_DURATION := 0.32
const REVEAL_FADE_DURATION := 0.22

@onready var balance_label: Label = %BalanceLabel
@onready var ticket_rows: VBoxContainer = %TicketRows

var _machines: Array = []
var _selected_machine_id: StringName
var _purchase_enabled := true


func set_extension_mode(enabled: bool) -> void:
	balance_label.visible = not enabled


func configure(machine) -> void:
	var machines: Array = []
	if machine != null:
		machines.append(machine)
	configure_machines(machines, machine.machine_id if machine != null else &"")


func configure_machines(machines: Array, selected_machine_id: StringName = &"", animate_reveal: bool = false) -> void:
	_machines = machines.duplicate()
	_selected_machine_id = selected_machine_id
	if _selected_machine_id.is_empty() and not _machines.is_empty():
		_selected_machine_id = _machines[0].machine_id
	_rebuild_rows(animate_reveal)
	refresh()


func refresh() -> void:
	balance_label.text = NumberFormatter.currency(GameState.money)
	for child in ticket_rows.get_children():
		child.call("refresh")


func set_purchase_enabled(enabled: bool) -> void:
	_purchase_enabled = enabled
	for child in ticket_rows.get_children():
		child.call("set_purchase_enabled", enabled)


func get_selected_machine():
	for machine in _machines:
		if machine.machine_id == _selected_machine_id:
			return machine
	return null


func get_row_count() -> int:
	return ticket_rows.get_child_count()


func get_buy_button(machine_id: StringName) -> Button:
	for child in ticket_rows.get_children():
		var machine = child.call("get_machine")
		if machine != null and machine.machine_id == machine_id:
			return child.call("get_buy_button") as Button
	return null


func select_machine(machine_id: StringName, emit_signal: bool = false) -> void:
	_selected_machine_id = machine_id
	for child in ticket_rows.get_children():
		var machine = child.call("get_machine")
		child.call("set_selected", machine != null and machine.machine_id == machine_id)
	if emit_signal:
		var selected_machine = get_selected_machine()
		if selected_machine != null:
			machine_selected.emit(selected_machine)


func _rebuild_rows(animate_reveal: bool) -> void:
	var previous_rows: Dictionary = {}
	for child in ticket_rows.get_children():
		var previous_machine = child.call("get_machine")
		if previous_machine != null:
			previous_rows[previous_machine.machine_id] = child

	var revealed_rows: Array[Control] = []
	for index in range(_machines.size()):
		var machine = _machines[index]
		var row: Control = previous_rows.get(machine.machine_id)
		var is_new_row := row == null
		if is_new_row:
			row = TICKET_ROW_SCENE.instantiate()
			row.name = "TicketRow_%s" % machine.machine_id
			row.connect("purchase_requested", _on_row_purchase_requested)
			row.connect("selected", _on_row_selected)
			ticket_rows.add_child(row)
		else:
			previous_rows.erase(machine.machine_id)
		ticket_rows.move_child(row, index)
		row.call("configure", machine, machine.machine_id == _selected_machine_id)
		row.call("set_purchase_enabled", _purchase_enabled)
		if is_new_row and animate_reveal:
			revealed_rows.append(row)

	for stale_row in previous_rows.values():
		stale_row.queue_free()

	if not revealed_rows.is_empty():
		_play_reveal_animation(revealed_rows)


func _play_reveal_animation(rows: Array[Control]) -> void:
	if GameState.reduced_motion:
		for row in rows:
			row.modulate.a = 1.0
			row.scale = Vector2.ONE
		return
	for row in rows:
		row.modulate.a = 0.0
		row.scale = Vector2(1.0, 0.08)
	for index in range(rows.size()):
		# Deferred so each row's container-assigned size is settled before
		# the pivot is measured, matching this project's other reveal tweens.
		_start_row_reveal.call_deferred(rows[index], index * REVEAL_STAGGER)


func _start_row_reveal(row: Control, delay: float) -> void:
	if not is_instance_valid(row):
		return
	row.pivot_offset = Vector2(row.size.x * 0.5, 0.0)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "scale", Vector2.ONE, REVEAL_SCALE_DURATION)
	tween.parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(row, "modulate:a", 1.0, REVEAL_FADE_DURATION)


func _on_row_purchase_requested(machine) -> void:
	purchase_requested.emit(machine)


func _on_row_selected(machine) -> void:
	select_machine(machine.machine_id)
	machine_selected.emit(machine)
