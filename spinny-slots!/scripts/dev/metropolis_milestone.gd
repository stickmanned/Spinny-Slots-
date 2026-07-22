extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/metropolis_job.tscn")
const MACHINES: Array[MetropolisMachineDefinition] = [
	preload("res://resources/machines/neon_arcade.tres"),
	preload("res://resources/machines/drone_dispatch.tres"),
	preload("res://resources/machines/firewall_terminal.tres"),
	preload("res://resources/machines/billboard_jackpot.tres"),
	preload("res://resources/machines/quantum_vault.tres"),
]
const SIMULATION_SPINS := 4000
const FREQUENCY_TOLERANCE := 0.05
const BALANCE_SIMULATION_SPINS := 120000
const TEST_SAVE_PATH := "user://metropolis_milestone_test_save.json"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	_verify_machine_data_shape()
	_verify_weighted_distribution(MACHINES[0])
	_verify_three_reel_match_evaluation()
	_verify_wide_reel_count_evaluation()
	_verify_cascade_invariants()
	_verify_ticket_purchase_and_spend()
	_verify_hack_charge_award_and_spend()
	_verify_surge_reroll()
	_verify_per_machine_upgrades()
	_verify_baseline_balance_band()
	_verify_save_round_trip()
	await _verify_job_scene_spin()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("Metropolis milestone checks passed: paytables, weighted RNG, match evaluation, cascade, mechanics, save round-trip, and job-scene spin flow.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_machine_data_shape() -> void:
	_assert_equal(MACHINES.size(), 5, "Metropolis defines all five machines")
	var expected_reel_counts := {
		&"neon_arcade": 3,
		&"drone_dispatch": 3,
		&"firewall": 3,
		&"billboard": 4,
		&"quantum_vault": 5,
	}
	var expected_ticket_prices := {
		&"neon_arcade": 10_000,
		&"drone_dispatch": 100_000,
		&"firewall": 250_000,
		&"billboard": 1_000_000,
		&"quantum_vault": 2_500_000,
	}
	for machine in MACHINES:
		_assert_equal(machine.symbols.size(), 5, "%s defines exactly five symbols" % machine.display_name)
		_assert_equal(
			machine.reel_count,
			int(expected_reel_counts[machine.machine_id]),
			"%s has the expected reel count" % machine.display_name
		)
		_assert_equal(machine.ticket_price, int(expected_ticket_prices[machine.machine_id]), "%s keeps its final ticket price" % machine.display_name)
		_assert_true(machine.screen_region.has_area(), "%s defines a cabinet screen region" % machine.display_name)
		_assert_equal(machine.payout_tiers.size(), 4, "%s defines all four payout tiers" % machine.display_name)
		var seen_tiers: Dictionary = {}
		for tier in machine.payout_tiers:
			seen_tiers[tier.tier] = true
			var expected_counts: Array[int] = [3]
			if machine.reel_count > 3:
				expected_counts.assign(range(3, machine.reel_count + 1))
			for count in expected_counts:
				_assert_true(
					tier.get_payout(count) > 0,
					"%s tier %s pays out for a %d-count match" % [machine.display_name, MetropolisSymbol.tier_name(tier.tier), count]
				)
		_assert_equal(seen_tiers.size(), 4, "%s payout tiers cover all four distinct tiers" % machine.display_name)


func _verify_weighted_distribution(machine: MetropolisMachineDefinition) -> void:
	var counts: Dictionary = {}
	for symbol in machine.symbols:
		counts[symbol.symbol_id] = 0
	for _spin_index in range(SIMULATION_SPINS):
		var symbol := MetropolisEconomy.roll_symbol_with_rng(machine, _shared_rng())
		counts[symbol.symbol_id] = int(counts[symbol.symbol_id]) + 1
	for symbol in machine.symbols:
		var observed := float(counts[symbol.symbol_id]) / float(SIMULATION_SPINS)
		var expected := MetropolisEconomy.get_symbol_probability(machine, symbol)
		_assert_true(
			absf(observed - expected) <= FREQUENCY_TOLERANCE,
			"%s symbol '%s' observed frequency %.3f stays within %.2f of configured %.3f" % [machine.display_name, symbol.symbol_id, observed, FREQUENCY_TOLERANCE, expected]
		)


var _rng_cache: RandomNumberGenerator


func _shared_rng() -> RandomNumberGenerator:
	if _rng_cache == null:
		_rng_cache = RandomNumberGenerator.new()
		_rng_cache.seed = 4242
	return _rng_cache


func _verify_three_reel_match_evaluation() -> void:
	var machine := MACHINES[0]
	var common := machine.symbols[0]
	var other := machine.symbols[1]
	var matched: Array[MetropolisSymbol] = [common, common, common]
	var matches := MetropolisEconomy.evaluate_matches(machine, matched)
	_assert_equal(matches.size(), 1, "Three matching reels produce exactly one match")
	if not matches.is_empty():
		_assert_equal(int(matches[0]["count"]), 3, "The match reports a count of 3")
		_assert_equal(int(matches[0]["payout"]), machine.get_payout(common.tier, 3), "The match pays the configured tier payout")

	var unmatched: Array[MetropolisSymbol] = [common, common, other]
	var no_matches := MetropolisEconomy.evaluate_matches(machine, unmatched)
	_assert_true(no_matches.is_empty(), "Two-of-three does not qualify as a win on a 3-reel machine")


func _verify_wide_reel_count_evaluation() -> void:
	var billboard := MACHINES[3]
	var common := billboard.symbols[0]
	var filler := billboard.symbols[1]

	var two_of_four: Array[MetropolisSymbol] = [common, common, filler, filler]
	var matches_2 := MetropolisEconomy.evaluate_matches(billboard, two_of_four)
	_assert_true(matches_2.is_empty(), "2-of-4 does not qualify as a Skyline win")

	var three_of_four: Array[MetropolisSymbol] = [common, common, common, filler]
	var matches_3 := MetropolisEconomy.evaluate_matches(billboard, three_of_four)
	_assert_equal(matches_3.size(), 1, "3-of-4 produces one Skyline match")
	if not matches_3.is_empty():
		_assert_equal(int(matches_3[0]["payout"]), billboard.get_payout(common.tier, 3), "3-of-4 pays Skyline's 3-count payout")

	var four_of_four: Array[MetropolisSymbol] = [common, common, common, common]
	var matches_4 := MetropolisEconomy.evaluate_matches(billboard, four_of_four)
	_assert_equal(matches_4.size(), 1, "4-of-4 produces one Skyline match")
	if not matches_4.is_empty():
		_assert_equal(int(matches_4[0]["payout"]), billboard.get_payout(common.tier, 4), "4-of-4 pays Skyline's 4-count payout")

	var quantum := MACHINES[4]
	var quantum_common := quantum.symbols[0]
	var quantum_filler := quantum.symbols[1]
	var five_of_five: Array[MetropolisSymbol] = [
		quantum_common, quantum_common, quantum_common, quantum_common, quantum_common,
	]
	var matches_5 := MetropolisEconomy.evaluate_matches(quantum, five_of_five)
	_assert_equal(matches_5.size(), 1, "Quantum Vault still resolves 5-of-5")
	if not matches_5.is_empty():
		_assert_equal(int(matches_5[0]["payout"]), quantum.get_payout(quantum_common.tier, 5), "Quantum 5-of-5 pays its configured payout")
	var quantum_two: Array[MetropolisSymbol] = [
		quantum_common, quantum_common, quantum_filler, quantum_filler, quantum.symbols[2],
	]
	_assert_true(MetropolisEconomy.evaluate_matches(quantum, quantum_two).is_empty(), "Quantum 2-of-5 remains a loss")


func _verify_cascade_invariants() -> void:
	var machine := MACHINES[3]
	_assert_true(machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.CASCADE_MATCH, "Billboard Jackpot is configured as a Cascade Match machine")
	var rng := RandomNumberGenerator.new()
	var max_possible_tiers := machine.mechanic.cascade_max_tiers + 1
	for seed_value in range(200):
		rng.seed = seed_value
		var outcome := MetropolisEconomy.calculate_machine_spin(machine, rng)
		var tiers: Array = outcome.get("tiers", [])
		_assert_true(tiers.size() <= max_possible_tiers, "Cascade never exceeds its configured cap plus one bonus tier (seed %d)" % seed_value)
		var summed_payout := 0
		for tier in tiers:
			summed_payout += int(tier.get("payout", 0))
		_assert_equal(summed_payout, int(outcome.get("gross_payout", -1)), "Gross payout equals the sum of every cascade tier's payout (seed %d)" % seed_value)


func _verify_ticket_purchase_and_spend() -> void:
	GameState.reset_for_new_game()
	var machine := MACHINES[0]
	GameState.money = machine.ticket_price
	_assert_true(MetropolisEconomy.purchase_ticket(machine), "A ticket can be purchased with exact cash")
	_assert_equal(GameState.money, 0, "Ticket purchase spends the full ticket price")
	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 1, "Ticket purchase grants exactly one ticket")
	_assert_true(not MetropolisEconomy.purchase_ticket(machine), "A second purchase fails without enough cash")

	var outcome := MetropolisEconomy.prepare_machine_spin(machine)
	_assert_true(not outcome.is_empty(), "A spin can be prepared while a ticket is held")
	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 0, "Preparing a spin consumes the held ticket")
	var second_outcome := MetropolisEconomy.prepare_machine_spin(machine)
	_assert_true(second_outcome.is_empty(), "A spin cannot be prepared without a ticket")


func _verify_hack_charge_award_and_spend() -> void:
	GameState.reset_for_new_game()
	var machine := MACHINES[2]
	_assert_true(machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.HACK_CHARGE, "Firewall Hacker Terminal is configured as a Hack Charge machine")
	var jackpot_symbol: MetropolisSymbol = null
	for symbol in machine.symbols:
		if symbol.tier == MetropolisSymbol.Tier.JACKPOT:
			jackpot_symbol = symbol
	_assert_true(jackpot_symbol != null, "Firewall Hacker Terminal defines a jackpot-tier symbol")

	# Search for a seed whose base roll lands the jackpot symbol at least
	# once, so awards_hack_charge is exercised deterministically.
	var rng := RandomNumberGenerator.new()
	var found_seed := -1
	for seed_value in range(500):
		rng.seed = seed_value
		var outcome := MetropolisEconomy.calculate_machine_spin(machine, rng)
		if bool(outcome.get("jackpot_landed", false)):
			found_seed = seed_value
			break
	_assert_true(found_seed >= 0, "At least one of the first 500 seeds lands the jackpot symbol")
	if found_seed >= 0:
		rng.seed = found_seed
		var outcome := MetropolisEconomy.calculate_machine_spin(machine, rng)
		_assert_true(bool(outcome.get("awards_hack_charge", false)), "Landing the jackpot symbol awards a Hack Charge")
		MetropolisEconomy.award_machine_spin(machine, outcome)
		_assert_equal(GameState.get_machine_mechanic_charges(machine.machine_id), 1, "Awarding a Hack Charge increments the banked charge count")

	var consumed := GameState.consume_machine_mechanic_charge(machine.machine_id)
	_assert_true(consumed, "A banked Hack Charge can be spent")
	_assert_equal(GameState.get_machine_mechanic_charges(machine.machine_id), 0, "Spending the only charge leaves zero remaining")
	_assert_true(not GameState.consume_machine_mechanic_charge(machine.machine_id), "A Hack Charge cannot be spent when none remain")

	# Weight-shift sanity: a heavily boosted reel should land non-common
	# symbols far more often than the machine's base weights alone.
	var boosted_count := 0
	var trials := 1000
	for _index in range(trials):
		var symbol := MetropolisEconomy.roll_symbol_with_rng(machine, _shared_rng(), machine.mechanic.hack_weight_shift_multiplier)
		if symbol.tier != MetropolisSymbol.Tier.COMMON:
			boosted_count += 1
	var baseline_non_common := 0.0
	for symbol in machine.symbols:
		if symbol.tier != MetropolisSymbol.Tier.COMMON:
			baseline_non_common += MetropolisEconomy.get_symbol_probability(machine, symbol)
	_assert_true(
		float(boosted_count) / float(trials) > baseline_non_common,
		"A Hack Charge-boosted reel lands non-common symbols more often than the base weights"
	)


func _verify_surge_reroll() -> void:
	GameState.reset_for_new_game()
	var machine := MACHINES[1]
	_assert_true(machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER, "Rideshare Drone Dispatch is configured as a Surge Multiplier machine")

	GameState.money = 0
	var poor_result := MetropolisEconomy.reroll_surge_multiplier_now(machine, 0)
	_assert_true(not bool(poor_result.get("ok", false)), "Rerolling without cash or a free token fails")

	GameState.add_machine_free_reroll(machine.machine_id)
	var free_result := MetropolisEconomy.reroll_surge_multiplier_now(machine, 0)
	_assert_true(bool(free_result.get("ok", false)), "Rerolling succeeds using a banked free token")
	_assert_true(bool(free_result.get("used_free_token", false)), "The reroll reports that it used the free token")
	_assert_equal(GameState.get_machine_free_rerolls(machine.machine_id), 0, "The free token is consumed by the reroll")

	var capped_result := MetropolisEconomy.reroll_surge_multiplier_now(machine, machine.mechanic.surge_max_rerolls_per_spin)
	_assert_true(not bool(capped_result.get("ok", false)), "Rerolling beyond the per-spin cap fails")


func _verify_per_machine_upgrades() -> void:
	GameState.reset_for_new_game()
	var luck_config := MetropolisEconomy.get_upgrade_config(&"luck")
	var coin_config := MetropolisEconomy.get_upgrade_config(&"coin_multiplier")
	_assert_true(luck_config != null and coin_config != null, "Metropolis upgrade configs load")
	_assert_equal(luck_config.max_level, 10, "Metropolis Luck cap is 10")
	_assert_equal(MetropolisEconomy.get_upgrade_config(&"spin_speed").max_level, 10, "Metropolis Spin Speed cap is 10")
	_assert_equal(coin_config.max_level, 24, "Metropolis Coin Multiplier cap is 24")
	# Junkyard's own configs must be untouched by the Metropolis fork.
	_assert_equal(Economy.get_upgrade_config(&"luck").max_level, 5, "Junkyard Luck cap stays 5 (fork did not alter it)")
	_assert_equal(Economy.get_upgrade_config(&"coin_multiplier").max_level, 10, "Junkyard Coin cap stays 10")

	var neon := MACHINES[0]
	var quantum := MACHINES[4]
	# Cost scales with each machine's ticket price via cost_fraction_of_ticket.
	var neon_luck_cost := MetropolisEconomy.get_upgrade_cost(neon, &"luck")
	var quantum_luck_cost := MetropolisEconomy.get_upgrade_cost(quantum, &"luck")
	_assert_equal(neon_luck_cost, roundi(neon.ticket_price * luck_config.cost_fraction_of_ticket), "Neon Luck L0 cost is a fraction of its ticket price")
	_assert_true(quantum_luck_cost > neon_luck_cost, "A pricier machine's upgrade costs more")

	# Purchasing raises only the targeted machine's track and spends the cost.
	GameState.money = 100_000_000
	var before := GameState.money
	var coin_cost := MetropolisEconomy.get_upgrade_cost(neon, &"coin_multiplier")
	_assert_true(MetropolisEconomy.purchase_upgrade(neon, &"coin_multiplier"), "A Metropolis upgrade can be purchased")
	_assert_equal(GameState.money, before - coin_cost, "Purchasing an upgrade deducts exactly its cost")
	_assert_equal(GameState.get_machine_upgrade_level(neon.machine_id, &"coin_multiplier"), 1, "Purchase raises the machine's upgrade level")
	_assert_equal(GameState.get_machine_upgrade_level(quantum.machine_id, &"coin_multiplier"), 0, "A different machine's track is unaffected (per-machine)")

	# The Coin Multiplier actually scales that machine's payout.
	var mult := MetropolisEconomy.get_upgrade_multiplier(neon.machine_id, &"coin_multiplier")
	_assert_true(mult > 1.0, "Coin Multiplier level raises the payout multiplier above 1.0")
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var base_spin := MetropolisEconomy.calculate_machine_spin(neon, rng, {"coin_multiplier": 1.0})
	rng.seed = 555
	var boosted_spin := MetropolisEconomy.calculate_machine_spin(neon, rng, {"coin_multiplier": mult})
	_assert_equal(
		int(boosted_spin.get("payout", 0)),
		floori(float(base_spin.get("gross_payout", 0)) * mult),
		"Coin Multiplier scales the same seeded spin's payout"
	)
	GameState.reset_for_new_game()


func _verify_baseline_balance_band() -> void:
	for machine in MACHINES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260720
		var total_payout := 0.0
		for _spin_index in range(BALANCE_SIMULATION_SPINS):
			var outcome := MetropolisEconomy.calculate_machine_spin(machine, rng)
			total_payout += float(outcome.get("payout", 0))
		var average_payout := total_payout / float(BALANCE_SIMULATION_SPINS)
		var rtp := average_payout / float(machine.ticket_price)
		_assert_true(
			rtp >= 0.70 and rtp <= 0.95,
			"%s fixed-seed baseline RTP %.1f%% stays near the 75-90%% target" % [machine.display_name, rtp * 100.0]
		)


func _verify_save_round_trip() -> void:
	GameState.reset_for_new_game()
	SaveManager.set_save_path_for_tests(TEST_SAVE_PATH)
	SaveManager.delete_save_for_tests()

	var machine := MACHINES[2]
	var surge_machine := MACHINES[1]
	GameState.add_machine_mechanic_charge(machine.machine_id, 3)
	GameState.add_machine_mechanic_charge(machine.machine_id, 3)
	GameState.add_machine_free_reroll(surge_machine.machine_id)
	GameState.increment_machine_upgrade_level(machine.machine_id, &"coin_multiplier")
	GameState.increment_machine_upgrade_level(machine.machine_id, &"coin_multiplier")
	GameState.increment_machine_upgrade_level(MACHINES[0].machine_id, &"luck")
	_assert_true(SaveManager.save_now(), "Metropolis mechanic state saves successfully")

	GameState.reset_for_new_game()
	_assert_equal(GameState.get_machine_mechanic_charges(machine.machine_id), 0, "State is actually cleared before loading")
	_assert_true(SaveManager.load_now(), "Metropolis mechanic state loads successfully")
	_assert_equal(GameState.get_machine_mechanic_charges(machine.machine_id), 2, "Hack Charges survive a save/load round-trip")
	_assert_equal(GameState.get_machine_free_rerolls(surge_machine.machine_id), 1, "Free reroll tokens survive a save/load round-trip")
	_assert_equal(GameState.get_machine_upgrade_level(machine.machine_id, &"coin_multiplier"), 2, "Per-machine upgrade levels survive a save/load round-trip")
	_assert_equal(GameState.get_machine_upgrade_level(MACHINES[0].machine_id, &"luck"), 1, "Each machine's separate upgrade track round-trips independently")

	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()


func _verify_job_scene_spin() -> void:
	GameState.reset_for_new_game()
	GameState.metropolis_unlocked = true
	var machine := MACHINES[0]
	GameState.selected_machine_id = machine.machine_id
	GameState.money = machine.ticket_price
	MetropolisEconomy.purchase_ticket(machine)
	MetropolisEconomy.set_rng_seed(77)

	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)

	var spin_button: Button = job.get_node("%SpinButton")
	var result_label: Label = job.get_node("%ResultLabel")
	_assert_true(spin_button != null, "The job scene resolves its SpinButton unique node")
	_assert_true(not spin_button.disabled, "The spin button is enabled while a ticket is held")

	var money_before := GameState.money
	spin_button.emit_signal("pressed")
	await get_tree().create_timer(AudioFx.get_spin_duration() + 0.6).timeout
	await _frames(2)

	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 0, "Spinning consumes the held ticket")
	_assert_true(not result_label.text.is_empty(), "The result label shows the landed symbols after a spin")
	_assert_true(GameState.money >= money_before, "Money never goes negative after a spin resolves")

	job.queue_free()
	await _frames(2)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])
