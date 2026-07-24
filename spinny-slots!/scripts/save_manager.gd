extends Node

const SAVE_VERSION := 3
const DEFAULT_SAVE_PATH := "user://spinny_slots_save.json"
const AUTOSAVE_DELAY_SECONDS := 0.4
const DEV_TEST_SCENE_PREFIX := "res://scenes/dev/"
const MAGNET_MACHINE_ID := "magnet_machine"

var _save_path := DEFAULT_SAVE_PATH
var _autosave_timer: Timer
var _is_applying_load := false
var _dev_test_mode := false
var _test_path_configured := false


func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY_SECONDS
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	_connect_game_state_signals()
	_dev_test_mode = _is_dev_test_command_line()
	if not _dev_test_mode:
		load_now()


func _exit_tree() -> void:
	if (
		_autosave_timer != null
		and not _autosave_timer.is_stopped()
		and _can_access_save_files()
	):
		save_now()


func _connect_game_state_signals() -> void:
	GameState.money_changed.connect(_on_int_value_changed)
	GameState.gems_changed.connect(_on_int_value_changed)
	GameState.upgrade_levels_changed.connect(_on_keyed_int_value_changed)
	GameState.music_volume_changed.connect(_on_float_value_changed)
	GameState.reduced_motion_changed.connect(_on_bool_value_changed)
	GameState.sfx_enabled_changed.connect(_on_bool_value_changed)
	GameState.story_progress_changed.connect(_on_story_progress_changed)
	GameState.machine_tickets_changed.connect(_on_keyed_int_value_changed)
	GameState.machine_mechanic_charges_changed.connect(_on_keyed_int_value_changed)
	GameState.machine_free_rerolls_changed.connect(_on_keyed_int_value_changed)
	GameState.machine_upgrade_levels_changed.connect(_on_machine_upgrade_level_changed)
	GameState.machine_unlocked.connect(_on_machine_id_changed)
	GameState.selected_machine_changed.connect(_on_machine_id_changed)


func _on_int_value_changed(_value: int) -> void:
	_queue_autosave()


func _on_float_value_changed(_value: float) -> void:
	_queue_autosave()


func _on_bool_value_changed(_value: bool) -> void:
	_queue_autosave()


func _on_keyed_int_value_changed(_id: StringName, _value: int) -> void:
	_queue_autosave()


func _on_machine_id_changed(_machine_id: StringName) -> void:
	_queue_autosave()


func _on_machine_upgrade_level_changed(_machine_id: StringName, _upgrade_id: StringName, _level: int) -> void:
	_queue_autosave()


func _on_story_progress_changed() -> void:
	_queue_autosave()


func _queue_autosave() -> void:
	if _is_applying_load or not _can_access_save_files():
		return
	_autosave_timer.start()


func _on_autosave_timeout() -> void:
	save_now()


## Writes a complete non-battle checkpoint immediately. Returns false if the
## write could not safely replace the primary save.
func save_now() -> bool:
	if _is_applying_load or not _can_access_save_files():
		return false
	if _autosave_timer != null:
		_autosave_timer.stop()
	return _write_document(_capture_document(), true)


## Checkpoint-friendly alias. Boss and area transitions should call this only
## after their authoritative state transaction has completed.
func flush() -> bool:
	return save_now()


## Loads primary, then backup, then a complete temporary file. Invalid or
## missing files produce a clean new-game state and a fresh primary save.
func load_now() -> bool:
	if not _can_access_save_files():
		return false
	if _autosave_timer != null:
		_autosave_timer.stop()

	var primary_result := _read_document(_save_path)
	if bool(primary_result.get("valid", false)):
		var primary_document: Dictionary = primary_result.get("document", {})
		_apply_document(primary_document)
		if bool(primary_result.get("needs_rewrite", false)):
			_write_document(primary_document, true)
		return true

	var backup_result := _read_document(_backup_path())
	if bool(backup_result.get("valid", false)):
		var backup_document: Dictionary = backup_result.get("document", {})
		_apply_document(backup_document)
		_write_document(backup_document, false)
		return true

	var temporary_result := _read_document(_temporary_path())
	if bool(temporary_result.get("valid", false)):
		var temporary_document: Dictionary = temporary_result.get("document", {})
		_apply_document(temporary_document)
		_write_document(temporary_document, false)
		return true

	_is_applying_load = true
	GameState.reset_for_new_game()
	_is_applying_load = false
	_write_document(_capture_document(), true)
	return false


## Tests must use a user:// path so save coverage cannot touch the repository.
## Configuring a path also opts explicit test runs into persistence operations.
func set_save_path_for_tests(path: String) -> void:
	assert(path.begins_with("user://"), "Test saves must stay under user://.")
	if not path.begins_with("user://"):
		return
	if _autosave_timer != null:
		_autosave_timer.stop()
	_save_path = path
	_test_path_configured = true


func get_save_path() -> String:
	return _save_path


func delete_save_for_tests() -> bool:
	if _autosave_timer != null:
		_autosave_timer.stop()
	var all_removed := true
	for path in [_save_path, _temporary_path(), _backup_path()]:
		if FileAccess.file_exists(path):
			all_removed = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK and all_removed
	return all_removed


func _can_access_save_files() -> bool:
	return not _dev_test_mode or _test_path_configured


func _is_dev_test_command_line() -> bool:
	for argument in OS.get_cmdline_args():
		if String(argument).begins_with(DEV_TEST_SCENE_PREFIX):
			return true
	return false


func _capture_document() -> Dictionary:
	var unlocked_machine_ids: Array[String] = []
	for machine_id in GameState.unlocked_machine_ids:
		unlocked_machine_ids.append(String(machine_id))

	return {
		"save_version": SAVE_VERSION,
		"wallet": GameState.money,
		"gems": GameState.gems,
		"settings": {
			"music_volume": GameState.music_volume,
			"reduced_motion": GameState.reduced_motion,
			"sfx_enabled": GameState.sfx_enabled,
		},
		"story": {
			"day_job_intro_seen": GameState.day_job_intro_seen,
			"day_job_tutorial_completed": GameState.day_job_tutorial_completed,
			"phone_notification_received": GameState.phone_notification_received,
			"phone_call_started": GameState.phone_call_started,
			"phone_call_completed": GameState.phone_call_completed,
			"ticket_purchase_tutorial_completed": GameState.ticket_purchase_tutorial_completed,
			"junk_king_intro_triggered": GameState.junk_king_intro_triggered,
			"junk_king_intro_completed": GameState.junk_king_intro_completed,
			"junk_king_available": GameState.junk_king_available,
			"junk_king_defeated": GameState.junk_king_defeated,
			"metropolis_unlocked": GameState.metropolis_unlocked,
			"metropolis_welcome_notification_received": GameState.metropolis_welcome_notification_received,
			"metropolis_welcome_call_started": GameState.metropolis_welcome_call_started,
			"metropolis_welcome_call_completed": GameState.metropolis_welcome_call_completed,
		},
		"machines": {
			"selected_machine_id": String(GameState.selected_machine_id),
			"unlocked_machine_ids": unlocked_machine_ids,
			"ticket_counts": _sanitize_nonnegative_int_dictionary(GameState.machine_ticket_counts),
			"mechanic_charges": _sanitize_nonnegative_int_dictionary(GameState.machine_mechanic_charges),
			"free_rerolls": _sanitize_nonnegative_int_dictionary(GameState.machine_free_rerolls),
		},
		"upgrades": _sanitize_nonnegative_int_dictionary(GameState.upgrade_levels),
	}


func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "error": "open_failed"}
	var contents := file.get_as_text()
	file.close()
	if contents.strip_edges().is_empty():
		return {"valid": false, "error": "empty"}

	var parser := JSON.new()
	if parser.parse(contents) != OK:
		return {"valid": false, "error": parser.get_error_message()}
	if not parser.data is Dictionary:
		return {"valid": false, "error": "root_not_dictionary"}

	var raw: Dictionary = parser.data
	var stored_version := int(raw.get("save_version", raw.get("version", 0)))
	if stored_version < 0 or stored_version > SAVE_VERSION:
		return {"valid": false, "error": "unsupported_version"}
	if not _contains_recognized_state(raw):
		return {"valid": false, "error": "missing_state"}

	var document := _normalize_document(raw)
	if document.is_empty():
		return {"valid": false, "error": "invalid_state"}
	return {
		"valid": true,
		"document": document,
		"needs_rewrite": not _uses_current_schema(raw),
	}


func _contains_recognized_state(raw: Dictionary) -> bool:
	for key in [
		"wallet",
		"money",
		"gems",
		"settings",
		"story",
		"machines",
		"unlocked_machine_ids",
		"unlocked_machines",
		"upgrades",
		"upgrade_levels",
		"game_state",
	]:
		if raw.has(key):
			return true
	return false


func _uses_current_schema(raw: Dictionary) -> bool:
	if int(raw.get("save_version", -1)) != SAVE_VERSION:
		return false
	if not raw.get("settings", null) is Dictionary:
		return false
	if not raw.get("story", null) is Dictionary:
		return false
	if not raw.get("machines", null) is Dictionary:
		return false
	var story: Dictionary = raw.get("story", {})
	var machines: Dictionary = raw.get("machines", {})
	return (
		story.has("junk_king_intro_triggered")
		and story.has("junk_king_intro_completed")
		and story.has("junk_king_available")
		and story.has("junk_king_defeated")
		and story.has("metropolis_unlocked")
		and story.has("metropolis_welcome_call_completed")
		and not machines.has("machine_upgrade_levels")
	)


func _normalize_document(raw: Dictionary) -> Dictionary:
	var base := raw
	if raw.get("game_state", null) is Dictionary:
		base = raw.get("game_state", {})

	var settings := _dictionary_or_empty(base.get("settings", {}))
	var story := _dictionary_or_empty(base.get("story", {}))
	var machines_value: Variant = base.get("machines", {})
	var machines := _dictionary_or_empty(machines_value)

	var unlocked_value: Variant = machines.get(
		"unlocked_machine_ids",
		base.get(
			"unlocked_machine_ids",
			base.get("unlocked_machines", machines_value if machines_value is Array else [])
		)
	)
	var unlocked_machine_ids := _sanitize_string_array(unlocked_value)
	var has_magnet_machine := MAGNET_MACHINE_ID in unlocked_machine_ids
	var has_any_boss_key := _has_any_boss_key(story) or _has_any_boss_key(base)

	var junk_king_intro_triggered := _read_bool_alias(
		story, base, "junk_king_intro_triggered", "junkKingIntroTriggered", false
	)
	var junk_king_intro_completed := _read_bool_alias(
		story, base, "junk_king_intro_completed", "junkKingIntroCompleted", false
	)
	var junk_king_available := _read_bool_alias(
		story, base, "junk_king_available", "junkKingAvailable", false
	)
	var junk_king_defeated := _read_bool_alias(
		story, base, "junk_king_defeated", "junkKingDefeated", false
	)
	var metropolis_unlocked := _read_bool_alias(
		story, base, "metropolis_unlocked", "metropolisUnlocked", false
	)
	# Missing on any pre-existing save (including ones that already unlocked
	# Metropolis) always defaults to false, so the welcome call is offered
	# exactly once on that player's next Metropolis visit.
	var metropolis_welcome_notification_received := _read_bool_alias(
		story, base, "metropolis_welcome_notification_received", "metropolisWelcomeNotificationReceived", false
	)
	var metropolis_welcome_call_started := _read_bool_alias(
		story, base, "metropolis_welcome_call_started", "metropolisWelcomeCallStarted", false
	)
	var metropolis_welcome_call_completed := _read_bool_alias(
		story, base, "metropolis_welcome_call_completed", "metropolisWelcomeCallCompleted", false
	)

	if has_magnet_machine and not has_any_boss_key:
		junk_king_intro_triggered = true
		junk_king_intro_completed = true
		junk_king_available = true
	if junk_king_defeated:
		junk_king_intro_triggered = true
		junk_king_intro_completed = true
		junk_king_available = false
		metropolis_unlocked = true
	elif junk_king_available:
		junk_king_intro_triggered = true
		junk_king_intro_completed = true
	elif junk_king_intro_completed:
		junk_king_intro_triggered = true

	var selected_machine_id := _read_string(
		machines.get("selected_machine_id", base.get("selected_machine_id", "")),
		""
	)
	var ticket_counts_value: Variant = machines.get(
		"ticket_counts",
		base.get("machine_ticket_counts", base.get("ticket_counts", {}))
	)
	var upgrades_value: Variant = base.get("upgrades", base.get("upgrade_levels", {}))
	var upgrade_levels := _sanitize_nonnegative_int_dictionary(upgrades_value)
	var legacy_machine_upgrades := _sanitize_nonnegative_int_dictionary(
		machines.get("machine_upgrade_levels", {})
	)
	_merge_legacy_machine_upgrades(upgrade_levels, legacy_machine_upgrades)

	return {
		"save_version": SAVE_VERSION,
		"wallet": _read_nonnegative_int(base.get("wallet", base.get("money", 0)), 0),
		"gems": _read_nonnegative_int(base.get("gems", 0), 0),
		"settings": {
			"music_volume": _read_unit_float(
				settings.get("music_volume", base.get("music_volume", GameState.music_volume)),
				GameState.music_volume
			),
			"reduced_motion": _read_bool_alias(
				settings, base, "reduced_motion", "reducedMotion", GameState.reduced_motion
			),
			"sfx_enabled": _read_bool_alias(
				settings, base, "sfx_enabled", "sfxEnabled", GameState.sfx_enabled
			),
		},
		"story": {
			"day_job_intro_seen": _read_bool_alias(
				story, base, "day_job_intro_seen", "dayJobIntroSeen", false
			),
			"day_job_tutorial_completed": _read_bool_alias(
				story, base, "day_job_tutorial_completed", "dayJobTutorialCompleted", false
			),
			"phone_notification_received": _read_bool_alias(
				story, base, "phone_notification_received", "phoneNotificationReceived", false
			),
			"phone_call_started": _read_bool_alias(
				story, base, "phone_call_started", "phoneCallStarted", false
			),
			"phone_call_completed": _read_bool_alias(
				story, base, "phone_call_completed", "phoneCallCompleted", false
			),
			"ticket_purchase_tutorial_completed": _read_bool_alias(
				story,
				base,
				"ticket_purchase_tutorial_completed",
				"ticketPurchaseTutorialCompleted",
				false
			),
			"junk_king_intro_triggered": junk_king_intro_triggered,
			"junk_king_intro_completed": junk_king_intro_completed,
			"junk_king_available": junk_king_available,
			"junk_king_defeated": junk_king_defeated,
			"metropolis_unlocked": metropolis_unlocked,
			"metropolis_welcome_notification_received": metropolis_welcome_notification_received,
			"metropolis_welcome_call_started": metropolis_welcome_call_started,
			"metropolis_welcome_call_completed": metropolis_welcome_call_completed,
		},
		"machines": {
			"selected_machine_id": selected_machine_id,
			"unlocked_machine_ids": unlocked_machine_ids,
			"ticket_counts": _sanitize_nonnegative_int_dictionary(ticket_counts_value),
			"mechanic_charges": _sanitize_nonnegative_int_dictionary(machines.get("mechanic_charges", {})),
			"free_rerolls": _sanitize_nonnegative_int_dictionary(machines.get("free_rerolls", {})),
		},
		"upgrades": upgrade_levels,
	}


func _apply_document(document: Dictionary) -> void:
	var settings := _dictionary_or_empty(document.get("settings", {}))
	var story := _dictionary_or_empty(document.get("story", {}))
	var machines := _dictionary_or_empty(document.get("machines", {}))
	var ticket_counts := _sanitize_nonnegative_int_dictionary(machines.get("ticket_counts", {}))
	var mechanic_charges := _sanitize_nonnegative_int_dictionary(machines.get("mechanic_charges", {}))
	var free_rerolls := _sanitize_nonnegative_int_dictionary(machines.get("free_rerolls", {}))
	var machine_upgrade_levels := _sanitize_nonnegative_int_dictionary(
		machines.get("machine_upgrade_levels", {})
	)
	var upgrade_levels := _sanitize_nonnegative_int_dictionary(document.get("upgrades", {}))
	var old_ticket_ids := _dictionary_keys_as_strings(GameState.machine_ticket_counts)
	var old_mechanic_charge_ids := _dictionary_keys_as_strings(GameState.machine_mechanic_charges)
	var old_free_reroll_ids := _dictionary_keys_as_strings(GameState.machine_free_rerolls)
	var old_upgrade_ids := _dictionary_keys_as_strings(GameState.upgrade_levels)

	_is_applying_load = true
	GameState.clear_junk_king_resolution_guards()
	GameState.money = int(document.get("wallet", 0))
	GameState.gems = int(document.get("gems", 0))
	GameState.music_volume = float(settings.get("music_volume", GameState.music_volume))
	GameState.reduced_motion = bool(settings.get("reduced_motion", false))
	GameState.sfx_enabled = bool(settings.get("sfx_enabled", true))

	GameState.day_job_intro_seen = bool(story.get("day_job_intro_seen", false))
	GameState.day_job_tutorial_completed = bool(story.get("day_job_tutorial_completed", false))
	GameState.phone_notification_received = bool(story.get("phone_notification_received", false))
	GameState.phone_call_started = bool(story.get("phone_call_started", false))
	GameState.phone_call_completed = bool(story.get("phone_call_completed", false))
	GameState.ticket_purchase_tutorial_completed = bool(
		story.get("ticket_purchase_tutorial_completed", false)
	)
	GameState.junk_king_intro_triggered = bool(story.get("junk_king_intro_triggered", false))
	GameState.junk_king_intro_completed = bool(story.get("junk_king_intro_completed", false))
	GameState.junk_king_available = bool(story.get("junk_king_available", false))
	GameState.junk_king_defeated = bool(story.get("junk_king_defeated", false))
	GameState.metropolis_unlocked = bool(story.get("metropolis_unlocked", false))
	GameState.metropolis_welcome_notification_received = bool(
		story.get("metropolis_welcome_notification_received", false)
	)
	GameState.metropolis_welcome_call_started = bool(story.get("metropolis_welcome_call_started", false))
	GameState.metropolis_welcome_call_completed = bool(story.get("metropolis_welcome_call_completed", false))

	GameState.unlocked_machine_ids.clear()
	for machine_id in _sanitize_string_array(machines.get("unlocked_machine_ids", [])):
		GameState.unlocked_machine_ids.append(StringName(machine_id))
	GameState.machine_ticket_counts.clear()
	for machine_id in ticket_counts:
		GameState.machine_ticket_counts[machine_id] = int(ticket_counts[machine_id])
	GameState.machine_mechanic_charges.clear()
	for machine_id in mechanic_charges:
		GameState.machine_mechanic_charges[machine_id] = int(mechanic_charges[machine_id])
	GameState.machine_free_rerolls.clear()
	for machine_id in free_rerolls:
		GameState.machine_free_rerolls[machine_id] = int(free_rerolls[machine_id])
	GameState.machine_upgrade_levels.clear()
	for upgrade_key in machine_upgrade_levels:
		GameState.machine_upgrade_levels[upgrade_key] = int(machine_upgrade_levels[upgrade_key])
	GameState.upgrade_levels.clear()
	for upgrade_id in upgrade_levels:
		GameState.upgrade_levels[upgrade_id] = int(upgrade_levels[upgrade_id])
	GameState.selected_machine_id = StringName(String(machines.get("selected_machine_id", "")))

	var ticket_ids := _merge_unique_strings(
		old_ticket_ids, _dictionary_keys_as_strings(GameState.machine_ticket_counts)
	)
	for machine_id in ticket_ids:
		GameState.machine_tickets_changed.emit(
			StringName(machine_id), GameState.get_machine_ticket_count(StringName(machine_id))
		)
	var mechanic_charge_ids := _merge_unique_strings(
		old_mechanic_charge_ids, _dictionary_keys_as_strings(GameState.machine_mechanic_charges)
	)
	for machine_id in mechanic_charge_ids:
		GameState.machine_mechanic_charges_changed.emit(
			StringName(machine_id), GameState.get_machine_mechanic_charges(StringName(machine_id))
		)
	var free_reroll_ids := _merge_unique_strings(
		old_free_reroll_ids, _dictionary_keys_as_strings(GameState.machine_free_rerolls)
	)
	for machine_id in free_reroll_ids:
		GameState.machine_free_rerolls_changed.emit(
			StringName(machine_id), GameState.get_machine_free_rerolls(StringName(machine_id))
		)
	var upgrade_ids := _merge_unique_strings(
		old_upgrade_ids, _dictionary_keys_as_strings(GameState.upgrade_levels)
	)
	for upgrade_id in upgrade_ids:
		GameState.upgrade_levels_changed.emit(
			StringName(upgrade_id), GameState.get_upgrade_level(StringName(upgrade_id))
		)
	GameState.story_progress_changed.emit()
	_is_applying_load = false


func _write_document(document: Dictionary, rotate_backup: bool) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(_save_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		push_error("SaveManager could not create the save directory.")
		return false

	var temporary_path := _temporary_path()
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		push_error("SaveManager could not open its temporary save file.")
		return false
	temporary_file.store_string(JSON.stringify(document, "\t"))
	temporary_file.flush()
	temporary_file.close()

	var primary_absolute := ProjectSettings.globalize_path(_save_path)
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var backup_absolute := ProjectSettings.globalize_path(_backup_path())
	var primary_was_rotated := false

	if rotate_backup and FileAccess.file_exists(_save_path):
		if FileAccess.file_exists(_backup_path()):
			if DirAccess.remove_absolute(backup_absolute) != OK:
				push_error("SaveManager could not replace the previous backup.")
				return false
		if DirAccess.rename_absolute(primary_absolute, backup_absolute) != OK:
			push_error("SaveManager could not rotate the primary save to its backup.")
			return false
		primary_was_rotated = true
	elif FileAccess.file_exists(_save_path):
		if DirAccess.remove_absolute(primary_absolute) != OK:
			push_error("SaveManager could not replace the invalid primary save.")
			return false

	if DirAccess.rename_absolute(temporary_absolute, primary_absolute) == OK:
		return true

	if primary_was_rotated and not FileAccess.file_exists(_save_path):
		DirAccess.rename_absolute(backup_absolute, primary_absolute)
	push_error("SaveManager could not promote the temporary save to primary.")
	return false


func _temporary_path() -> String:
	return _save_path + ".tmp"


func _backup_path() -> String:
	return _save_path + ".bak"


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _sanitize_string_array(value: Variant) -> Array[String]:
	var sanitized: Array[String] = []
	if not value is Array:
		return sanitized
	for item in value:
		if not item is String and not item is StringName:
			continue
		var text := String(item)
		if not text.is_empty() and text not in sanitized:
			sanitized.append(text)
	return sanitized


func _sanitize_nonnegative_int_dictionary(value: Variant) -> Dictionary:
	var sanitized: Dictionary = {}
	if not value is Dictionary:
		return sanitized
	for raw_key in value:
		var key := String(raw_key)
		var raw_value: Variant = value.get(raw_key, 0)
		if key.is_empty() or (not raw_value is int and not raw_value is float):
			continue
		sanitized[key] = maxi(int(raw_value), 0)
	return sanitized


func _read_nonnegative_int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return maxi(int(value), 0)
	return fallback


func _read_unit_float(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return clampf(float(value), 0.0, 1.0)
	return fallback


func _read_string(value: Variant, fallback: String) -> String:
	if value is String or value is StringName:
		return String(value)
	return fallback


func _read_bool_alias(
	primary: Dictionary,
	fallback_source: Dictionary,
	snake_case_key: String,
	camel_case_key: String,
	default_value: bool
) -> bool:
	for source in [primary, fallback_source]:
		if source.has(snake_case_key) and source[snake_case_key] is bool:
			return bool(source[snake_case_key])
		if source.has(camel_case_key) and source[camel_case_key] is bool:
			return bool(source[camel_case_key])
	return default_value


func _has_any_boss_key(source: Dictionary) -> bool:
	for key in [
		"junk_king_intro_triggered",
		"junkKingIntroTriggered",
		"junk_king_intro_completed",
		"junkKingIntroCompleted",
		"junk_king_available",
		"junkKingAvailable",
		"junk_king_defeated",
		"junkKingDefeated",
		"metropolis_unlocked",
		"metropolisUnlocked",
	]:
		if source.has(key):
			return true
	return false


func _dictionary_keys_as_strings(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in source:
		keys.append(String(key))
	return keys


func _merge_unique_strings(first: Array[String], second: Array[String]) -> Array[String]:
	var merged := first.duplicate()
	for value in second:
		if value not in merged:
			merged.append(value)
	return merged


## Area 2 originally saved upgrades as "machine_id::upgrade_id". Preserve the
## highest earned level for each upgrade when moving to the shared global
## track; taking the maximum avoids both progress loss and double-counting.
func _merge_legacy_machine_upgrades(global_levels: Dictionary, legacy_levels: Dictionary) -> void:
	for legacy_key in legacy_levels:
		var parts := String(legacy_key).split("::", false)
		if parts.size() < 2:
			continue
		var upgrade_id := parts[parts.size() - 1]
		var legacy_level := maxi(int(legacy_levels[legacy_key]), 0)
		global_levels[upgrade_id] = maxi(int(global_levels.get(upgrade_id, 0)), legacy_level)
