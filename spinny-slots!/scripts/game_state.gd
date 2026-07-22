extends Node

signal money_changed(value: int)
signal money_spent(amount: int)
signal gems_changed(value: int)
signal upgrade_levels_changed(upgrade_id: StringName, level: int)
signal music_volume_changed(value: float)
signal reduced_motion_changed(value: bool)
signal sfx_enabled_changed(value: bool)
signal story_progress_changed
signal machine_tickets_changed(machine_id: StringName, count: int)
signal machine_mechanic_charges_changed(machine_id: StringName, count: int)
signal machine_free_rerolls_changed(machine_id: StringName, count: int)
signal machine_upgrade_levels_changed(machine_id: StringName, upgrade_id: StringName, level: int)
signal machine_unlocked(machine_id: StringName)
signal selected_machine_changed(machine_id: StringName)

var money: int = 0:
	set(value):
		money = maxi(value, 0)
		money_changed.emit(money)

# TODO(gems): jackpot currency, see GAME_PLAN 7
var gems: int = 0:
	set(value):
		gems = maxi(value, 0)
		gems_changed.emit(gems)

var music_volume: float = 0.3:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		music_volume_changed.emit(music_volume)

var reduced_motion := false:
	set(value):
		reduced_motion = value
		reduced_motion_changed.emit(reduced_motion)

var sfx_enabled := true:
	set(value):
		sfx_enabled = value
		sfx_enabled_changed.emit(sfx_enabled)

var day_job_intro_seen := false:
	set(value):
		if day_job_intro_seen == value:
			return
		day_job_intro_seen = value
		story_progress_changed.emit()

var day_job_tutorial_completed := false:
	set(value):
		if day_job_tutorial_completed == value:
			return
		day_job_tutorial_completed = value
		story_progress_changed.emit()

var phone_notification_received := false:
	set(value):
		if phone_notification_received == value:
			return
		phone_notification_received = value
		story_progress_changed.emit()

var phone_call_started := false:
	set(value):
		if phone_call_started == value:
			return
		phone_call_started = value
		story_progress_changed.emit()

var phone_call_completed := false:
	set(value):
		if phone_call_completed == value:
			return
		phone_call_completed = value
		story_progress_changed.emit()

var ticket_purchase_tutorial_completed := false:
	set(value):
		if ticket_purchase_tutorial_completed == value:
			return
		ticket_purchase_tutorial_completed = value
		story_progress_changed.emit()

var junk_king_intro_triggered := false:
	set(value):
		if junk_king_intro_triggered == value:
			return
		junk_king_intro_triggered = value
		story_progress_changed.emit()

var junk_king_intro_completed := false:
	set(value):
		if junk_king_intro_completed == value:
			return
		junk_king_intro_completed = value
		story_progress_changed.emit()

var junk_king_available := false:
	set(value):
		if junk_king_available == value:
			return
		junk_king_available = value
		story_progress_changed.emit()

var junk_king_defeated := false:
	set(value):
		if junk_king_defeated == value:
			return
		junk_king_defeated = value
		story_progress_changed.emit()

var metropolis_unlocked := false:
	set(value):
		if metropolis_unlocked == value:
			return
		metropolis_unlocked = value
		story_progress_changed.emit()

var selected_machine_id: StringName = &"":
	set(value):
		if selected_machine_id == value:
			return
		selected_machine_id = value
		selected_machine_changed.emit(selected_machine_id)

var unlocked_machine_ids: Array[StringName] = []
var machine_ticket_counts: Dictionary = {}
## Metropolis-only: banked Hack Charges (Firewall Hacker Terminal) and free
## Surge reroll tokens (Rideshare Drone Dispatch), both keyed by machine_id.
## Empty for machines without that mechanic; Junkyard machines never use these.
var machine_mechanic_charges: Dictionary = {}
var machine_free_rerolls: Dictionary = {}
var upgrade_levels: Dictionary = {}
## Metropolis-only: each machine upgrades independently. Keyed
## "machine_id::upgrade_id" -> level. Junkyard keeps using upgrade_levels.
var machine_upgrade_levels: Dictionary = {}

var _resolved_junk_king_battle_tokens: Dictionary = {}
var _next_junk_king_resolution_id := 0


func _ready() -> void:
	reset_for_new_game()


func reset_for_new_game() -> void:
	money = Economy.get_starting_balance()
	gems = 0
	day_job_intro_seen = false
	day_job_tutorial_completed = false
	phone_notification_received = false
	phone_call_started = false
	phone_call_completed = false
	ticket_purchase_tutorial_completed = false
	junk_king_intro_triggered = false
	junk_king_intro_completed = false
	junk_king_available = false
	junk_king_defeated = false
	metropolis_unlocked = false
	selected_machine_id = &""
	unlocked_machine_ids.clear()
	machine_ticket_counts.clear()
	machine_mechanic_charges.clear()
	machine_free_rerolls.clear()
	machine_upgrade_levels.clear()
	upgrade_levels.clear()
	clear_junk_king_resolution_guards()
	reduced_motion = false
	sfx_enabled = true


func add_money(amount: int) -> void:
	assert(amount >= 0, "Money awards cannot be negative.")
	money += amount


func add_gems(amount: int) -> void:
	assert(amount >= 0, "Gem awards cannot be negative.")
	if amount > 0:
		gems += amount


func spend_money(amount: int) -> bool:
	assert(amount >= 0, "Money costs cannot be negative.")
	if money < amount:
		return false
	money -= amount
	if amount > 0:
		money_spent.emit(amount)
	return true


func get_upgrade_level(upgrade_id: StringName) -> int:
	return int(upgrade_levels.get(String(upgrade_id), 0))


func increment_upgrade_level(upgrade_id: StringName) -> void:
	var next_level := get_upgrade_level(upgrade_id) + 1
	upgrade_levels[String(upgrade_id)] = next_level
	upgrade_levels_changed.emit(upgrade_id, next_level)


func mark_phone_notification_received() -> void:
	if phone_notification_received:
		return
	phone_notification_received = true


func mark_phone_call_started() -> void:
	if phone_call_started:
		return
	phone_call_started = true

func mark_phone_call_completed() -> void:
	if phone_call_completed:
		return
	phone_call_started = true
	phone_call_completed = true


func mark_ticket_purchase_tutorial_completed() -> void:
	if ticket_purchase_tutorial_completed:
		return
	ticket_purchase_tutorial_completed = true


func mark_junk_king_intro_triggered() -> void:
	if junk_king_intro_triggered:
		return
	junk_king_intro_triggered = true


func mark_junk_king_intro_completed() -> void:
	if junk_king_intro_completed and junk_king_available:
		return
	junk_king_intro_triggered = true
	junk_king_intro_completed = true
	if not junk_king_defeated:
		junk_king_available = true


func mark_junk_king_available() -> void:
	if junk_king_defeated or junk_king_available:
		return
	junk_king_intro_triggered = true
	junk_king_intro_completed = true
	junk_king_available = true


func mark_junk_king_defeated() -> void:
	if junk_king_defeated and not junk_king_available and metropolis_unlocked:
		return
	junk_king_intro_triggered = true
	junk_king_intro_completed = true
	junk_king_available = false
	junk_king_defeated = true
	metropolis_unlocked = true


func mark_metropolis_unlocked() -> void:
	if metropolis_unlocked:
		return
	metropolis_unlocked = true


## Returns a transient token for one boss attempt. Tokens are deliberately not
## saved; loading always returns to the last safe, non-battle checkpoint.
func create_junk_king_resolution_token() -> String:
	_next_junk_king_resolution_id += 1
	return "%d:%d" % [Time.get_ticks_usec(), _next_junk_king_resolution_id]


## Applies the one-time victory payout for a battle attempt. The caller must
## pass only the boss's battle score; the player's temporary score is not paid.
func resolve_junk_king_victory(resolution_token: String, boss_score: int) -> bool:
	assert(boss_score >= 0, "The Junk King battle score cannot be negative.")
	if resolution_token.is_empty() or boss_score < 0:
		return false
	if junk_king_defeated or _resolved_junk_king_battle_tokens.has(resolution_token):
		return false
	_resolved_junk_king_battle_tokens[resolution_token] = true
	add_money(boss_score)
	mark_junk_king_defeated()
	return true


## Resolves one loss exactly once and changes no progression other than the
## wallet recovery amount. A fresh token allows a later retry to resolve.
func resolve_junk_king_defeat(resolution_token: String) -> bool:
	if resolution_token.is_empty():
		return false
	if junk_king_defeated or _resolved_junk_king_battle_tokens.has(resolution_token):
		return false
	_resolved_junk_king_battle_tokens[resolution_token] = true
	money = 30
	return true


func has_resolved_junk_king_battle(resolution_token: String) -> bool:
	return not resolution_token.is_empty() and _resolved_junk_king_battle_tokens.has(resolution_token)


func clear_junk_king_resolution_guards() -> void:
	_resolved_junk_king_battle_tokens.clear()
	_next_junk_king_resolution_id = 0


func unlock_machine(machine_id: StringName) -> void:
	if machine_id in unlocked_machine_ids:
		return
	unlocked_machine_ids.append(machine_id)
	machine_unlocked.emit(machine_id)
	story_progress_changed.emit()


func is_machine_unlocked(machine_id: StringName) -> bool:
	return machine_id in unlocked_machine_ids


func get_machine_ticket_count(machine_id: StringName) -> int:
	return int(machine_ticket_counts.get(String(machine_id), 0))


func add_machine_ticket(machine_id: StringName, amount: int = 1) -> void:
	assert(amount >= 0, "Ticket awards cannot be negative.")
	var next_count := get_machine_ticket_count(machine_id) + amount
	machine_ticket_counts[String(machine_id)] = next_count
	machine_tickets_changed.emit(machine_id, next_count)


func consume_machine_ticket(machine_id: StringName) -> bool:
	var count := get_machine_ticket_count(machine_id)
	if count <= 0:
		return false
	machine_ticket_counts[String(machine_id)] = count - 1
	machine_tickets_changed.emit(machine_id, count - 1)
	return true


func get_machine_mechanic_charges(machine_id: StringName) -> int:
	return int(machine_mechanic_charges.get(String(machine_id), 0))


## Charges are capped by the caller (the machine's MetropolisMechanicConfig
## defines the cap); GameState just stores whatever count it is given.
func set_machine_mechanic_charges(machine_id: StringName, count: int) -> void:
	var clamped := maxi(count, 0)
	machine_mechanic_charges[String(machine_id)] = clamped
	machine_mechanic_charges_changed.emit(machine_id, clamped)


func add_machine_mechanic_charge(machine_id: StringName, cap: int) -> void:
	var next_count := mini(get_machine_mechanic_charges(machine_id) + 1, maxi(cap, 0))
	set_machine_mechanic_charges(machine_id, next_count)


func consume_machine_mechanic_charge(machine_id: StringName) -> bool:
	var count := get_machine_mechanic_charges(machine_id)
	if count <= 0:
		return false
	set_machine_mechanic_charges(machine_id, count - 1)
	return true


func get_machine_free_rerolls(machine_id: StringName) -> int:
	return int(machine_free_rerolls.get(String(machine_id), 0))


func add_machine_free_reroll(machine_id: StringName) -> void:
	var next_count := get_machine_free_rerolls(machine_id) + 1
	machine_free_rerolls[String(machine_id)] = next_count
	machine_free_rerolls_changed.emit(machine_id, next_count)


func consume_machine_free_reroll(machine_id: StringName) -> bool:
	var count := get_machine_free_rerolls(machine_id)
	if count <= 0:
		return false
	machine_free_rerolls[String(machine_id)] = count - 1
	machine_free_rerolls_changed.emit(machine_id, count - 1)
	return true


func _machine_upgrade_key(machine_id: StringName, upgrade_id: StringName) -> String:
	return "%s::%s" % [String(machine_id), String(upgrade_id)]


func get_machine_upgrade_level(machine_id: StringName, upgrade_id: StringName) -> int:
	return int(machine_upgrade_levels.get(_machine_upgrade_key(machine_id, upgrade_id), 0))


func increment_machine_upgrade_level(machine_id: StringName, upgrade_id: StringName) -> void:
	var next_level := get_machine_upgrade_level(machine_id, upgrade_id) + 1
	machine_upgrade_levels[_machine_upgrade_key(machine_id, upgrade_id)] = next_level
	machine_upgrade_levels_changed.emit(machine_id, upgrade_id, next_level)
