extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")
const MAX_SEED_SEARCH := 5000

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	_verify_rarest_symbol_identification()
	_verify_gem_rewards_scale_with_machine_tier()
	_verify_outcome_reports_accurate_rarest_hits()
	_verify_award_rarest_bonus()
	await _verify_confetti_effect()
	await _verify_end_to_end_spin_awards_gems_and_confetti()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("Milestone 3c checks passed: rarest-symbol identification, tiered gem rewards, accurate rarest-hit reporting, gem bonus awarding, confetti cleanup, and end-to-end spin integration.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_rarest_symbol_identification() -> void:
	var expected_rarest_ids := {
		&"cardboard_cash": &"gold_box",
		&"can_crusher": &"scrap",
		&"magnet_machine": &"magnet",
	}
	for machine in PROGRESSION.machines:
		var rarest := Economy.get_rarest_symbol(machine)
		_assert_true(rarest != null, "%s has an identifiable rarest symbol" % machine.display_name)
		_assert_equal(rarest.symbol_id, expected_rarest_ids[machine.machine_id], "%s's rarest symbol is its lowest-weight symbol" % machine.display_name)
		for symbol in machine.symbols:
			_assert_true(rarest.weight <= symbol.weight, "%s's rarest symbol '%s' has the minimum weight on the machine" % [machine.display_name, rarest.symbol_id])


func _verify_gem_rewards_scale_with_machine_tier() -> void:
	var cardboard: MachineDefinition = PROGRESSION.machines[0]
	var can_crusher: MachineDefinition = PROGRESSION.machines[1]
	var magnet: MachineDefinition = PROGRESSION.machines[2]
	_assert_equal(cardboard.rarest_symbol_gem_reward, 1, "Cardboard Cash awards 1 gem per rarest item")
	_assert_equal(can_crusher.rarest_symbol_gem_reward, 3, "Can Crusher awards 3 gems per rarest item")
	_assert_equal(magnet.rarest_symbol_gem_reward, 8, "Magnet Machine awards 8 gems per rarest item")
	_assert_true(cardboard.rarest_symbol_gem_reward < can_crusher.rarest_symbol_gem_reward, "Gem reward increases from Cardboard Cash to Can Crusher")
	_assert_true(can_crusher.rarest_symbol_gem_reward < magnet.rarest_symbol_gem_reward, "Gem reward increases from Can Crusher to Magnet Machine, the highest-end machine")


func _verify_outcome_reports_accurate_rarest_hits() -> void:
	for machine in PROGRESSION.machines:
		var rarest := Economy.get_rarest_symbol(machine)
		for seed_value in [11, 42, 4242, 777, 99]:
			Economy.set_rng_seed(seed_value)
			var predicted: Array[SlotSymbol] = []
			for _reel_index in range(Economy.REEL_COUNT):
				predicted.append(Economy.roll_symbol(machine))
			var expected_hits := 0
			for symbol in predicted:
				if symbol == rarest:
					expected_hits += 1
			GameState.reset_for_new_game()
			GameState.add_machine_ticket(machine.machine_id)
			Economy.set_rng_seed(seed_value)
			var outcome := Economy.prepare_machine_spin(machine)
			_assert_equal(int(outcome.get("rarest_hits", -1)), expected_hits, "%s seed %d reports %d rarest-symbol hits" % [machine.display_name, seed_value, expected_hits])
	GameState.reset_for_new_game()


func _verify_award_rarest_bonus() -> void:
	GameState.reset_for_new_game()
	var machine: MachineDefinition = PROGRESSION.machines[2]
	var no_hit_outcome := {"rarest_hits": 0}
	_assert_equal(Economy.award_rarest_bonus(machine, no_hit_outcome), 0, "No rarest hits awards zero gems")
	_assert_equal(GameState.gems, 0, "No rarest hits leaves the gem balance untouched")

	var one_hit_outcome := {"rarest_hits": 1}
	var awarded := Economy.award_rarest_bonus(machine, one_hit_outcome)
	_assert_equal(awarded, machine.rarest_symbol_gem_reward, "One rarest hit awards exactly the machine's configured gem reward")
	_assert_equal(GameState.gems, machine.rarest_symbol_gem_reward, "Gem balance reflects the single-hit award")

	GameState.reset_for_new_game()
	var three_hit_outcome := {"rarest_hits": 3}
	var awarded_triple := Economy.award_rarest_bonus(machine, three_hit_outcome)
	_assert_equal(awarded_triple, machine.rarest_symbol_gem_reward * 3, "Landing the rarest symbol on all three reels multiplies the gem reward by three")
	_assert_equal(Economy.award_rarest_bonus(null, one_hit_outcome), 0, "A null machine cannot award gems")
	GameState.reset_for_new_game()


func _verify_confetti_effect() -> void:
	var effect := ConfettiEffect.new()
	add_child(effect)
	effect.size = Vector2(1280, 720)
	await _frames(1)

	effect.play(false)
	await _frames(1)
	_assert_equal(effect.get_child_count(), ConfettiEffect.PIECE_COUNT, "Confetti spawns the configured number of rectangle pieces")
	var seen_colors: Dictionary = {}
	for index in range(effect.get_child_count()):
		var piece := effect.get_child(index) as ColorRect
		_assert_true(piece is ColorRect, "Confetti pieces are simple ColorRects")
		_assert_equal(piece.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Confetti pieces never intercept pointer input")
		var expected_color: Color = ConfettiEffect.RAINBOW_COLORS[index % ConfettiEffect.RAINBOW_COLORS.size()]
		_assert_equal(piece.color, expected_color, "Confetti piece %d uses its cycled rainbow color" % index)
		seen_colors[piece.color] = true
	_assert_true(seen_colors.size() >= mini(ConfettiEffect.RAINBOW_COLORS.size(), ConfettiEffect.PIECE_COUNT), "Confetti rain alternates through multiple rainbow colors, not one flat color")

	await effect.finished
	await _frames(1)
	_assert_equal(effect.get_child_count(), 0, "Every confetti piece cleans itself up once it lands")

	effect.play(true)
	await _frames(1)
	_assert_equal(effect.get_child_count(), 0, "Reduced motion skips spawning visual confetti pieces")
	await effect.finished
	_assert_equal(effect.get_child_count(), 0, "Reduced-motion confetti still reports completion")

	effect.queue_free()
	await _frames(1)


func _verify_end_to_end_spin_awards_gems_and_confetti() -> void:
	GameState.reset_for_new_game()
	_prepare_machine_mode_state()
	var machine: MachineDefinition = PROGRESSION.machines[0]
	var rarest := Economy.get_rarest_symbol(machine)
	var seed_value := _find_seed_with_rarest_hit(machine, rarest)
	_assert_true(seed_value >= 0, "A deterministic seed exists whose spin lands the rarest symbol within %d attempts" % MAX_SEED_SEARCH)
	if seed_value < 0:
		return

	Economy.set_rng_seed(seed_value)
	var predicted: Array[SlotSymbol] = []
	for _reel_index in range(Economy.REEL_COUNT):
		predicted.append(Economy.roll_symbol(machine))
	var expected_hits := 0
	for symbol in predicted:
		if symbol == rarest:
			expected_hits += 1
	var expected_gems := machine.rarest_symbol_gem_reward * expected_hits

	GameState.add_machine_ticket(machine.machine_id)
	Economy.set_rng_seed(seed_value)
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)
	var confetti: ConfettiEffect = job.get_node("ConfettiEffectLayer/ConfettiEffect")
	# A one-element array, not a bare int: GDScript lambdas capture local
	# value-type variables by value, so a raw int here would never observe
	# updates made inside the connected callable.
	var confetti_play_count := [0]
	confetti.finished.connect(func() -> void: confetti_play_count[0] += 1)
	var spin_button: Button = job.get_node("SelectorLayer/Overlay/MachineArea/SpinButton")
	var gems_before := GameState.gems
	spin_button.emit_signal("pressed")
	# The reel animation runs first; confetti only spawns once the result
	# (and its rarest-symbol hits) is revealed.
	await get_tree().create_timer(AudioFx.get_spin_duration() + 0.05).timeout
	_assert_true(confetti.get_child_count() > 0, "Landing the rarest symbol spawns confetti alongside the spin result")
	await get_tree().create_timer(CoinCollectionEffect.get_max_duration() + 0.3).timeout
	_assert_equal(GameState.gems - gems_before, expected_gems, "Completing the spin awards exactly the expected rarest-item gem bonus")
	# Confetti runs independently of (and can outlast) the coin-collection
	# animation, so give it its own full duration before checking completion.
	await get_tree().create_timer(ConfettiEffect.get_max_duration()).timeout
	_assert_true(confetti_play_count[0] >= 1, "Confetti finishes its rain and reports completion")
	_assert_equal(confetti.get_child_count(), 0, "Confetti cleans itself up after the celebration")

	# Pressing spin again (with no ticket left) must not award a second bonus.
	spin_button.emit_signal("pressed")
	await _frames(2)
	_assert_equal(GameState.gems - gems_before, expected_gems, "A spin without a ticket cannot award a duplicate gem bonus")

	job.queue_free()
	await _frames(2)
	GameState.reset_for_new_game()


func _find_seed_with_rarest_hit(machine: MachineDefinition, rarest: SlotSymbol) -> int:
	for seed_value in range(1, MAX_SEED_SEARCH):
		Economy.set_rng_seed(seed_value)
		var hit := false
		for _reel_index in range(Economy.REEL_COUNT):
			if Economy.roll_symbol(machine) == rarest:
				hit = true
		if hit:
			return seed_value
	return -1


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
