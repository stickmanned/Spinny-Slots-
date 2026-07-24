extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")
const SIMULATION_SPINS := 300

var _failures: Array[String] = []
var _money_spent_events: Array[int] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	GameState.money_spent.connect(_on_money_spent)
	_verify_upgrade_configs_and_costs()
	_verify_purchase_flow_and_spend_signal()
	_verify_luck_effect()
	_verify_coin_multiplier_rounding()
	_verify_spin_speed_audio_sync()
	_verify_first_machine_floor_and_variety()
	await _verify_upgrade_rows_ui()
	await _verify_spin_interaction_safety()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("Milestone 3b checks passed: upgrade costs and purchases, luck/coin/speed effects, audio-synced spin duration, HUD multiplier display, capped coin collection, reduced motion, and spin interaction safety.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _on_money_spent(amount: int) -> void:
	_money_spent_events.append(amount)


func _verify_upgrade_configs_and_costs() -> void:
	GameState.reset_for_new_game()
	var configs := Economy.get_upgrade_configs()
	_assert_equal(configs.size(), 3, "Three upgrade tracks are configured")
	var expected_ids: Array[StringName] = [&"luck", &"spin_speed", &"coin_multiplier"]
	for index in range(expected_ids.size()):
		_assert_equal(configs[index].upgrade_id, expected_ids[index], "Upgrade track %d is %s" % [index, expected_ids[index]])
	for config in configs:
		_assert_true(config.max_level >= 1, "%s has at least one purchasable level" % config.upgrade_id)
		_assert_true(config.icon != null, "%s has an icon" % config.upgrade_id)
		for level in range(3):
			GameState.upgrade_levels[String(config.upgrade_id)] = level
			var expected_cost := roundi(config.base_cost * pow(config.cost_growth, level))
			_assert_equal(Economy.get_upgrade_cost(config.upgrade_id), expected_cost, "%s cost follows base*growth^level at level %d" % [config.upgrade_id, level])
		GameState.upgrade_levels[String(config.upgrade_id)] = config.max_level
		_assert_true(Economy.is_upgrade_maxed(config.upgrade_id), "%s reports maxed at max_level" % config.upgrade_id)
		_assert_equal(Economy.get_upgrade_cost(config.upgrade_id), -1, "%s has no cost once maxed" % config.upgrade_id)
	GameState.reset_for_new_game()


func _verify_purchase_flow_and_spend_signal() -> void:
	GameState.reset_for_new_game()
	var cost := Economy.get_upgrade_cost(&"luck")
	GameState.money = cost - 1
	_money_spent_events.clear()
	_assert_true(not Economy.purchase_upgrade(&"luck"), "Unaffordable upgrade purchase is blocked")
	_assert_equal(Economy.get_upgrade_level(&"luck"), 0, "Blocked purchase does not raise the level")
	_assert_equal(GameState.money, cost - 1, "Blocked purchase deducts nothing")
	_assert_equal(_money_spent_events.size(), 0, "Blocked purchase does not report spent money (no coin-drop sound)")
	GameState.money = cost
	_assert_true(Economy.purchase_upgrade(&"luck"), "Affordable upgrade purchase succeeds")
	_assert_equal(Economy.get_upgrade_level(&"luck"), 1, "Purchase raises the level by one")
	_assert_equal(GameState.money, 0, "Purchase deducts exactly the configured cost")
	_assert_equal(_money_spent_events, [cost], "Successful purchase reports the spend exactly once (single coin-drop sound)")
	GameState.reset_for_new_game()


func _verify_luck_effect() -> void:
	GameState.reset_for_new_game()
	var machine: MachineDefinition = PROGRESSION.machines[0]
	var base_probabilities: Dictionary = {}
	for symbol in machine.symbols:
		base_probabilities[symbol.symbol_id] = Economy.get_symbol_probability(machine, symbol)
	GameState.upgrade_levels["luck"] = 2
	var luck_multiplier := Economy.get_upgrade_multiplier(&"luck")
	_assert_float_close(luck_multiplier, 1.3, 0.001, "Luck level 2 multiplies rarer odds by 1.3")
	var total_weight := Economy.get_symbol_weight_total(machine)
	var effective_weights := Economy.get_effective_symbol_weights(machine)
	var weight_sum := 0.0
	for symbol_id in effective_weights:
		weight_sum += float(effective_weights[symbol_id])
	_assert_float_close(weight_sum, total_weight, 0.01, "Luck keeps the total symbol weight normalized")
	var common_id: StringName = &"box"
	for symbol in machine.symbols:
		var probability := Economy.get_symbol_probability(machine, symbol)
		if symbol.symbol_id == common_id:
			_assert_true(probability > 0.0, "Common symbol stays possible with luck")
			_assert_true(probability < float(base_probabilities[symbol.symbol_id]), "Luck lowers the common symbol's odds")
		else:
			_assert_float_close(probability, float(base_probabilities[symbol.symbol_id]) * luck_multiplier, 0.001, "Luck multiplies %s odds by exactly the displayed multiplier" % symbol.symbol_id)
	GameState.upgrade_levels["luck"] = Economy.get_upgrade_config(&"luck").max_level
	var common_symbol: SlotSymbol = null
	for symbol in machine.symbols:
		if symbol.symbol_id == common_id:
			common_symbol = symbol
	_assert_true(Economy.get_symbol_probability(machine, common_symbol) >= Economy.COMMON_WEIGHT_FLOOR - 0.001, "Common symbol never drops below its weight floor at max luck")
	GameState.reset_for_new_game()


func _verify_coin_multiplier_rounding() -> void:
	GameState.reset_for_new_game()
	var machine: MachineDefinition = PROGRESSION.machines[0]
	GameState.upgrade_levels["coin_multiplier"] = 3
	var coin_multiplier := Economy.get_upgrade_multiplier(&"coin_multiplier")
	_assert_float_close(coin_multiplier, 1.45, 0.001, "Coin multiplier level 3 is 1.45x")
	GameState.add_machine_ticket(machine.machine_id)
	Economy.set_rng_seed(777)
	var predicted: Array[SlotSymbol] = []
	for _reel_index in range(Economy.REEL_COUNT):
		predicted.append(Economy.roll_symbol(machine))
	var base_total := 0
	for symbol in predicted:
		base_total += symbol.payout
	Economy.set_rng_seed(777)
	var outcome := Economy.prepare_machine_spin(machine)
	_assert_equal(int(outcome.get("base_total", -1)), base_total, "Spin outcome sums each reel's own payout")
	_assert_equal(int(outcome.get("payout", -1)), floori(base_total * coin_multiplier), "Coin multiplier applies to the summed payout and rounds down")
	var money_before := GameState.money
	var awarded := Economy.award_machine_spin(outcome)
	_assert_equal(GameState.money - money_before, awarded, "Awarding the spin adds exactly the multiplied payout once")
	GameState.reset_for_new_game()


func _verify_spin_speed_audio_sync() -> void:
	GameState.reset_for_new_game()
	var stream_length := AudioFx.get_spin_stream_length()
	_assert_true(stream_length > 2.5, "Slot-machine audio stream loaded with a real duration")
	var previous_duration := INF
	var speed_config := Economy.get_upgrade_config(&"spin_speed")
	for level in range(Economy.get_upgrade_max_level(&"spin_speed") + 1):
		GameState.upgrade_levels["spin_speed"] = level
		var speed := Economy.get_spin_speed_multiplier()
		_assert_float_close(speed, 1.0 + speed_config.effect_per_level * level, 0.001, "Spin-speed multiplier matches its configured per-level effect at level %d" % level)
		var duration := AudioFx.get_spin_duration()
		var expected_duration: float = maxf(stream_length / speed, AudioFx.MIN_SPIN_DURATION)
		_assert_float_close(duration, expected_duration, 0.001, "Spin duration is the audio length divided by speed (clamped) at level %d" % level)
		_assert_true(duration <= previous_duration + 0.001, "Spin duration never increases with speed level %d" % level)
		_assert_true(duration >= AudioFx.MIN_SPIN_DURATION - 0.001, "Spin duration respects the minimum readable duration")
		_assert_float_close(AudioFx.get_spin_pitch() * duration, stream_length, 0.01, "Audio pitch keeps playback exactly as long as the spin at level %d" % level)
		previous_duration = duration
	GameState.upgrade_levels["spin_speed"] = 0
	_assert_float_close(AudioFx.get_spin_duration(), stream_length, 0.001, "Default spin duration matches the slot-machine audio duration")
	GameState.reset_for_new_game()


func _verify_first_machine_floor_and_variety() -> void:
	GameState.reset_for_new_game()
	var machine: MachineDefinition = PROGRESSION.machines[0]
	GameState.add_machine_ticket(machine.machine_id, SIMULATION_SPINS)
	Economy.set_rng_seed(4242)
	var saw_mixed_result := false
	var seen_symbol_ids: Dictionary = {}
	for _spin_index in range(SIMULATION_SPINS):
		var outcome := Economy.prepare_machine_spin(machine)
		var payout := int(outcome.get("payout", 0))
		if payout < 30:
			_failures.append("First machine paid $%d, below the $30 floor" % payout)
			break
		var symbols: Array = outcome.get("symbols", [])
		seen_symbol_ids[symbols[0].symbol_id] = true
		seen_symbol_ids[symbols[1].symbol_id] = true
		seen_symbol_ids[symbols[2].symbol_id] = true
		if symbols[0] != symbols[1] or symbols[1] != symbols[2]:
			saw_mixed_result = true
	_assert_true(saw_mixed_result, "Reels roll independently, producing mixed combinations")
	_assert_equal(seen_symbol_ids.size(), machine.symbols.size(), "Every configured symbol appears across repeated spins")
	GameState.reset_for_new_game()


func _verify_upgrade_rows_ui() -> void:
	GameState.reset_for_new_game()
	_prepare_machine_mode_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)
	var rows: VBoxContainer = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel/Content/UpgradeRows")
	_assert_equal(rows.get_child_count(), 3, "HUD shows one row per upgrade track")
	var luck_row := rows.get_child(0) as Button
	var status: Label = luck_row.get_node("ContentMargin/Content/Details/UpgradeStatus")
	var cost: Label = luck_row.get_node("ContentMargin/Content/CostLabel")
	_assert_equal(status.text, "LV 0  •  1x", "Luck row starts at level 0 with a 1x multiplier")
	_assert_equal(cost.text, "$%d" % Economy.get_upgrade_cost(&"luck"), "Luck row shows the live upgrade cost")
	_assert_true(luck_row.disabled, "Unaffordable upgrade row is disabled")
	GameState.money = Economy.get_upgrade_cost(&"luck")
	await _frames(1)
	_assert_true(not luck_row.disabled, "Affordable upgrade row enables immediately")
	luck_row.emit_signal("pressed")
	await _frames(1)
	_assert_equal(Economy.get_upgrade_level(&"luck"), 1, "Pressing the row purchases the upgrade")
	_assert_equal(GameState.money, 0, "Row purchase deducts the exact cost")
	_assert_equal(status.text, "LV 1  •  1.15x", "Row multiplier updates immediately and matches the internal 1.15x")
	_assert_float_close(Economy.get_upgrade_multiplier(&"luck"), 1.15, 0.001, "Displayed multiplier equals the internally applied multiplier")
	var machine: MachineDefinition = PROGRESSION.machines[0]
	var odds_rows: VBoxContainer = job.get_node("TicketLayer/Overlay/LeftColumn/OddsPanel").get_node("%Rows")
	for symbol_index in range(machine.symbols.size()):
		var symbol: SlotSymbol = machine.symbols[symbol_index]
		var percent_label: Label = odds_rows.get_child(symbol_index).get_node("%PercentLabel")
		var expected_percent := "%d%%" % roundi(Economy.get_symbol_probability(machine, symbol) * 100.0)
		_assert_equal(percent_label.text, expected_percent, "Odds panel refreshes %s odds immediately after a luck purchase" % symbol.symbol_id)
	var hooked_connections := 0
	for connection in luck_row.button_down.get_connections():
		if connection["callable"].get_object() == AudioFx:
			hooked_connections += 1
	_assert_equal(hooked_connections, 1, "Click sound hooks each button exactly once (no bubbling duplicates)")
	job.queue_free()
	await _frames(2)


func _verify_spin_interaction_safety() -> void:
	GameState.reset_for_new_game()
	_prepare_machine_mode_state()
	var machine: MachineDefinition = PROGRESSION.machines[0]
	GameState.money = 0
	GameState.add_machine_ticket(machine.machine_id, 2)
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)
	var spin_button: Button = job.get_node("SelectorLayer/Overlay/MachineArea/SpinButton")
	var payout_label: Label = job.get_node("SelectorLayer/Overlay/MachineArea/PayoutLabel")
	var coin_value: Label = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel/CurrencyContent/Coins/CoinValue")
	var coin_effect: CoinCollectionEffect = job.get_node("CoinEffectLayer/CoinCollectionEffect")
	var completed_spins: Array[int] = []
	var presented_balances: Array[int] = []
	var spawned_origins: Array[Vector2] = []
	var spawned_targets: Array[Vector2] = []
	job.connect("spin_completed", func(_machine_id: StringName, payout: int) -> void: completed_spins.append(payout))
	coin_effect.balance_progressed.connect(func(value: int) -> void: presented_balances.append(value))
	coin_effect.coin_spawned.connect(func(origin: Vector2, target: Vector2) -> void:
		spawned_origins.append(origin)
		spawned_targets.append(target)
	)
	spin_button.emit_signal("pressed")
	spin_button.emit_signal("pressed")
	spin_button.emit_signal("pressed")
	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 1, "Rapid presses consume exactly one ticket")
	_assert_true(spin_button.disabled, "Spin button is disabled while a spin is running")
	await get_tree().create_timer(AudioFx.get_spin_duration() + 0.05).timeout
	var expected_payout_origin := payout_label.get_global_rect().get_center()
	var expected_balance_target := coin_value.get_global_rect().get_center()
	_assert_true(spawned_origins.size() >= CoinCollectionEffect.MIN_VISUAL_COINS, "A valid payout spawns multiple visible coins")
	_assert_true(spawned_origins.size() <= CoinCollectionEffect.MAX_VISUAL_COINS, "A payout never exceeds the capped visual coin count")
	for temporary_coin in coin_effect.get_children():
		_assert_equal((temporary_coin as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "Temporary coin Controls never intercept pointer input")
	if not spawned_origins.is_empty():
		_assert_true(spawned_origins[0].distance_to(expected_payout_origin) <= 16.0, "Coins originate inside the live payout label")
		_assert_true(spawned_targets[0].distance_to(expected_balance_target) <= 0.5, "Coins target the live HUD balance position")
	_assert_equal(GameState.money, 0, "Presentation starts before the authoritative reward is awarded")
	_assert_true(spin_button.disabled, "Spin remains disabled throughout the reward sequence")
	await get_tree().create_timer(CoinCollectionEffect.get_max_duration() + 0.1).timeout
	_assert_equal(completed_spins.size(), 1, "Rapid presses award exactly one spin result")
	_assert_equal(GameState.money, completed_spins[0], "The single result is paid exactly once")
	_assert_true(presented_balances.size() >= 2, "Balance presentation advances across multiple coin arrivals")
	if not presented_balances.is_empty():
		_assert_equal(presented_balances[-1], GameState.money, "The final presented balance exactly matches authoritative money")
	_assert_equal(coin_value.text, NumberFormatter.compact(GameState.money), "HUD balance settles on the authoritative awarded amount")
	await _frames(2)
	_assert_equal(coin_effect.get_child_count(), 0, "All temporary coin Controls are cleaned up")
	_assert_equal(CoinCollectionEffect.get_visual_coin_count(1000000), CoinCollectionEffect.MAX_VISUAL_COINS, "Large rewards remain capped at the visual coin limit")

	GameState.reduced_motion = true
	var spawned_before_reduced_motion := spawned_origins.size()
	spin_button.emit_signal("pressed")
	await get_tree().create_timer(AudioFx.get_spin_duration() + CoinCollectionEffect.REDUCED_MOTION_DURATION + 0.1).timeout
	_assert_equal(completed_spins.size(), 2, "Reduced-motion reward sequence still completes exactly once")
	_assert_equal(spawned_origins.size(), spawned_before_reduced_motion, "Reduced motion replaces traveling coins with balance feedback")
	_assert_equal(GameState.money, completed_spins[0] + completed_spins[1], "Reduced-motion payout is mathematically exact")
	_assert_equal(coin_effect.get_child_count(), 0, "Reduced motion creates no temporary coin Controls")

	var money_before := GameState.money
	spin_button.emit_signal("pressed")
	await _frames(2)
	_assert_equal(completed_spins.size(), 2, "A spin without a ticket cannot trigger another reward effect")
	_assert_equal(GameState.money, money_before, "A failed spin cannot award money")
	_assert_true(not GameState.spend_money(money_before + 1), "Spending more than the balance is rejected")
	_assert_equal(GameState.money, money_before, "A rejected spend leaves the balance unchanged (never negative)")
	GameState.reduced_motion = false
	job.queue_free()
	await _frames(2)


func _prepare_machine_mode_state() -> void:
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.selected_machine_id = PROGRESSION.machines[0].machine_id
	GameState.unlock_machine(PROGRESSION.machines[0].machine_id)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func _assert_float_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (expected %.3f, got %.3f)" % [message, expected, actual])
