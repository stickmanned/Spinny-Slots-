extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const JOB_SCENE: PackedScene = preload("res://scenes/metropolis_job.tscn")
const MACHINES: Array[MetropolisMachineDefinition] = [
	preload("res://resources/machines/neon_arcade.tres"),
	preload("res://resources/machines/drone_dispatch.tres"),
	preload("res://resources/machines/firewall_terminal.tres"),
	preload("res://resources/machines/billboard_jackpot.tres"),
	preload("res://resources/machines/quantum_vault.tres"),
]
const RECT_TOLERANCE := 1.0
const MAX_SPIN_FRAMES := 900
const MAX_TRANSITION_FRAMES := 240

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 8.0
	_verify_compact_number_formatting()
	await _verify_ticket_odds_and_stable_layout()
	await _verify_all_machine_purchase_spin_payouts()
	await _verify_mechanic_controls_and_state()
	await _verify_map_round_trip()
	Engine.time_scale = 1.0
	GameState.reset_for_new_game()
	if _failures.is_empty():
		print("Metropolis stabilization checks passed: map round-trip, clipped ticket UI, stable layout, 4-reel Skyline, real purchase/spin/payout paths, and mechanic controls.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_ticket_odds_and_stable_layout() -> void:
	_prepare_metropolis_state()
	GameState.money = 5_000_000
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	var ticket_shop := job.get_node("%TicketShopPanel") as PanelContainer
	var ticket_scroll := ticket_shop.get_node("Content/TicketScroll") as ScrollContainer
	var ticket_rows := ticket_shop.get_node("%TicketRows") as VBoxContainer
	var balance_label := ticket_shop.get_node("%BalanceLabel") as Label
	var paytable := job.get_node("%PaytablePanel") as PanelContainer
	var odds_title := paytable.get_node("Content/Title") as Label
	_assert_true(ticket_shop.clip_contents, "Ticket panel clips all row presentation to its bounds")
	_assert_true(ticket_scroll.clip_contents, "Ticket ScrollContainer clips rows while scrolling")
	_assert_true(not balance_label.visible, "Metropolis ticket header hides the redundant cash balance")
	_assert_equal(odds_title.text, "ODDS", "Metropolis lower-left panel is titled ODDS")
	_assert_equal(ticket_rows.get_child_count(), MACHINES.size(), "Metropolis renders one ticket row per machine")

	for row in ticket_rows.get_children():
		var row_control := row as Control
		var row_rect := row_control.get_global_rect()
		var ticket_art := row.get_node("%TicketArt") as TextureRect
		var machine_name := row.get_node("%MachineName") as Label
		var price_label := row.get_node("%PriceLabel") as Label
		_assert_true(ticket_art.texture != null, "%s has ticket art" % row.name)
		_assert_true(_rect_contains(row_rect, ticket_art.get_global_rect()), "%s ticket art stays inside its button" % row.name)
		_assert_true(_rect_contains(row_rect, machine_name.get_global_rect()), "%s machine name stays inside its button" % row.name)
		_assert_true(_rect_contains(row_rect, price_label.get_global_rect()), "%s price stays inside its button" % row.name)
		var machine = row.call("get_machine")
		_assert_equal(price_label.text, NumberFormatter.currency(machine.ticket_price), "%s price uses compact currency formatting" % row.name)

	var first_row := ticket_rows.get_child(0) as Control
	first_row.call("_on_mouse_entered")
	await get_tree().create_timer(0.2).timeout
	_assert_true(
		_rect_contains(ticket_scroll.get_global_rect(), first_row.get_global_rect()),
		"A hovered ticket can enlarge without being cut by the scroll viewport walls"
	)
	first_row.call("_on_mouse_exited")
	var skyline_ticket := MACHINES[3].ticket_texture as AtlasTexture
	_assert_true(
		skyline_ticket != null and skyline_ticket.region.size.y >= 800.0,
		"Skyline ticket atlas includes the complete top and bottom artwork"
	)

	var selector := job.get_node("%MachineSelectorPanel") as PanelContainer
	var cabinet := selector.get_node("%CabinetArt") as TextureRect
	var left_arrow := selector.get_node("%LeftArrow") as Control
	var right_arrow := selector.get_node("%RightArrow") as Control
	var payout_label := job.get_node("%PayoutLabel") as Label
	var spin_button := job.get_node("%SpinButton") as Button
	var base_rects := {
		"cabinet": cabinet.get_global_rect(),
		"left_arrow": left_arrow.get_global_rect(),
		"right_arrow": right_arrow.get_global_rect(),
		"payout": payout_label.get_global_rect(),
		"spin": spin_button.get_global_rect(),
	}

	for machine in MACHINES:
		selector.call("configure", MACHINES, machine.machine_id)
		job.call("_on_selection_changed", machine)
		var cabinet_texture := machine.cabinet_texture as AtlasTexture
		_assert_true(cabinet_texture != null, "%s uses a cabinet atlas texture" % machine.display_name)
		_assert_true(cabinet_texture.region.end.x >= 1005.0, "%s cabinet atlas includes its full right edge without cutoff" % machine.display_name)
		_assert_rect_close(cabinet.get_global_rect(), base_rects["cabinet"], "%s cabinet stays fixed" % machine.display_name)
		_assert_rect_close(left_arrow.get_global_rect(), base_rects["left_arrow"], "%s left arrow stays fixed" % machine.display_name)
		_assert_rect_close(right_arrow.get_global_rect(), base_rects["right_arrow"], "%s right arrow stays fixed" % machine.display_name)
		_assert_rect_close(payout_label.get_global_rect(), base_rects["payout"], "%s payout region stays fixed" % machine.display_name)
		_assert_rect_close(spin_button.get_global_rect(), base_rects["spin"], "%s Spin button stays fixed" % machine.display_name)
		_assert_true(_rect_contains(get_viewport().get_visible_rect(), spin_button.get_global_rect()), "%s Spin button stays inside the viewport" % machine.display_name)
		var active_strip := selector.call("get_active_reel_strip") as Control
		_assert_equal(int(active_strip.call("get_reel_count")), machine.reel_count, "%s presents its configured reel count" % machine.display_name)
		_assert_true(_rect_contains(cabinet.get_global_rect(), active_strip.get_global_rect()), "%s reel display stays inside its cabinet" % machine.display_name)

	# The ticket panel now expands to fill whatever room the left column has
	# (matching Junkyard), so pin it to a known-small height here to prove the
	# scroll/clip mechanics still work when content genuinely overflows,
	# independent of how tall the host viewport happens to be.
	ticket_shop.size_flags_vertical = 0
	ticket_shop.custom_minimum_size.y = 220
	await _frames(2)
	ticket_scroll.scroll_vertical = 100000
	await _frames(3)
	var scroll_bar := ticket_scroll.get_v_scroll_bar()
	_assert_true(
		ticket_scroll.scroll_vertical > 0,
		"Five Metropolis ticket rows can scroll within the clipped viewport (viewport %s, rows %s, max %.1f, page %.1f)" % [
			ticket_scroll.size, ticket_rows.size, scroll_bar.max_value, scroll_bar.page,
		]
	)

	job.queue_free()
	await _frames(3)


func _verify_compact_number_formatting() -> void:
	_assert_equal(NumberFormatter.compact(999), "999", "Values below one thousand stay exact")
	_assert_equal(NumberFormatter.compact(1_000), "1K", "Thousands use K")
	_assert_equal(NumberFormatter.compact(1_250), "1.25K", "Compact values retain useful precision")
	_assert_equal(NumberFormatter.compact(1_000_000), "1M", "Millions use M")
	_assert_equal(NumberFormatter.compact(1_250_000_000), "1.25B", "Billions use B")
	_assert_equal(NumberFormatter.compact(100_000_000_000), "100B", "Whole three-digit abbreviations keep trailing zeroes")


func _verify_all_machine_purchase_spin_payouts() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)
	var ticket_shop := job.get_node("%TicketShopPanel") as PanelContainer
	var spin_button := job.get_node("%SpinButton") as Button
	var payout_label := job.get_node("%PayoutLabel") as Label

	for machine in MACHINES:
		GameState.money = machine.ticket_price * 2
		await _frames(2)
		var buy_button := ticket_shop.call("get_buy_button", machine.machine_id) as Button
		_assert_true(buy_button != null, "%s has a ticket purchase button" % machine.display_name)
		if buy_button == null:
			continue
		_assert_true(not buy_button.disabled, "%s ticket is purchasable with enough cash" % machine.display_name)
		buy_button.emit_signal("pressed")
		await _frames(3)
		_assert_equal(GameState.selected_machine_id, machine.machine_id, "%s ticket click selects that machine" % machine.display_name)
		_assert_equal(GameState.money, machine.ticket_price, "%s purchase deducts its exact ticket price" % machine.display_name)
		_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 1, "%s purchase grants one ticket" % machine.display_name)
		_assert_equal(spin_button.text, "SPIN (1)", "%s Spin counter reflects its ticket" % machine.display_name)
		_assert_true(not spin_button.disabled, "%s Spin button enables with a ticket" % machine.display_name)

		var options := _current_job_options(job, machine)
		var seeded := _find_positive_outcome(machine, options)
		_assert_true(not seeded.is_empty(), "%s has a deterministic positive test spin" % machine.display_name)
		if seeded.is_empty():
			continue
		var expected: Dictionary = seeded["outcome"]
		MetropolisEconomy.set_rng_seed(int(seeded["seed"]))
		spin_button.emit_signal("pressed")
		await _wait_for_spin(job, machine.display_name)
		var expected_payout := int(expected.get("payout", 0))
		_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 0, "%s spin consumes exactly one ticket" % machine.display_name)
		_assert_equal(GameState.money, machine.ticket_price + expected_payout, "%s credits the exact predetermined payout" % machine.display_name)
		_assert_equal(payout_label.text, NumberFormatter.reward(expected_payout), "%s payout label shows the awarded amount" % machine.display_name)
		var money_after_spin := GameState.money
		spin_button.emit_signal("pressed")
		await _frames(3)
		_assert_equal(GameState.money, money_after_spin, "%s cannot award again without another ticket" % machine.display_name)

	job.queue_free()
	await _frames(3)


func _verify_mechanic_controls_and_state() -> void:
	_prepare_metropolis_state()
	GameState.money = 10_000_000
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)
	var selector := job.get_node("%MachineSelectorPanel") as PanelContainer

	var surge_machine := MACHINES[1]
	selector.call("configure", MACHINES, surge_machine.machine_id)
	job.call("_on_selection_changed", surge_machine)
	GameState.add_machine_free_reroll(surge_machine.machine_id)
	await _frames(3)
	var surge_panel := job.get_node("%SurgePanel") as Control
	var surge_reroll := job.get_node("%SurgeRerollButton") as Button
	_assert_true(surge_panel.visible, "Rideshare shows its Surge controls")
	surge_reroll.emit_signal("pressed")
	await _frames(2)
	_assert_equal(GameState.get_machine_free_rerolls(surge_machine.machine_id), 0, "Surge reroll consumes a free token before cash")
	_assert_equal(int(job.get("_surge_rerolls_used")), 1, "Surge reroll advances the per-spin reroll count")

	var surge_seeded := _find_positive_outcome(surge_machine, {"surge_multiplier": 1.0})
	if not surge_seeded.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(surge_seeded["seed"])
		var base := MetropolisEconomy.calculate_machine_spin(surge_machine, rng, {"surge_multiplier": 1.0})
		rng.seed = int(surge_seeded["seed"])
		var tripled := MetropolisEconomy.calculate_machine_spin(surge_machine, rng, {"surge_multiplier": 3.0})
		_assert_equal(int(tripled["payout"]), int(base["payout"]) * 3, "Surge multiplier scales the same predetermined spin")

	var hack_machine := MACHINES[2]
	selector.call("configure", MACHINES, hack_machine.machine_id)
	job.call("_on_selection_changed", hack_machine)
	GameState.add_machine_mechanic_charge(hack_machine.machine_id, hack_machine.mechanic.hack_max_charges)
	await _frames(4)
	var hack_panel := job.get_node("%HackPanel") as Control
	var hack_buttons := job.get_node("%HackReelButtons") as HBoxContainer
	_assert_true(hack_panel.visible, "Firewall shows its Hack Charge controls")
	_assert_equal(hack_buttons.get_child_count(), hack_machine.reel_count, "Firewall offers one Hack target button per reel")
	if hack_buttons.get_child_count() > 0:
		var first_reel_button := hack_buttons.get_child(0) as Button
		first_reel_button.emit_signal("pressed")
		_assert_equal(int(job.get("_hack_target_reel_index")), 0, "Clicking Reel 1 selects it for the Hack Charge")

	GameState.add_machine_ticket(hack_machine.machine_id)
	var charges_before := GameState.get_machine_mechanic_charges(hack_machine.machine_id)
	var prepared := MetropolisEconomy.prepare_machine_spin(hack_machine, {"spend_hack_charge_on_reel_index": 0})
	_assert_true(bool(prepared.get("hack_charge_spent", false)), "Preparing a hacked spin records the selected reel shift")
	_assert_equal(int(prepared.get("hack_charge_reel_index", -1)), 0, "Hack Charge affects only the selected reel index")
	_assert_equal(GameState.get_machine_mechanic_charges(hack_machine.machine_id), charges_before - 1, "Preparing the hacked spin consumes one charge")

	var quantum := MACHINES[4]
	selector.call("configure", MACHINES, quantum.machine_id)
	job.call("_on_selection_changed", quantum)
	await _frames(3)
	var quantum_row: Array[MetropolisSymbol] = [
		quantum.symbols[0], quantum.symbols[4], quantum.symbols[1], quantum.symbols[2], quantum.symbols[3],
	]
	var flags: Array = job.call("_superposition_flags_for_row", quantum_row)
	_assert_equal(flags.size(), quantum.reel_count, "Superposition presentation emits one flag per Quantum reel")
	for index in range(flags.size()):
		_assert_equal(bool(flags[index]), index == 1, "Only the predetermined Superposition reel receives the effect flag")

	job.queue_free()
	await _frames(3)


func _verify_map_round_trip() -> void:
	GameState.reset_for_new_game()
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.reduced_motion = true
	GameState.metropolis_unlocked = false
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await _frames(12)
	var scene_host := main.get_node("SceneHost")
	_assert_equal(scene_host.get_child_count(), 1, "Main hosts exactly one area scene")
	var junkyard := scene_host.get_child(0)
	_assert_equal(junkyard.name, "JunkyardJob", "Main starts in Junkyard")
	var junkyard_hud := junkyard.get_node("Hud")
	_assert_equal(String(junkyard_hud.call("get_current_map_id")), MapConfig.JUNKYARD_ID, "Junkyard HUD owns the Junkyard map ID")

	var map_button := junkyard_hud.get_node("%MapButton") as Button
	map_button.emit_signal("pressed")
	await _frames(3)
	var locked_metropolis := _find_map_card(junkyard_hud, MapConfig.METROPOLIS_ID)
	_assert_true(locked_metropolis != null, "Map Select renders a Metropolis card before unlock")
	if locked_metropolis != null:
		_assert_true(not bool(locked_metropolis.call("is_unlocked_map")), "Metropolis remains locked before the Junk King unlock")
		locked_metropolis.emit_signal("pressed")
		await _frames(4)
		_assert_equal(scene_host.get_child(0).name, "JunkyardJob", "Clicking locked Metropolis does not navigate")

	(junkyard_hud.get_node("%CloseMapButton") as Button).emit_signal("pressed")
	GameState.metropolis_unlocked = true
	map_button.emit_signal("pressed")
	await _frames(3)
	var metropolis_card := _find_map_card(junkyard_hud, MapConfig.METROPOLIS_ID)
	_assert_true(metropolis_card != null and bool(metropolis_card.call("is_unlocked_map")), "Metropolis card unlocks after progression")
	if metropolis_card != null:
		metropolis_card.emit_signal("pressed")
		metropolis_card.emit_signal("pressed")
	await _wait_for_hosted_scene(scene_host, "MetropolisJob")
	_assert_equal(scene_host.get_child_count(), 1, "Repeated travel clicks still leave one hosted scene")
	var metropolis := scene_host.get_child(0)
	_assert_equal(metropolis.name, "MetropolisJob", "Map Select travels to Metropolis")
	var metropolis_hud := metropolis.get_node("Hud")
	_assert_equal(String(metropolis_hud.call("get_current_map_id")), MapConfig.METROPOLIS_ID, "Metropolis HUD owns the Metropolis map ID")

	(metropolis_hud.get_node("%MapButton") as Button).emit_signal("pressed")
	await _frames(3)
	var current_metropolis := _find_map_card(metropolis_hud, MapConfig.METROPOLIS_ID)
	var junkyard_card := _find_map_card(metropolis_hud, MapConfig.JUNKYARD_ID)
	_assert_true(current_metropolis != null and bool(current_metropolis.call("is_current_map")), "Metropolis card is marked CURRENT AREA after travel")
	_assert_true(junkyard_card != null and not bool(junkyard_card.call("is_current_map")), "Junkyard becomes a travel destination in Metropolis")
	if junkyard_card != null:
		junkyard_card.emit_signal("pressed")
	await _wait_for_hosted_scene(scene_host, "JunkyardJob")
	var returned_junkyard := scene_host.get_child(0)
	_assert_equal(returned_junkyard.name, "JunkyardJob", "Map Select returns from Metropolis to Junkyard")
	var returned_hud := returned_junkyard.get_node("Hud")
	(returned_hud.get_node("%MapButton") as Button).emit_signal("pressed")
	await _frames(3)
	var current_junkyard := _find_map_card(returned_hud, MapConfig.JUNKYARD_ID)
	_assert_true(current_junkyard != null and bool(current_junkyard.call("is_current_map")), "Junkyard is CURRENT AREA again after the round trip")

	main.queue_free()
	await _frames(4)


func _prepare_metropolis_state() -> void:
	GameState.reset_for_new_game()
	GameState.metropolis_unlocked = true
	GameState.day_job_tutorial_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.reduced_motion = true
	GameState.selected_machine_id = MACHINES[0].machine_id


func _current_job_options(job: Control, machine: MetropolisMachineDefinition) -> Dictionary:
	var options := {}
	if machine.get_mechanic_kind() == MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER:
		options["surge_multiplier"] = float(job.get("_surge_current_value"))
	return options


func _find_positive_outcome(machine: MetropolisMachineDefinition, options: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(20_000):
		rng.seed = seed_value
		var outcome := MetropolisEconomy.calculate_machine_spin(machine, rng, options)
		if int(outcome.get("payout", 0)) > 0:
			return {"seed": seed_value, "outcome": outcome}
	return {}


func _wait_for_spin(job: Control, machine_name: String) -> void:
	for _index in range(MAX_SPIN_FRAMES):
		if not bool(job.get("_spin_in_progress")):
			return
		await get_tree().process_frame
	_failures.append("%s spin did not finish within %d frames" % [machine_name, MAX_SPIN_FRAMES])


func _wait_for_hosted_scene(scene_host: Node, expected_name: String) -> void:
	for _index in range(MAX_TRANSITION_FRAMES):
		if scene_host.get_child_count() == 1 and scene_host.get_child(0).name == expected_name:
			return
		await get_tree().process_frame
	_failures.append("Main did not host %s within %d frames" % [expected_name, MAX_TRANSITION_FRAMES])


func _find_map_card(hud: Node, map_id: String) -> Button:
	var cards := hud.get_node("%MapCardsContainer")
	for child in cards.get_children():
		if String(child.call("get_map_id")) == map_id:
			return child as Button
	return null


func _rect_contains(outer: Rect2, inner: Rect2) -> bool:
	var grown := outer.grow(RECT_TOLERANCE)
	return grown.has_point(inner.position) and grown.has_point(inner.end)


func _assert_rect_close(actual: Rect2, expected: Rect2, message: String) -> void:
	if not actual.position.is_equal_approx(expected.position) or not actual.size.is_equal_approx(expected.size):
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])
