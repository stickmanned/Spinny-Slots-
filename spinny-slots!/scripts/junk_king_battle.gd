class_name JunkKingBattle
extends Control

signal return_to_junkyard_requested
signal metropolis_requested

enum PresentationState {
	SELECTING_POWER_UPS,
	READY_FOR_PLAYER,
	PRESENTING_SPIN,
	PRESENTING_ROUND,
	FINAL_TOTALS,
	RESULT_DIALOGUE,
	RESULT_RESOLVED,
	EXITING,
}

const BATTLE_CONFIG: JunkKingBattleConfig = preload(
	"res://resources/battles/junk_king_battle.tres"
)
const JUNKYARD_PROGRESSION: JunkyardProgressionConfig = preload(
	"res://resources/story/junkyard_progression.tres"
)
const VICTORY_DIALOGUE: DialogueData = preload(
	"res://resources/dialogue/junk_king_victory.tres"
)
const DEFEAT_DIALOGUE: DialogueData = preload(
	"res://resources/dialogue/junk_king_defeat.tres"
)

const MACHINE_REVEAL_DURATION := 0.18
const BOSS_THINK_DURATION := 0.72
const ROUND_CHANGE_DURATION := 0.58
const OUTCOME_REVEAL_DURATION := 0.24
const WALLET_COUNT_DURATION := 0.62
const REDUCED_MOTION_DELAY := 0.08
const MIN_REEL_DURATION := 0.3

## Battle-log palette. Each speaker and value class keeps one colour so a glance
## at the log is enough to tell who scored and which power-up caused it.
const LOG_COLOR_PLAYER := "4fc3ff"
const LOG_COLOR_BOSS := "ff8a5c"
const LOG_COLOR_POWER_UP := "ffd24a"
const LOG_COLOR_GAIN := "7de58a"
const LOG_COLOR_MUTED := "8ca3bc"
const LOG_COLOR_TOTALS := "c7d6e6"
const MAX_LOG_ENTRIES := 6
const LOG_SYMBOL_ICON_SIZE := 30

@export var seed_override: int = 0

@onready var round_label: Label = %RoundLabel
@onready var turn_label: Label = %TurnLabel
@onready var active_machine_label: Label = %ActiveMachineLabel
@onready var active_effect_label: Label = %ActiveEffectLabel
@onready var battle_log: RichTextLabel = %BattleLog
@onready var spin_button: Button = %SpinButton
@onready var footer_label: Label = %FooterLabel
@onready var boss_panel: BattleContestantPanel = %BossPanel
@onready var player_panel: BattleContestantPanel = %PlayerPanel
@onready var selection_layer: CanvasLayer = %SelectionLayer
@onready var selection_root: Control = %SelectionRoot
@onready var selection_panel: PowerUpSelectionPanel = %PowerUpSelectionPanel
@onready var outcome_layer: CanvasLayer = %OutcomeLayer
@onready var outcome_panel: PanelContainer = %OutcomePanel
@onready var outcome_title: Label = %OutcomeTitle
@onready var outcome_totals: Label = %OutcomeTotals
@onready var outcome_message: Label = %OutcomeMessage
@onready var primary_outcome_button: Button = %PrimaryOutcomeButton
@onready var secondary_outcome_button: Button = %SecondaryOutcomeButton
@onready var dialogue_box := %DialogueBox

var _engine := JunkKingBattleEngine.new()
var _presentation_state := PresentationState.SELECTING_POWER_UPS
var _armed_player_power_up_id: StringName = &""
var _resolution_token := ""
var _result_winner: StringName = &""
var _outcome_mode: StringName = &""
var _sequence_generation := 0
var _navigation_emitted := false
var _permanent_resolution_attempted := false
var _log_lines: Array[String] = []
var _outcome_tween: Tween


func _ready() -> void:
	spin_button.pressed.connect(_on_spin_pressed)
	selection_panel.selection_confirmed.connect(_on_selection_confirmed)
	player_panel.power_up_requested.connect(_on_player_power_up_requested)
	player_panel.power_up_focused.connect(_on_power_up_focused)
	boss_panel.power_up_focused.connect(_on_power_up_focused)
	primary_outcome_button.pressed.connect(_on_primary_outcome_pressed)
	secondary_outcome_button.pressed.connect(_on_secondary_outcome_pressed)
	dialogue_box.finished.connect(_on_result_dialogue_finished)
	ButtonHover.attach(spin_button)
	ButtonHover.attach(primary_outcome_button)
	ButtonHover.attach(secondary_outcome_button)
	_begin_attempt()


func _exit_tree() -> void:
	_sequence_generation += 1
	if _outcome_tween != null and _outcome_tween.is_valid():
		_outcome_tween.kill()
	AudioFx.stop_spin()


func get_engine() -> JunkKingBattleEngine:
	return _engine


func get_armed_player_power_up_id() -> StringName:
	return _armed_player_power_up_id


func is_input_locked() -> bool:
	return _presentation_state != PresentationState.READY_FOR_PLAYER


func _begin_attempt() -> void:
	_presentation_state = PresentationState.SELECTING_POWER_UPS
	_navigation_emitted = false
	_permanent_resolution_attempted = false
	_result_winner = &""
	_outcome_mode = &""
	_armed_player_power_up_id = &""
	_resolution_token = ""
	_log_lines.clear()
	selection_layer.visible = true
	selection_root.modulate.a = 1.0
	outcome_layer.visible = false
	spin_button.disabled = true
	boss_panel.configure_identity(
		"JUNK KING", JUNKYARD_PROGRESSION.junk_king_portrait, "KING"
	)
	player_panel.configure_identity("YOU", null, "YOU")
	boss_panel.set_total(0, false)
	player_panel.set_total(0, false)
	boss_panel.set_result("Waiting for the challenge...")
	player_panel.set_result("Choose three power-ups to begin.")
	boss_panel.configure_machine(null)
	player_panel.configure_machine(null)
	boss_panel.set_turn_active(false)
	player_panel.set_turn_active(false)

	var seed_value := seed_override
	if seed_value == 0:
		seed_value = int(Time.get_ticks_usec() & 0x7fffffff)
	var configured := _engine.configure(BATTLE_CONFIG, seed_value, GameState.upgrade_levels)
	if not bool(configured.get("ok", false)):
		_show_setup_error(_error_message(configured))
		return

	player_panel.set_upgrade_profile(_engine.get_upgrade_profile(JunkKingBattleEngine.PLAYER), false)
	boss_panel.set_upgrade_profile(_engine.get_upgrade_profile(JunkKingBattleEngine.JUNK_KING), true)
	var boss_loadout := _engine.get_loadout(JunkKingBattleEngine.JUNK_KING)
	boss_panel.set_power_ups(boss_loadout, false)
	_refresh_power_up_states()
	selection_panel.configure(_engine.get_power_up_catalog())
	round_label.text = "Round 1 / %d" % BATTLE_CONFIG.regulation_rounds
	turn_label.text = "CHOOSE YOUR POWER-UPS"
	active_machine_label.text = "Round Machine: Waiting..."
	footer_label.text = "Spins  You 0 / %d   ·   Junk King 0 / %d" % [
		BATTLE_CONFIG.regulation_rounds,
		BATTLE_CONFIG.regulation_rounds,
	]
	active_effect_label.text = "Select exactly three unique power-ups, then review your loadout."
	_append_log(
		"%s\n%s"
		% [
			_tint("JUNK KING EQUIPPED", LOG_COLOR_BOSS),
			_tint(_format_loadout(boss_loadout), LOG_COLOR_POWER_UP),
		]
	)
	_append_log(_tint("Choose three different power-ups to begin.", LOG_COLOR_MUTED))


func _show_setup_error(message_text: String) -> void:
	selection_layer.visible = false
	turn_label.text = "BATTLE UNAVAILABLE"
	active_effect_label.text = message_text
	_append_log("Battle setup failed: %s" % message_text)
	outcome_title.text = "BATTLE UNAVAILABLE"
	outcome_totals.text = "No battle state was changed."
	_set_outcome_message(message_text)
	primary_outcome_button.text = "RETURN TO JUNKYARD"
	primary_outcome_button.disabled = false
	secondary_outcome_button.visible = false
	_outcome_mode = &"setup_error"
	outcome_layer.visible = true


func _on_selection_confirmed(power_up_ids: Array[StringName]) -> void:
	if _presentation_state != PresentationState.SELECTING_POWER_UPS:
		return
	var selection := _engine.select_player_power_ups(power_up_ids)
	if not bool(selection.get("ok", false)):
		selection_panel.confirm_button.disabled = false
		active_effect_label.text = _error_message(selection)
		return
	var started := _engine.confirm_player_loadout()
	if not bool(started.get("ok", false)):
		selection_panel.confirm_button.disabled = false
		active_effect_label.text = _error_message(started)
		return

	_resolution_token = GameState.create_junk_king_resolution_token()
	player_panel.set_power_ups(_engine.get_loadout(JunkKingBattleEngine.PLAYER), true)
	_refresh_power_up_states()
	_append_log(
		"%s\n%s"
		% [
			_tint("YOU EQUIPPED", LOG_COLOR_PLAYER),
			_tint(
				_format_loadout(_engine.get_loadout(JunkKingBattleEngine.PLAYER)),
				LOG_COLOR_POWER_UP
			),
		]
	)
	await _hide_selection()
	if not is_inside_tree():
		return
	await _ready_player_turn()


func _hide_selection() -> void:
	if GameState.reduced_motion:
		selection_layer.visible = false
		return
	var generation := _sequence_generation
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(selection_root, "modulate:a", 0.0, MACHINE_REVEAL_DURATION)
	await _wait_safely(MACHINE_REVEAL_DURATION, generation)
	if generation == _sequence_generation and is_inside_tree():
		selection_layer.visible = false


func _ready_player_turn() -> void:
	if not is_inside_tree() or _engine.get_current_contestant() != JunkKingBattleEngine.PLAYER:
		return
	_presentation_state = PresentationState.PRESENTING_ROUND
	_armed_player_power_up_id = &""
	_refresh_status_ui()
	turn_label.text = "YOUR TURN"
	var machine := _engine.get_current_machine()
	await _present_machine(player_panel, machine)
	if not is_inside_tree():
		return
	# The machine is round state, so both panels show the same cabinet before
	# either contestant spins. Outcomes remain independently prepared later.
	boss_panel.configure_machine(machine)
	_presentation_state = PresentationState.READY_FOR_PLAYER
	active_effect_label.text = "Choose at most one active power-up, then spin."
	_refresh_status_ui()


func _on_player_power_up_requested(power_up_id: StringName) -> void:
	if _presentation_state != PresentationState.READY_FOR_PLAYER:
		return
	var available := false
	var display_name := String(power_up_id)
	for status in _engine.get_loadout_status(JunkKingBattleEngine.PLAYER):
		if StringName(status.get("power_up_id", &"")) != power_up_id:
			continue
		var definition: PowerUpDefinition = status.get("definition")
		available = bool(status.get("available", false)) and definition != null and definition.is_active
		if definition != null:
			display_name = definition.display_name
		break
	if not available:
		active_effect_label.text = "%s cannot be armed on this turn." % display_name
		return
	if _armed_player_power_up_id == power_up_id:
		_armed_player_power_up_id = &""
		active_effect_label.text = "No active power-up armed."
	else:
		_armed_player_power_up_id = power_up_id
		active_effect_label.text = "%s armed for this spin. Choose it again to cancel." % display_name
	_refresh_power_up_states()


func _on_power_up_focused(description: String) -> void:
	if _presentation_state in [PresentationState.READY_FOR_PLAYER, PresentationState.PRESENTING_ROUND]:
		active_effect_label.text = description


func _on_spin_pressed() -> void:
	if _presentation_state != PresentationState.READY_FOR_PLAYER:
		return
	if not _engine.can_prepare_spin(JunkKingBattleEngine.PLAYER):
		return
	_presentation_state = PresentationState.PRESENTING_SPIN
	_refresh_status_ui()
	await _perform_turn(JunkKingBattleEngine.PLAYER, _armed_player_power_up_id)


func _perform_turn(contestant: StringName, active_power_up_id: StringName = &"") -> void:
	if not is_inside_tree():
		return
	var prepared := (
		_engine.prepare_player_spin(active_power_up_id)
		if contestant == JunkKingBattleEngine.PLAYER
		else _engine.prepare_boss_spin()
	)
	if not bool(prepared.get("ok", false)):
		_append_log("Spin rejected: %s" % _error_message(prepared))
		if contestant == JunkKingBattleEngine.PLAYER:
			_presentation_state = PresentationState.READY_FOR_PLAYER
		_refresh_status_ui()
		return

	var generation := _sequence_generation
	var panel := player_panel if contestant == JunkKingBattleEngine.PLAYER else boss_panel
	var contestant_name := "YOU" if contestant == JunkKingBattleEngine.PLAYER else "JUNK KING"
	var machine: MachineDefinition = prepared.get("machine")
	if panel.get_configured_machine() != machine:
		await _present_machine(panel, machine)
		if generation != _sequence_generation or not is_inside_tree():
			return
	turn_label.text = "%s SPINS" % contestant_name
	active_machine_label.text = "Round Machine: %s · BOTH CONTESTANTS" % String(
		prepared.get("machine_name", "Unknown")
	)
	active_effect_label.text = _format_prepared_effect(prepared)
	panel.set_result("Spinning...")
	var spin_speed_multiplier := maxf(float(prepared.get("spin_speed_multiplier", 1.0)), 0.01)
	var total_duration := (
		REDUCED_MOTION_DELAY
		if GameState.reduced_motion
		else AudioFx.get_spin_duration_for_multiplier(spin_speed_multiplier)
	)
	var blink_duration := 0.0 if GameState.reduced_motion else panel.get_reel_blink_duration()
	var reel_duration := (
		REDUCED_MOTION_DELAY
		if GameState.reduced_motion
		else maxf(total_duration - blink_duration, MIN_REEL_DURATION)
	)
	panel.play_spin(prepared, reel_duration, GameState.reduced_motion)
	AudioFx.play_spin(spin_speed_multiplier)
	await _wait_safely(total_duration, generation)
	AudioFx.stop_spin()
	if generation != _sequence_generation or not is_inside_tree():
		return

	var token := StringName(prepared.get("token", &""))
	var resolved := _engine.resolve_spin(token)
	if not bool(resolved.get("ok", false)):
		_append_log("Result commit failed: %s" % _error_message(resolved))
		return
	if bool(resolved.get("idempotent_replay", false)):
		push_warning("Junk King presentation attempted to resolve a spin more than once.")
		return

	if contestant == JunkKingBattleEngine.PLAYER:
		_armed_player_power_up_id = &""
	_update_after_resolved_spin(panel, resolved)
	await _continue_after_spin()


func _update_after_resolved_spin(panel: BattleContestantPanel, outcome: Dictionary) -> void:
	var payout := maxi(int(outcome.get("payout", 0)), 0)
	var siphon_amount := maxi(int(outcome.get("siphon_amount", 0)), 0)
	var result_text := "+$%d" % payout
	if siphon_amount > 0:
		result_text += "  ($%d siphoned)" % siphon_amount
	panel.set_result("%s | %s" % [_format_symbol_ids(outcome.get("symbol_ids", [])), result_text])
	active_effect_label.text = _format_resolved_effect(outcome)
	var scores := _engine.get_scores()
	player_panel.set_total(int(scores.get(String(JunkKingBattleEngine.PLAYER), 0)))
	boss_panel.set_total(int(scores.get(String(JunkKingBattleEngine.JUNK_KING), 0)))
	_append_log(_format_result_log(outcome))
	_refresh_status_ui()


func _continue_after_spin() -> void:
	match _engine.get_state():
		JunkKingBattleEngine.BattleState.BOSS_TURN, JunkKingBattleEngine.BattleState.SUDDEN_DEATH_BOSS_TURN:
			await _run_boss_turn()
		JunkKingBattleEngine.BattleState.ROUND_COMPLETE:
			await _present_round_complete()
		JunkKingBattleEngine.BattleState.BATTLE_COMPLETE:
			await _show_final_totals()
		_:
			_append_log("Battle paused in unexpected state: %s." % _engine.get_state_name())


func _run_boss_turn() -> void:
	if not is_inside_tree():
		return
	_presentation_state = PresentationState.PRESENTING_SPIN
	_refresh_status_ui()
	turn_label.text = "JUNK KING'S TURN"
	var machine := _engine.get_current_machine()
	await _present_machine(boss_panel, machine)
	if not is_inside_tree():
		return
	var boss_active_id := _engine.get_boss_ai_active_power_up_id()
	if boss_active_id != &"":
		active_effect_label.text = "Junk King prepares %s." % _power_up_name(boss_active_id)
	else:
		active_effect_label.text = "The Junk King studies the reels..."
	var generation := _sequence_generation
	await _wait_safely(
		REDUCED_MOTION_DELAY if GameState.reduced_motion else BOSS_THINK_DURATION,
		generation
	)
	if generation != _sequence_generation or not is_inside_tree():
		return
	await _perform_turn(JunkKingBattleEngine.JUNK_KING)


func _present_round_complete() -> void:
	if not is_inside_tree():
		return
	_presentation_state = PresentationState.PRESENTING_ROUND
	_refresh_status_ui()
	var is_regulation_end := (
		_engine.get_round() >= BATTLE_CONFIG.regulation_rounds
		and _engine.get_sudden_death_round() == 0
	)
	var scores := _engine.get_scores()
	var tied := int(scores.get("player", 0)) == int(scores.get("junk_king", 0))
	if is_regulation_end and tied:
		turn_label.text = "TIE - SUDDEN DEATH"
		active_effect_label.text = "Each contestant receives one spin on the same random machine."
		_append_log("Regulation ended in a tie. A paired sudden-death round begins.")
	elif _engine.get_sudden_death_round() > 0 and tied:
		turn_label.text = "STILL TIED"
		active_effect_label.text = "Another paired sudden-death round will begin."
		_append_log("Sudden death remains tied. Selecting a new shared machine.")
	else:
		turn_label.text = "ROUND %d COMPLETE" % _engine.get_round()
		active_effect_label.text = "Both results are committed. Preparing the next round."
	var generation := _sequence_generation
	await _wait_safely(
		REDUCED_MOTION_DELAY if GameState.reduced_motion else ROUND_CHANGE_DURATION,
		generation
	)
	if generation != _sequence_generation or not is_inside_tree():
		return
	var advanced := _engine.advance_round()
	if not bool(advanced.get("ok", false)):
		_append_log("Round transition failed: %s" % _error_message(advanced))
		return
	if StringName(advanced.get("phase", &"")) == JunkKingBattleEngine.SUDDEN_DEATH:
		_append_log(
			"Sudden death %d uses %s for both contestants."
			% [
				int(advanced.get("sudden_death_round", 0)),
				String((advanced.get("current_machine") as MachineDefinition).display_name),
			]
		)
	await _ready_player_turn()


func _present_machine(panel: BattleContestantPanel, machine: MachineDefinition) -> void:
	if machine == null:
		return
	active_machine_label.text = "Round Machine: %s · BOTH CONTESTANTS" % machine.display_name
	if GameState.reduced_motion:
		panel.configure_machine(machine)
		return
	var generation := _sequence_generation
	var fade_out := create_tween()
	fade_out.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade_out.tween_property(panel, "modulate:a", 0.42, MACHINE_REVEAL_DURATION * 0.45)
	await _wait_safely(MACHINE_REVEAL_DURATION * 0.45, generation)
	if generation != _sequence_generation or not is_inside_tree():
		return
	panel.configure_machine(machine)
	var fade_in := create_tween()
	fade_in.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_in.tween_property(panel, "modulate:a", 1.0, MACHINE_REVEAL_DURATION * 0.55)
	await _wait_safely(MACHINE_REVEAL_DURATION * 0.55, generation)


func _refresh_status_ui() -> void:
	var counts := _engine.get_spin_counts()
	var player_regulation := int(counts.get("player_regulation", 0))
	var boss_regulation := int(counts.get("junk_king_regulation", 0))
	var player_sudden := int(counts.get("player_sudden_death", 0))
	var boss_sudden := int(counts.get("junk_king_sudden_death", 0))
	if _engine.get_sudden_death_round() > 0:
		round_label.text = "Sudden Death %d" % _engine.get_sudden_death_round()
		footer_label.text = (
			"Spins  You %d / %d   ·   Junk King %d / %d   ·   Sudden death %d / %d"
			% [
				player_regulation,
				BATTLE_CONFIG.regulation_rounds,
				boss_regulation,
				BATTLE_CONFIG.regulation_rounds,
				player_sudden,
				boss_sudden,
			]
		)
	else:
		round_label.text = "Round %d / %d" % [
			clampi(_engine.get_round(), 1, BATTLE_CONFIG.regulation_rounds),
			BATTLE_CONFIG.regulation_rounds,
		]
		footer_label.text = "Spins  You %d / %d   ·   Junk King %d / %d" % [
			player_regulation,
			BATTLE_CONFIG.regulation_rounds,
			boss_regulation,
			BATTLE_CONFIG.regulation_rounds,
		]
	var player_turn := _engine.get_current_contestant() == JunkKingBattleEngine.PLAYER
	var boss_turn := _engine.get_current_contestant() == JunkKingBattleEngine.JUNK_KING
	player_panel.set_turn_active(player_turn)
	boss_panel.set_turn_active(boss_turn)
	spin_button.disabled = not (
		_presentation_state == PresentationState.READY_FOR_PLAYER
		and _engine.can_prepare_spin(JunkKingBattleEngine.PLAYER)
	)
	_refresh_power_up_states()


func _refresh_power_up_states() -> void:
	player_panel.set_power_up_states(
		_make_power_up_state_map(
			JunkKingBattleEngine.PLAYER,
			_presentation_state == PresentationState.READY_FOR_PLAYER
		)
	)
	boss_panel.set_power_up_states(_make_power_up_state_map(JunkKingBattleEngine.JUNK_KING, false))


func _make_power_up_state_map(contestant: StringName, allow_activation: bool) -> Dictionary:
	var states: Dictionary = {}
	for status in _engine.get_loadout_status(contestant):
		var power_up_id := StringName(status.get("power_up_id", &""))
		states[power_up_id] = {
			"uses_remaining": int(status.get("uses_remaining", 0)),
			"armed": contestant == JunkKingBattleEngine.PLAYER and power_up_id == _armed_player_power_up_id,
			"can_activate": (
				allow_activation
				and bool(status.get("is_active", false))
				and bool(status.get("available", false))
			),
		}
	return states


func _show_final_totals() -> void:
	if _presentation_state == PresentationState.FINAL_TOTALS:
		return
	_presentation_state = PresentationState.FINAL_TOTALS
	_refresh_status_ui()
	_result_winner = _engine.get_winner()
	var scores := _engine.get_scores()
	outcome_title.text = "FINAL AMOUNTS"
	outcome_totals.text = "YOU: $%d\nJUNK KING: $%d" % [
		int(scores.get(String(JunkKingBattleEngine.PLAYER), 0)),
		int(scores.get(String(JunkKingBattleEngine.JUNK_KING), 0)),
	]
	_set_outcome_message("Both contestants completed the 10 spins.")
	if _engine.get_sudden_death_round() > 0:
		_set_outcome_message(
			"Both contestants completed the 10 spins and %d paired sudden-death round%s."
			% [
				_engine.get_sudden_death_round(),
				"" if _engine.get_sudden_death_round() == 1 else "s",
			]
		)
	primary_outcome_button.text = "VIEW RESULT"
	primary_outcome_button.disabled = false
	secondary_outcome_button.visible = false
	_outcome_mode = &"final_totals"
	await _reveal_outcome_panel()


func _reveal_outcome_panel() -> void:
	outcome_layer.visible = true
	outcome_panel.pivot_offset = outcome_panel.size * 0.5
	if GameState.reduced_motion:
		outcome_panel.modulate.a = 1.0
		outcome_panel.scale = Vector2.ONE
		return
	outcome_panel.modulate.a = 0.0
	outcome_panel.scale = Vector2(0.94, 0.94)
	_outcome_tween = create_tween()
	_outcome_tween.set_parallel(true)
	_outcome_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_outcome_tween.tween_property(outcome_panel, "modulate:a", 1.0, OUTCOME_REVEAL_DURATION)
	_outcome_tween.tween_property(outcome_panel, "scale", Vector2.ONE, OUTCOME_REVEAL_DURATION)
	var generation := _sequence_generation
	await _wait_safely(OUTCOME_REVEAL_DURATION, generation)


func _on_primary_outcome_pressed() -> void:
	match _outcome_mode:
		&"final_totals":
			primary_outcome_button.disabled = true
			outcome_layer.visible = false
			_begin_result_dialogue()
		&"victory_unlock":
			_request_navigation(true)
		&"defeat_wallet", &"setup_error":
			_request_navigation(false)


func _on_secondary_outcome_pressed() -> void:
	if _outcome_mode == &"victory_unlock":
		_request_navigation(false)


func _begin_result_dialogue() -> void:
	if _presentation_state != PresentationState.FINAL_TOTALS:
		return
	_presentation_state = PresentationState.RESULT_DIALOGUE
	dialogue_box.use_phone_call_layout("JUNK KING", JUNKYARD_PROGRESSION.junk_king_portrait)
	dialogue_box.set_input_debounce(0.16)
	dialogue_box.chars_per_second = 120.0 if GameState.reduced_motion else 32.0
	var dialogue := VICTORY_DIALOGUE if _result_winner == JunkKingBattleEngine.PLAYER else DEFEAT_DIALOGUE
	dialogue_box.play(dialogue.lines)


func _on_result_dialogue_finished() -> void:
	if _presentation_state != PresentationState.RESULT_DIALOGUE:
		return
	_presentation_state = PresentationState.RESULT_RESOLVED
	dialogue_box.fade_out(0.0 if GameState.reduced_motion else 0.16)
	var generation := _sequence_generation
	await _wait_safely(REDUCED_MOTION_DELAY if GameState.reduced_motion else 0.16, generation)
	if generation != _sequence_generation or not is_inside_tree():
		return
	if _result_winner == JunkKingBattleEngine.PLAYER:
		await _resolve_victory()
	else:
		await _resolve_defeat()


func _resolve_victory() -> void:
	if _permanent_resolution_attempted:
		return
	_permanent_resolution_attempted = true
	var scores := _engine.get_scores()
	var boss_score := maxi(int(scores.get(String(JunkKingBattleEngine.JUNK_KING), 0)), 0)
	var wallet_before := GameState.money
	var applied := GameState.resolve_junk_king_victory(_resolution_token, boss_score)
	if applied:
		AudioFx.play_coin_drop()
	if not SaveManager.flush():
		push_error("Junk King victory resolved in memory, but the save could not be written.")
	outcome_title.text = "METROPOLIS UNLOCKED"
	outcome_totals.text = "JUNK KING'S WINNINGS: $%d\nWALLET: $%d -> $%d" % [
		boss_score,
		wallet_before,
		GameState.money,
	]
	_set_outcome_message("Congratulations, you've unlocked Metropolis!")
	primary_outcome_button.text = "VISIT METROPOLIS"
	primary_outcome_button.disabled = true
	secondary_outcome_button.text = "RETURN TO JUNKYARD"
	secondary_outcome_button.visible = true
	_outcome_mode = &"victory_unlock"
	_append_log(
		"Victory resolved%s: the Junk King's $%d battle total was added once."
		% ["" if applied else " previously", boss_score]
	)
	await _reveal_outcome_panel()
	var generation := _sequence_generation
	if applied and not GameState.reduced_motion and wallet_before != GameState.money:
		_outcome_tween = create_tween()
		_outcome_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_outcome_tween.tween_method(
			_set_victory_wallet_outcome_value.bind(boss_score),
			wallet_before,
			GameState.money,
			WALLET_COUNT_DURATION
		)
		await _wait_safely(WALLET_COUNT_DURATION, generation)
	else:
		_set_victory_wallet_outcome_value(GameState.money, boss_score)
	if generation == _sequence_generation and is_inside_tree():
		primary_outcome_button.disabled = false


func _resolve_defeat() -> void:
	if _permanent_resolution_attempted:
		return
	_permanent_resolution_attempted = true
	var wallet_before := GameState.money
	var applied := GameState.resolve_junk_king_defeat(_resolution_token)
	if not SaveManager.flush():
		push_error("Junk King defeat resolved in memory, but the save could not be written.")
	outcome_title.text = "WALLET RESET"
	outcome_totals.text = "WALLET: $%d" % wallet_before
	_set_outcome_message("")
	primary_outcome_button.text = "RETURN TO JUNKYARD"
	primary_outcome_button.disabled = true
	secondary_outcome_button.visible = false
	_outcome_mode = &"defeat_wallet"
	await _reveal_outcome_panel()
	var generation := _sequence_generation
	if applied and not GameState.reduced_motion and wallet_before != GameState.money:
		_outcome_tween = create_tween()
		_outcome_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_outcome_tween.tween_method(_set_wallet_outcome_value, wallet_before, GameState.money, WALLET_COUNT_DURATION)
		await _wait_safely(WALLET_COUNT_DURATION, generation)
	else:
		_set_wallet_outcome_value(GameState.money)
	if generation != _sequence_generation or not is_inside_tree():
		return
	primary_outcome_button.disabled = false
	_append_log("Defeat resolved%s: wallet set to exactly $30 once." % ("" if applied else " previously"))


## An empty supporting message is hidden rather than left as a blank expanding
## row, so the remaining title/amount/button group stays centred in the panel.
func _set_outcome_message(message_text: String) -> void:
	outcome_message.text = message_text
	outcome_message.visible = not message_text.is_empty()


func _set_wallet_outcome_value(value: int) -> void:
	outcome_totals.text = "WALLET: $%d" % maxi(value, 0)


func _set_victory_wallet_outcome_value(value: int, boss_score: int) -> void:
	outcome_totals.text = "JUNK KING'S WINNINGS: $%d\nWALLET: $%d" % [
		maxi(boss_score, 0),
		maxi(value, 0),
	]


func _request_navigation(to_metropolis: bool) -> void:
	if _navigation_emitted:
		return
	_navigation_emitted = true
	_presentation_state = PresentationState.EXITING
	_sequence_generation += 1
	spin_button.disabled = true
	AudioFx.stop_spin()
	if to_metropolis:
		metropolis_requested.emit()
	else:
		return_to_junkyard_requested.emit()


func _wait_safely(duration: float, generation: int) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout
	if generation != _sequence_generation:
		return


func _append_log(entry: String) -> void:
	if entry.is_empty():
		return
	# Plain status messages get the muted colour so only scored spins stand out.
	_log_lines.append(entry if entry.contains("[color=") else _tint(entry, LOG_COLOR_MUTED))
	while _log_lines.size() > MAX_LOG_ENTRIES:
		_log_lines.pop_front()
	battle_log.text = "\n\n".join(_log_lines)
	battle_log.scroll_to_line(maxi(battle_log.get_line_count() - 1, 0))


func _tint(text_value: String, hex_color: String) -> String:
	return "[color=#%s]%s[/color]" % [hex_color, text_value]


func _format_loadout(loadout: Array[PowerUpDefinition]) -> String:
	var names: Array[String] = []
	for power_up in loadout:
		names.append(power_up.display_name)
	return ", ".join(names)


func _format_prepared_effect(outcome: Dictionary) -> String:
	var notes: Array[String] = []
	var active_id := StringName(outcome.get("active_power_up_id", &""))
	if active_id != &"":
		notes.append("Active: %s" % _power_up_name(active_id))
	var incoming: Array = outcome.get("incoming_effects", [])
	for record in incoming:
		if record is Dictionary:
			var effect_id := StringName(record.get("effect_id", &""))
			if effect_id != &"":
				notes.append("Incoming: %s" % _power_up_name(effect_id))
	if notes.is_empty():
		return "No active power-up effect on this spin."
	return " | ".join(notes)


func _format_resolved_effect(outcome: Dictionary) -> String:
	var notes: Array[String] = []
	if bool(outcome.get("rerolled", false)):
		notes.append("Scrap Reroll replaced three lowest-value symbols")
	var conditional_id := StringName(outcome.get("conditional_modifier_id", &""))
	if conditional_id != &"":
		notes.append(
			"%s x%.2f" % [_power_up_name(conditional_id), float(outcome.get("conditional_multiplier", 1.0))]
		)
	if float(outcome.get("final_surge_multiplier", 1.0)) > 1.0:
		notes.append("Final Surge x%.2f" % float(outcome.get("final_surge_multiplier", 1.0)))
	var active_id := StringName(outcome.get("active_power_up_id", &""))
	if active_id != &"":
		if bool(outcome.get("overcharge_failed", false)):
			notes.append("Overcharge failed: payout $0")
		else:
			notes.append(_power_up_name(active_id))
	var siphon_amount := int(outcome.get("siphon_amount", 0))
	if siphon_amount > 0:
		notes.append("Payout Siphon transferred $%d" % siphon_amount)
	if notes.is_empty():
		return "Configured symbol rewards applied with no bonus modifier."
	return " | ".join(notes)


## Two short colour-coded lines per spin: who scored what, then the reels and
## the running amounts. The machine already has its own top-bar readout, so it
## is left out of the log to keep each entry scannable.
func _format_result_log(outcome: Dictionary) -> String:
	var contestant := StringName(outcome.get("contestant", &""))
	var is_player := contestant == JunkKingBattleEngine.PLAYER
	var scores: Dictionary = outcome.get("score_after", {})
	var headline := "%s   %s" % [
		_tint("YOU" if is_player else "JUNK KING", LOG_COLOR_PLAYER if is_player else LOG_COLOR_BOSS),
		_tint(
			"+$%d" % maxi(int(outcome.get("payout", 0)), 0),
			LOG_COLOR_GAIN if is_player else LOG_COLOR_BOSS
		),
	]
	var active_id := StringName(outcome.get("active_power_up_id", &""))
	if active_id != &"":
		headline += "   %s" % _tint(_power_up_name(active_id), LOG_COLOR_POWER_UP)
	var siphon_amount := maxi(int(outcome.get("siphon_amount", 0)), 0)
	if siphon_amount > 0:
		headline += "   %s" % _tint("siphon $%d" % siphon_amount, LOG_COLOR_POWER_UP)
	var detail := "%s   %s" % [
		_format_symbol_icons(outcome),
		_tint(
			"You $%d · King $%d"
			% [
				int(scores.get(String(JunkKingBattleEngine.PLAYER), 0)),
				int(scores.get(String(JunkKingBattleEngine.JUNK_KING), 0)),
			],
			LOG_COLOR_TOTALS
		),
	]
	return "%s\n%s" % [headline, detail]


## Renders the rolled reel as inline artwork for the RichText battle log. Any
## symbol without a usable on-disk icon falls back to its readable name so the
## line never silently loses information.
func _format_symbol_icons(outcome: Dictionary) -> String:
	var symbols: Variant = outcome.get("symbols", [])
	if not symbols is Array or (symbols as Array).is_empty():
		return _tint(_format_symbol_ids(outcome.get("symbol_ids", [])), LOG_COLOR_MUTED)
	var parts: Array[String] = []
	for symbol in symbols as Array:
		if symbol is SlotSymbol and symbol.icon != null and not symbol.icon.resource_path.is_empty():
			parts.append(
				"[img width=%d height=%d]%s[/img]"
				% [LOG_SYMBOL_ICON_SIZE, LOG_SYMBOL_ICON_SIZE, symbol.icon.resource_path]
			)
		elif symbol is SlotSymbol:
			parts.append(_tint(symbol.display_name, LOG_COLOR_MUTED))
	if parts.is_empty():
		return _tint(_format_symbol_ids(outcome.get("symbol_ids", [])), LOG_COLOR_MUTED)
	return " ".join(parts)


func _format_symbol_ids(values: Variant) -> String:
	if not values is Array:
		return "unknown symbols"
	var labels: Array[String] = []
	for value in values:
		labels.append(String(value).replace("_", " ").capitalize())
	return " / ".join(labels)


func _power_up_name(power_up_id: StringName) -> String:
	var definition := BATTLE_CONFIG.get_power_up(power_up_id)
	return definition.display_name if definition != null else String(power_up_id)


func _error_message(result: Dictionary) -> String:
	if result.has("message"):
		return String(result.get("message", "Unknown battle error."))
	var errors: Variant = result.get("errors", [])
	if errors is Array or errors is PackedStringArray:
		return "; ".join(errors)
	return "Unknown battle error."
