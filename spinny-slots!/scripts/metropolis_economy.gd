extends Node

## Metropolis's spin-resolution engine. Every independently rolled symbol pays
## a flat reward; configured matches and cascades add bonuses on top. It follows
## the same outcome pipeline as Economy: every reel's result (and every mechanic
## effect layered on top of it) is fully computed here before any animation
## plays; GameState is only mutated by prepare_machine_spin (ticket/charge
## costs, paid up front) and award_machine_spin (rewards, applied only after
## presentation finishes).

## Upgrade levels and prices delegate to Economy's persistent global track.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func get_upgrade_configs() -> Array[UpgradeConfig]:
	return Economy.get_upgrade_configs()


func get_upgrade_config(upgrade_id: StringName) -> UpgradeConfig:
	return Economy.get_upgrade_config(upgrade_id)


func get_upgrade_level(_machine_id: StringName, upgrade_id: StringName) -> int:
	return Economy.get_upgrade_level(upgrade_id)


func get_upgrade_multiplier(_machine_id: StringName, upgrade_id: StringName) -> float:
	return Economy.get_upgrade_multiplier(upgrade_id)


func is_upgrade_maxed(_machine_id: StringName, upgrade_id: StringName) -> bool:
	return Economy.is_upgrade_maxed(upgrade_id)


## Cost scales off the machine's own ticket price (cost_fraction_of_ticket),
## grown per level, so one config prices sensibly across every machine.
func get_upgrade_cost(_machine: MetropolisMachineDefinition, upgrade_id: StringName) -> int:
	return Economy.get_upgrade_cost(upgrade_id)


func purchase_upgrade(_machine: MetropolisMachineDefinition, upgrade_id: StringName) -> bool:
	return Economy.purchase_upgrade(upgrade_id)


func get_spin_speed_multiplier(_machine_id: StringName) -> float:
	return Economy.get_spin_speed_multiplier()


func set_rng_seed(value: int) -> void:
	_rng.seed = value


## Guarded spend path (mirrors Economy.purchase_ticket): cash is taken before
## the ticket is ever granted, so a failed spend can never hand out a ticket.
func purchase_ticket(machine: MetropolisMachineDefinition) -> bool:
	if machine == null or not Economy.can_afford(machine.ticket_price):
		return false
	if not GameState.spend_money(machine.ticket_price):
		return false
	GameState.add_machine_ticket(machine.machine_id)
	return true


func get_symbol_weight_total(machine: MetropolisMachineDefinition) -> float:
	if machine == null:
		return 0.0
	var total := 0.0
	for symbol in machine.symbols:
		total += maxf(symbol.weight, 0.0)
	return total


## Boosts every non-Common-tier symbol's weight by non_common_multiplier
## while leaving Common-tier symbols untouched, mirroring the shape of
## Economy.calculate_effective_symbol_weights. Used both at 1.0 (no change)
## and, for one Hack Charge-targeted reel, at the mechanic's configured
## shift multiplier.
func calculate_effective_weights(
	machine: MetropolisMachineDefinition, non_common_multiplier: float = 1.0
) -> Dictionary:
	if machine == null or machine.symbols.is_empty():
		return {}
	var safe_multiplier := maxf(non_common_multiplier, 0.0)
	var weights: Dictionary = {}
	for symbol in machine.symbols:
		var weight := maxf(symbol.weight, 0.0)
		if symbol.tier != MetropolisSymbol.Tier.COMMON:
			weight *= safe_multiplier
		weights[symbol.symbol_id] = weight
	return weights


func get_symbol_probability(machine: MetropolisMachineDefinition, symbol: MetropolisSymbol) -> float:
	if machine == null or symbol == null:
		return 0.0
	var weights := calculate_effective_weights(machine)
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	if total <= 0.0:
		return 0.0
	return float(weights.get(symbol.symbol_id, 0.0)) / total


func roll_symbol_with_rng(
	machine: MetropolisMachineDefinition,
	rng: RandomNumberGenerator,
	non_common_multiplier: float = 1.0
) -> MetropolisSymbol:
	if machine == null or machine.symbols.is_empty() or rng == null:
		return null
	var weights := calculate_effective_weights(machine, non_common_multiplier)
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	if total <= 0.0:
		return machine.symbols[0]
	var roll := rng.randf() * total
	var cumulative := 0.0
	for symbol in machine.symbols:
		cumulative += float(weights.get(symbol.symbol_id, 0.0))
		if roll < cumulative:
			return symbol
	return machine.symbols[machine.symbols.size() - 1]


## Rolls every reel independently. Each reel's symbol is fully decided here,
## before any presentation exists to play back — no reel may be influenced
## by another reel's roll or by anything that happens after this returns.
func roll_reels(
	machine: MetropolisMachineDefinition,
	rng: RandomNumberGenerator,
	per_reel_multiplier: Array = []
) -> Array[MetropolisSymbol]:
	var symbols: Array[MetropolisSymbol] = []
	if machine == null:
		return symbols
	for reel_index in range(machine.reel_count):
		var multiplier := 1.0
		if reel_index < per_reel_multiplier.size():
			multiplier = float(per_reel_multiplier[reel_index])
		symbols.append(roll_symbol_with_rng(machine, rng, multiplier))
	return symbols


## 3-reel machines only ever pay exact 3-of-3; wider machines pay any symbol
## that hits 3 or more times (non-contiguous positions).
func evaluate_matches(
	machine: MetropolisMachineDefinition, symbols: Array[MetropolisSymbol]
) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	if machine == null:
		return matches
	var counts: Dictionary = {}
	var symbol_by_id: Dictionary = {}
	for symbol in symbols:
		if symbol == null:
			continue
		counts[symbol.symbol_id] = int(counts.get(symbol.symbol_id, 0)) + 1
		symbol_by_id[symbol.symbol_id] = symbol
	for symbol_id in counts:
		var count := int(counts[symbol_id])
		var qualifies := count == machine.reel_count if machine.reel_count == 3 else count >= 3
		if not qualifies:
			continue
		var symbol: MetropolisSymbol = symbol_by_id[symbol_id]
		matches.append({
			"symbol_id": symbol_id,
			"symbol": symbol,
			"tier": symbol.tier,
			"count": count,
			"payout": machine.get_payout(symbol.tier, count),
		})
	return matches


func total_payout(matches: Array[Dictionary]) -> int:
	var total := 0
	for match_entry in matches:
		total += int(match_entry.get("payout", 0))
	return total


func total_symbol_payout(symbols: Array[MetropolisSymbol]) -> int:
	var total := 0
	for symbol in symbols:
		if symbol != null:
			total += maxi(symbol.payout, 0)
	return total


## Convenience wrappers over MetropolisEconomy's own RNG, for UI callers that
## don't own a RandomNumberGenerator (mirrors Economy.roll_symbol vs
## roll_symbol_with_rng).
func roll_surge_multiplier_now(machine: MetropolisMachineDefinition) -> float:
	return roll_surge_multiplier(machine, _rng)


func reroll_surge_multiplier_now(machine: MetropolisMachineDefinition, rerolls_used: int) -> Dictionary:
	return reroll_surge_multiplier(machine, _rng, rerolls_used)


func roll_surge_multiplier(machine: MetropolisMachineDefinition, rng: RandomNumberGenerator) -> float:
	if machine == null or machine.mechanic == null or machine.mechanic.surge_multiplier_sequence.is_empty():
		return 1.0
	var sequence := machine.mechanic.surge_multiplier_sequence
	return float(sequence[rng.randi_range(0, sequence.size() - 1)])


## Consumes a reroll (a banked free token first, cash otherwise) and returns
## a freshly, fully predetermined dial value. The caller only animates the
## dial landing on the returned value; it never decides the value itself.
func reroll_surge_multiplier(
	machine: MetropolisMachineDefinition, rng: RandomNumberGenerator, rerolls_used: int
) -> Dictionary:
	if machine == null or machine.mechanic == null:
		return {"ok": false, "message": "This machine has no Surge dial."}
	if rerolls_used >= machine.mechanic.surge_max_rerolls_per_spin:
		return {"ok": false, "message": "No rerolls remaining this spin."}
	var used_free_token := false
	if GameState.get_machine_free_rerolls(machine.machine_id) > 0:
		GameState.consume_machine_free_reroll(machine.machine_id)
		used_free_token = true
	else:
		var cost := machine.mechanic.surge_reroll_cost
		if not Economy.can_afford(cost) or not GameState.spend_money(cost):
			return {"ok": false, "message": "Not enough cash to reroll."}
	return {"ok": true, "value": roll_surge_multiplier(machine, rng), "used_free_token": used_free_token}


## Ticket- and charge-consuming entry point. Mirrors Economy.prepare_machine_spin:
## every cost is paid here, before presentation exists, so a spin can never be
## shown without its cost already committed.
func prepare_machine_spin(machine: MetropolisMachineDefinition, options: Dictionary = {}) -> Dictionary:
	if machine == null or machine.symbols.is_empty():
		return {}
	if not GameState.consume_machine_ticket(machine.machine_id):
		return {}
	var effective_options := options.duplicate()
	# The same persistent upgrade levels apply to every machine in every area.
	effective_options["luck_multiplier"] = Economy.get_upgrade_multiplier(&"luck")
	effective_options["coin_multiplier"] = Economy.get_upgrade_multiplier(&"coin_multiplier")
	var hack_reel_index := int(effective_options.get("spend_hack_charge_on_reel_index", -1))
	if (
		hack_reel_index >= 0
		and hack_reel_index < machine.reel_count
		and machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.HACK_CHARGE
	):
		if not GameState.consume_machine_mechanic_charge(machine.machine_id):
			effective_options["spend_hack_charge_on_reel_index"] = -1
	else:
		effective_options["spend_hack_charge_on_reel_index"] = -1
	return calculate_machine_spin(machine, _rng, effective_options)


## Pure calculation from caller-owned inputs: no ticket, charge, or wallet
## state is read or changed. Reproducible from a seed for tests.
func calculate_machine_spin(
	machine: MetropolisMachineDefinition,
	rng: RandomNumberGenerator,
	options: Dictionary = {}
) -> Dictionary:
	if machine == null or machine.symbols.is_empty() or rng == null:
		return {}

	var hack_reel_index := int(options.get("spend_hack_charge_on_reel_index", -1))
	var hack_charge_spent := (
		hack_reel_index >= 0
		and hack_reel_index < machine.reel_count
		and machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.HACK_CHARGE
	)
	# Luck shifts every reel's non-common weights up; Hack Charge stacks an
	# extra shift onto the one chosen reel for this spin only.
	var luck_multiplier := maxf(float(options.get("luck_multiplier", 1.0)), 0.0)
	var per_reel_multiplier: Array = []
	per_reel_multiplier.resize(machine.reel_count)
	for index in range(machine.reel_count):
		per_reel_multiplier[index] = luck_multiplier
	if hack_charge_spent:
		per_reel_multiplier[hack_reel_index] = luck_multiplier * machine.mechanic.hack_weight_shift_multiplier

	var tiers: Array[Dictionary] = []
	var final_symbols: Array[MetropolisSymbol] = []
	var cascade_jackpot_seen := false
	if machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.CASCADE_MATCH:
		var cascade := _resolve_cascade(machine, rng, luck_multiplier)
		tiers = cascade["tiers"]
		final_symbols = cascade["final_row"]
		cascade_jackpot_seen = bool(cascade["jackpot_seen"])
	else:
		final_symbols = roll_reels(machine, rng, per_reel_multiplier)
		var matches := evaluate_matches(machine, final_symbols)
		tiers = [{
			"row": final_symbols.duplicate(),
			"matches": matches,
			"tier_multiplier": 1.0,
			"payout": total_payout(matches),
		}]

	var initial_symbols: Array[MetropolisSymbol] = final_symbols
	if not tiers.is_empty():
		initial_symbols = tiers[0].get("row", final_symbols)
	var symbol_payout := total_symbol_payout(initial_symbols)
	var match_bonus := 0
	var jackpot_landed := cascade_jackpot_seen
	for tier in tiers:
		match_bonus += int(tier.get("payout", 0))
		var row: Array = tier.get("row", [])
		for symbol in row:
			if symbol != null and symbol.tier == MetropolisSymbol.Tier.JACKPOT:
				jackpot_landed = true

	var gross_payout := symbol_payout + match_bonus
	var surge_multiplier := maxf(float(options.get("surge_multiplier", 1.0)), 0.0)
	var coin_multiplier := maxf(float(options.get("coin_multiplier", 1.0)), 0.0)
	var final_payout := maxi(floori(float(gross_payout) * surge_multiplier * coin_multiplier), 0)
	var mechanic_kind := machine.get_mechanic_kind()

	return {
		"machine_id": machine.machine_id,
		"symbols": final_symbols,
		"tiers": tiers,
		"base_total": symbol_payout,
		"symbol_payout": symbol_payout,
		"match_bonus": match_bonus,
		"gross_payout": gross_payout,
		"surge_multiplier": surge_multiplier,
		"coin_multiplier": coin_multiplier,
		"luck_multiplier": luck_multiplier,
		"payout": final_payout,
		"hack_charge_spent": hack_charge_spent,
		"hack_charge_reel_index": hack_reel_index if hack_charge_spent else -1,
		"awards_hack_charge": jackpot_landed and mechanic_kind == MetropolisMechanicConfig.Kind.HACK_CHARGE,
		"awards_free_reroll": jackpot_landed and mechanic_kind == MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER,
		"jackpot_landed": jackpot_landed,
	}


## Applies the already-fully-computed reward. Called only after the
## presentation layer finishes playing back the outcome from prepare/calculate.
func award_machine_spin(machine: MetropolisMachineDefinition, outcome: Dictionary) -> int:
	var payout := maxi(int(outcome.get("payout", 0)), 0)
	GameState.add_money(payout)
	if machine != null and machine.mechanic != null:
		if bool(outcome.get("awards_hack_charge", false)):
			GameState.add_machine_mechanic_charge(machine.machine_id, machine.mechanic.hack_max_charges)
		if bool(outcome.get("awards_free_reroll", false)):
			GameState.add_machine_free_reroll(machine.machine_id)
	return payout


## Runs the full cascade chain up front and returns every tier's precomputed
## result. The presentation layer only plays this list back tier by tier; it
## never decides a match, a refill symbol, or the bonus tier itself.
func _resolve_cascade(
	machine: MetropolisMachineDefinition, rng: RandomNumberGenerator, luck_multiplier: float = 1.0
) -> Dictionary:
	var mechanic := machine.mechanic
	var luck_per_reel: Array = []
	luck_per_reel.resize(machine.reel_count)
	for index in range(machine.reel_count):
		luck_per_reel[index] = luck_multiplier
	var tiers: Array[Dictionary] = []
	var current_row := roll_reels(machine, rng, luck_per_reel)
	var tier_index := 0
	var jackpot_seen := false
	while true:
		if _row_contains_jackpot(current_row):
			jackpot_seen = true
		var matches := evaluate_matches(machine, current_row)
		if matches.is_empty():
			break
		var multiplier := 1.0
		if not mechanic.cascade_tier_multipliers.is_empty():
			var multiplier_index := mini(tier_index, mechanic.cascade_tier_multipliers.size() - 1)
			multiplier = float(mechanic.cascade_tier_multipliers[multiplier_index])
		var tier_gross := total_payout(matches)
		tiers.append({
			"row": current_row.duplicate(),
			"matches": matches,
			"tier_multiplier": multiplier,
			"payout": floori(float(tier_gross) * multiplier),
		})
		tier_index += 1
		var effective_cap := mechanic.cascade_max_tiers
		if mechanic.cascade_jackpot_grants_bonus_tier and jackpot_seen:
			effective_cap += 1
		if tier_index >= effective_cap:
			# Clear and refill the final paid match for presentation, but do not
			# evaluate another paying tier after the configured cap.
			current_row = _refill_row(machine, rng, current_row, matches, luck_multiplier)
			break
		current_row = _refill_row(machine, rng, current_row, matches, luck_multiplier)
	return {"tiers": tiers, "final_row": current_row, "jackpot_seen": jackpot_seen}


func _refill_row(
	machine: MetropolisMachineDefinition,
	rng: RandomNumberGenerator,
	row: Array[MetropolisSymbol],
	matches: Array[Dictionary],
	luck_multiplier: float = 1.0
) -> Array[MetropolisSymbol]:
	var matched_ids: Dictionary = {}
	for match_entry in matches:
		matched_ids[match_entry.get("symbol_id", &"")] = true
	var next_row: Array[MetropolisSymbol] = []
	for symbol in row:
		if symbol != null and matched_ids.has(symbol.symbol_id):
			next_row.append(roll_symbol_with_rng(machine, rng, luck_multiplier))
		else:
			next_row.append(symbol)
	return next_row


func _row_contains_jackpot(row: Array[MetropolisSymbol]) -> bool:
	for symbol in row:
		if symbol != null and symbol.tier == MetropolisSymbol.Tier.JACKPOT:
			return true
	return false
