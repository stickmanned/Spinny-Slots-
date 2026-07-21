extends Node

const BATTLE_CONFIG: JunkKingBattleConfig = preload("res://resources/battles/junk_king_battle.tres")
const JUNKYARD_PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")
const INTRO_DIALOGUE: DialogueData = preload("res://resources/dialogue/junk_king_intro.tres")
const DEFEAT_DIALOGUE: DialogueData = preload("res://resources/dialogue/junk_king_defeat.tres")
const VICTORY_DIALOGUE: DialogueData = preload("res://resources/dialogue/junk_king_victory.tres")
const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const DIALOGUE_SCENE: PackedScene = preload("res://scenes/ui/dialogue_box.tscn")
const POWER_UP_SELECTION_SCENE: PackedScene = preload("res://scenes/ui/power_up_selection_panel.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/junk_king_battle.tscn")
const TEST_SAVE_PATH := "user://junk_king_feature_test.json"
const MAX_SUDDEN_DEATH_PAIRS := 30

var _failures: Array[String] = []
var _selection_confirm_count := 0
var _confirmed_selection: Array[StringName] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	SaveManager.set_save_path_for_tests(TEST_SAVE_PATH)
	SaveManager.delete_save_for_tests()
	_verify_content_and_generated_assets()
	_verify_configuration_and_loadout_rules()
	_verify_upgrade_separation_and_reward_pipeline()
	_verify_seeded_machine_schedules()
	_verify_turn_locks_power_ups_and_complete_battle()
	_verify_repeated_paired_sudden_death()
	_verify_game_state_resolution_transactions()
	_verify_save_round_trip_and_migrations()
	await _verify_dialogue_input_debounce()
	await _verify_power_up_selection_panel()
	await _verify_battle_upgrade_ui()
	await _verify_magnet_trigger_confirmation_and_presence()
	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()

	if _failures.is_empty():
		print(
			"Junk King feature checks passed: isolated max boss upgrades, shared seeded schedules, turn locks, "
			+ "10-round scoring, power-up traces and charges, repeated sudden death, "
			+ "idempotent outcomes, exact dialogue/assets, save migrations, Magnet trigger, confirmation, and layout."
		)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_dialogue_input_debounce() -> void:
	var dialogue := DIALOGUE_SCENE.instantiate()
	add_child(dialogue)
	await get_tree().process_frame
	dialogue.set_input_debounce(0.16)
	var lines: Array[String] = ["First line", "Second line"]
	dialogue.play(lines)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	dialogue._input(click)
	_assert_true(not dialogue.is_typing(), "One click completes the current typed line")
	dialogue._input(click)
	_assert_equal(dialogue.get_line_index(), 0, "An immediate duplicate click cannot skip to the next line")
	OS.delay_msec(170)
	dialogue._input(click)
	_assert_equal(dialogue.get_line_index(), 1, "Dialogue advances once after the debounce window")
	dialogue.queue_free()
	await get_tree().process_frame


func _verify_battle_upgrade_ui() -> void:
	GameState.reset_for_new_game()
	GameState.upgrade_levels = {"luck": 2, "coin_multiplier": 4, "spin_speed": 3}
	GameState.reduced_motion = true
	var battle := BATTLE_SCENE.instantiate() as JunkKingBattle
	battle.seed_override = 84001
	add_child(battle)
	await _frames(4)
	var player_panel := battle.get_node("%PlayerPanel") as BattleContestantPanel
	var boss_panel := battle.get_node("%BossPanel") as BattleContestantPanel
	_assert_true(
		player_panel.get_upgrade_summary_text().contains("CURRENT UPGRADES")
		and player_panel.get_upgrade_summary_text().contains("Luck LV 2/5 x1.30")
		and player_panel.get_upgrade_summary_text().contains("Coins LV 4/10 x1.60")
		and player_panel.get_upgrade_summary_text().contains("Speed LV 3/5 x1.75"),
		"The battle UI accurately displays the player's current upgrade snapshot"
	)
	_assert_true(
		boss_panel.get_upgrade_summary_text().contains("FIXED MAX UPGRADES")
		and boss_panel.get_upgrade_summary_text().contains("Luck LV 5/5 x1.75")
		and boss_panel.get_upgrade_summary_text().contains("Coins LV 10/10 x2.50")
		and boss_panel.get_upgrade_summary_text().contains("Speed LV 5/5 x2.25"),
		"The battle UI accurately displays the Junk King's fixed maximum upgrades"
	)
	var ui_loadout: Array[StringName] = [&"interference_shield", &"triple_welder", &"mixed_load_bonus"]
	battle.call("_on_selection_confirmed", ui_loadout)
	await _frames(5)
	_assert_true(
		(battle.get_node("%ActiveMachineLabel") as Label).text.contains("BOTH CONTESTANTS"),
		"The battle UI explicitly identifies the round machine as shared"
	)
	_assert_true(
		player_panel.get_configured_machine() == boss_panel.get_configured_machine(),
		"Both contestant panels display the same machine before the round's first spin"
	)
	battle.queue_free()
	await _frames(3)
	GameState.reset_for_new_game()


func _verify_content_and_generated_assets() -> void:
	_assert_equal(INTRO_DIALOGUE.lines.size(), 3, "The Junk King introduction has exactly three lines")
	_assert_equal(
		INTRO_DIALOGUE.lines[0],
		"Dang! You are really getting somewhere with the slot machines...",
		"The first introduction line is exact"
	)
	_assert_equal(
		INTRO_DIALOGUE.lines[1].replace("[color=#ffe638]", "").replace("[/color]", ""),
		"I, the JUNK KING, challenge you to a slot machine battle!",
		"The second introduction line renders the exact required text"
	)
	_assert_true(
		INTRO_DIALOGUE.lines[1].contains("[color=#ffe638]JUNK KING[/color]"),
		"JUNK KING is highlighted yellow with RichTextLabel BBCode"
	)
	_assert_equal(INTRO_DIALOGUE.lines[2], "I'll be waiting for you...", "The third introduction line is exact")
	_assert_equal(
		DEFEAT_DIALOGUE.lines,
		["HAHAHAHAHA, I WIN!!", "Next time, make sure you are prepared.", "Here's $30 so you can start over."],
		"The three defeat lines are exact and ordered"
	)
	_assert_equal(
		VICTORY_DIALOGUE.lines,
		[
			"HOW DID YOU BEAT ME?!?!?",
			"ARGGGHHHHHHHHHHHHHHHHHHH!!!",
			"I'm so...",
			"PROUD OF YOU!!!",
			"You are SOOOO READY for the Casino at Metropolis!",
		],
		"The five victory lines are exact and ordered"
	)
	_assert_true(
		JUNKYARD_PROGRESSION.junk_king_portrait != null
		and JUNKYARD_PROGRESSION.junk_king_texture != null,
		"The supplied Junk King artwork is configured for dialogue and arrival"
	)
	var dialogue_portrait := JUNKYARD_PROGRESSION.junk_king_portrait as AtlasTexture
	var full_character := JUNKYARD_PROGRESSION.junk_king_texture as AtlasTexture
	_assert_true(
		dialogue_portrait != null
		and full_character != null
		and dialogue_portrait.region == full_character.region,
		"The Junk King phone portrait includes the full uncropped character"
	)
	var icon_paths: Dictionary = {}
	for definition in BATTLE_CONFIG.power_ups:
		_assert_true(definition.icon != null, "%s has its own generated icon" % definition.display_name)
		if definition.icon == null:
			continue
		var icon_path := definition.icon.resource_path
		_assert_true(icon_path.ends_with(".png"), "%s uses a generated PNG" % definition.display_name)
		_assert_true(FileAccess.file_exists(icon_path), "%s icon exists on disk" % definition.display_name)
		icon_paths[icon_path] = true
	_assert_equal(icon_paths.size(), BATTLE_CONFIG.power_ups.size(), "Every power-up uses a distinct generated image")


func _verify_configuration_and_loadout_rules() -> void:
	_assert_true(
		BATTLE_CONFIG.get_validation_errors().is_empty(),
		"The production Junk King configuration passes its domain validation"
	)
	_assert_equal(BATTLE_CONFIG.regulation_rounds, 10, "The battle has exactly 10 regulation rounds")
	_assert_equal(BATTLE_CONFIG.machines.size(), 3, "The battle references exactly three Junkyard machines")
	_assert_equal(BATTLE_CONFIG.junkyard_upgrades.size(), 3, "The battle references all three Junkyard upgrade tracks")
	_assert_true(BATTLE_CONFIG.power_ups.size() >= 10, "The selectable catalog contains at least ten power-ups")

	var catalog_ids: Dictionary = {}
	for definition in BATTLE_CONFIG.power_ups:
		catalog_ids[definition.power_up_id] = true
	_assert_equal(
		catalog_ids.size(),
		BATTLE_CONFIG.power_ups.size(),
		"Every catalog power-up ID is unique"
	)

	var engine := JunkKingBattleEngine.new(BATTLE_CONFIG, 71001)
	_assert_equal(engine.get_state_name(), &"power_up_selection", "A configured battle starts in loadout selection")
	_assert_equal(engine.get_loadout_ids(JunkKingBattleEngine.JUNK_KING).size(), 3, "The Junk King has exactly three configured power-ups")
	_assert_equal(
		engine.get_loadout_ids(JunkKingBattleEngine.JUNK_KING),
		[&"odds_disruptor", &"payout_siphon", &"final_surge"],
		"The Junk King's fixed loadout is visible and deterministic"
	)

	var incomplete := engine.confirm_player_loadout()
	_assert_error(incomplete, &"incomplete_loadout", "The battle cannot start before three choices are staged")

	var too_few: Array[StringName] = [&"luck_booster", &"payout_doubler"]
	_assert_error(
		engine.select_player_power_ups(too_few),
		&"invalid_loadout_size",
		"A two-item player loadout is rejected"
	)
	var duplicates: Array[StringName] = [&"luck_booster", &"luck_booster", &"final_surge"]
	_assert_error(
		engine.select_player_power_ups(duplicates),
		&"duplicate_power_up",
		"Duplicate power-ups are rejected"
	)
	var unknown: Array[StringName] = [&"luck_booster", &"final_surge", &"not_a_power_up"]
	_assert_error(
		engine.select_player_power_ups(unknown),
		&"unknown_power_up",
		"Unknown power-ups are rejected"
	)

	var valid: Array[StringName] = [&"interference_shield", &"payout_doubler", &"final_surge"]
	var selection := engine.select_player_power_ups(valid)
	_assert_ok(selection, "Exactly three unique catalog power-ups can be staged")
	_assert_equal(engine.get_loadout_ids(JunkKingBattleEngine.PLAYER), valid, "The staged player loadout preserves its three unique choices")
	_assert_ok(engine.confirm_player_loadout(), "Review confirmation starts the battle")
	_assert_equal(engine.get_current_contestant(), JunkKingBattleEngine.PLAYER, "The player always receives the first turn")
	_assert_error(
		engine.select_player_power_ups(valid),
		&"invalid_state",
		"The loadout cannot be changed after confirmation"
	)


func _verify_upgrade_separation_and_reward_pipeline() -> void:
	var expected_max_levels := {
		"luck": 5,
		"coin_multiplier": 10,
		"spin_speed": 5,
	}
	var expected_max_multipliers := {
		"luck": 1.75,
		"coin_multiplier": 2.5,
		"spin_speed": 2.25,
	}
	var player_cases: Array[Dictionary] = [
		{},
		{"luck": 2, "coin_multiplier": 4, "spin_speed": 3},
		expected_max_levels,
	]
	var reference_boss_profile: Dictionary = {}
	for case_index in range(player_cases.size()):
		var engine := JunkKingBattleEngine.new(BATTLE_CONFIG, 81000 + case_index, player_cases[case_index])
		var boss_profile := engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING)
		if reference_boss_profile.is_empty():
			reference_boss_profile = boss_profile
		else:
			_assert_equal(
				boss_profile,
				reference_boss_profile,
				"The Junk King's profile is identical for unupgraded, partial, and maxed players"
			)
		var boss_levels: Dictionary = boss_profile.get("levels", {})
		var boss_multipliers: Dictionary = boss_profile.get("multipliers", {})
		for upgrade_id in expected_max_levels:
			_assert_equal(
				int(boss_levels.get(upgrade_id, -1)),
				int(expected_max_levels[upgrade_id]),
				"The Junk King always uses the configured maximum %s level" % upgrade_id
			)
			_assert_float_close(
				float(boss_multipliers.get(upgrade_id, 0.0)),
				float(expected_max_multipliers[upgrade_id]),
				"The Junk King's %s multiplier is derived from the configured maximum" % upgrade_id
			)

	var mutable_player_levels := {"luck": 1, "coin_multiplier": 2, "spin_speed": 3}
	var snapshot_engine := JunkKingBattleEngine.new(BATTLE_CONFIG, 82001, mutable_player_levels)
	var player_snapshot_before := snapshot_engine.get_upgrade_profile(JunkKingBattleEngine.PLAYER)
	var boss_snapshot_before := snapshot_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING)
	mutable_player_levels["luck"] = 5
	mutable_player_levels["coin_multiplier"] = 10
	var exposed_boss_copy := snapshot_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING)
	(exposed_boss_copy.get("levels", {}) as Dictionary)["luck"] = 0
	_assert_equal(
		snapshot_engine.get_upgrade_profile(JunkKingBattleEngine.PLAYER),
		player_snapshot_before,
		"Mutating the source player dictionary cannot alter the battle-owned player snapshot"
	)
	_assert_equal(
		snapshot_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING),
		boss_snapshot_before,
		"Mutating a returned boss profile copy cannot alter the battle-owned boss snapshot"
	)

	GameState.reset_for_new_game()
	GameState.money = 100000
	var live_engine := JunkKingBattleEngine.new(BATTLE_CONFIG, 82002, GameState.upgrade_levels)
	var live_boss_before := live_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING)
	_assert_true(Economy.purchase_upgrade(&"luck"), "A player Luck purchase succeeds during separation verification")
	_assert_equal(
		live_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING),
		live_boss_before,
		"Buying a player upgrade does not change any Junk King upgrade value"
	)
	GameState.reset_for_new_game()
	_assert_equal(
		live_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING),
		live_boss_before,
		"Resetting player upgrades does not change the Junk King's battle snapshot"
	)

	var loadout: Array[StringName] = [&"interference_shield", &"triple_welder", &"mixed_load_bonus"]
	var pipeline_engine := JunkKingBattleEngine.new(BATTLE_CONFIG, 83001, {})
	_assert_ok(pipeline_engine.begin_battle(loadout), "The isolated reward-pipeline battle starts")
	var player_prepared := pipeline_engine.prepare_player_spin()
	_assert_float_close(float(player_prepared.get("luck_upgrade_multiplier", 0.0)), 1.0, "An unupgraded player spin uses base Luck")
	_assert_float_close(float(player_prepared.get("coin_upgrade_multiplier", 0.0)), 1.0, "An unupgraded player spin uses base Coin multiplier")
	_assert_float_close(float(player_prepared.get("spin_speed_multiplier", 0.0)), 1.0, "An unupgraded player spin uses base Spin Speed")
	pipeline_engine.resolve_spin(StringName(player_prepared.get("token", &"")))
	var shared_machine_id := StringName(player_prepared.get("machine_id", &""))
	_assert_equal(pipeline_engine.get_current_round_machine_id(), shared_machine_id, "The round machine is unchanged before the boss turn")
	var boss_prepared := pipeline_engine.prepare_boss_spin()
	_assert_equal(StringName(boss_prepared.get("machine_id", &"")), shared_machine_id, "Both contestants use the same configured machine in the round")
	_assert_float_close(float(boss_prepared.get("luck_upgrade_multiplier", 0.0)), 1.75, "Junk King Luck uses its fixed maximum")
	_assert_float_close(float(boss_prepared.get("coin_upgrade_multiplier", 0.0)), 2.5, "Junk King Coin multiplier uses its fixed maximum")
	_assert_float_close(float(boss_prepared.get("spin_speed_multiplier", 0.0)), 2.25, "Junk King Spin Speed uses its fixed maximum")
	_assert_equal(
		int(boss_prepared.get("gross_payout", -1)),
		floori(float(boss_prepared.get("base_total", 0)) * 2.5),
		"The Junk King's configured Coin multiplier applies once before power-ups and rounding"
	)
	_assert_true(
		StringName(player_prepared.get("token", &"")) != StringName(boss_prepared.get("token", &"")),
		"Shared-machine contestant outcomes receive independent spin tokens"
	)

	var found_independent_symbols := false
	for seed_value in range(83010, 83030):
		var independent_engine := JunkKingBattleEngine.new(BATTLE_CONFIG, seed_value, {})
		independent_engine.begin_battle(loadout)
		var independent_player := independent_engine.prepare_player_spin()
		independent_engine.resolve_spin(StringName(independent_player.get("token", &"")))
		var independent_boss := independent_engine.prepare_boss_spin()
		if independent_player.get("symbol_ids", []) != independent_boss.get("symbol_ids", []):
			found_independent_symbols = true
			break
	_assert_true(found_independent_symbols, "Independent rolls on the shared machine can produce different symbol results")

	GameState.reset_for_new_game()


func _verify_seeded_machine_schedules() -> void:
	var loadout: Array[StringName] = [&"luck_booster", &"triple_welder", &"mixed_load_bonus"]
	var signatures: Dictionary = {}
	for seed_value in [101, 102, 103, 104]:
		var engine := JunkKingBattleEngine.new(BATTLE_CONFIG, seed_value)
		var start := engine.begin_battle(loadout)
		if not _assert_ok(start, "Seed %d starts with a valid loadout" % seed_value):
			continue
		var player_schedule := engine.get_schedule_ids(JunkKingBattleEngine.PLAYER)
		var boss_schedule := engine.get_schedule_ids(JunkKingBattleEngine.JUNK_KING)
		_assert_equal(boss_schedule, player_schedule, "Seed %d creates one shared round-machine schedule" % seed_value)
		_verify_balanced_schedule(player_schedule, engine.get_extra_machine_id(), "Shared seed %d" % seed_value)
		_assert_equal(
			engine.get_current_round_machine_id(),
			player_schedule[0],
			"The first shared machine is stored as round state for seed %d" % seed_value
		)
		signatures[_schedule_signature(player_schedule)] = true
	_assert_true(signatures.size() > 1, "Different RNG seeds produce more than one machine order")


func _verify_balanced_schedule(
	schedule: Array[StringName],
	extra_machine_id: StringName,
	label: String
) -> void:
	_assert_equal(schedule.size(), 10, "%s schedule contains exactly ten spins" % label)
	var counts: Dictionary = {}
	for machine_id in schedule:
		counts[machine_id] = int(counts.get(machine_id, 0)) + 1
	for machine in BATTLE_CONFIG.machines:
		var expected_count := 4 if machine.machine_id == extra_machine_id else 3
		_assert_equal(
			int(counts.get(machine.machine_id, 0)),
			expected_count,
			"%s uses %s exactly %d times" % [label, machine.display_name, expected_count]
		)
	_assert_equal(counts.size(), 3, "%s can use all three Junkyard machines" % label)


func _verify_turn_locks_power_ups_and_complete_battle() -> void:
	var engine := JunkKingBattleEngine.new(BATTLE_CONFIG, 424242)
	var loadout: Array[StringName] = [&"interference_shield", &"payout_doubler", &"final_surge"]
	if not _assert_ok(engine.begin_battle(loadout), "The full deterministic battle starts"):
		return

	_assert_error(engine.prepare_boss_spin(), &"wrong_turn", "The Junk King cannot spin before the player")
	_assert_equal(
		_get_uses_remaining(engine, JunkKingBattleEngine.PLAYER, &"payout_doubler"),
		2,
		"Payout Doubler starts with two charges"
	)
	var first_round_machine_id := engine.get_current_round_machine_id()
	_assert_equal(
		engine.get_current_round_machine_id(),
		first_round_machine_id,
		"Repeated reads cannot re-randomize the first round machine"
	)
	var first_prepared := engine.prepare_player_spin(&"payout_doubler")
	if not _assert_ok(first_prepared, "The first player result is prepared before presentation"):
		return
	_assert_error(
		engine.prepare_player_spin(),
		&"spin_already_prepared",
		"A second player request cannot prepare a duplicate pending spin"
	)
	_assert_error(
		engine.prepare_boss_spin(),
		&"spin_already_prepared",
		"The opponent cannot skip ahead while presentation is unresolved"
	)
	_assert_equal(
		_get_uses_remaining(engine, JunkKingBattleEngine.PLAYER, &"payout_doubler"),
		2,
		"Preparing a spin does not consume a charge before resolution"
	)
	_assert_float_close(
		float(first_prepared.get("manual_multiplier", 0.0)),
		2.0,
		"Payout Doubler records its exact 2x multiplier"
	)
	_assert_equal(
		int(first_prepared.get("gross_payout", -1)),
		int(first_prepared.get("base_total", 0)) * 2,
		"Payout Doubler applies after the configured base payout"
	)
	_assert_true(
		_trace_contains(first_prepared, "Payout Doubler applied x2.00"),
		"The result trace explains Payout Doubler math"
	)

	var first_token := StringName(first_prepared.get("token", &""))
	var first_resolved := engine.resolve_spin(first_token)
	if not _assert_ok(first_resolved, "The first prepared token resolves once"):
		return
	var scores_after_first := engine.get_scores()
	var replay := engine.resolve_spin(first_token)
	_assert_true(bool(replay.get("idempotent_replay", false)), "Resolving the same spin token returns an idempotent replay")
	_assert_equal(engine.get_scores(), scores_after_first, "An idempotent token replay cannot duplicate score")
	_assert_equal(
		_get_uses_remaining(engine, JunkKingBattleEngine.PLAYER, &"payout_doubler"),
		1,
		"Resolving the first doubled spin consumes exactly one charge"
	)
	_assert_error(
		engine.prepare_player_spin(),
		&"wrong_turn",
		"The player cannot take a second turn before the Junk King"
	)

	var first_boss := engine.prepare_boss_spin()
	if not _assert_ok(first_boss, "The Junk King prepares after the player's result resolves"):
		return
	_assert_equal(
		StringName(first_boss.get("machine_id", &"")),
		first_round_machine_id,
		"Player and Junk King use the same machine in regulation round one"
	)
	engine.resolve_spin(StringName(first_boss.get("token", &"")))
	_assert_equal(engine.get_state_name(), &"round_complete", "Both resolved spins lock the completed round")
	_assert_error(engine.prepare_player_spin(), &"wrong_turn", "The next round cannot start before round presentation advances")
	if not _assert_ok(engine.advance_round(), "Round one advances after both totals update"):
		return

	for round_number in range(2, 11):
		_assert_equal(engine.get_round(), round_number, "The battle advances to regulation round %d" % round_number)
		_assert_equal(engine.get_current_contestant(), JunkKingBattleEngine.PLAYER, "The player starts regulation round %d" % round_number)
		var round_machine_id := engine.get_current_round_machine_id()

		var active_power_up_id: StringName = &"payout_doubler" if round_number == 2 else &""
		if round_number == 3:
			_assert_error(
				engine.prepare_player_spin(&"payout_doubler"),
				&"power_up_depleted",
				"Payout Doubler cannot be activated after both charges are consumed"
			)
		var player_prepared := engine.prepare_player_spin(active_power_up_id)
		if not _assert_ok(player_prepared, "Player round %d prepares exactly one result" % round_number):
			return
		_assert_equal(
			StringName(player_prepared.get("machine_id", &"")),
			round_machine_id,
			"The player uses the stored shared machine in regulation round %d" % round_number
		)

		if round_number >= 8:
			_assert_float_close(
				float(player_prepared.get("final_surge_multiplier", 0.0)),
				1.5,
				"Final Surge applies exactly 1.5x on regulation round %d" % round_number
			)
		if round_number == 5:
			_assert_true(
				_incoming_effect_cancelled_by(player_prepared, &"odds_disruptor", &"interference_shield"),
				"Interference Shield traceably cancels the Junk King's round-four Odds Disruptor"
			)
			_assert_float_close(
				float(player_prepared.get("non_common_weight_multiplier", 0.0)),
				1.0,
				"A shielded Odds Disruptor leaves this loadout's local symbol weights unchanged"
			)
		if round_number == 9:
			var gross_payout := int(player_prepared.get("gross_payout", 0))
			var expected_siphon := floori(float(gross_payout) * 0.2)
			_assert_equal(
				int(player_prepared.get("siphon_amount", -1)),
				expected_siphon,
				"Payout Siphon transfers floor(20% of the positive gross payout)"
			)
			_assert_equal(
				int(player_prepared.get("payout", -1)),
				gross_payout - expected_siphon,
				"The player keeps gross payout minus the traceable siphon transfer"
			)

		var player_resolved := engine.resolve_spin(StringName(player_prepared.get("token", &"")))
		_assert_ok(player_resolved, "Player round %d resolves" % round_number)
		if round_number == 2:
			_assert_equal(
				_get_uses_remaining(engine, JunkKingBattleEngine.PLAYER, &"payout_doubler"),
				0,
				"The second resolved doubled spin consumes the final charge"
			)
		if round_number == 5:
			_assert_equal(
				_get_uses_remaining(engine, JunkKingBattleEngine.PLAYER, &"interference_shield"),
				0,
				"Interference Shield consumes its single charge only when the cancellation resolves"
			)

		var boss_prepared := engine.prepare_boss_spin()
		if not _assert_ok(boss_prepared, "Junk King round %d prepares after the player" % round_number):
			return
		_assert_equal(
			StringName(boss_prepared.get("machine_id", &"")),
			round_machine_id,
			"Player and Junk King share the stored machine in regulation round %d" % round_number
		)
		if round_number == BATTLE_CONFIG.odds_disruptor_round:
			_assert_equal(
				StringName(boss_prepared.get("active_power_up_id", &"")),
				&"odds_disruptor",
				"The Junk King deterministically arms Odds Disruptor on round four"
			)
		if round_number == BATTLE_CONFIG.payout_siphon_round:
			_assert_equal(
				StringName(boss_prepared.get("active_power_up_id", &"")),
				&"payout_siphon",
				"The Junk King deterministically arms Payout Siphon on round eight"
			)
		_assert_ok(
			engine.resolve_spin(StringName(boss_prepared.get("token", &""))),
			"Junk King round %d resolves" % round_number
		)

		if round_number < 10:
			_assert_equal(engine.get_state_name(), &"round_complete", "Regulation round %d ends only after both spins" % round_number)
			if not _assert_ok(engine.advance_round(), "Regulation round %d advances" % round_number):
				return

	_finish_battle_from_tie_if_needed(engine)
	var summary := engine.get_summary()
	var spin_counts: Dictionary = summary.get("spins_completed", {})
	_assert_equal(int(spin_counts.get("player_regulation", -1)), 10, "The player receives exactly ten regulation spins")
	_assert_equal(int(spin_counts.get("junk_king_regulation", -1)), 10, "The Junk King receives exactly ten regulation spins")
	_assert_equal(engine.get_state_name(), &"battle_complete", "The deterministic battle reaches a terminal winner")
	var scores: Dictionary = summary.get("scores", {})
	var expected_winner: StringName = (
		JunkKingBattleEngine.PLAYER
		if int(scores.get("player", 0)) > int(scores.get("junk_king", 0))
		else JunkKingBattleEngine.JUNK_KING
	)
	_assert_equal(StringName(summary.get("winner", &"")), expected_winner, "The winner is determined only from separate battle scores")
	_assert_true(int(scores.get("player", -1)) >= 0 and int(scores.get("junk_king", -1)) >= 0, "Battle totals can never become negative")
	_assert_equal(
		engine.get_spin_history().size(),
		20 + 2 * int(spin_counts.get("player_sudden_death", 0)),
		"Spin history records each committed result exactly once"
	)


func _finish_battle_from_tie_if_needed(engine: JunkKingBattleEngine) -> void:
	var pairs := 0
	while engine.get_state() != JunkKingBattleEngine.BattleState.BATTLE_COMPLETE and pairs < MAX_SUDDEN_DEATH_PAIRS:
		if engine.get_state() == JunkKingBattleEngine.BattleState.ROUND_COMPLETE:
			if not _assert_ok(engine.advance_round(), "A tied score advances into a sudden-death pair"):
				return
		_assert_equal(engine.get_current_contestant(), JunkKingBattleEngine.PLAYER, "The player starts sudden-death pair %d" % (pairs + 1))
		var machine_id := engine.get_current_machine().machine_id
		var player_prepared := engine.prepare_player_spin()
		if not _assert_ok(player_prepared, "Sudden-death player result %d prepares" % (pairs + 1)):
			return
		engine.resolve_spin(StringName(player_prepared.get("token", &"")))
		_assert_equal(engine.get_current_contestant(), JunkKingBattleEngine.JUNK_KING, "The Junk King follows in sudden-death pair %d" % (pairs + 1))
		_assert_equal(engine.get_current_machine().machine_id, machine_id, "Both contestants use the same sudden-death machine")
		var boss_prepared := engine.prepare_boss_spin()
		if not _assert_ok(boss_prepared, "Sudden-death Junk King result %d prepares" % (pairs + 1)):
			return
		engine.resolve_spin(StringName(boss_prepared.get("token", &"")))
		pairs += 1
	_assert_true(pairs < MAX_SUDDEN_DEATH_PAIRS, "Sudden death reaches a winner within the deterministic safety bound")


func _verify_repeated_paired_sudden_death() -> void:
	var tie_config := _make_always_tied_config()
	_assert_true(tie_config.get_validation_errors().is_empty(), "The deterministic tie fixture is a valid battle configuration")
	var tie_loadout: Array[StringName] = [&"neutral_a", &"neutral_b", &"neutral_c"]
	var engine := JunkKingBattleEngine.new(tie_config, 9001)
	if not _assert_ok(engine.begin_battle(tie_loadout), "The deterministic tie fixture starts"):
		return

	for round_number in range(1, 11):
		var player_prepared := engine.prepare_player_spin()
		if not _assert_ok(player_prepared, "Tie fixture player round %d prepares" % round_number):
			return
		engine.resolve_spin(StringName(player_prepared.get("token", &"")))
		var boss_prepared := engine.prepare_boss_spin()
		if not _assert_ok(boss_prepared, "Tie fixture boss round %d prepares" % round_number):
			return
		engine.resolve_spin(StringName(boss_prepared.get("token", &"")))
		if round_number < 10:
			engine.advance_round()

	_assert_equal(engine.get_state_name(), &"round_complete", "Equal regulation totals wait at the sudden-death boundary")
	for sudden_death_round in range(1, 3):
		if not _assert_ok(engine.advance_round(), "Repeated tie advances to sudden-death round %d" % sudden_death_round):
			return
		_assert_equal(engine.get_sudden_death_round(), sudden_death_round, "Sudden-death round counter increments once per tied pair")
		var shared_machine_id := engine.get_current_machine().machine_id
		var player_prepared := engine.prepare_player_spin()
		engine.resolve_spin(StringName(player_prepared.get("token", &"")))
		_assert_equal(engine.get_current_machine().machine_id, shared_machine_id, "Player and boss share the selected machine in tied pair %d" % sudden_death_round)
		var boss_prepared := engine.prepare_boss_spin()
		engine.resolve_spin(StringName(boss_prepared.get("token", &"")))
		_assert_equal(engine.get_state_name(), &"round_complete", "A tied sudden-death pair repeats instead of declaring a winner")

	var counts := engine.get_spin_counts()
	_assert_equal(int(counts.get("player_regulation", -1)), 10, "Tie fixture preserves ten player regulation spins")
	_assert_equal(int(counts.get("junk_king_regulation", -1)), 10, "Tie fixture preserves ten boss regulation spins")
	_assert_equal(int(counts.get("player_sudden_death", -1)), 2, "Two tied sudden-death pairs give the player two extra spins")
	_assert_equal(int(counts.get("junk_king_sudden_death", -1)), 2, "Two tied sudden-death pairs give the boss two extra spins")
	_assert_equal(engine.get_scores().get("player"), engine.get_scores().get("junk_king"), "Repeated sudden death continues only while scores remain tied")


func _make_always_tied_config() -> JunkKingBattleConfig:
	var config := JunkKingBattleConfig.new()
	var machines: Array[MachineDefinition] = []
	for index in range(3):
		var symbol := SlotSymbol.new()
		symbol.symbol_id = StringName("tie_symbol_%d" % index)
		symbol.display_name = "Tie Symbol %d" % index
		symbol.payout = 1
		symbol.weight = 1.0
		var machine := MachineDefinition.new()
		machine.machine_id = StringName("tie_machine_%d" % index)
		machine.display_name = "Tie Machine %d" % index
		machine.symbols = [symbol]
		machines.append(machine)

	var power_ups: Array[PowerUpDefinition] = []
	for suffix in ["a", "b", "c"]:
		var definition := PowerUpDefinition.new()
		definition.power_up_id = StringName("neutral_%s" % suffix)
		definition.display_name = "Neutral %s" % String(suffix).to_upper()
		definition.description = "Deterministic test-only neutral effect."
		definition.effect_kind = PowerUpDefinition.EffectKind.LUCK_BOOSTER
		definition.max_uses = -1
		definition.weight_multiplier = 1.0
		power_ups.append(definition)
	var neutral_upgrades: Array[UpgradeConfig] = []
	for upgrade_id in [&"luck", &"coin_multiplier", &"spin_speed"]:
		var upgrade := UpgradeConfig.new()
		upgrade.upgrade_id = upgrade_id
		upgrade.display_name = String(upgrade_id)
		upgrade.max_level = 1
		upgrade.effect_per_level = 0.0
		neutral_upgrades.append(upgrade)

	config.machines.assign(machines)
	config.junkyard_upgrades.assign(neutral_upgrades)
	config.power_ups.assign(power_ups)
	config.boss_loadout.assign(power_ups)
	return config


func _verify_game_state_resolution_transactions() -> void:
	GameState.reset_for_new_game()
	GameState.money = 400
	GameState.add_gems(11)
	GameState.unlock_machine(&"magnet_machine")
	GameState.add_machine_ticket(&"magnet_machine", 3)
	GameState.upgrade_levels["luck"] = 2
	GameState.selected_machine_id = &"magnet_machine"
	GameState.mark_junk_king_intro_completed()
	var unrelated_before := _unrelated_progress_snapshot()
	var victory_token := GameState.create_junk_king_resolution_token()
	_assert_true(GameState.resolve_junk_king_victory(victory_token, 175), "The first victory transaction resolves")
	_assert_equal(GameState.money, 575, "Victory adds only the Junk King's $175 battle score")
	_assert_true(GameState.junk_king_defeated, "Victory marks the Junk King defeated")
	_assert_true(GameState.metropolis_unlocked, "Victory unlocks Metropolis")
	_assert_true(not GameState.junk_king_available, "A defeated Junk King is no longer challengeable")
	_assert_equal(_unrelated_progress_snapshot(), unrelated_before, "Victory preserves unrelated machines, tickets, upgrades, and gems")
	_assert_true(not GameState.resolve_junk_king_victory(victory_token, 175), "The same victory token cannot award twice")
	_assert_true(
		not GameState.resolve_junk_king_victory(GameState.create_junk_king_resolution_token(), 175),
		"Defeated progression prevents a second victory reward under a new token"
	)
	_assert_equal(GameState.money, 575, "Rejected victory replays leave the wallet unchanged")

	GameState.reset_for_new_game()
	GameState.money = 999
	GameState.add_gems(7)
	GameState.unlock_machine(&"magnet_machine")
	GameState.add_machine_ticket(&"magnet_machine", 4)
	GameState.upgrade_levels["spin_speed"] = 3
	GameState.selected_machine_id = &"magnet_machine"
	GameState.mark_junk_king_intro_completed()
	var loss_progress_before := _unrelated_progress_snapshot()
	var defeat_token := GameState.create_junk_king_resolution_token()
	_assert_true(GameState.resolve_junk_king_defeat(defeat_token), "The first defeat transaction resolves")
	_assert_equal(GameState.money, 30, "Defeat sets the wallet to exactly $30")
	_assert_equal(_unrelated_progress_snapshot(), loss_progress_before, "Defeat preserves unrelated progression")
	_assert_true(GameState.junk_king_available, "The Junk King remains available after a loss")
	_assert_true(not GameState.junk_king_defeated, "A loss does not mark the Junk King defeated")
	_assert_true(not GameState.resolve_junk_king_defeat(defeat_token), "The same defeat token cannot reset the wallet twice")
	GameState.money = 44
	_assert_true(not GameState.resolve_junk_king_defeat(defeat_token), "A replayed defeat callback stays rejected after later wallet changes")
	_assert_equal(GameState.money, 44, "A rejected defeat replay cannot overwrite later earnings")


func _unrelated_progress_snapshot() -> Dictionary:
	return {
		"gems": GameState.gems,
		"selected_machine_id": GameState.selected_machine_id,
		"unlocked_machine_ids": GameState.unlocked_machine_ids.duplicate(),
		"machine_ticket_counts": GameState.machine_ticket_counts.duplicate(true),
		"upgrade_levels": GameState.upgrade_levels.duplicate(true),
	}


func _verify_save_round_trip_and_migrations() -> void:
	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()
	GameState.money = 812
	GameState.add_gems(13)
	GameState.music_volume = 0.67
	GameState.reduced_motion = true
	GameState.sfx_enabled = false
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.unlock_machine(&"magnet_machine")
	GameState.selected_machine_id = &"magnet_machine"
	GameState.add_machine_ticket(&"magnet_machine", 6)
	GameState.upgrade_levels["coin_multiplier"] = 4
	GameState.mark_junk_king_intro_completed()
	_assert_true(SaveManager.save_now(), "The safe test-path checkpoint writes successfully")
	var saved_text := _read_test_save_text()
	_assert_true(not saved_text.contains("battle_state"), "Transient battle state is absent from the save document")
	_assert_true(not saved_text.contains("resolution_token"), "Transient resolution tokens are absent from the save document")

	GameState.reset_for_new_game()
	_assert_true(SaveManager.load_now(), "The complete save reloads from the isolated test path")
	_assert_equal(GameState.money, 812, "Wallet survives a save round trip")
	_assert_equal(GameState.gems, 13, "Gems survive a save round trip")
	_assert_float_close(GameState.music_volume, 0.67, "Music volume survives a save round trip")
	_assert_true(GameState.reduced_motion and not GameState.sfx_enabled, "Accessibility and audio settings survive a save round trip")
	_assert_true(GameState.phone_call_completed and GameState.ticket_purchase_tutorial_completed, "Existing story progress survives a save round trip")
	_assert_true(GameState.junk_king_intro_triggered and GameState.junk_king_intro_completed, "Junk King introduction flags survive a save round trip")
	_assert_true(GameState.junk_king_available and not GameState.junk_king_defeated, "An undefeated available boss survives reload")
	_assert_true(GameState.is_machine_unlocked(&"magnet_machine"), "Machine unlocks survive a save round trip")
	_assert_equal(GameState.get_machine_ticket_count(&"magnet_machine"), 6, "Machine tickets survive a save round trip")
	_assert_equal(GameState.get_upgrade_level(&"coin_multiplier"), 4, "Upgrade levels survive a save round trip")

	SaveManager.delete_save_for_tests()
	_write_test_save({
		"save_version": 1,
		"money": 345,
		"gems": 2,
		"unlocked_machine_ids": ["magnet_machine"],
		"machine_ticket_counts": {"magnet_machine": 2},
		"upgrade_levels": {"luck": 1},
	})
	_assert_true(SaveManager.load_now(), "A legacy Magnet Machine save migrates")
	_assert_true(GameState.junk_king_intro_triggered, "Legacy Magnet ownership marks the intro triggered")
	_assert_true(GameState.junk_king_intro_completed, "Legacy Magnet ownership marks the intro completed instead of replaying it")
	_assert_true(GameState.junk_king_available, "Legacy Magnet ownership makes the undefeated boss available")
	_assert_true(not GameState.junk_king_defeated and not GameState.metropolis_unlocked, "Legacy Magnet ownership does not invent a boss victory")

	SaveManager.delete_save_for_tests()
	_write_test_save({
		"save_version": 1,
		"wallet": 500,
		"story": {"junkKingDefeated": true},
		"machines": {"unlocked_machine_ids": ["magnet_machine"]},
	})
	_assert_true(SaveManager.load_now(), "A legacy defeated-boss save migrates")
	_assert_true(GameState.junk_king_defeated, "Migrated defeat flag remains true")
	_assert_true(not GameState.junk_king_available, "A migrated defeated boss is normalized to unavailable")
	_assert_true(GameState.metropolis_unlocked, "A migrated defeated boss implies Metropolis unlocked")

	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()
	GameState.money = 111
	_assert_true(SaveManager.save_now(), "Backup fixture writes its first checkpoint")
	GameState.money = 222
	_assert_true(SaveManager.save_now(), "Backup fixture rotates its previous checkpoint")
	var corrupt_file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if corrupt_file == null:
		_failures.append("The isolated primary save can be opened for corruption recovery coverage")
	else:
		corrupt_file.store_string("{ invalid json")
		corrupt_file.close()
		GameState.money = 0
		_assert_true(SaveManager.load_now(), "An invalid primary save recovers from its valid backup")
		_assert_equal(GameState.money, 111, "Backup recovery restores the previous complete checkpoint")
	SaveManager.delete_save_for_tests()


func _write_test_save(document: Dictionary) -> void:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("The isolated legacy save fixture can be opened for writing")
		return
	file.store_string(JSON.stringify(document, "\t"))
	file.close()


func _read_test_save_text() -> String:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	if file == null:
		_failures.append("The isolated save can be opened for inspection")
		return ""
	var contents := file.get_as_text()
	file.close()
	return contents


func _verify_power_up_selection_panel() -> void:
	var panel := POWER_UP_SELECTION_SCENE.instantiate() as PowerUpSelectionPanel
	add_child(panel)
	await _frames(2)
	panel.configure(BATTLE_CONFIG.power_ups)
	_selection_confirm_count = 0
	_confirmed_selection.clear()
	panel.selection_confirmed.connect(_on_test_selection_confirmed)

	for index in range(3):
		panel.call("_on_power_up_toggled", true, BATTLE_CONFIG.power_ups[index])
	panel.call("_on_power_up_toggled", true, BATTLE_CONFIG.power_ups[0])
	panel.call("_on_power_up_toggled", true, BATTLE_CONFIG.power_ups[3])
	var selected_ids := panel.get_selected_ids()
	_assert_equal(selected_ids.size(), 3, "The selection panel caps the loadout at exactly three")
	_assert_equal(_unique_string_name_count(selected_ids), 3, "The selection panel never stores duplicate choices")
	_assert_true(BATTLE_CONFIG.power_ups[3].power_up_id not in selected_ids, "A fourth selection is refused until another choice is removed")

	panel.call("_on_confirm_pressed")
	_assert_equal(_selection_confirm_count, 0, "The first confirmation click opens review without starting the battle")
	panel.call("_on_confirm_pressed")
	_assert_equal(_selection_confirm_count, 1, "The reviewed three-item selection confirms exactly once")
	_assert_equal(_confirmed_selection, selected_ids, "The confirmation emits the reviewed three unique IDs")
	panel.queue_free()
	await _frames(2)


func _on_test_selection_confirmed(power_up_ids: Array[StringName]) -> void:
	_selection_confirm_count += 1
	_confirmed_selection.assign(power_up_ids)


func _verify_magnet_trigger_confirmation_and_presence() -> void:
	GameState.reset_for_new_game()
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.reduced_motion = true
	GameState.sfx_enabled = false
	var first_machine := BATTLE_CONFIG.machines[0]
	var magnet_machine := BATTLE_CONFIG.get_machine(&"magnet_machine")
	GameState.unlock_machine(first_machine.machine_id)
	GameState.selected_machine_id = first_machine.machine_id
	GameState.money = magnet_machine.ticket_price - 1

	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(4)
	var selector_phase := int(job.get("_phase"))
	var wallet_before_failed_purchase := GameState.money
	job.call("_on_ticket_purchase_requested", magnet_machine)
	_assert_equal(GameState.money, wallet_before_failed_purchase, "A failed Magnet purchase deducts no money")
	_assert_true(not GameState.is_machine_unlocked(&"magnet_machine"), "A failed Magnet purchase does not unlock the machine")
	_assert_true(not GameState.junk_king_intro_triggered, "A failed Magnet purchase does not trigger the boss introduction")
	_assert_equal(int(job.get("_phase")), selector_phase, "A failed Magnet purchase leaves the Junkyard interaction phase unchanged")

	GameState.money = magnet_machine.ticket_price
	job.call("_on_ticket_purchase_requested", magnet_machine)
	_assert_true(GameState.is_machine_unlocked(&"magnet_machine"), "The first successful Magnet purchase unlocks the machine")
	_assert_equal(GameState.get_machine_ticket_count(&"magnet_machine"), 1, "The first successful Magnet purchase grants one ticket")
	_assert_true(GameState.junk_king_intro_triggered, "The first successful Magnet unlock triggers the Junk King introduction")
	_assert_true(not GameState.junk_king_intro_completed, "The trigger checkpoint does not prematurely complete the cinematic")
	var purchase_layer := job.get_node("PurchaseLayer") as CanvasLayer
	var ticket_layer := job.get_node("TicketLayer") as CanvasLayer
	purchase_layer.visible = true
	ticket_layer.visible = true
	job.call("_begin_junk_king_phone_call")
	_assert_true(
		not purchase_layer.visible and ticket_layer.visible,
		"The Junk King call keeps the persistent machine list visible"
	)
	_assert_float_close(
		float(job.get_node("DialogueBox").get("input_debounce_seconds")),
		0.16,
		"The Junk King call enables rapid-input protection",
		0.001
	)

	job.call("_finish_junk_king_phone_call")
	await _frames(2)
	_assert_true(ticket_layer.visible, "The machine list remains visible after the Junk King call")
	if not GameState.junk_king_intro_completed:
		job.call("_on_junk_king_arrival_completed")
	job.call("_show_machine_selector", false)
	await _frames(3)
	selector_phase = int(job.get("_phase"))
	var tickets_before_repeat := GameState.get_machine_ticket_count(&"magnet_machine")
	GameState.money = magnet_machine.ticket_price
	job.call("_on_ticket_purchase_requested", magnet_machine)
	_assert_equal(
		GameState.get_machine_ticket_count(&"magnet_machine"),
		tickets_before_repeat + 1,
		"A repeat Magnet ticket purchase still grants exactly one ticket"
	)
	_assert_equal(int(job.get("_phase")), selector_phase, "A repeat Magnet purchase does not replay the introduction")
	_assert_true(GameState.junk_king_intro_completed and GameState.junk_king_available, "A repeat purchase preserves completed available boss progression")

	var presence := job.get_node("%JunkKingPresence") as JunkKingPresence
	var presence_rect := presence.get_presence_global_rect()
	var left_column := job.get_node("TicketLayer/Overlay/LeftColumn") as Control
	var selector := job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel") as Control
	var cabinet := selector.get_node("%CabinetArt") as Control
	var left_arrow := selector.get_node("%LeftArrow") as Control
	_assert_true(presence_rect.size.x > 0.0 and presence_rect.size.y > 0.0, "The Junk King receives a positive responsive layout size")
	_assert_true(presence_rect.position.x >= left_column.get_global_rect().end.x, "The Junk King stays to the right of the left HUD column")
	_assert_true(presence_rect.end.x <= cabinet.get_global_rect().position.x, "The Junk King stays to the left of the slot cabinet")
	_assert_true(not presence_rect.intersects(left_arrow.get_global_rect()), "The Junk King does not overlap the machine navigation arrow")
	var visual_root := presence.get_node("%VisualRoot") as Control
	await get_tree().create_timer(0.08).timeout
	_assert_float_close(visual_root.rotation, 0.0, "Reduced motion replaces constant rocking with a non-rotating glow pulse", 0.0001)
	get_tree().root.content_scale_size = Vector2i(1280, 1920)
	get_tree().root.size = Vector2i(1280, 1920)
	await _frames(4)
	presence_rect = presence.get_presence_global_rect()
	_assert_true(
		Rect2(Vector2.ZERO, Vector2(1280, 1920)).encloses(presence_rect),
		"The Junk King remains fully inside the tall-window layout from the reported screenshot"
	)
	_assert_true(ticket_layer.visible, "The machine list stays visible in the tall-window encounter layout")

	var confirmation := job.get_node("JunkKingConfirmation") as CanvasLayer
	var presence_button := presence.get_node("%PresenceButton") as Button
	await _click_gui(presence_button.get_global_rect().get_center())
	_assert_true(bool(confirmation.call("is_open")), "Clicking the available Junk King opens the confirmation")
	job.call("_on_junk_king_activated")
	_assert_true(bool(confirmation.call("is_open")), "A repeated activation cannot open a duplicate confirmation")
	var title := confirmation.get_node("ModalRoot/PromptPanel/Layout/Title") as Label
	_assert_equal(title.text, "Are you ready to challenge the Junk King?", "The confirmation uses the required prompt text")
	var declines := [0]
	confirmation.connect("declined", func() -> void: declines[0] += 1)
	confirmation.call("_decline")
	confirmation.call("_decline")
	_assert_equal(declines[0], 1, "Rapid No input emits only one declined choice")
	_assert_true(not bool(confirmation.call("is_open")), "Selecting No closes the confirmation")
	_assert_equal(int(job.get("_phase")), selector_phase, "Selecting No safely returns to the Junkyard selector")
	_assert_true(GameState.junk_king_available, "Selecting No keeps the Junk King available")
	var challenge_requests := [0]
	job.connect("junk_king_challenge_confirmed", func() -> void: challenge_requests[0] += 1)
	await _click_gui(presence_button.get_global_rect().get_center())
	_assert_true(bool(confirmation.call("is_open")), "The Junk King remains clickable after declining once")
	var yes_button := confirmation.get_node("ModalRoot/PromptPanel/Layout/Choices/YesButton") as Button
	await _click_gui(yes_button.get_global_rect().get_center())
	_assert_equal(challenge_requests[0], 1, "Selecting Yes requests the Junk King fight exactly once")
	confirmation.call("_accept")
	_assert_equal(challenge_requests[0], 1, "Repeated Yes input cannot request a duplicate fight")
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(3)

	job.queue_free()
	await _frames(3)
	SaveManager.delete_save_for_tests()


func _get_uses_remaining(
	engine: JunkKingBattleEngine,
	contestant: StringName,
	power_up_id: StringName
) -> int:
	for status in engine.get_loadout_status(contestant):
		if StringName(status.get("power_up_id", &"")) == power_up_id:
			return int(status.get("uses_remaining", 0))
	return 0


func _incoming_effect_cancelled_by(
	outcome: Dictionary,
	effect_id: StringName,
	shield_id: StringName
) -> bool:
	var details: Array = outcome.get("incoming_effects", [])
	for detail in details:
		if (
			StringName(detail.get("effect_id", &"")) == effect_id
			and StringName(detail.get("cancelled_by", &"")) == shield_id
		):
			return true
	return false


func _trace_contains(outcome: Dictionary, phrase: String) -> bool:
	var trace: Array = outcome.get("trace", [])
	for line in trace:
		if String(line).contains(phrase):
			return true
	return false


func _schedule_signature(schedule: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for machine_id in schedule:
		parts.append(String(machine_id))
	return ",".join(parts)


func _unique_string_name_count(values: Array[StringName]) -> int:
	var unique: Dictionary = {}
	for value in values:
		unique[value] = true
	return unique.size()


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _click_gui(position: Vector2) -> void:
	var input_position := get_viewport().get_screen_transform() * position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = input_position
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = input_position
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


func _assert_ok(result: Dictionary, message: String) -> bool:
	if bool(result.get("ok", false)):
		return true
	_failures.append(
		"%s (error %s: %s)"
		% [message, result.get("error", &"missing_error"), result.get("message", "no message")]
	)
	return false


func _assert_error(result: Dictionary, expected_error: StringName, message: String) -> void:
	if bool(result.get("ok", false)) or StringName(result.get("error", &"")) != expected_error:
		_failures.append(
			"%s (expected error %s, got %s)"
			% [message, expected_error, result.get("error", &"successful_result")]
		)


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func _assert_float_close(
	actual: float,
	expected: float,
	message: String,
	tolerance: float = 0.00001
) -> void:
	if not is_equal_approx(actual, expected) and absf(actual - expected) > tolerance:
		_failures.append("%s (expected %.6f, got %.6f)" % [message, expected, actual])
