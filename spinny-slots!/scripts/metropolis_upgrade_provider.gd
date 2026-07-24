class_name MetropolisUpgradeProvider
extends RefCounted

## Legacy adapter kept for compatibility. Both areas now delegate to Economy's
## persistent global track, so changing machines cannot reset levels or costs.

var _machine: MetropolisMachineDefinition


func _init(machine: MetropolisMachineDefinition) -> void:
	_machine = machine


func get_upgrade_configs() -> Array[UpgradeConfig]:
	return Economy.get_upgrade_configs()


func get_upgrade_level(upgrade_id: StringName) -> int:
	return Economy.get_upgrade_level(upgrade_id)


func get_upgrade_multiplier(upgrade_id: StringName) -> float:
	return Economy.get_upgrade_multiplier(upgrade_id)


func is_upgrade_maxed(upgrade_id: StringName) -> bool:
	return Economy.is_upgrade_maxed(upgrade_id)


func get_upgrade_cost(upgrade_id: StringName) -> int:
	return Economy.get_upgrade_cost(upgrade_id)


func can_afford(amount: int) -> bool:
	return Economy.can_afford(amount)


func purchase_upgrade(upgrade_id: StringName) -> bool:
	return Economy.purchase_upgrade(upgrade_id)
