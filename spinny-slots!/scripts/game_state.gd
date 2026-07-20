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
signal machine_unlocked(machine_id: StringName)

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

var day_job_intro_seen := false
var day_job_tutorial_completed := false
var phone_notification_received := false
var phone_call_started := false
var phone_call_completed := false
var ticket_purchase_tutorial_completed := false
var selected_machine_id: StringName = &""
var unlocked_machine_ids: Array[StringName] = []
var machine_ticket_counts: Dictionary = {}
var upgrade_levels: Dictionary = {}


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
	selected_machine_id = &""
	unlocked_machine_ids.clear()
	machine_ticket_counts.clear()
	upgrade_levels.clear()
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
	story_progress_changed.emit()


func mark_phone_call_started() -> void:
	if phone_call_started:
		return
	phone_call_started = true
	story_progress_changed.emit()

func mark_phone_call_completed() -> void:
	phone_call_started = true
	phone_call_completed = true
	story_progress_changed.emit()


func mark_ticket_purchase_tutorial_completed() -> void:
	if ticket_purchase_tutorial_completed:
		return
	ticket_purchase_tutorial_completed = true
	story_progress_changed.emit()


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
