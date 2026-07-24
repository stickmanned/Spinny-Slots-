extends Node

## Deterministic coverage for the one-time Metropolis welcome phone call:
## trigger/persistence rules, dialogue content, control-locking while the
## call is open, and save/load round trips (including legacy-save defaults).

const JOB_SCENE: PackedScene = preload("res://scenes/metropolis_job.tscn")
const JUNKYARD_JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const JUNKYARD_PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")
const WELCOME_CALL_DIALOGUE: DialogueData = preload("res://resources/dialogue/metropolis_welcome_call.tres")
const MACHINES: Array[MetropolisMachineDefinition] = [
	preload("res://resources/machines/neon_arcade.tres"),
	preload("res://resources/machines/drone_dispatch.tres"),
	preload("res://resources/machines/firewall_terminal.tres"),
	preload("res://resources/machines/billboard_jackpot.tres"),
	preload("res://resources/machines/quantum_vault.tres"),
]
const TEST_SAVE_PATH := "user://metropolis_welcome_call_test.json"
const EXPECTED_LINES: Array[String] = [
	"Welcome to Metropolis!",
	"This city is absolutely MASSIVE, so always watch where you're going!",
	"The slot machines here are also upgraded",
	"Some can give you random boosts, like multiply your total earnings per spin",
	"or some can literally \"Hack\" your spin if you have the special key!",
	"Just one tip before I go..",
	"Make sure to upgrade in the right upgrades panel so you can get the most out of the machines!",
	"happy gambling, and PEACE!",
]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 8.0
	SaveManager.set_save_path_for_tests(TEST_SAVE_PATH)
	SaveManager.delete_save_for_tests()

	_verify_dialogue_content()
	await _verify_first_entry_shows_notification()
	await _verify_answering_opens_rich_kid_layout()
	await _verify_controls_locked_while_call_open()
	await _verify_natural_completion_sets_state()
	await _verify_skip_completes_safely()
	await _verify_leaving_before_answering_offers_call_again()
	await _verify_interrupted_call_remains_available()
	await _verify_completed_call_never_returns()
	await _verify_save_round_trip()
	await _verify_legacy_save_defaults_safely()
	await _verify_junkyard_calls_still_work()
	await _verify_portrait_and_panel_layout()

	Engine.time_scale = 1.0
	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()

	if _failures.is_empty():
		print(
			"Metropolis welcome call checks passed: trigger/notification rules, Rich Kid "
			+ "presentation, exact dialogue, control locking, exact-once completion (natural "
			+ "and skipped), interrupted-call persistence, save migrations, Junkyard call "
			+ "regressions, and 1280x720 layout containment."
		)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_dialogue_content() -> void:
	_assert_equal(WELCOME_CALL_DIALOGUE.lines, EXPECTED_LINES, "The welcome call resource has all eight exact lines in order")


func _prepare_metropolis_state() -> void:
	GameState.reset_for_new_game()
	GameState.metropolis_unlocked = true
	GameState.day_job_tutorial_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.junk_king_defeated = true
	GameState.reduced_motion = true
	GameState.money = 5_000_000
	GameState.selected_machine_id = MACHINES[0].machine_id


func _verify_first_entry_shows_notification() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	_assert_true(_phone_call_active(phone), "First Metropolis entry with the welcome call unseen shows an active incoming-call notification")
	_assert_true(GameState.metropolis_welcome_notification_received, "Showing the notification marks it received")
	_assert_true(not GameState.metropolis_welcome_call_completed, "The call is not completed just by showing the notification")

	job.queue_free()
	await _frames(3)


func _verify_answering_opens_rich_kid_layout() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout

	var dialogue_box := job.get_node("%DialogueBox") as CanvasLayer
	var portrait := dialogue_box.get_node("%Portrait") as TextureRect
	var speaker_name := dialogue_box.get_node("%SpeakerName") as Label
	var message := dialogue_box.get_node("%Message") as RichTextLabel
	_assert_true(portrait.visible and portrait.texture == JUNKYARD_PROGRESSION.rich_kid_portrait, "Answering shows the exact Rich Kid portrait artwork")
	_assert_equal(speaker_name.text, JUNKYARD_PROGRESSION.phone_call_speaker, "Answering shows the exact Rich Kid speaker name")
	_assert_equal(message.text, EXPECTED_LINES[0], "The phone-call dialogue opens on the first welcome line")
	_assert_equal(int(job.get("_phase")), 1, "Answering enters the WELCOME_CALL phase")
	_assert_true(GameState.metropolis_welcome_call_started, "Answering marks the welcome call started")

	job.queue_free()
	await _frames(3)


func _verify_controls_locked_while_call_open() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout

	var spin_button := job.get_node("%SpinButton") as Button
	_assert_true(spin_button.disabled, "The Spin button is disabled while the welcome call is open")

	GameState.add_machine_ticket(MACHINES[0].machine_id, 1)
	var money_before := GameState.money
	var tickets_before := GameState.get_machine_ticket_count(MACHINES[0].machine_id)
	job.call("_on_spin_pressed")
	await _frames(2)
	_assert_equal(GameState.money, money_before, "Spin presses cannot spend money while the welcome call is open")
	_assert_equal(GameState.get_machine_ticket_count(MACHINES[0].machine_id), tickets_before, "Spin presses cannot consume a ticket while the welcome call is open")
	_assert_true(not bool(job.get("_spin_in_progress")), "A blocked spin press never starts a spin")

	var tickets_before_purchase := GameState.get_machine_ticket_count(MACHINES[1].machine_id)
	job.call("_on_purchase_requested", MACHINES[1])
	await _frames(2)
	_assert_equal(GameState.get_machine_ticket_count(MACHINES[1].machine_id), tickets_before_purchase, "Ticket purchases cannot be activated while the welcome call is open")

	var selected_before := GameState.selected_machine_id
	job.call("_on_selection_changed", MACHINES[2])
	await _frames(2)
	_assert_equal(GameState.selected_machine_id, selected_before, "Machine selection cannot be activated while the welcome call is open")

	job.queue_free()
	await _frames(3)


func _verify_natural_completion_sets_state() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout

	var dialogue_box := job.get_node("%DialogueBox") as CanvasLayer
	await _advance_dialogue_to_completion(dialogue_box)
	await get_tree().create_timer(0.4).timeout

	_assert_true(GameState.metropolis_welcome_call_completed, "Finishing every line sets the persistent completion state")
	_assert_equal(int(job.get("_phase")), 0, "Finishing the call returns Metropolis to its normal phase")
	var spin_button := job.get_node("%SpinButton") as Button
	_assert_true(not spin_button.disabled or GameState.get_machine_ticket_count(MACHINES[0].machine_id) <= 0, "The Spin button returns to normal availability after the call")
	var phone_after := job.get_node("%PhoneNotification") as CanvasLayer
	_assert_true(_phone_call_idle(phone_after), "The phone returns to its normal idle state after the call completes")

	job.queue_free()
	await _frames(3)


func _verify_skip_completes_safely() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout

	var dialogue_box := job.get_node("%DialogueBox") as CanvasLayer
	dialogue_box.call("skip")
	await get_tree().create_timer(0.4).timeout

	_assert_true(GameState.metropolis_welcome_call_completed, "Skipping through the dialogue API also completes the call")
	_assert_equal(int(job.get("_phase")), 0, "Skipping the call returns Metropolis to its normal phase")

	job.queue_free()
	await _frames(3)


func _verify_leaving_before_answering_offers_call_again() -> void:
	_prepare_metropolis_state()
	var first_job := JOB_SCENE.instantiate() as Control
	add_child(first_job)
	await _frames(6)
	first_job.queue_free()
	await _frames(3)

	_assert_true(not GameState.metropolis_welcome_call_completed, "Leaving before answering never marks the call completed")

	var second_job := JOB_SCENE.instantiate() as Control
	add_child(second_job)
	await _frames(6)
	var phone := second_job.get_node("%PhoneNotification") as CanvasLayer
	_assert_true(_phone_call_active(phone), "A later Metropolis visit offers the unanswered call again")

	second_job.queue_free()
	await _frames(3)


func _verify_interrupted_call_remains_available() -> void:
	_prepare_metropolis_state()
	var first_job := JOB_SCENE.instantiate() as Control
	add_child(first_job)
	await _frames(6)
	var phone := first_job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout
	_assert_true(GameState.metropolis_welcome_call_started, "The interrupted call was answered before being abandoned")
	_assert_true(not GameState.metropolis_welcome_call_completed, "An abandoned mid-call state is not marked completed")
	first_job.queue_free()
	await _frames(3)

	var second_job := JOB_SCENE.instantiate() as Control
	add_child(second_job)
	await _frames(6)
	var second_phone := second_job.get_node("%PhoneNotification") as CanvasLayer
	_assert_true(_phone_call_active(second_phone), "An interrupted, incomplete call remains available after re-entry")
	_assert_equal(int(second_job.get("_phase")), 0, "A fresh scene instance restarts in the normal phase rather than a stuck call state")

	var dialogue_box := second_job.get_node("%DialogueBox") as CanvasLayer
	second_phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout
	var message := dialogue_box.get_node("%Message") as RichTextLabel
	_assert_equal(message.text, EXPECTED_LINES[0], "Restarting the interrupted call replays from the first line")

	second_job.queue_free()
	await _frames(3)


func _verify_completed_call_never_returns() -> void:
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)
	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout
	var dialogue_box := job.get_node("%DialogueBox") as CanvasLayer
	await _advance_dialogue_to_completion(dialogue_box)
	await get_tree().create_timer(0.4).timeout
	job.queue_free()
	await _frames(3)

	var second_job := JOB_SCENE.instantiate() as Control
	add_child(second_job)
	await _frames(6)
	var second_phone := second_job.get_node("%PhoneNotification") as CanvasLayer
	_assert_true(_phone_call_idle(second_phone), "Returning after completion never shows the notification again")
	second_phone.emit_signal("activated")
	await _frames(3)
	_assert_equal(int(second_job.get("_phase")), 0, "Returning after completion never reopens the dialogue")

	second_job.queue_free()
	await _frames(3)


func _verify_save_round_trip() -> void:
	SaveManager.delete_save_for_tests()
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)
	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout
	var dialogue_box := job.get_node("%DialogueBox") as CanvasLayer
	await _advance_dialogue_to_completion(dialogue_box)
	await get_tree().create_timer(0.4).timeout
	job.queue_free()
	await _frames(3)

	_assert_true(SaveManager.save_now(), "The completed welcome call checkpoint saves successfully")
	GameState.reset_for_new_game()
	_assert_true(SaveManager.load_now(), "The save reloads from the isolated test path")
	_assert_true(GameState.metropolis_welcome_call_completed, "The completed state survives a save/load round trip")
	_assert_true(GameState.metropolis_welcome_call_started, "The started flag survives a save/load round trip")
	_assert_true(GameState.metropolis_welcome_notification_received, "The notification-received flag survives a save/load round trip")

	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()


func _verify_legacy_save_defaults_safely() -> void:
	SaveManager.delete_save_for_tests()
	_write_test_save({
		"save_version": 3,
		"wallet": 999,
		"story": {
			"junk_king_intro_triggered": true,
			"junk_king_intro_completed": true,
			"junk_king_available": false,
			"junk_king_defeated": true,
			"metropolis_unlocked": true,
		},
		"machines": {"unlocked_machine_ids": ["magnet_machine"]},
	})
	_assert_true(SaveManager.load_now(), "A save that predates the welcome call still loads")
	_assert_true(GameState.metropolis_unlocked, "The legacy save keeps Metropolis unlocked")
	_assert_true(not GameState.metropolis_welcome_call_completed, "A save missing the new key defaults to not completed")
	_assert_true(not GameState.metropolis_welcome_notification_received, "A save missing the new key defaults its notification flag to unset")

	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)
	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	_assert_true(_phone_call_active(phone), "A migrated pre-existing save receives the welcome call once on its next Metropolis visit")
	job.queue_free()
	await _frames(3)

	SaveManager.delete_save_for_tests()
	GameState.reset_for_new_game()


func _verify_junkyard_calls_still_work() -> void:
	GameState.reset_for_new_game()
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.money = JUNKYARD_PROGRESSION.phone_call_threshold
	var job := JUNKYARD_JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)

	job.call("_begin_phone_call")
	await get_tree().create_timer(0.4).timeout
	var dialogue_box := job.get_node("DialogueBox") as CanvasLayer
	var portrait := dialogue_box.get_node("%Portrait") as TextureRect
	var speaker_name := dialogue_box.get_node("%SpeakerName") as Label
	_assert_true(portrait.visible and portrait.texture == JUNKYARD_PROGRESSION.rich_kid_portrait, "The Junkyard Rich Kid call still shows its portrait")
	_assert_equal(speaker_name.text, JUNKYARD_PROGRESSION.phone_call_speaker, "The Junkyard Rich Kid call still shows its speaker name")
	_assert_equal(
		dialogue_box.get_node("%Message").get("text"),
		JUNKYARD_PROGRESSION.phone_call_dialogue.lines[0],
		"The Junkyard Rich Kid call still opens on its first configured line"
	)

	await _advance_dialogue_to_completion(dialogue_box)
	await _frames(6)
	_assert_true(GameState.phone_call_completed, "The Junkyard Rich Kid call still completes and persists its own flag")

	job.queue_free()
	await _frames(3)
	GameState.reset_for_new_game()


func _verify_portrait_and_panel_layout() -> void:
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	_prepare_metropolis_state()
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(6)
	var phone := job.get_node("%PhoneNotification") as CanvasLayer
	phone.emit_signal("activated")
	await get_tree().create_timer(0.4).timeout

	var dialogue_box := job.get_node("%DialogueBox") as CanvasLayer
	var dialogue_panel := dialogue_box.get_node("%DialoguePanel") as PanelContainer
	var portrait := dialogue_box.get_node("%Portrait") as TextureRect
	var message := dialogue_box.get_node("%Message") as RichTextLabel
	var continue_indicator := dialogue_box.get_node("%ContinueIndicator") as Label
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280, 720))

	_assert_true(_rect_contains(viewport_rect, dialogue_panel.get_global_rect()), "The phone-call panel stays fully inside the 1280x720 viewport")
	_assert_true(_rect_contains(dialogue_panel.get_global_rect(), portrait.get_global_rect()), "The portrait stays fully inside the phone-call panel (no bottom crop)")
	_assert_equal(portrait.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "The portrait preserves its aspect ratio instead of stretching or cropping to cover")

	# The dialogue is already in its phone-call layout at this point (still on
	# line one). Reuse that same live layout to check every remaining line's
	# rendered text fits without needing scroll or overlapping the indicator,
	# without re-triggering the one-time call flow per line.
	for line in EXPECTED_LINES:
		message.text = line
		message.visible_characters = -1
		await _frames(2)
		_assert_true(
			message.get_content_height() <= message.size.y + 1.0,
			"Line fits without clipping or unintended scrolling: \"%s\"" % line
		)
		_assert_true(
			_rect_contains(dialogue_panel.get_global_rect(), message.get_global_rect()),
			"Line's text region stays inside the phone-call panel: \"%s\"" % line
		)
		if continue_indicator.visible:
			_assert_true(
				not message.get_global_rect().intersects(continue_indicator.get_global_rect()),
				"Line does not overlap the continue indicator: \"%s\"" % line
			)

	await _advance_dialogue_to_completion(dialogue_box)
	await get_tree().create_timer(0.4).timeout
	job.queue_free()
	await _frames(3)

	GameState.reset_for_new_game()


func _advance_dialogue_to_completion(dialogue_box: CanvasLayer, max_steps: int = 40) -> void:
	for _step in range(max_steps):
		if not bool(dialogue_box.get("_is_playing")):
			return
		dialogue_box.call("advance")
		await _frames(1)
	_failures.append("Dialogue did not reach completion within %d advance() calls" % max_steps)


func _write_test_save(document: Dictionary) -> void:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("The isolated legacy save fixture can be opened for writing")
		return
	file.store_string(JSON.stringify(document, "\t"))
	file.close()


## PhoneNotification.is_showing() only reports button visibility, which stays
## true for the disabled idle icon too. An "active" call is visible AND
## enabled (see phone_notification.gd's show_notification vs show_idle).
func _phone_call_active(phone: CanvasLayer) -> bool:
	var button := phone.get_node("%PhoneButton") as Button
	return button.visible and not button.disabled


func _phone_call_idle(phone: CanvasLayer) -> bool:
	var button := phone.get_node("%PhoneButton") as Button
	return button.visible and button.disabled


func _rect_contains(outer: Rect2, inner: Rect2) -> bool:
	var grown := outer.grow(1.0)
	return grown.has_point(inner.position) and grown.has_point(inner.end)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])
