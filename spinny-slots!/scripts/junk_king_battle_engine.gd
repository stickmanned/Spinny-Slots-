class_name JunkKingBattleEngine
extends RefCounted

## Pure battle-domain model. It owns only transient battle state and a seeded
## RNG; it never reads or writes tickets, wallets, gems, upgrades, or saves.

signal state_changed(previous_state: int, new_state: int)
signal spin_prepared(outcome: Dictionary)
signal spin_resolved(outcome: Dictionary)
signal battle_completed(summary: Dictionary)

enum BattleState {
	IDLE,
	POWER_UP_SELECTION,
	PLAYER_TURN,
	BOSS_TURN,
	ROUND_COMPLETE,
	SUDDEN_DEATH_PLAYER_TURN,
	SUDDEN_DEATH_BOSS_TURN,
	BATTLE_COMPLETE,
}

const PLAYER: StringName = &"player"
const JUNK_KING: StringName = &"junk_king"
const REGULATION: StringName = &"regulation"
const SUDDEN_DEATH: StringName = &"sudden_death"

var _config: JunkKingBattleConfig
var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _state: int = BattleState.IDLE
var _phase: StringName = REGULATION
var _current_round: int = 1
var _sudden_death_round: int = 0
var _sudden_death_machine: MachineDefinition
var _extra_machine: MachineDefinition

var _player_loadout: Array[PowerUpDefinition] = []
var _boss_loadout: Array[PowerUpDefinition] = []
var _round_schedule: Array[MachineDefinition] = []
var _current_round_machine: MachineDefinition
var _player_upgrade_profile: Dictionary = {}
var _boss_upgrade_profile: Dictionary = {}
var _player_remaining_uses: Dictionary = {}
var _boss_remaining_uses: Dictionary = {}
var _player_pending_hostiles: Array[Dictionary] = []
var _boss_pending_hostiles: Array[Dictionary] = []

var _player_score: int = 0
var _boss_score: int = 0
var _player_regulation_spins: int = 0
var _boss_regulation_spins: int = 0
var _player_sudden_death_spins: int = 0
var _boss_sudden_death_spins: int = 0
var _winner: StringName = &""

var _next_spin_id: int = 0
var _next_hostile_id: int = 0
var _pending_spin: Dictionary = {}
var _resolved_spins: Dictionary = {}
var _spin_history: Array[Dictionary] = []
var _battle_log: Array[String] = []


func _init(
	battle_config: JunkKingBattleConfig = null,
	seed_value: int = 0,
	player_upgrade_levels: Dictionary = {}
) -> void:
	if battle_config != null:
		configure(battle_config, seed_value, player_upgrade_levels)


## Configures a fresh attempt and enters power-up selection. A caller may use
## the same seed to reproduce schedules, symbols, rerolls, and Overcharge.
func configure(
	battle_config: JunkKingBattleConfig,
	seed_value: int,
	player_upgrade_levels: Dictionary = {}
) -> Dictionary:
	_config = battle_config
	_seed = seed_value
	_rng.seed = seed_value
	_reset_runtime()
	if _config == null:
		return _error(&"missing_config", "A Junk King battle configuration is required.")
	var errors := _config.get_validation_errors()
	if not errors.is_empty():
		return {
			"ok": false,
			"error": &"invalid_config",
			"errors": errors,
			"state": _state,
		}
	_player_upgrade_profile = _config.make_upgrade_profile(player_upgrade_levels)
	_boss_upgrade_profile = _config.make_upgrade_profile({}, true)
	_boss_loadout.assign(_config.boss_loadout)
	_set_state(BattleState.POWER_UP_SELECTION)
	return {
		"ok": true,
		"seed": _seed,
		"state": _state,
		"state_name": get_state_name(),
		"catalog": get_power_up_catalog(),
		"boss_loadout": get_loadout(JUNK_KING),
		"player_upgrades": get_upgrade_profile(PLAYER),
		"boss_upgrades": get_upgrade_profile(JUNK_KING),
	}


## Stages exactly three unique catalog entries for review. This does not start
## the fight; confirm_player_loadout() is the explicit confirmation boundary.
func select_player_power_ups(power_up_ids: Array[StringName]) -> Dictionary:
	if _state != BattleState.POWER_UP_SELECTION:
		return _error(&"invalid_state", "Power-ups can only be selected before the battle starts.")
	if power_up_ids.size() != _config.loadout_size:
		return _error(
			&"invalid_loadout_size",
			"Select exactly %d different power-ups." % _config.loadout_size
		)
	var selected: Array[PowerUpDefinition] = []
	var seen: Dictionary = {}
	for power_up_id in power_up_ids:
		if seen.has(power_up_id):
			return _error(&"duplicate_power_up", "A power-up can only appear once in a loadout.")
		var definition := _config.get_power_up(power_up_id)
		if definition == null:
			return _error(&"unknown_power_up", "Unknown power-up: %s." % power_up_id)
		seen[power_up_id] = true
		selected.append(definition)
	_player_loadout.assign(selected)
	return {
		"ok": true,
		"selection": get_loadout(PLAYER),
		"selection_ids": get_loadout_ids(PLAYER),
		"can_confirm": true,
	}


func select_player_power_up_definitions(definitions: Array[PowerUpDefinition]) -> Dictionary:
	var power_up_ids: Array[StringName] = []
	for definition in definitions:
		if definition == null:
			return _error(&"unknown_power_up", "The selected loadout contains an empty power-up.")
		power_up_ids.append(definition.power_up_id)
	return select_player_power_ups(power_up_ids)


## Builds balanced schedules and begins round one. Neither contestant's
## permanent economy state is touched.
func confirm_player_loadout() -> Dictionary:
	if _state != BattleState.POWER_UP_SELECTION:
		return _error(&"invalid_state", "The loadout can only be confirmed once.")
	if _player_loadout.size() != _config.loadout_size:
		return _error(
			&"incomplete_loadout",
			"Select exactly %d different power-ups before confirming." % _config.loadout_size
		)
	_initialize_uses()
	_build_regulation_schedule()
	_set_state(BattleState.PLAYER_TURN)
	return {
		"ok": true,
		"seed": _seed,
		"state": _state,
		"state_name": get_state_name(),
		"round": _current_round,
		"current_contestant": PLAYER,
		"current_machine": get_current_machine(),
		"current_round_machine_id": get_current_round_machine_id(),
		"player_schedule": get_schedule_ids(PLAYER),
		"boss_schedule": get_schedule_ids(JUNK_KING),
		"extra_machine_id": get_extra_machine_id(),
		"player_loadout": get_loadout_ids(PLAYER),
		"boss_loadout": get_loadout_ids(JUNK_KING),
		"player_upgrades": get_upgrade_profile(PLAYER),
		"boss_upgrades": get_upgrade_profile(JUNK_KING),
	}


func begin_battle(player_power_up_ids: Array[StringName]) -> Dictionary:
	var selection := select_player_power_ups(player_power_up_ids)
	if not bool(selection.get("ok", false)):
		return selection
	return confirm_player_loadout()


## Prepares the player's complete result and locks further spin requests. The
## returned token must be passed to resolve_spin() after presentation finishes.
func prepare_player_spin(active_power_up_id: StringName = &"") -> Dictionary:
	return prepare_spin(PLAYER, active_power_up_id)


## Uses deterministic AI: Odds Disruptor on regulation round 4 and Payout
## Siphon on round 8, when configured/equipped and still charged.
func prepare_boss_spin() -> Dictionary:
	return prepare_spin(JUNK_KING, get_boss_ai_active_power_up_id())


## Computes the full outcome before presentation. No score, charge, or pending
## hostile effect is committed until resolve_spin() accepts the generated token.
func prepare_spin(contestant: StringName, active_power_up_id: StringName = &"") -> Dictionary:
	if contestant != PLAYER and contestant != JUNK_KING:
		return _error(&"invalid_contestant", "Unknown battle contestant.")
	if not can_prepare_spin(contestant):
		if not _pending_spin.is_empty():
			return _error_with_token(
				&"spin_already_prepared",
				"A spin is already awaiting presentation.",
				StringName(_pending_spin.get("token", &""))
			)
		return _error(&"wrong_turn", "It is not %s's turn." % String(contestant))
	var active_definition := _get_loadout_power_up(contestant, active_power_up_id)
	if active_power_up_id != &"":
		var active_error := _validate_manual_activation(contestant, active_definition, active_power_up_id)
		if not active_error.is_empty():
			return active_error
	var machine := get_current_machine()
	if machine == null:
		return _error(&"missing_machine", "No machine is scheduled for this spin.")

	var trace: Array[String] = []
	var commit_data := {
		"consume_power_up_ids": [],
		"remove_hostile_ids": [],
		"queue_hostile_effect_id": &"",
	}
	var incoming_resolution := _resolve_incoming_hostiles_for_preparation(contestant, trace, commit_data)
	var upgrade_profile := get_upgrade_profile(contestant)
	var luck_upgrade_multiplier := _get_profile_multiplier(upgrade_profile, &"luck")
	var coin_upgrade_multiplier := _get_profile_multiplier(upgrade_profile, &"coin_multiplier")
	var spin_speed_multiplier := _get_profile_multiplier(upgrade_profile, &"spin_speed")
	var non_common_multiplier := (
		float(incoming_resolution.get("weight_multiplier", 1.0)) * luck_upgrade_multiplier
	)
	trace.append(
		"2. %s upgrades: Luck Lv %d x%.2f, Coin Lv %d x%.2f, Spin Speed Lv %d x%.2f."
		% [
			"Player" if contestant == PLAYER else "Junk King",
			_get_profile_level(upgrade_profile, &"luck"),
			luck_upgrade_multiplier,
			_get_profile_level(upgrade_profile, &"coin_multiplier"),
			coin_upgrade_multiplier,
			_get_profile_level(upgrade_profile, &"spin_speed"),
			spin_speed_multiplier,
		]
	)
	var luck := _get_loadout_effect(contestant, PowerUpDefinition.EffectKind.LUCK_BOOSTER)
	if luck != null:
		non_common_multiplier *= luck.weight_multiplier
		trace.append(
			"3. Power-up weights: Luck Booster x%.2f; combined non-common multiplier x%.4f."
			% [luck.weight_multiplier, non_common_multiplier]
		)
	else:
		trace.append(
			"3. Power-up weights: no Luck Booster; combined non-common multiplier x%.4f."
			% non_common_multiplier
		)
	var effective_weights := Economy.calculate_effective_symbol_weights(machine, non_common_multiplier)
	trace[-1] += " Effective weights: %s." % str(effective_weights)

	var initial_outcome := Economy.calculate_machine_spin(machine, _rng, non_common_multiplier, 1.0)
	if initial_outcome.is_empty():
		return _error(&"spin_calculation_failed", "The scheduled machine could not calculate a result.")
	var initial_symbols: Array[SlotSymbol] = _symbols_from_outcome(initial_outcome)
	var initial_symbol_ids := _symbol_ids(initial_symbols)
	trace.append("4. Independently rolled symbols: %s." % _format_symbol_ids(initial_symbol_ids))

	var final_outcome := initial_outcome
	var final_symbols := initial_symbols
	var rerolled := false
	var scrap_reroll := _get_loadout_effect(contestant, PowerUpDefinition.EffectKind.SCRAP_REROLL)
	if (
		scrap_reroll != null
		and _has_power_up_charge(contestant, scrap_reroll)
		and _all_lowest_value_symbols(machine, initial_symbols)
	):
		final_outcome = Economy.calculate_machine_spin(machine, _rng, non_common_multiplier, 1.0)
		final_symbols = _symbols_from_outcome(final_outcome)
		rerolled = true
		_add_consumption(commit_data, scrap_reroll.power_up_id)
		trace.append(
			"5. Scrap Reroll consumed one charge; replacement symbols: %s."
			% _format_symbol_ids(_symbol_ids(final_symbols))
		)
	else:
		trace.append("5. Scrap Reroll did not trigger.")

	var base_payout := maxi(int(final_outcome.get("base_total", 0)), 0)
	var payout_value := float(base_payout) * coin_upgrade_multiplier
	trace.append("6. Configured symbol payouts sum to $%d." % base_payout)
	trace.append(
		"7. %s Coin Multiplier x%.2f applied before power-ups: $%.2f."
		% ["Player" if contestant == PLAYER else "Junk King", coin_upgrade_multiplier, payout_value]
	)

	var conditional_modifier_id: StringName = &""
	var conditional_multiplier := 1.0
	var triple_welder := _get_loadout_effect(contestant, PowerUpDefinition.EffectKind.TRIPLE_WELDER)
	var mixed_load := _get_loadout_effect(contestant, PowerUpDefinition.EffectKind.MIXED_LOAD_BONUS)
	if triple_welder != null and _all_symbol_ids_match(final_symbols):
		conditional_modifier_id = triple_welder.power_up_id
		conditional_multiplier = triple_welder.payout_multiplier
	elif mixed_load != null and _all_symbol_ids_differ(final_symbols):
		conditional_modifier_id = mixed_load.power_up_id
		conditional_multiplier = mixed_load.payout_multiplier
	payout_value *= conditional_multiplier
	if conditional_modifier_id == &"":
		trace.append("8. No Triple Welder or Mixed Load Bonus modifier applied.")
	else:
		trace.append(
			"8. %s applied x%.2f (the two conditional bonuses are mutually exclusive)."
			% [_config.get_power_up(conditional_modifier_id).display_name, conditional_multiplier]
		)

	var final_surge_multiplier := 1.0
	var final_surge := _get_loadout_effect(contestant, PowerUpDefinition.EffectKind.FINAL_SURGE)
	if (
		final_surge != null
		and _phase == REGULATION
		and payout_value > 0.0
		and final_surge.applies_during_regulation_round(_current_round)
	):
		final_surge_multiplier = final_surge.payout_multiplier
		payout_value *= final_surge_multiplier
		trace.append(
			"9. Final Surge applied x%.2f in regulation round %d."
			% [final_surge_multiplier, _current_round]
		)
	else:
		trace.append("9. Final Surge did not apply (sudden death never qualifies).")

	var manual_multiplier := 1.0
	var overcharge_roll := -1.0
	var overcharge_failed := false
	if active_definition != null:
		_add_consumption(commit_data, active_definition.power_up_id)
		match active_definition.effect_kind:
			PowerUpDefinition.EffectKind.PAYOUT_DOUBLER:
				manual_multiplier = active_definition.payout_multiplier
				payout_value *= manual_multiplier
				trace.append("10. Payout Doubler applied x%.2f." % manual_multiplier)
			PowerUpDefinition.EffectKind.OVERCHARGE:
				overcharge_roll = _rng.randf()
				overcharge_failed = overcharge_roll < active_definition.failure_chance
				if overcharge_failed:
					payout_value = 0.0
					trace.append(
						"10. Overcharge roll %.6f was below %.2f; payout forced to $0."
						% [overcharge_roll, active_definition.failure_chance]
					)
				else:
					manual_multiplier = active_definition.payout_multiplier
					payout_value *= manual_multiplier
					trace.append(
						"10. Overcharge roll %.6f passed; x%.2f applied."
						% [overcharge_roll, manual_multiplier]
					)
			PowerUpDefinition.EffectKind.ODDS_DISRUPTOR, PowerUpDefinition.EffectKind.PAYOUT_SIPHON:
				commit_data["queue_hostile_effect_id"] = active_definition.power_up_id
				trace.append(
					"10. %s armed for the opponent; no own payout multiplier applied."
					% active_definition.display_name
				)
			_:
				return _error(&"unsupported_active_power_up", "That power-up cannot be manually activated.")
	else:
		trace.append("10. No manual power-up was armed for this spin.")

	var gross_payout := clampi(floori(payout_value), 0, _config.score_cap)
	trace.append("11. Floored once and clamped: final pre-siphon payout is $%d." % gross_payout)

	var siphon_record: Dictionary = incoming_resolution.get("siphon", {})
	var siphon_amount := 0
	var siphon_source: StringName = &""
	if not siphon_record.is_empty() and gross_payout > 0:
		var siphon_definition := _config.get_power_up(StringName(siphon_record.get("effect_id", &"")))
		if siphon_definition != null:
			siphon_amount = clampi(
				floori(float(gross_payout) * siphon_definition.transfer_fraction),
				0,
				gross_payout
			)
			siphon_source = StringName(siphon_record.get("source", &""))
			_add_hostile_removal(commit_data, int(siphon_record.get("hostile_id", -1)))
	var net_payout := maxi(gross_payout - siphon_amount, 0)
	if siphon_amount > 0:
		trace.append(
			"12. Payout Siphon transferred floor($%d x 0.20) = $%d to %s; spinner keeps $%d."
			% [gross_payout, siphon_amount, String(siphon_source), net_payout]
		)
	elif not siphon_record.is_empty() and gross_payout == 0:
		trace.append("12. Payout Siphon remains pending because this payout is $0.")
	else:
		trace.append("12. No Payout Siphon transfer applied.")

	_next_spin_id += 1
	var token := StringName("junk_king_spin_%d_%d" % [_seed, _next_spin_id])
	var opponent := get_opponent(contestant)
	var score_deltas := {
		String(contestant): net_payout,
		String(opponent): 0,
	}
	if siphon_amount > 0 and siphon_source != &"":
		score_deltas[String(siphon_source)] = int(score_deltas.get(String(siphon_source), 0)) + siphon_amount
	trace.append("13. Awaiting idempotent score commit for token %s." % token)
	var result := {
		"ok": true,
		"token": token,
		"resolved": false,
		"contestant": contestant,
		"opponent": opponent,
		"phase": _phase,
		"round": _current_round,
		"sudden_death_round": _sudden_death_round,
		"machine": machine,
		"machine_id": machine.machine_id,
		"machine_name": machine.display_name,
		"active_power_up_id": active_power_up_id,
		"initial_symbols": initial_symbols,
		"initial_symbol_ids": initial_symbol_ids,
		"symbols": final_symbols,
		"symbol_ids": _symbol_ids(final_symbols),
		"rerolled": rerolled,
		"base_total": base_payout,
		"upgrade_profile": upgrade_profile,
		"luck_upgrade_multiplier": luck_upgrade_multiplier,
		"coin_upgrade_multiplier": coin_upgrade_multiplier,
		"spin_speed_multiplier": spin_speed_multiplier,
		"conditional_modifier_id": conditional_modifier_id,
		"conditional_multiplier": conditional_multiplier,
		"final_surge_multiplier": final_surge_multiplier,
		"manual_multiplier": manual_multiplier,
		"overcharge_roll": overcharge_roll,
		"overcharge_failed": overcharge_failed,
		"non_common_weight_multiplier": non_common_multiplier,
		"effective_weights": effective_weights,
		"gross_payout": gross_payout,
		"siphon_amount": siphon_amount,
		"siphon_source": siphon_source,
		"payout": net_payout,
		"score_deltas": score_deltas,
		"incoming_effects": incoming_resolution.get("details", []),
		"trace": trace,
		"log": _join_trace(trace),
		"_commit": commit_data,
	}
	_pending_spin = result
	var public_result := _copy_outcome(result)
	spin_prepared.emit(public_result)
	return public_result


## Commits a prepared result once. Repeating a previously resolved token
## returns the original outcome with idempotent_replay=true and changes nothing.
func resolve_spin(token: StringName) -> Dictionary:
	if _resolved_spins.has(token):
		var replay := _copy_outcome(_resolved_spins[token])
		replay["idempotent_replay"] = true
		return replay
	if _pending_spin.is_empty() or StringName(_pending_spin.get("token", &"")) != token:
		return _error(&"invalid_spin_token", "The spin token is unknown or no longer pending.")

	var result := _copy_outcome(_pending_spin)
	var contestant := StringName(result.get("contestant", &""))
	var commit_data: Dictionary = result.get("_commit", {})
	for hostile_id in commit_data.get("remove_hostile_ids", []):
		_remove_pending_hostile(contestant, int(hostile_id))
	for power_up_id in commit_data.get("consume_power_up_ids", []):
		_consume_power_up_charge(contestant, StringName(power_up_id))
	var queued_effect_id := StringName(commit_data.get("queue_hostile_effect_id", &""))
	if queued_effect_id != &"":
		_queue_hostile_effect(get_opponent(contestant), contestant, queued_effect_id)

	var score_before := get_scores()
	var requested_deltas: Dictionary = result.get("score_deltas", {})
	var player_delta := maxi(int(requested_deltas.get(String(PLAYER), 0)), 0)
	var boss_delta := maxi(int(requested_deltas.get(String(JUNK_KING), 0)), 0)
	_player_score = clampi(_player_score + player_delta, 0, _config.score_cap)
	_boss_score = clampi(_boss_score + boss_delta, 0, _config.score_cap)
	var score_after := get_scores()
	var actual_deltas := {
		String(PLAYER): int(score_after[String(PLAYER)]) - int(score_before[String(PLAYER)]),
		String(JUNK_KING): int(score_after[String(JUNK_KING)]) - int(score_before[String(JUNK_KING)]),
	}
	_increment_spin_count(contestant, StringName(result.get("phase", REGULATION)))

	_pending_spin.clear()
	_transition_after_resolved_spin(contestant)
	var trace: Array = result.get("trace", [])
	trace.append(
		"14. Committed once: player +$%d, Junk King +$%d; totals are $%d to $%d."
		% [actual_deltas[String(PLAYER)], actual_deltas[String(JUNK_KING)], _player_score, _boss_score]
	)
	result["trace"] = trace
	result["log"] = _join_trace(trace)
	result["resolved"] = true
	result["idempotent_replay"] = false
	result["score_before"] = score_before
	result["score_after"] = score_after
	result["actual_score_deltas"] = actual_deltas
	result["spins_completed"] = get_spin_counts()
	result["state_after"] = _state
	result["state_after_name"] = get_state_name()
	result["battle_complete"] = _state == BattleState.BATTLE_COMPLETE
	result.erase("_commit")
	_resolved_spins[token] = result
	_spin_history.append(result)
	_battle_log.append(_format_result_summary(result))
	var public_result := _copy_outcome(result)
	spin_resolved.emit(public_result)
	if _state == BattleState.BATTLE_COMPLETE:
		battle_completed.emit(get_summary())
	return public_result


## Releases the round-complete presentation lock. During a tied score after
## regulation (or a tied sudden-death pair), this selects one random Junkyard
## machine that both contestants must use for the next sudden-death pair.
func advance_round() -> Dictionary:
	if _state != BattleState.ROUND_COMPLETE or not _pending_spin.is_empty():
		return _error(&"invalid_state", "There is no completed round ready to advance.")
	if _phase == REGULATION and _current_round < _config.regulation_rounds:
		_current_round += 1
		_current_round_machine = _round_schedule[_current_round - 1]
		_set_state(BattleState.PLAYER_TURN)
	else:
		if _player_score != _boss_score:
			return _error(&"not_tied", "Sudden death only begins while the scores are tied.")
		_phase = SUDDEN_DEATH
		_sudden_death_round += 1
		_sudden_death_machine = _config.machines[_rng.randi_range(0, _config.machines.size() - 1)]
		_set_state(BattleState.SUDDEN_DEATH_PLAYER_TURN)
	return {
		"ok": true,
		"state": _state,
		"state_name": get_state_name(),
		"phase": _phase,
		"round": _current_round,
		"sudden_death_round": _sudden_death_round,
		"current_contestant": get_current_contestant(),
		"current_machine": get_current_machine(),
		"current_round_machine_id": get_current_round_machine_id(),
	}


func can_prepare_spin(contestant: StringName) -> bool:
	if not _pending_spin.is_empty():
		return false
	return (
		(contestant == PLAYER and _state in [BattleState.PLAYER_TURN, BattleState.SUDDEN_DEATH_PLAYER_TURN])
		or (contestant == JUNK_KING and _state in [BattleState.BOSS_TURN, BattleState.SUDDEN_DEATH_BOSS_TURN])
	)


func get_boss_ai_active_power_up_id() -> StringName:
	if _phase != REGULATION or get_current_contestant() != JUNK_KING:
		return &""
	var requested_id: StringName = &""
	if _current_round == _config.odds_disruptor_round:
		requested_id = &"odds_disruptor"
	elif _current_round == _config.payout_siphon_round:
		requested_id = &"payout_siphon"
	var definition := _get_loadout_power_up(JUNK_KING, requested_id)
	if definition == null or not _has_power_up_charge(JUNK_KING, definition):
		return &""
	return requested_id


func get_state() -> int:
	return _state


func get_state_name() -> StringName:
	match _state:
		BattleState.IDLE:
			return &"idle"
		BattleState.POWER_UP_SELECTION:
			return &"power_up_selection"
		BattleState.PLAYER_TURN:
			return &"player_turn"
		BattleState.BOSS_TURN:
			return &"boss_turn"
		BattleState.ROUND_COMPLETE:
			return &"round_complete"
		BattleState.SUDDEN_DEATH_PLAYER_TURN:
			return &"sudden_death_player_turn"
		BattleState.SUDDEN_DEATH_BOSS_TURN:
			return &"sudden_death_boss_turn"
		BattleState.BATTLE_COMPLETE:
			return &"battle_complete"
	return &"unknown"


func get_seed() -> int:
	return _seed


func get_current_contestant() -> StringName:
	if _state in [BattleState.PLAYER_TURN, BattleState.SUDDEN_DEATH_PLAYER_TURN]:
		return PLAYER
	if _state in [BattleState.BOSS_TURN, BattleState.SUDDEN_DEATH_BOSS_TURN]:
		return JUNK_KING
	return &""


func get_opponent(contestant: StringName) -> StringName:
	return JUNK_KING if contestant == PLAYER else PLAYER


func get_current_machine() -> MachineDefinition:
	if _config == null:
		return null
	if _phase == SUDDEN_DEATH:
		return _sudden_death_machine
	return _current_round_machine


func get_current_round_machine_id() -> StringName:
	var machine := get_current_machine()
	return machine.machine_id if machine != null else &""


func get_round() -> int:
	return _current_round


func get_sudden_death_round() -> int:
	return _sudden_death_round


func get_scores() -> Dictionary:
	return {
		String(PLAYER): _player_score,
		String(JUNK_KING): _boss_score,
	}


func get_spin_counts() -> Dictionary:
	return {
		"player_regulation": _player_regulation_spins,
		"junk_king_regulation": _boss_regulation_spins,
		"player_sudden_death": _player_sudden_death_spins,
		"junk_king_sudden_death": _boss_sudden_death_spins,
	}


func get_power_up_catalog() -> Array[PowerUpDefinition]:
	var result: Array[PowerUpDefinition] = []
	if _config != null:
		result.assign(_config.power_ups)
	return result


func get_loadout(contestant: StringName) -> Array[PowerUpDefinition]:
	var result: Array[PowerUpDefinition] = []
	if contestant == PLAYER:
		result.assign(_player_loadout)
	elif contestant == JUNK_KING:
		result.assign(_boss_loadout)
	return result


func get_loadout_ids(contestant: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in get_loadout(contestant):
		ids.append(definition.power_up_id)
	return ids


func get_loadout_status(contestant: StringName) -> Array[Dictionary]:
	var statuses: Array[Dictionary] = []
	for definition in get_loadout(contestant):
		statuses.append({
			"definition": definition,
			"power_up_id": definition.power_up_id,
			"is_active": definition.is_active,
			"max_uses": definition.max_uses,
			"uses_remaining": _get_remaining_uses(contestant, definition.power_up_id),
			"available": _has_power_up_charge(contestant, definition),
		})
	return statuses


## Returns a deep copy so UI and tests cannot mutate either contestant's
## battle-owned upgrade snapshot.
func get_upgrade_profile(contestant: StringName) -> Dictionary:
	if contestant == PLAYER:
		return _player_upgrade_profile.duplicate(true)
	if contestant == JUNK_KING:
		return _boss_upgrade_profile.duplicate(true)
	return {}


func get_available_active_power_ups(contestant: StringName) -> Array[PowerUpDefinition]:
	var available: Array[PowerUpDefinition] = []
	for definition in get_loadout(contestant):
		if definition.is_active and _has_power_up_charge(contestant, definition):
			available.append(definition)
	return available


func get_schedule_ids(contestant: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	if contestant != PLAYER and contestant != JUNK_KING:
		return ids
	for machine in _round_schedule:
		ids.append(machine.machine_id)
	return ids


func get_extra_machine_id() -> StringName:
	return _extra_machine.machine_id if _extra_machine != null else &""


func get_pending_spin() -> Dictionary:
	return _copy_outcome(_pending_spin)


func get_spin_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for outcome in _spin_history:
		result.append(_copy_outcome(outcome))
	return result


func get_battle_log() -> Array[String]:
	var result: Array[String] = []
	result.assign(_battle_log)
	return result


func get_winner() -> StringName:
	return _winner


func get_summary() -> Dictionary:
	return {
		"state": _state,
		"state_name": get_state_name(),
		"seed": _seed,
		"phase": _phase,
		"round": _current_round,
		"sudden_death_rounds": _sudden_death_round,
		"winner": _winner,
		"scores": get_scores(),
		"spins_completed": get_spin_counts(),
		"player_loadout": get_loadout_ids(PLAYER),
		"boss_loadout": get_loadout_ids(JUNK_KING),
		"player_schedule": get_schedule_ids(PLAYER),
		"boss_schedule": get_schedule_ids(JUNK_KING),
		"round_schedule": get_schedule_ids(PLAYER),
		"player_upgrades": get_upgrade_profile(PLAYER),
		"boss_upgrades": get_upgrade_profile(JUNK_KING),
		"extra_machine_id": get_extra_machine_id(),
		"battle_log": get_battle_log(),
	}


func _reset_runtime() -> void:
	_state = BattleState.IDLE
	_phase = REGULATION
	_current_round = 1
	_sudden_death_round = 0
	_sudden_death_machine = null
	_extra_machine = null
	_player_loadout.clear()
	_boss_loadout.clear()
	_round_schedule.clear()
	_current_round_machine = null
	_player_upgrade_profile.clear()
	_boss_upgrade_profile.clear()
	_player_remaining_uses.clear()
	_boss_remaining_uses.clear()
	_player_pending_hostiles.clear()
	_boss_pending_hostiles.clear()
	_player_score = 0
	_boss_score = 0
	_player_regulation_spins = 0
	_boss_regulation_spins = 0
	_player_sudden_death_spins = 0
	_boss_sudden_death_spins = 0
	_winner = &""
	_next_spin_id = 0
	_next_hostile_id = 0
	_pending_spin.clear()
	_resolved_spins.clear()
	_spin_history.clear()
	_battle_log.clear()


func _initialize_uses() -> void:
	_player_remaining_uses.clear()
	_boss_remaining_uses.clear()
	for definition in _player_loadout:
		_player_remaining_uses[String(definition.power_up_id)] = definition.max_uses
	for definition in _boss_loadout:
		_boss_remaining_uses[String(definition.power_up_id)] = definition.max_uses


func _build_regulation_schedule() -> void:
	_extra_machine = _config.machines[_rng.randi_range(0, _config.machines.size() - 1)]
	_round_schedule = _make_balanced_schedule()
	_current_round_machine = _round_schedule[0] if not _round_schedule.is_empty() else null


func _make_balanced_schedule() -> Array[MachineDefinition]:
	var schedule: Array[MachineDefinition] = []
	for machine in _config.machines:
		for _copy_index in range(_config.base_machine_appearances):
			schedule.append(machine)
	for _extra_index in range(_config.extra_machine_appearances):
		schedule.append(_extra_machine)
	for index in range(schedule.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := schedule[index]
		schedule[index] = schedule[swap_index]
		schedule[swap_index] = temporary
	return schedule


func _resolve_incoming_hostiles_for_preparation(
	contestant: StringName,
	trace: Array[String],
	commit_data: Dictionary
) -> Dictionary:
	var details: Array[Dictionary] = []
	var combined_weight_multiplier := 1.0
	var siphon: Dictionary = {}
	var pending := _get_pending_hostiles(contestant)
	var shield := _get_loadout_effect(contestant, PowerUpDefinition.EffectKind.INTERFERENCE_SHIELD)
	var shield_available := shield != null and _has_power_up_charge(contestant, shield)
	var shield_used := false
	for record in pending:
		var effect_id := StringName(record.get("effect_id", &""))
		var definition := _config.get_power_up(effect_id)
		if definition == null:
			continue
		if shield_available and not shield_used:
			shield_used = true
			_add_consumption(commit_data, shield.power_up_id)
			_add_hostile_removal(commit_data, int(record.get("hostile_id", -1)))
			details.append({
				"effect_id": effect_id,
				"source": record.get("source", &""),
				"cancelled_by": shield.power_up_id,
			})
			continue
		match definition.effect_kind:
			PowerUpDefinition.EffectKind.ODDS_DISRUPTOR:
				combined_weight_multiplier *= definition.weight_multiplier
				_add_hostile_removal(commit_data, int(record.get("hostile_id", -1)))
				details.append({
					"effect_id": effect_id,
					"source": record.get("source", &""),
					"weight_multiplier": definition.weight_multiplier,
				})
			PowerUpDefinition.EffectKind.PAYOUT_SIPHON:
				if siphon.is_empty():
					siphon = record
				details.append({
					"effect_id": effect_id,
					"source": record.get("source", &""),
					"transfer_fraction": definition.transfer_fraction,
				})
	if details.is_empty():
		trace.append("1. No incoming hostile effect applied.")
	else:
		var detail_messages: Array[String] = []
		for detail in details:
			if detail.has("cancelled_by"):
				detail_messages.append(
					"%s cancelled by Interference Shield"
					% _display_name(StringName(detail.get("effect_id", &"")))
				)
			elif detail.has("weight_multiplier"):
				detail_messages.append(
					"Odds Disruptor applied x%.2f non-common weights"
					% float(detail.get("weight_multiplier", 1.0))
				)
			else:
				detail_messages.append("Payout Siphon armed for the next positive payout")
		trace.append("1. Incoming effects: %s." % "; ".join(detail_messages))
	return {
		"weight_multiplier": combined_weight_multiplier,
		"siphon": siphon,
		"details": details,
	}


func _validate_manual_activation(
	contestant: StringName,
	definition: PowerUpDefinition,
	requested_id: StringName
) -> Dictionary:
	if definition == null:
		return _error(&"power_up_not_equipped", "%s is not equipped." % requested_id)
	if not definition.is_active:
		return _error(&"power_up_not_active", "%s activates automatically." % definition.display_name)
	if not _has_power_up_charge(contestant, definition):
		return _error(&"power_up_depleted", "%s has no uses remaining." % definition.display_name)
	match definition.effect_kind:
		PowerUpDefinition.EffectKind.PAYOUT_DOUBLER, PowerUpDefinition.EffectKind.OVERCHARGE, PowerUpDefinition.EffectKind.ODDS_DISRUPTOR, PowerUpDefinition.EffectKind.PAYOUT_SIPHON:
			return {}
	return _error(&"unsupported_active_power_up", "%s cannot be armed manually." % definition.display_name)


func _transition_after_resolved_spin(contestant: StringName) -> void:
	if _phase == REGULATION:
		if contestant == PLAYER:
			_set_state(BattleState.BOSS_TURN)
		elif _boss_regulation_spins >= _config.regulation_rounds:
			if _player_score == _boss_score:
				_set_state(BattleState.ROUND_COMPLETE)
			else:
				_complete_battle()
		else:
			_set_state(BattleState.ROUND_COMPLETE)
	else:
		if contestant == PLAYER:
			_set_state(BattleState.SUDDEN_DEATH_BOSS_TURN)
		elif _player_score == _boss_score:
			_set_state(BattleState.ROUND_COMPLETE)
		else:
			_complete_battle()


func _complete_battle() -> void:
	_winner = PLAYER if _player_score > _boss_score else JUNK_KING
	_set_state(BattleState.BATTLE_COMPLETE)


func _increment_spin_count(contestant: StringName, phase: StringName) -> void:
	if phase == REGULATION:
		if contestant == PLAYER:
			_player_regulation_spins = mini(_player_regulation_spins + 1, _config.regulation_rounds)
		else:
			_boss_regulation_spins = mini(_boss_regulation_spins + 1, _config.regulation_rounds)
	elif contestant == PLAYER:
		_player_sudden_death_spins += 1
	else:
		_boss_sudden_death_spins += 1


func _queue_hostile_effect(target: StringName, source: StringName, effect_id: StringName) -> void:
	_next_hostile_id += 1
	var record := {
		"hostile_id": _next_hostile_id,
		"effect_id": effect_id,
		"source": source,
	}
	if target == PLAYER:
		_player_pending_hostiles.append(record)
	else:
		_boss_pending_hostiles.append(record)


func _remove_pending_hostile(contestant: StringName, hostile_id: int) -> void:
	var pending := _get_pending_hostiles(contestant)
	for index in range(pending.size() - 1, -1, -1):
		if int(pending[index].get("hostile_id", -1)) == hostile_id:
			pending.remove_at(index)
			return


func _get_pending_hostiles(contestant: StringName) -> Array[Dictionary]:
	return _player_pending_hostiles if contestant == PLAYER else _boss_pending_hostiles


func _add_consumption(commit_data: Dictionary, power_up_id: StringName) -> void:
	var consumptions: Array = commit_data.get("consume_power_up_ids", [])
	if power_up_id not in consumptions:
		consumptions.append(power_up_id)
	commit_data["consume_power_up_ids"] = consumptions


func _add_hostile_removal(commit_data: Dictionary, hostile_id: int) -> void:
	if hostile_id < 0:
		return
	var removals: Array = commit_data.get("remove_hostile_ids", [])
	if hostile_id not in removals:
		removals.append(hostile_id)
	commit_data["remove_hostile_ids"] = removals


func _consume_power_up_charge(contestant: StringName, power_up_id: StringName) -> void:
	var definition := _get_loadout_power_up(contestant, power_up_id)
	if definition == null or definition.max_uses < 0:
		return
	var uses := _player_remaining_uses if contestant == PLAYER else _boss_remaining_uses
	var key := String(power_up_id)
	uses[key] = maxi(int(uses.get(key, 0)) - 1, 0)


func _has_power_up_charge(contestant: StringName, definition: PowerUpDefinition) -> bool:
	if definition == null:
		return false
	return definition.max_uses < 0 or _get_remaining_uses(contestant, definition.power_up_id) > 0


func _get_remaining_uses(contestant: StringName, power_up_id: StringName) -> int:
	var definition := _get_loadout_power_up(contestant, power_up_id)
	if definition == null:
		return 0
	if definition.max_uses < 0:
		return -1
	var uses := _player_remaining_uses if contestant == PLAYER else _boss_remaining_uses
	return maxi(int(uses.get(String(power_up_id), definition.max_uses)), 0)


func _get_loadout_power_up(contestant: StringName, power_up_id: StringName) -> PowerUpDefinition:
	if power_up_id == &"":
		return null
	for definition in get_loadout(contestant):
		if definition.power_up_id == power_up_id:
			return definition
	return null


func _get_loadout_effect(contestant: StringName, effect_kind: int) -> PowerUpDefinition:
	for definition in get_loadout(contestant):
		if definition.effect_kind == effect_kind:
			return definition
	return null


func _symbols_from_outcome(outcome: Dictionary) -> Array[SlotSymbol]:
	var result: Array[SlotSymbol] = []
	var symbols: Array = outcome.get("symbols", [])
	for symbol in symbols:
		if symbol is SlotSymbol:
			result.append(symbol as SlotSymbol)
	return result


func _symbol_ids(symbols: Array[SlotSymbol]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for symbol in symbols:
		ids.append(symbol.symbol_id)
	return ids


func _all_lowest_value_symbols(machine: MachineDefinition, symbols: Array[SlotSymbol]) -> bool:
	if machine == null or machine.symbols.is_empty() or symbols.size() != Economy.REEL_COUNT:
		return false
	var lowest := machine.symbols[0]
	for symbol in machine.symbols:
		if symbol.payout < lowest.payout:
			lowest = symbol
	for symbol in symbols:
		if symbol.symbol_id != lowest.symbol_id:
			return false
	return true


func _all_symbol_ids_match(symbols: Array[SlotSymbol]) -> bool:
	if symbols.size() != Economy.REEL_COUNT:
		return false
	return symbols[0].symbol_id == symbols[1].symbol_id and symbols[1].symbol_id == symbols[2].symbol_id


func _all_symbol_ids_differ(symbols: Array[SlotSymbol]) -> bool:
	if symbols.size() != Economy.REEL_COUNT:
		return false
	return (
		symbols[0].symbol_id != symbols[1].symbol_id
		and symbols[0].symbol_id != symbols[2].symbol_id
		and symbols[1].symbol_id != symbols[2].symbol_id
	)


func _format_symbol_ids(symbol_ids: Array[StringName]) -> String:
	var labels: Array[String] = []
	for symbol_id in symbol_ids:
		labels.append(String(symbol_id))
	return " / ".join(labels)


func _display_name(power_up_id: StringName) -> String:
	var definition := _config.get_power_up(power_up_id)
	return definition.display_name if definition != null else String(power_up_id)


func _get_profile_level(profile: Dictionary, upgrade_id: StringName) -> int:
	var levels: Dictionary = profile.get("levels", {})
	return maxi(int(levels.get(String(upgrade_id), 0)), 0)


func _get_profile_multiplier(profile: Dictionary, upgrade_id: StringName) -> float:
	var multipliers: Dictionary = profile.get("multipliers", {})
	return maxf(float(multipliers.get(String(upgrade_id), 1.0)), 0.0)


func _format_result_summary(result: Dictionary) -> String:
	var phase_label := "Round %d" % int(result.get("round", 0))
	if StringName(result.get("phase", REGULATION)) == SUDDEN_DEATH:
		phase_label = "Sudden Death %d" % int(result.get("sudden_death_round", 0))
	return "%s: %s used %s, rolled %s, and added $%d (totals: Player $%d, Junk King $%d)." % [
		phase_label,
		String(result.get("contestant", &"")),
		String(result.get("machine_name", "")),
		_format_symbol_ids(_string_names_from_variant(result.get("symbol_ids", []))),
		int(result.get("payout", 0)),
		_player_score,
		_boss_score,
	]


func _string_names_from_variant(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if values is Array:
		for value in values:
			result.append(StringName(value))
	return result


func _join_trace(trace: Array) -> String:
	var lines := PackedStringArray()
	for entry in trace:
		lines.append(String(entry))
	return "\n".join(lines)


func _copy_outcome(outcome: Dictionary) -> Dictionary:
	return outcome.duplicate(true) if not outcome.is_empty() else {}


func _set_state(next_state: int) -> void:
	if _state == next_state:
		return
	var previous := _state
	_state = next_state
	state_changed.emit(previous, _state)


func _error(code: StringName, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message,
		"state": _state,
		"state_name": get_state_name(),
	}


func _error_with_token(code: StringName, message: String, token: StringName) -> Dictionary:
	var result := _error(code, message)
	result["token"] = token
	return result
