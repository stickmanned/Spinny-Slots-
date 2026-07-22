class_name MetropolisUpgradeProvider
extends RefCounted

## Adapts one Metropolis machine's per-machine upgrade track to the same
## interface the shared HUD upgrade panel already expects from Economy
## (Junkyard). This lets the exact same upgrade UI drive either area without
## the UI knowing which economy it is talking to.

var _machine: MetropolisMachineDefinition


func _init(machine: MetropolisMachineDefinition) -> void:
	_machine = machine


func get_upgrade_configs() -> Array[UpgradeConfig]:
	return MetropolisEconomy.get_upgrade_configs()


func get_upgrade_level(upgrade_id: StringName) -> int:
	return MetropolisEconomy.get_upgrade_level(_machine.machine_id, upgrade_id)


func get_upgrade_multiplier(upgrade_id: StringName) -> float:
	return MetropolisEconomy.get_upgrade_multiplier(_machine.machine_id, upgrade_id)


func is_upgrade_maxed(upgrade_id: StringName) -> bool:
	return MetropolisEconomy.is_upgrade_maxed(_machine.machine_id, upgrade_id)


func get_upgrade_cost(upgrade_id: StringName) -> int:
	return MetropolisEconomy.get_upgrade_cost(_machine, upgrade_id)


func can_afford(amount: int) -> bool:
	return Economy.can_afford(amount)


func purchase_upgrade(upgrade_id: StringName) -> bool:
	return MetropolisEconomy.purchase_upgrade(_machine, upgrade_id)
