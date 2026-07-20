extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const MAIN_SCENE := "res://scenes/main.tscn"
const EXPECTED_PROJECT_NAME := "Spinny Slots!"
const EXPECTED_HACKATIME_PROJECT := "Spinny-Slots-"
const BAG_CONTENT_SIZE := Vector2(150.0, 190.0)
const DUMPSTER_TEXTURE_SIZE := Vector2(2000.0, 2000.0)
const DUMPSTER_TEXTURE_SCALE := 0.27
const TUTORIAL_TEXT := "Drag the trash bag into the dumpster."
const DIALOGUE_SCENE: PackedScene = preload("res://scenes/ui/dialogue_box.tscn")
const TEST_SEEN_LINES: Array[String] = ["Previously seen line."]

var _failures: Array[String] = []
var _skip_finished_emitted := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	_assert_true(ProjectSettings.get_setting("application/config/name") == EXPECTED_PROJECT_NAME, "Project name remains canonical")
	_assert_true(ProjectSettings.get_setting("application/run/main_scene") == MAIN_SCENE, "Main scene remains configured")
	_assert_true(ProjectSettings.get_setting("hackatime/project_name") == EXPECTED_HACKATIME_PROJECT, "Hackatime project name remains canonical")
	_assert_true(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1280, "Base viewport width remains 1280")
	_assert_true(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 720, "Base viewport height remains 720")
	_assert_true(get_tree().root.has_node("Economy"), "Economy autoload is available")
	_assert_true(get_tree().root.has_node("GameState"), "GameState autoload is available")
	GameState.reset_for_new_game()

	var job := JOB_SCENE.instantiate()
	add_child(job)
	await get_tree().process_frame
	await get_tree().process_frame

	await _verify_layout(job, Vector2i(1280, 720))
	await _verify_layout(job, Vector2i(1920, 1080))
	await _verify_layout(job, Vector2i(1280, 720))
	await _verify_intro_and_tutorial(job)
	await _verify_drag_loop(job)
	await _verify_failure_paths(job)
	await _verify_rapid_input_guard(job)
	await _verify_session_seen_state(job)
	await _verify_click_spam()

	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("Milestone 2b checks passed: dialogue, input staging, responsive layout, tutorial handoff, 6 valid bags, and regression guards.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_layout(job: Control, resolution: Vector2i) -> void:
	get_tree().root.content_scale_size = resolution
	get_tree().root.size = resolution
	await get_tree().process_frame
	await get_tree().process_frame

	var viewport_bounds := Rect2(Vector2.ZERO, Vector2(resolution))
	var dumpster: Node2D = job.get_node("World/Dumpster")
	var bag: Area2D = job.get_node("World/TrashBag")
	var upgrade_panel: PanelContainer = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel")
	var currency_panel: PanelContainer = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel")
	var dialogue_panel: PanelContainer = job.get_node("DialogueBox/Overlay/DialoguePanel")
	var tutorial_prompt: PanelContainer = job.get_node("TutorialLayer/Overlay/TutorialPrompt")
	var message: RichTextLabel = job.get_node("DialogueBox/Overlay/DialoguePanel/Content/Message")
	var coin_icon: TextureRect = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel/CurrencyContent/Coins/Icon")
	var gem_icon: TextureRect = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel/CurrencyContent/Gems/Icon")
	var settings_button: Button = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/TopRightButtons/SettingsButton")
	var settings_layer: CanvasLayer = job.get_node("Hud/SettingsLayer")
	var settings_panel: PanelContainer = job.get_node("Hud/SettingsLayer/ModalRoot/SettingsPanel")
	var close_button: Button = job.get_node("Hud/SettingsLayer/ModalRoot/SettingsPanel/CloseButton")
	var panel_style := job.theme.get_stylebox("panel", "PanelContainer") as StyleBoxTexture
	var dumpster_size := DUMPSTER_TEXTURE_SIZE * DUMPSTER_TEXTURE_SCALE * dumpster.scale
	var dumpster_bounds := Rect2(dumpster.global_position - dumpster_size * 0.5, dumpster_size)
	var bag_size := BAG_CONTENT_SIZE * bag.scale
	var bag_bounds := Rect2(bag.global_position - bag_size * 0.5, bag_size)

	_assert_true(viewport_bounds.encloses(dumpster_bounds), "Dumpster is fully visible at %dx%d" % [resolution.x, resolution.y])
	_assert_true(viewport_bounds.encloses(bag_bounds), "Trash bag is fully grabbable at %dx%d" % [resolution.x, resolution.y])
	_assert_true(not dumpster_bounds.intersects(upgrade_panel.get_global_rect()), "Dumpster does not overlap the upgrade HUD at %dx%d" % [resolution.x, resolution.y])
	_assert_true(not bag_bounds.intersects(currency_panel.get_global_rect()), "Trash bag does not overlap the currency HUD at %dx%d" % [resolution.x, resolution.y])
	_assert_true(upgrade_panel.get_global_rect().end.x <= resolution.x, "Upgrade panel is not clipped at %dx%d" % [resolution.x, resolution.y])
	_assert_true(currency_panel.get_global_rect().position.x >= 0.0, "Currency panel is not clipped at %dx%d" % [resolution.x, resolution.y])
	_assert_true(viewport_bounds.encloses(dialogue_panel.get_global_rect()), "Dialogue is fully visible at %dx%d" % [resolution.x, resolution.y])
	_assert_true(not dialogue_panel.get_global_rect().intersects(dumpster_bounds), "Dialogue does not cover the dumpster at %dx%d" % [resolution.x, resolution.y])
	_assert_true(viewport_bounds.encloses(tutorial_prompt.get_global_rect()), "Tutorial prompt is fully visible at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(dumpster.global_position.x, resolution.x * 0.5, 0.5, "Dumpster is horizontally centered at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(bag.global_position.x, resolution.x * 0.22, 0.5, "Trash bag is shifted right at %dx%d" % [resolution.x, resolution.y])
	_assert_equal(message.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "Dialogue text is centered at %dx%d" % [resolution.x, resolution.y])
	_assert_string_equal(job.theme.default_font.resource_path, "res://assets/fonts/fredoka_one/fredoka_one_regular.ttf", "Fredoka One is the active UI font")
	_assert_true(panel_style != null and panel_style.texture.resource_path == "res://assets/art/ui/game_gui/panel_patterned.png", "Panels use the patterned 2D Game GUI artwork")
	_assert_true(panel_style != null and panel_style.modulate_color.is_equal_approx(Color("3bb1fc")), "Panels use the #3BB1FC GUI color")
	_assert_true(settings_button.custom_minimum_size.x >= 64.0 and settings_button.custom_minimum_size.y >= 64.0, "Settings button has an accessible click target")
	_assert_string_equal(settings_button.icon.resource_path, "res://assets/art/ui/game_gui/gear_icon.png", "Settings button uses the GUI gear artwork")
	_assert_true(settings_button.icon.get_size().x >= 40.0 and settings_button.icon.get_size().y >= 40.0, "Settings gear artwork is large and crisp enough for the control")
	_assert_true(job.theme.get_color("font_outline_color", "Label") == Color.BLACK, "Labels use a black font outline")
	_assert_true(job.theme.get_color("font_outline_color", "Button") == Color.BLACK, "Buttons use a black font outline")
	_assert_true(job.theme.get_color("font_outline_color", "RichTextLabel") == Color.BLACK, "Dialogue text uses a black font outline")
	settings_button.emit_signal("pressed")
	_assert_true(settings_layer.visible and settings_panel.visible, "Settings button opens the settings panel")
	close_button.emit_signal("pressed")
	_assert_true(not settings_layer.visible, "Settings close button hides the settings panel")
	_assert_string_equal(coin_icon.texture.resource_path, "res://assets/art/ui/game_gui/coin_icon.png", "Coin HUD uses the new GUI icon")
	_assert_string_equal(gem_icon.texture.resource_path, "res://assets/art/ui/game_gui/gem_icon.png", "Gem HUD uses the new GUI icon")


func _verify_intro_and_tutorial(job: Control) -> void:
	var dialogue: CanvasLayer = job.get_node("DialogueBox")
	var message: RichTextLabel = job.get_node("DialogueBox/Overlay/DialoguePanel/Content/Message")
	var indicator: Label = job.get_node("DialogueBox/Overlay/DialoguePanel/Content/ContinueIndicator")
	var currency_panel: PanelContainer = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel")
	var upgrade_panel: PanelContainer = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel")
	var tutorial_prompt: PanelContainer = job.get_node("TutorialLayer/Overlay/TutorialPrompt")
	var bag: Area2D = job.get_node("World/TrashBag")

	_assert_equal(int(job.get("_phase")), 0, "Fresh launch begins in INTRO")
	_assert_true(not job.get("_drag_enabled"), "The bag is not draggable during INTRO")
	_assert_float_close(currency_panel.modulate.a, 0.0, 0.01, "Currency HUD starts hidden")
	_assert_float_close(upgrade_panel.modulate.a, 0.0, 0.01, "Upgrade HUD starts hidden")
	_assert_equal(int(dialogue.call("get_line_index")), 0, "The first intro line starts automatically")
	_assert_true(dialogue.call("is_typing"), "The first line begins with typewriter reveal")

	await get_tree().create_timer(0.08).timeout
	_assert_true(message.visible_characters >= 0 and message.visible_characters < message.get_total_character_count(), "The first line reveals progressively")
	_dialogue_mouse_click(job, bag.global_position)
	_assert_true(not job.get("_is_dragging"), "Clicking the bag during INTRO does not begin a drag")
	_assert_true(not dialogue.call("is_typing"), "Clicking the bag completes the current line")
	_assert_true(indicator.visible, "Continue indicator appears only after the line completes")

	_dialogue_mouse_click(job, Vector2(640.0, 300.0))
	_assert_equal(int(dialogue.call("get_line_index")), 1, "A completed-line click advances exactly one line")
	_assert_true(dialogue.call("is_typing"), "The second line starts typing")
	_dialogue_key(dialogue, KEY_SPACE)
	_assert_true(not dialogue.call("is_typing"), "Space completes a mid-type line")

	_dialogue_key(dialogue, KEY_ENTER)
	_assert_equal(int(dialogue.call("get_line_index")), 2, "Enter advances to the third line")
	_assert_true(dialogue.call("is_typing"), "The third line starts typing")
	_dialogue_mouse_click(job, Vector2(640.0, 300.0))
	_assert_true(not dialogue.call("is_typing"), "Click completes the third line mid-type")
	_dialogue_mouse_click(job, Vector2(640.0, 300.0))

	_assert_equal(int(job.get("_phase")), 1, "Dismissing the third line enters TUTORIAL")
	_assert_true(GameState.day_job_intro_seen, "The intro is marked seen for this session")
	_assert_true(job.get("_drag_enabled"), "The bag becomes draggable in TUTORIAL")
	_assert_string_equal(tutorial_prompt.get_node("Text").text, TUTORIAL_TEXT, "Tutorial copy matches the requested instruction")
	_assert_all_controls_ignore_mouse(tutorial_prompt, "Tutorial prompt")

	await get_tree().create_timer(0.38).timeout
	_assert_float_close(currency_panel.modulate.a, 1.0, 0.01, "Coins and gems fade in after the intro")
	_assert_float_close(upgrade_panel.modulate.a, 0.0, 0.01, "Upgrade panel remains hidden after the intro")
	_assert_float_close(tutorial_prompt.modulate.a, 1.0, 0.01, "Tutorial prompt fades in")
	_assert_float_close(job.get_node("DialogueBox/Overlay/DialoguePanel").modulate.a, 0.0, 0.01, "Dialogue box fades out")

	var money_before_pass_through := GameState.money
	_viewport_mouse_button(bag.global_position, true)
	await get_tree().process_frame
	_assert_true(job.get("_is_dragging"), "A bag click passes through the tutorial overlay")
	_viewport_mouse_button(bag.global_position, false)
	await get_tree().create_timer(0.30).timeout
	_assert_equal(GameState.money, money_before_pass_through, "Pass-through verification does not award an invalid drop")


func _verify_drag_loop(job: Control) -> void:
	var initial_money := Economy.get_starting_balance()
	for index in range(6):
		await _perform_valid_drop(job, index == 0)
		_assert_equal(GameState.money, initial_money + index + 1, "Bag %d awards exactly one configured payout" % (index + 1))
		_assert_true(not job.get("_interaction_locked"), "Bag %d finishes with interaction unlocked" % (index + 1))
		_assert_true(job.get_node("World/TrashBag").visible, "Exactly one reusable bag remains visible after bag %d" % (index + 1))
		if index == 0:
			_assert_equal(int(job.get("_phase")), 2, "The first deposit enters PLAYING without delaying the award")
			_assert_true(GameState.day_job_tutorial_completed, "The first deposit completes the tutorial for this session")
			await get_tree().create_timer(0.42).timeout
			_assert_float_close(job.get_node("TutorialLayer/Overlay/TutorialPrompt").modulate.a, 0.0, 0.01, "Tutorial prompt fades out in 0.4 seconds")

	var coin_value: Label = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel/CurrencyContent/Coins/CoinValue")
	_assert_equal(int(coin_value.text), initial_money + 6, "Coin HUD updates through the tutorial deposit and five subsequent deposits")
	var gem_value: Label = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel/CurrencyContent/Gems/GemValue")
	_assert_equal(int(gem_value.text), 0, "Gem placeholder remains display-only at zero")


func _verify_failure_paths(job: Control) -> void:
	var money_before := GameState.money
	await _perform_invalid_drop(job, Vector2(760.0, 120.0))
	_assert_equal(GameState.money, money_before, "Release outside the dumpster awards no money")

	var upgrade_panel: PanelContainer = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel")
	await _perform_invalid_drop(job, upgrade_panel.get_global_rect().get_center())
	_assert_equal(GameState.money, money_before, "Release on the HUD awards no money")

	await _perform_invalid_drop(job, Vector2(-120.0, -120.0))
	_assert_equal(GameState.money, money_before, "Release off-screen awards no money")


func _verify_rapid_input_guard(job: Control) -> void:
	var money_before := GameState.money
	var bag: Area2D = job.get_node("World/TrashBag")
	var drop_zone: Area2D = job.get_node("World/Dumpster/DropZone")
	var grab_point := bag.global_position + Vector2(16.0, -12.0)
	_mouse_button(job, grab_point, true)
	var grab_offset := bag.global_position - grab_point
	var target_cursor := drop_zone.global_position - grab_offset
	_mouse_motion(job, target_cursor)
	_mouse_button(job, target_cursor, false)
	for _spam_index in range(8):
		_mouse_button(job, target_cursor, true)
		_mouse_motion(job, target_cursor + Vector2(3.0, 2.0))
		_mouse_button(job, target_cursor + Vector2(3.0, 2.0), false)
	await get_tree().create_timer(0.30).timeout
	await get_tree().process_frame
	_assert_equal(GameState.money, money_before + Economy.get_day_job_bag_payout(), "Rapid click-drag-release spam cannot double-award")


func _verify_session_seen_state(job: Control) -> void:
	job.queue_free()
	await get_tree().process_frame
	var reloaded_job := JOB_SCENE.instantiate()
	add_child(reloaded_job)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_equal(int(reloaded_job.get("_phase")), 2, "Reloading the scene after completion skips seen onboarding")
	_assert_true(reloaded_job.get("_drag_enabled"), "Reloaded PLAYING state keeps the bag draggable")
	_assert_float_close(reloaded_job.get_node("TutorialLayer/Overlay/TutorialPrompt").modulate.a, 0.0, 0.01, "Completed tutorial stays hidden on scene reload")
	reloaded_job.queue_free()
	await get_tree().process_frame


func _verify_click_spam() -> void:
	GameState.reset_for_new_game()
	var spam_job := JOB_SCENE.instantiate()
	add_child(spam_job)
	await get_tree().process_frame
	await get_tree().process_frame
	var dialogue: CanvasLayer = spam_job.get_node("DialogueBox")
	var expected_line_indices: Array[int] = [0, 1, 1, 2, 2, 2]
	var expected_typing: Array[bool] = [false, true, false, true, false, false]
	for index in range(expected_line_indices.size()):
		dialogue.call("advance")
		_assert_equal(int(dialogue.call("get_line_index")), expected_line_indices[index], "Rapid advance %d does not skip a line" % (index + 1))
		_assert_true(dialogue.call("is_typing") == expected_typing[index], "Rapid advance %d preserves two-stage input" % (index + 1))
	for _extra_click in range(12):
		dialogue.call("advance")
	_assert_equal(int(spam_job.get("_phase")), 1, "Click spam finishes cleanly in TUTORIAL")
	_assert_true(not GameState.day_job_tutorial_completed, "Intro click spam cannot complete the drag tutorial")
	spam_job.queue_free()
	await get_tree().process_frame

	var skip_box := DIALOGUE_SCENE.instantiate()
	add_child(skip_box)
	await get_tree().process_frame
	_skip_finished_emitted = false
	skip_box.connect("finished", _on_skip_finished)
	skip_box.call("play", TEST_SEEN_LINES)
	skip_box.call("skip")
	_assert_true(_skip_finished_emitted, "The public skip API finishes previously seen dialogue immediately")
	skip_box.queue_free()
	await get_tree().process_frame


func _perform_valid_drop(job: Control, check_drag_cues: bool) -> void:
	var bag: Area2D = job.get_node("World/TrashBag")
	var drop_zone: Area2D = job.get_node("World/Dumpster/DropZone")
	var highlight: Sprite2D = job.get_node("World/Dumpster/DumpsterHighlight")
	var original_position := bag.global_position
	var grab_point := original_position + Vector2(22.0, -17.0)
	_mouse_button(job, grab_point, true)
	var grab_offset := original_position - grab_point

	if check_drag_cues:
		var intermediate_cursor := grab_point + Vector2(72.0, 28.0)
		_mouse_motion(job, intermediate_cursor)
		_assert_vector_close(bag.global_position, original_position + Vector2(72.0, 28.0), 0.1, "Dragging preserves the initial grab offset")
		_assert_true(bag.z_index > 2 and bag.rotation != 0.0, "Dragging raises the bag and applies a lift cue")

	var target_cursor := drop_zone.global_position - grab_offset
	_mouse_motion(job, target_cursor)
	_assert_true(highlight.visible, "Dumpster highlights while the dragged bag overlaps its drop zone")
	_mouse_button(job, target_cursor, false)
	_assert_true(_has_floating_reward(job), "A configured floating payout indicator appears on a valid drop")
	await get_tree().create_timer(0.30).timeout
	await get_tree().process_frame


func _perform_invalid_drop(job: Control, release_position: Vector2) -> void:
	var bag: Area2D = job.get_node("World/TrashBag")
	var ground_position := bag.position
	var grab_point := bag.global_position + Vector2(18.0, -14.0)
	_mouse_button(job, grab_point, true)
	_mouse_motion(job, release_position)
	_mouse_button(job, release_position, false)
	await get_tree().create_timer(0.30).timeout
	await get_tree().process_frame
	_assert_vector_close(bag.position, ground_position, 0.5, "Invalid drop returns the bag to its valid ground position")
	_assert_true(not job.get("_interaction_locked"), "Invalid-drop return unlocks interaction")


func _has_floating_reward(job: Control) -> bool:
	for child in job.get_children():
		if child is Label and child.text == "+$%d" % Economy.get_day_job_bag_payout():
			return true
	return false


func _mouse_button(job: Control, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	job._input(event)


func _mouse_motion(job: Control, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	job._input(event)


func _dialogue_mouse_click(job: Control, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	job._input(event)
	job.get_node("DialogueBox").call("_input", event)


func _viewport_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	get_viewport().push_input(event)


func _dialogue_key(dialogue: CanvasLayer, keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	dialogue.call("_input", event)


func _on_skip_finished() -> void:
	_skip_finished_emitted = true


func _assert_all_controls_ignore_mouse(root: Control, description: String) -> void:
	_assert_equal(root.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores mouse input" % description)
	for child in root.get_children():
		if child is Control:
			_assert_all_controls_ignore_mouse(child, description)


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %d, got %d)" % [message, expected, actual])


func _assert_string_equal(actual: String, expected: String, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected '%s', got '%s')" % [message, expected, actual])


func _assert_float_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _assert_vector_close(actual: Vector2, expected: Vector2, tolerance: float, message: String) -> void:
	if actual.distance_to(expected) > tolerance:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])
