extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")
const SIMULATION_SPINS := 5000
const FREQUENCY_TOLERANCE := 0.05

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	_verify_paytable_shape()
	for machine in PROGRESSION.machines:
		_verify_weighted_distribution(machine)
	await _verify_odds_panel_and_cycling()
	await _verify_reel_lands_on_predetermined_symbol()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("Milestone 3 checks passed: three-machine paytables, weighted RNG distribution, odds panel cycling, and predetermined reel presentation.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_paytable_shape() -> void:
	_assert_equal(PROGRESSION.machines.size(), 3, "Junkyard progression lists all three machines")
	for machine in PROGRESSION.machines:
		_assert_equal(machine.symbols.size(), 3, "%s defines exactly three symbols" % machine.display_name)
		_assert_float_close(Economy.get_symbol_weight_total(machine), 100.0, 0.01, "%s symbol weights sum to 100" % machine.display_name)
		_assert_true(machine.screen_region.has_area(), "%s defines a cabinet screen region for its reels" % machine.display_name)
		var expected := Economy.get_expected_payout(machine)
		if machine.machine_id == &"cardboard_cash":
			var min_payout := machine.symbols[0].payout
			for symbol in machine.symbols:
				min_payout = mini(min_payout, symbol.payout)
			_assert_true(min_payout * Economy.REEL_COUNT >= machine.ticket_price, "%s's worst three-reel result still pays at least the ticket price (bankruptcy protection on the first machine)" % machine.display_name)
		else:
			_assert_true(expected < float(machine.ticket_price), "%s keeps a house edge (expected payout %.2f < ticket price %d)" % [machine.display_name, expected, machine.ticket_price])
			_assert_true(expected > float(machine.ticket_price) * 0.75, "%s does not punish the player too harshly (expected payout %.2f)" % [machine.display_name, expected])


func _verify_weighted_distribution(machine: MachineDefinition) -> void:
	Economy.set_rng_seed(4242)
	var counts: Dictionary = {}
	var payout_total := 0
	for symbol in machine.symbols:
		counts[symbol.symbol_id] = 0
	for _spin_index in range(SIMULATION_SPINS):
		var symbol := Economy.roll_symbol(machine)
		counts[symbol.symbol_id] = int(counts[symbol.symbol_id]) + 1
		payout_total += symbol.payout
	for symbol in machine.symbols:
		var observed := float(counts[symbol.symbol_id]) / float(SIMULATION_SPINS)
		var expected := Economy.get_symbol_probability(machine, symbol)
		_assert_true(
			absf(observed - expected) <= FREQUENCY_TOLERANCE,
			"%s symbol '%s' observed frequency %.3f stays within %.2f of configured %.3f" % [machine.display_name, symbol.symbol_id, observed, FREQUENCY_TOLERANCE, expected]
		)
	var observed_average := float(payout_total) / float(SIMULATION_SPINS)
	var expected_average := Economy.get_expected_payout(machine) / float(Economy.REEL_COUNT)
	_assert_true(
		absf(observed_average - expected_average) <= expected_average * 0.1 + 1.0,
		"%s observed average payout %.2f stays close to expected %.2f" % [machine.display_name, observed_average, expected_average]
	)


func _verify_odds_panel_and_cycling() -> void:
	GameState.reset_for_new_game()
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.selected_machine_id = PROGRESSION.machines[0].machine_id
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)

	var odds_panel: PanelContainer = job.get_node("TicketLayer/Overlay/LeftColumn/OddsPanel")
	var right_arrow: TextureButton = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/RightArrow")
	var machine_name_label: Label = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/MachineName")

	for expected_index in range(PROGRESSION.machines.size()):
		var machine: MachineDefinition = PROGRESSION.machines[expected_index]
		_assert_equal(machine_name_label.text, machine.display_name, "Selector shows %s before checking its odds" % machine.display_name)
		var rows_container: VBoxContainer = odds_panel.get_node("%Rows")
		_assert_equal(rows_container.get_child_count(), machine.symbols.size(), "Odds panel shows one row per %s symbol" % machine.display_name)
		for symbol_index in range(machine.symbols.size()):
			var symbol: SlotSymbol = machine.symbols[symbol_index]
			var row := rows_container.get_child(symbol_index)
			var percent_label: Label = row.get_node("%PercentLabel")
			var expected_percent := "%d%%" % roundi(Economy.get_symbol_probability(machine, symbol) * 100.0)
			_assert_equal(percent_label.text, expected_percent, "%s odds row for %s shows the configured probability" % [machine.display_name, symbol.display_name])
			var value_label: Label = row.get_node("%ValueLabel")
			_assert_equal(value_label.text, "$%d" % symbol.payout, "%s odds row for %s shows the symbol's coin value" % [machine.display_name, symbol.display_name])
		right_arrow.emit_signal("pressed")
		await _frames(2)

	job.queue_free()
	await _frames(2)


func _verify_reel_lands_on_predetermined_symbol() -> void:
	GameState.reset_for_new_game()
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	var machine: MachineDefinition = PROGRESSION.machines[0]
	GameState.selected_machine_id = machine.machine_id
	GameState.unlock_machine(machine.machine_id)
	GameState.add_machine_ticket(machine.machine_id)
	Economy.set_rng_seed(99)
	var expected_symbols: Array[SlotSymbol] = []
	for _reel_index in range(Economy.REEL_COUNT):
		expected_symbols.append(Economy.roll_symbol(machine))
	Economy.set_rng_seed(99)

	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)
	var spin_button: Button = job.get_node("SelectorLayer/Overlay/MachineArea/SpinButton")
	spin_button.emit_signal("pressed")
	await get_tree().create_timer(AudioFx.get_spin_duration() + 0.6).timeout

	var reel_strip: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/CabinetArt/ReelStrip")
	var window_count := 0
	for reel_window in reel_strip.get_children():
		if reel_window is Control:
			var reel_icon := reel_window.get_node("Icon") as TextureRect
			_assert_true(reel_icon.texture == expected_symbols[window_count].icon, "Reel window %d lands on its own predetermined result symbol" % window_count)
			_assert_float_close(reel_icon.modulate.a, 1.0, 0.01, "Blink presentation ends with the landed icon fully visible")
			_assert_true(reel_window.clip_contents, "Reel window %d clips its enlarged icon away from neighboring reels" % window_count)
			_assert_true(reel_icon.size.x >= reel_window.size.x * 1.5, "Reel icon %d is enlarged by at least 50%% inside its window" % window_count)
			if window_count > 0:
				var previous_window := reel_strip.get_child(window_count - 1) as Control
				_assert_true(not previous_window.get_rect().intersects(reel_window.get_rect()), "Reel windows %d and %d retain a non-overlapping gap" % [window_count - 1, window_count])
			window_count += 1
	_assert_equal(window_count, 3, "The cabinet screen shows three reel windows")
	var cabinet: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/CabinetArt")
	_assert_true(cabinet.get_global_rect().encloses(reel_strip.get_global_rect()), "Reel windows sit inside the cabinet's screen area")

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


func _assert_float_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (expected %.3f, got %.3f)" % [message, expected, actual])
