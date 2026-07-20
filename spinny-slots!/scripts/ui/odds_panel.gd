extends PanelContainer

const ODDS_ROW_SCENE: PackedScene = preload("res://scenes/ui/odds_row.tscn")

@onready var rows_container: VBoxContainer = %Rows


func configure(machine: MachineDefinition) -> void:
	for child in rows_container.get_children():
		child.queue_free()
	if machine == null:
		return
	for symbol in machine.symbols:
		var row := ODDS_ROW_SCENE.instantiate()
		rows_container.add_child(row)
		row.call("configure", symbol, Economy.get_symbol_probability(machine, symbol))
