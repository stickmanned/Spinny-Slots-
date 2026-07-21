class_name JunkKingBattleConfig
extends Resource

@export_group("Battle")
@export_range(1, 100, 1) var regulation_rounds: int = 10
@export_range(1, 10, 1) var loadout_size: int = 3
@export_range(1, 10, 1) var base_machine_appearances: int = 3
@export_range(1, 10, 1) var extra_machine_appearances: int = 1
@export_range(1, 2147483647, 1) var score_cap: int = 2147483647

@export_group("Catalog")
@export var machines: Array[MachineDefinition] = []
@export var junkyard_upgrades: Array[UpgradeConfig] = []
@export var power_ups: Array[PowerUpDefinition] = []
@export var boss_loadout: Array[PowerUpDefinition] = []
@export var boss_loadout_visible: bool = true

@export_group("Junk King AI")
@export_range(1, 100, 1) var odds_disruptor_round: int = 4
@export_range(1, 100, 1) var payout_siphon_round: int = 8


func get_power_up(power_up_id: StringName) -> PowerUpDefinition:
	for definition in power_ups:
		if definition != null and definition.power_up_id == power_up_id:
			return definition
	return null


func has_power_up(power_up_id: StringName) -> bool:
	return get_power_up(power_up_id) != null


func get_machine(machine_id: StringName) -> MachineDefinition:
	for machine in machines:
		if machine != null and machine.machine_id == machine_id:
			return machine
	return null


func get_upgrade(upgrade_id: StringName) -> UpgradeConfig:
	for upgrade in junkyard_upgrades:
		if upgrade != null and upgrade.upgrade_id == upgrade_id:
			return upgrade
	return null


## Creates a value-only snapshot for one contestant. The returned nested
## dictionaries share no mutable state with GameState or another contestant.
func make_upgrade_profile(requested_levels: Dictionary, use_maximums: bool = false) -> Dictionary:
	var levels: Dictionary = {}
	var maximum_levels: Dictionary = {}
	var multipliers: Dictionary = {}
	var display_names: Dictionary = {}
	for upgrade in junkyard_upgrades:
		if upgrade == null:
			continue
		var key := String(upgrade.upgrade_id)
		var requested_level := int(requested_levels.get(key, 0))
		var level := upgrade.max_level if use_maximums else clampi(requested_level, 0, upgrade.max_level)
		levels[key] = level
		maximum_levels[key] = upgrade.max_level
		multipliers[key] = 1.0 + upgrade.effect_per_level * level
		display_names[key] = upgrade.display_name
	return {
		"levels": levels,
		"maximum_levels": maximum_levels,
		"multipliers": multipliers,
		"display_names": display_names,
	}.duplicate(true)


## Returns human-readable errors instead of asserting so scene code and
## deterministic tests can report a malformed designer Resource cleanly.
func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if regulation_rounds != 10:
		errors.append("The Junk King battle must have exactly 10 regulation rounds.")
	if loadout_size != 3:
		errors.append("Each Junk King battle loadout must contain exactly 3 power-ups.")
	if machines.size() != 3:
		errors.append("The Junk King battle must reference exactly 3 Junkyard machines.")
	if regulation_rounds != machines.size() * base_machine_appearances + extra_machine_appearances:
		errors.append("The machine schedule must contain three of every machine plus one extra.")
	if extra_machine_appearances != 1:
		errors.append("The Junk King schedule must contain exactly one extra machine appearance.")
	if score_cap <= 0:
		errors.append("The battle score cap must be positive.")
	var machine_ids: Dictionary = {}
	for machine in machines:
		if machine == null or machine.machine_id == &"":
			errors.append("Every battle machine must be a valid configured Resource.")
			continue
		if machine_ids.has(machine.machine_id):
			errors.append("Battle machine IDs must be unique: %s." % machine.machine_id)
		machine_ids[machine.machine_id] = true
	var required_upgrade_ids: Array[StringName] = [&"luck", &"coin_multiplier", &"spin_speed"]
	var upgrade_ids: Dictionary = {}
	for upgrade in junkyard_upgrades:
		if upgrade == null or upgrade.upgrade_id == &"":
			errors.append("Every Junkyard battle upgrade must be a valid configured Resource.")
			continue
		if upgrade_ids.has(upgrade.upgrade_id):
			errors.append("Junkyard battle upgrade IDs must be unique: %s." % upgrade.upgrade_id)
		upgrade_ids[upgrade.upgrade_id] = true
	for required_id in required_upgrade_ids:
		if not upgrade_ids.has(required_id):
			errors.append("The Junk King battle is missing the %s Junkyard upgrade." % required_id)
	var power_up_ids: Dictionary = {}
	for definition in power_ups:
		if definition == null or definition.power_up_id == &"":
			errors.append("Every power-up must be a valid configured Resource.")
			continue
		if power_up_ids.has(definition.power_up_id):
			errors.append("Power-up IDs must be unique: %s." % definition.power_up_id)
		power_up_ids[definition.power_up_id] = true
	if boss_loadout.size() != loadout_size:
		errors.append("The Junk King's loadout must contain exactly %d power-ups." % loadout_size)
	var boss_ids: Dictionary = {}
	for definition in boss_loadout:
		if definition == null or not power_up_ids.has(definition.power_up_id):
			errors.append("Every Junk King power-up must come from the battle catalog.")
			continue
		if boss_ids.has(definition.power_up_id):
			errors.append("The Junk King's loadout cannot contain duplicates.")
		boss_ids[definition.power_up_id] = true
	if odds_disruptor_round < 1 or odds_disruptor_round > regulation_rounds:
		errors.append("The Odds Disruptor AI round must be inside regulation.")
	if payout_siphon_round < 1 or payout_siphon_round > regulation_rounds:
		errors.append("The Payout Siphon AI round must be inside regulation.")
	return errors
