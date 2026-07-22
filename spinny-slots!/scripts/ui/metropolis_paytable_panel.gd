extends PanelContainer

const PAYTABLE_ROW_SCENE: PackedScene = preload("res://scenes/ui/metropolis_paytable_row.tscn")

@onready var rows_container: VBoxContainer = %Rows


## Reads entirely from the machine's own data, so it automatically shows the
## correct 3-, 4-, or 5-reel payout curve for whichever machine is
## selected, with no per-machine UI code.
func configure(machine: MetropolisMachineDefinition) -> void:
	for child in rows_container.get_children():
		child.queue_free()
	if machine == null:
		return
	for symbol in machine.symbols:
		var row := PAYTABLE_ROW_SCENE.instantiate()
		rows_container.add_child(row)
		row.call(
			"configure",
			symbol,
			machine.get_payout_tier(symbol.tier),
			MetropolisEconomy.get_symbol_probability(machine, symbol)
		)
