extends Node

const DAY_JOB_ECONOMY: EconomyConfig = preload("res://resources/economy/day_job_economy.tres")
const UPGRADE_CONFIGS: Array[UpgradeConfig] = [
	preload("res://resources/upgrades/luck.tres"),
	preload("res://resources/upgrades/spin_speed.tres"),
	preload("res://resources/upgrades/coin_multiplier.tres"),
]
const REEL_COUNT := 3
# Luck boosts every non-common symbol; the common symbol can never drop below
# this share of the total weight, so common results stay possible.
const COMMON_WEIGHT_FLOOR := 0.05

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func set_rng_seed(value: int) -> void:
	_rng.seed = value


func get_starting_balance() -> int:
	return DAY_JOB_ECONOMY.starting_balance


func get_day_job_bag_payout() -> int:
	return DAY_JOB_ECONOMY.day_job_bag_payout


func award_day_job_bag() -> int:
	var payout := get_day_job_bag_payout()
	GameState.add_money(payout)
	return payout


func can_afford(amount: int) -> bool:
	return amount >= 0 and GameState.money >= amount


func get_shortfall(amount: int) -> int:
	return maxi(amount - GameState.money, 0)


func purchase_ticket(machine: MachineDefinition) -> bool:
	if machine == null or not can_afford(machine.ticket_price):
		return false
	if not GameState.spend_money(machine.ticket_price):
		return false
	GameState.add_machine_ticket(machine.machine_id)
	GameState.unlock_machine(machine.machine_id)
	return true


func get_symbol_weight_total(machine: MachineDefinition) -> float:
	if machine == null:
		return 0.0
	var total := 0.0
	for symbol in machine.symbols:
		total += maxf(symbol.weight, 0.0)
	return total


func get_effective_symbol_weights(machine: MachineDefinition) -> Dictionary:
	return calculate_effective_symbol_weights(machine, get_upgrade_multiplier(&"luck"))


## Pure weight calculation for simulations and isolated battle scores. The
## supplied multiplier affects every symbol except the machine's most common
## symbol while preserving the machine's configured total weight and common
## symbol floor. This method does not read or mutate GameState or the Economy
## RNG.
func calculate_effective_symbol_weights(
	machine: MachineDefinition,
	non_common_weight_multiplier: float = 1.0
) -> Dictionary:
	if machine == null or machine.symbols.is_empty():
		return {}
	var total := get_symbol_weight_total(machine)
	if total <= 0.0:
		return {}
	var common := _get_most_common_symbol(machine)
	var safe_multiplier := maxf(non_common_weight_multiplier, 0.0)
	var weights: Dictionary = {}
	var boosted_total := 0.0
	for symbol in machine.symbols:
		if symbol == common:
			continue
		var weight := maxf(symbol.weight, 0.0) * safe_multiplier
		weights[symbol.symbol_id] = weight
		boosted_total += weight
	var floor_weight := total * COMMON_WEIGHT_FLOOR
	var common_weight := total - boosted_total
	if common_weight < floor_weight and boosted_total > 0.0:
		var squeeze := (total - floor_weight) / boosted_total
		for symbol_id in weights:
			weights[symbol_id] *= squeeze
		common_weight = floor_weight
	weights[common.symbol_id] = common_weight
	return weights


func get_symbol_probability(machine: MachineDefinition, symbol: SlotSymbol) -> float:
	var total := get_symbol_weight_total(machine)
	if total <= 0.0:
		return 0.0
	var weights := get_effective_symbol_weights(machine)
	return float(weights.get(symbol.symbol_id, 0.0)) / total


func get_expected_payout(machine: MachineDefinition) -> float:
	if machine == null:
		return 0.0
	var expected_per_reel := 0.0
	for symbol in machine.symbols:
		expected_per_reel += get_symbol_probability(machine, symbol) * symbol.payout
	return expected_per_reel * REEL_COUNT * get_upgrade_multiplier(&"coin_multiplier")


func prepare_machine_spin(machine: MachineDefinition) -> Dictionary:
	if machine == null or machine.symbols.is_empty():
		return {}
	if not GameState.consume_machine_ticket(machine.machine_id):
		return {}
	return calculate_machine_spin(
		machine,
		_rng,
		get_upgrade_multiplier(&"luck"),
		get_upgrade_multiplier(&"coin_multiplier")
	)


## Calculates a complete spin from caller-owned inputs without consuming a
## ticket, changing the wallet, reading upgrades, or mutating permanent state.
## The caller owns the supplied RNG, making the result reproducible by seed.
## Presentation code should animate this finished result and only then commit
## its reward through the appropriate normal- or battle-score path.
func calculate_machine_spin(
	machine: MachineDefinition,
	rng: RandomNumberGenerator,
	non_common_weight_multiplier: float = 1.0,
	payout_multiplier: float = 1.0
) -> Dictionary:
	if machine == null or machine.symbols.is_empty() or rng == null:
		return {}
	var symbols: Array[SlotSymbol] = []
	var base_total := 0
	for _reel_index in range(REEL_COUNT):
		var symbol := roll_symbol_with_rng(machine, rng, non_common_weight_multiplier)
		symbols.append(symbol)
		base_total += symbol.payout
	# Payouts are always rounded down to whole dollars.
	var payout := floori(base_total * maxf(payout_multiplier, 0.0))
	var rarest_symbol := get_rarest_symbol(machine)
	var rarest_hits := 0
	if rarest_symbol != null:
		for symbol in symbols:
			if symbol == rarest_symbol:
				rarest_hits += 1
	return {
		"machine_id": machine.machine_id,
		"symbols": symbols,
		"base_total": base_total,
		"payout": payout,
		"rarest_hits": rarest_hits,
	}


func award_machine_spin(outcome: Dictionary) -> int:
	var payout := maxi(int(outcome.get("payout", 0)), 0)
	GameState.add_money(payout)
	return payout


## Gems awarded for landing a machine's rarest symbol, scaled by how many
## copies landed in one spin. Call once per spin outcome, after the reward
## presentation, so a duplicated call can never double-award gems.
func award_rarest_bonus(machine: MachineDefinition, outcome: Dictionary) -> int:
	if machine == null:
		return 0
	var rarest_hits := maxi(int(outcome.get("rarest_hits", 0)), 0)
	var gems := machine.rarest_symbol_gem_reward * rarest_hits
	if gems > 0:
		GameState.add_gems(gems)
	return gems


func roll_symbol(machine: MachineDefinition) -> SlotSymbol:
	return roll_symbol_with_rng(machine, _rng, get_upgrade_multiplier(&"luck"))


## Pure symbol roll using a caller-owned RNG and explicit non-common weight
## multiplier. It deliberately mirrors roll_symbol's ordering and boundary
## behavior so existing seeded normal spins remain unchanged.
func roll_symbol_with_rng(
	machine: MachineDefinition,
	rng: RandomNumberGenerator,
	non_common_weight_multiplier: float = 1.0
) -> SlotSymbol:
	if machine == null or machine.symbols.is_empty() or rng == null:
		return null
	var total := get_symbol_weight_total(machine)
	if total <= 0.0:
		return machine.symbols[0]
	var weights := calculate_effective_symbol_weights(machine, non_common_weight_multiplier)
	var roll := rng.randf() * total
	var cumulative := 0.0
	for symbol in machine.symbols:
		cumulative += float(weights.get(symbol.symbol_id, 0.0))
		if roll < cumulative:
			return symbol
	return machine.symbols[machine.symbols.size() - 1]


func get_upgrade_configs() -> Array[UpgradeConfig]:
	return UPGRADE_CONFIGS


func get_upgrade_config(upgrade_id: StringName) -> UpgradeConfig:
	for config in UPGRADE_CONFIGS:
		if config.upgrade_id == upgrade_id:
			return config
	return null


func get_upgrade_level(upgrade_id: StringName) -> int:
	var config := get_upgrade_config(upgrade_id)
	if config == null:
		return 0
	return mini(GameState.get_upgrade_level(upgrade_id), config.max_level)


func get_upgrade_multiplier(upgrade_id: StringName) -> float:
	var config := get_upgrade_config(upgrade_id)
	if config == null:
		return 1.0
	return 1.0 + config.effect_per_level * get_upgrade_level(upgrade_id)


func is_upgrade_maxed(upgrade_id: StringName) -> bool:
	var config := get_upgrade_config(upgrade_id)
	return config != null and get_upgrade_level(upgrade_id) >= config.max_level


func get_upgrade_cost(upgrade_id: StringName) -> int:
	var config := get_upgrade_config(upgrade_id)
	if config == null or is_upgrade_maxed(upgrade_id):
		return -1
	return roundi(config.base_cost * pow(config.cost_growth, get_upgrade_level(upgrade_id)))


func purchase_upgrade(upgrade_id: StringName) -> bool:
	var cost := get_upgrade_cost(upgrade_id)
	if cost < 0 or not can_afford(cost):
		return false
	if not GameState.spend_money(cost):
		return false
	GameState.increment_upgrade_level(upgrade_id)
	return true


func get_spin_speed_multiplier() -> float:
	return get_upgrade_multiplier(&"spin_speed")


func _get_most_common_symbol(machine: MachineDefinition) -> SlotSymbol:
	var common: SlotSymbol = machine.symbols[0]
	for symbol in machine.symbols:
		if symbol.weight > common.weight:
			common = symbol
	return common


## The lowest-weight (rarest) symbol on a machine. Landing this is the
## trigger for the confetti celebration and the rarest-item gem bonus.
func get_rarest_symbol(machine: MachineDefinition) -> SlotSymbol:
	if machine == null or machine.symbols.is_empty():
		return null
	var rarest: SlotSymbol = machine.symbols[0]
	for symbol in machine.symbols:
		if symbol.weight < rarest.weight:
			rarest = symbol
	return rarest
