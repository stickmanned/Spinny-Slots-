extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	await _verify_phone_call_and_purchase()
	await _verify_story_reload_restoration()
	await _verify_machine_ticket_spin_loop()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("Milestone 2c checks passed: phone trigger, modal call, live ticket affordability, reload-safe integrated machine mode, and repeatable ticket spin loop.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _verify_phone_call_and_purchase() -> void:
	GameState.reset_for_new_game()
	_prepare_completed_day_job()
	GameState.money = PROGRESSION.phone_call_threshold - 1
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)

	_assert_equal(int(job.get("_phase")), 2, "Below threshold remains in PLAYING")
	_assert_true(bool(job.get("_drag_enabled")), "Trash remains draggable below the phone threshold")
	GameState.add_money(1)
	await _frames(2)
	_assert_true(GameState.phone_notification_received, "Reaching the configured threshold records the phone notification")
	_assert_equal(int(job.get("_phase")), 3, "Reaching the threshold enters PHONE_AVAILABLE")
	var phone: CanvasLayer = job.get_node("PhoneNotification")
	_assert_true(bool(phone.call("is_showing")), "Phone notification is visible")
	_assert_true(job.get_node("PhoneNotification/Overlay/PhoneButton/Badge").visible, "Phone badge is visible")
	_assert_true(bool(job.get("_drag_enabled")), "Trash loop stays playable while the phone buzzes")
	await get_tree().create_timer(0.42).timeout
	var phone_button: Button = job.get_node("PhoneNotification/Overlay/PhoneButton")
	_assert_float_close(phone_button.scale.x, 1.0, 0.03, "Phone pop settles back to full scale")
	_assert_true(phone_button.get_theme_stylebox("normal") is StyleBoxEmpty, "Phone has no panel or button plate")
	_assert_float_close(phone_button.size.x / phone_button.size.y, 610.0 / 990.0, 0.02, "Phone hit target follows the visible sprite aspect")
	var phone_hit_rect := Rect2(Vector2.ZERO, phone_button.size)
	_assert_true(phone_hit_rect.has_point(phone_button.size * 0.5), "Phone center is clickable")
	_assert_true(not phone_hit_rect.has_point(Vector2(-2.0, phone_button.size.y * 0.5)), "A click just outside the phone hit target is ignored")
	await _click_gui(phone_button.global_position + Vector2(-2.0, phone_button.size.y * 0.5))
	_assert_equal(int(job.get("_phase")), 3, "An actual click just outside the phone does not activate it")
	await _assert_phone_layout(job, Vector2i(1280, 720))
	await _assert_phone_layout(job, Vector2i(1920, 1080))

	var phone_key := InputEventKey.new()
	phone_key.keycode = KEY_P
	phone_key.pressed = true
	phone._unhandled_input(phone_key)
	await get_tree().create_timer(0.32).timeout
	_assert_equal(int(job.get("_phase")), 4, "Phone activation enters PHONE_CALL")
	_assert_true(not bool(job.get("_drag_enabled")), "Phone call disables bag dragging")
	_assert_true(job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/TopRightButtons/SettingsButton").disabled, "Phone call disables HUD controls")
	_assert_float_close(job.get_node("CallDimLayer/Overlay/CallDim").color.a, 0.55, 0.03, "Phone call dims the world")
	var portrait: TextureRect = job.get_node("DialogueBox/Overlay/DialoguePanel/Content/Portrait")
	var portrait_texture := portrait.texture as AtlasTexture
	_assert_true(portrait_texture != null, "Phone call uses a tightly framed rich-kid portrait atlas")
	_assert_true(portrait_texture.region.position.x <= 416.0 and portrait_texture.region.position.y <= 449.0, "Portrait atlas keeps the character's top-left bounds")
	_assert_true(portrait_texture.region.end.x >= 1559.0 and portrait_texture.region.end.y >= 1561.0, "Portrait atlas keeps the full character uncropped")
	_assert_true(portrait.size.x >= 220.0 and portrait.size.y >= 220.0, "Rich-kid portrait is large enough to anchor the call")
	_assert_equal(portrait.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Portrait fits without cropping or stretching")
	var speaker_name: Label = job.get_node("DialogueBox/Overlay/DialoguePanel/Content/SpeakerName")
	_assert_float_close(speaker_name.get_rect().get_center().x, portrait.get_rect().get_center().x, 1.0, "Rich Kid name is centered over the portrait")
	var call_message: RichTextLabel = job.get_node("DialogueBox/Overlay/DialoguePanel/Content/Message")
	_assert_true(call_message.get_theme_font_size("normal_font_size") >= 27, "Phone-call dialogue text is enlarged")
	_mouse_press(job, job.get_node("World/TrashBag").global_position)
	_assert_true(not bool(job.get("_is_dragging")), "Bag does not move when clicked during the call")

	var dialogue: CanvasLayer = job.get_node("DialogueBox")
	for line_index in range(3):
		_assert_equal(int(dialogue.call("get_line_index")), line_index, "Phone call reaches line %d without skipping" % (line_index + 1))
		dialogue.call("advance")
		_assert_true(not bool(dialogue.call("is_typing")), "Mid-type advance completes phone line %d" % (line_index + 1))
		dialogue.call("advance")
	await get_tree().create_timer(0.32).timeout
	_assert_true(GameState.phone_call_completed, "Completing the call records its persistent story flag")
	_assert_equal(int(job.get("_phase")), 5, "Call completion enters TICKET_PURCHASE")
	_assert_true(bool(job.get("_drag_enabled")), "Trash loop is restored during guided purchase")
	_assert_true(job.get_node("PurchaseLayer").visible, "Guided ticket shop is visible")
	_assert_true(job.get_node("TicketLayer").visible, "The persistent ticket panel opens for guided purchase")
	_assert_true(job.get_node_or_null("PurchaseLayer/Overlay/TicketShopPanel") == null, "Guided purchase does not create a second ticket panel")
	var purchase_canvas: CanvasLayer = job.get_node("PurchaseLayer")
	var ticket_canvas: CanvasLayer = job.get_node("TicketLayer")
	_assert_true(purchase_canvas.layer > phone.layer, "Purchase dimmer also covers the phone")
	_assert_true(ticket_canvas.layer > purchase_canvas.layer, "Ticket panel stays highlighted above the dimmer")
	await get_tree().create_timer(0.4).timeout

	GameState.money = 20
	await _frames(2)
	var machine := PROGRESSION.machines[0]
	var guided_ticket_shop: PanelContainer = job.get_node("TicketLayer/Overlay/LeftColumn/MachineTicketShop")
	var guided_panel_rect := guided_ticket_shop.get_global_rect()
	_assert_equal(int(guided_ticket_shop.call("get_row_count")), 1, "Tutorial ticket list only offers Cardboard Cash before the first purchase")
	var buy_button := guided_ticket_shop.call("get_buy_button", machine.machine_id) as Button
	_assert_true(buy_button != null, "Guided ticket list exposes Cardboard Cash's compact Buy button")
	_assert_true(buy_button.disabled, "Ticket purchase disables when balance is insufficient")
	var guided_price: Label = buy_button.get_node("ContentMargin/Content/TicketDetails/PriceLabel")
	_assert_equal(guided_price.text, "$30", "Insufficient ticket state keeps the configured price visible")
	_assert_true("need" not in buy_button.tooltip_text.to_lower(), "Insufficient ticket state removes shortfall wording")
	for _index in range(10):
		Economy.award_day_job_bag()
	await _frames(2)
	_assert_true(not buy_button.disabled, "Ticket purchase re-enables immediately after earning the difference")
	buy_button.emit_signal("pressed")
	_assert_equal(GameState.money, 0, "Ticket purchase deducts the configured $30")
	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 1, "Ticket purchase grants exactly one spin ticket")
	_assert_true(GameState.is_machine_unlocked(machine.machine_id), "First ticket purchase unlocks Cardboard Cash")
	# Long enough to cover the purchase bounce, the machine-mode fade, and the
	# staggered per-row reveal tween for the two newly unlocked tickets.
	await get_tree().create_timer(1.3).timeout
	_assert_equal(int(job.get("_phase")), 6, "Purchase opens MACHINE_SELECTOR")
	_assert_true(job.get_node("SelectorLayer").visible, "Machine mode remains inside the Junkyard scene")
	_assert_true(not job.get_node("World").visible, "Dumpster and trash bag are hidden after the first ticket purchase")
	_assert_true(job.get_node("World/TrashBag/BagShape").disabled, "Hidden trash bag cannot be dragged")
	_assert_true(job.get_node("World/Dumpster/DropZone/DropShape").disabled, "Hidden dumpster drop zone is disabled")
	_assert_true(job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/TopRightButtons/SettingsButton").visible, "Settings remains visible in machine mode")
	_assert_true(job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel").modulate.a > 0.98, "Existing upgrades panel is revealed on the right")
	_assert_true(job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel").visible, "The original Junkyard currency panel remains visible in machine mode")
	_assert_true(job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel").modulate.a > 0.98, "The original currency panel remains fully readable")
	_assert_true(job.get_node("TicketLayer").visible, "The same ticket panel remains open in machine mode")
	_assert_true(bool(phone.call("is_showing")), "Answered phone remains visible in machine mode")
	_assert_true(job.get_node("PhoneNotification/Overlay/PhoneButton").disabled, "Answered phone is static until message history exists")
	_assert_true(not job.get_node("PhoneNotification/Overlay/PhoneButton/Badge").visible, "Answered phone has no unread badge")
	var machine_ticket_shop: PanelContainer = job.get_node("TicketLayer/Overlay/LeftColumn/MachineTicketShop")
	_assert_true(machine_ticket_shop == guided_ticket_shop, "Guided purchase animates into the persistent ticket panel")
	_assert_true(machine_ticket_shop.get_global_rect().is_equal_approx(guided_panel_rect), "Ticket panel keeps the same position and size after purchase")
	_assert_equal(int(machine_ticket_shop.call("get_row_count")), 3, "Ticket section uses one compact row per implemented machine")
	var ticket_rows_container: VBoxContainer = machine_ticket_shop.get_node("Content/TicketScroll/TicketRows")
	for row_index in range(ticket_rows_container.get_child_count()):
		var revealed_row := ticket_rows_container.get_child(row_index)
		_assert_float_close(revealed_row.modulate.a, 1.0, 0.02, "Ticket row %d finishes its reveal fully visible" % row_index)
		_assert_float_close(revealed_row.scale.y, 1.0, 0.02, "Ticket row %d finishes its reveal at full scale" % row_index)
	var ticket_row := ticket_rows_container.get_child(0) as Button
	_assert_true(ticket_row != null, "Each ticket is one unified purchase button")
	_assert_true(ticket_row.get_node("ContentMargin/Content/TicketArt").size.x >= 100.0, "Cardboard Cash ticket art is large enough to read")
	var ticket_price: Label = ticket_row.get_node("ContentMargin/Content/TicketDetails/PriceLabel")
	_assert_true("x" not in ticket_price.text.to_lower(), "Ticket inventory is not shown in the left ticket panel")
	var ticket_texture := machine.ticket_texture as AtlasTexture
	_assert_true(ticket_texture != null, "Cardboard Cash ticket uses a tightly framed atlas")
	_assert_true(ticket_texture.region.size.x <= 1250.0 and ticket_texture.region.size.y <= 650.0, "Transparent source padding cannot shrink the visible ticket art")
	var left_arrow: TextureButton = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/LeftArrow")
	var right_arrow: TextureButton = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/RightArrow")
	_assert_true(not left_arrow.disabled, "Three-machine selector enables its left arrow")
	_assert_true(not right_arrow.disabled, "Three-machine selector enables its right arrow")
	_assert_true(left_arrow.texture_normal.resource_path.ends_with("arrow_left.svg"), "Left selector uses its crisp left-arrow asset")
	_assert_true(right_arrow.texture_normal.resource_path.ends_with("arrow_right.svg"), "Right selector uses its crisp right-arrow asset")
	var cabinet_texture := machine.cabinet_texture as AtlasTexture
	_assert_true(cabinet_texture != null, "Cardboard Cash uses a padded cabinet atlas")
	_assert_true(cabinet_texture.region.position.x <= 460.0 and cabinet_texture.region.position.y <= 244.0, "Cabinet atlas includes the artwork's top-left bounds")
	_assert_true(cabinet_texture.region.end.x >= 1644.0 and cabinet_texture.region.end.y >= 1730.0, "Cabinet atlas includes the lever, base, and right edge")
	await _assert_job_layout(job, Vector2i(1280, 720))
	await _assert_job_layout(job, Vector2i(1920, 1080))
	job.queue_free()
	await _frames(2)


func _verify_story_reload_restoration() -> void:
	GameState.reset_for_new_game()
	_prepare_completed_day_job()
	GameState.money = PROGRESSION.phone_call_threshold
	GameState.mark_phone_notification_received()
	var job := await _spawn_job()
	_assert_equal(int(job.get("_phase")), 3, "Reload after phone pop restores PHONE_AVAILABLE without refiring")
	job.queue_free()
	await _frames(2)

	GameState.mark_phone_call_started()
	job = await _spawn_job()
	_assert_equal(int(job.get("_phase")), 4, "Reload during call restores PHONE_CALL")
	job.queue_free()
	await _frames(2)

	GameState.mark_phone_call_completed()
	job = await _spawn_job()
	_assert_equal(int(job.get("_phase")), 5, "Reload after call restores TICKET_PURCHASE")
	job.queue_free()
	await _frames(2)

	GameState.ticket_purchase_tutorial_completed = true
	GameState.unlock_machine(PROGRESSION.machines[0].machine_id)
	job = await _spawn_job()
	_assert_equal(int(job.get("_phase")), 6, "Reload after purchase restores MACHINE_SELECTOR")
	_assert_true(GameState.phone_notification_received, "Phone notification remains one-shot across every scene reload")
	job.queue_free()
	await _frames(2)


func _verify_machine_ticket_spin_loop() -> void:
	GameState.reset_for_new_game()
	var machine := PROGRESSION.machines[0]
	GameState.money = 0
	GameState.unlock_machine(machine.machine_id)
	GameState.add_machine_ticket(machine.machine_id)
	GameState.selected_machine_id = machine.machine_id
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	_prepare_completed_day_job()
	var job := await _spawn_job()
	var spin_button: Button = job.get_node("SelectorLayer/Overlay/MachineArea/SpinButton")
	_assert_true(not spin_button.disabled, "Owned ticket enables the separate Spin button")
	_assert_equal(spin_button.text, "SPIN (1)", "Spin button displays the selected machine's owned ticket count")
	var expected_symbols := _predict_spin_symbols(machine, 1)
	var expected_total := 0
	var expected_names: Array[String] = []
	for expected_symbol in expected_symbols:
		expected_total += expected_symbol.payout
		expected_names.append(expected_symbol.display_name)
	_assert_true(expected_total >= machine.ticket_price, "The first machine's three-reel payout always covers the ticket price")
	spin_button.emit_signal("pressed")
	await get_tree().create_timer(AudioFx.get_spin_duration() + 0.6).timeout
	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 0, "One spin consumes exactly one ticket")
	_assert_equal(spin_button.text, "SPIN (0)", "Spin button updates immediately when a ticket is consumed")
	_assert_equal(GameState.money, expected_total, "Spin awards the predetermined weighted three-reel payout")
	var result_label: Label = job.get_node("SelectorLayer/Overlay/MachineArea/ResultLabel")
	_assert_equal(result_label.text, "  •  ".join(expected_names), "Result label names all three predetermined symbols")
	var ticket_shop: PanelContainer = job.get_node("TicketLayer/Overlay/LeftColumn/MachineTicketShop")
	var buy_button := ticket_shop.call("get_buy_button", machine.machine_id) as Button
	_assert_true(not buy_button.disabled, "A payout covering the ticket price immediately enables another purchase")
	buy_button.emit_signal("pressed")
	_assert_equal(GameState.get_machine_ticket_count(machine.machine_id), 1, "Buying again restores one spin ticket")
	_assert_equal(spin_button.text, "SPIN (1)", "Spin button updates immediately after buying a ticket")
	_assert_equal(GameState.money, expected_total - machine.ticket_price, "Repeat ticket purchase leaves the predetermined profit")
	await _assert_job_layout(job, Vector2i(1280, 720))
	await _assert_job_layout(job, Vector2i(1920, 1080))
	job.queue_free()
	await _frames(2)


func _predict_spin_symbols(machine: MachineDefinition, seed_value: int) -> Array[SlotSymbol]:
	Economy.set_rng_seed(seed_value)
	var symbols: Array[SlotSymbol] = []
	for _reel_index in range(Economy.REEL_COUNT):
		symbols.append(Economy.roll_symbol(machine))
	Economy.set_rng_seed(seed_value)
	return symbols


func _spawn_job() -> Control:
	var job := JOB_SCENE.instantiate() as Control
	add_child(job)
	await _frames(3)
	return job


func _prepare_completed_day_job() -> void:
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true


func _assert_job_layout(job: Control, resolution: Vector2i) -> void:
	get_tree().root.content_scale_size = resolution
	get_tree().root.size = resolution
	await _frames(3)
	var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
	for path in [
		"TicketLayer/Overlay/LeftColumn/OddsPanel",
		"TicketLayer/Overlay/LeftColumn/MachineTicketShop",
		"SelectorLayer/Overlay/MachineArea",
		"SelectorLayer/Overlay/MachineArea/MachineSelectorPanel",
		"SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/CabinetArt/ReelStrip",
		"SelectorLayer/Overlay/MachineArea/SpinButton",
		"Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel",
		"Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel",
		"Hud/Layout/SafeMargin/Columns/RightStack/TopRightButtons/SettingsButton",
		"PhoneNotification/Overlay/PhoneButton",
	]:
		var control: Control = job.get_node(path)
		var control_rect := control.get_global_rect()
		_assert_true(bounds.encloses(control_rect), "%s fits at %dx%d: %s" % [path, resolution.x, resolution.y, control_rect])
	var selector: PanelContainer = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel")
	_assert_true(selector.get_theme_stylebox("panel") is StyleBoxEmpty, "Machine selector has no opaque panel chrome")
	var odds_panel: Control = job.get_node("TicketLayer/Overlay/LeftColumn/OddsPanel")
	var left_panel: Control = job.get_node("TicketLayer/Overlay/LeftColumn/MachineTicketShop")
	var machine_area: Control = job.get_node("SelectorLayer/Overlay/MachineArea")
	var currency_panel: Control = job.get_node("Hud/Layout/SafeMargin/Columns/LeftStack/CurrencyPanel")
	var upgrade_panel: Control = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/UpgradePanel")
	var settings_button: Button = job.get_node("Hud/Layout/SafeMargin/Columns/RightStack/TopRightButtons/SettingsButton")
	var cabinet: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/CabinetArt")
	var reel_strip: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/CabinetArt/ReelStrip")
	var left_arrow: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/LeftArrow")
	var right_arrow: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/SelectorRow/RightArrow")
	var machine_name: Control = job.get_node("SelectorLayer/Overlay/MachineArea/MachineSelectorPanel/Content/MachineName")
	_assert_true(not machine_name.visible, "Machine name label stays hidden so its space goes to the enlarged cabinet")
	var payout: Control = job.get_node("SelectorLayer/Overlay/MachineArea/PayoutLabel")
	var spin: Control = job.get_node("SelectorLayer/Overlay/MachineArea/SpinButton")
	var phone: Control = job.get_node("PhoneNotification/Overlay/PhoneButton")
	_assert_true(currency_panel.get_global_rect().end.y <= left_panel.get_global_rect().position.y + 4.0, "Ticket panel extends below rather than replacing the Junkyard currency panel")
	_assert_true(left_panel.get_global_rect().end.y <= odds_panel.get_global_rect().position.y + 4.0, "Odds panel sits below the ticket panel")
	var upper_gap := left_panel.get_global_rect().position.y - currency_panel.get_global_rect().end.y
	var lower_gap := odds_panel.get_global_rect().position.y - left_panel.get_global_rect().end.y
	_assert_float_close(upper_gap, 16.0, 1.0, "Currency-to-ticket gap uses the shared panel spacing at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(lower_gap, 16.0, 1.0, "Ticket-to-odds gap uses the shared panel spacing at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(odds_panel.get_global_rect().position.x, currency_panel.get_global_rect().position.x, 0.5, "Odds panel aligns with the currency panel")
	_assert_float_close(odds_panel.get_global_rect().size.x, currency_panel.get_global_rect().size.x, 0.5, "Odds and currency panels keep one consistent width")
	_assert_true(odds_panel.get_global_rect().end.x <= machine_area.get_global_rect().position.x, "Odds panel stays left of the active machine at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(left_panel.get_global_rect().position.x, currency_panel.get_global_rect().position.x, 0.5, "Ticket panel aligns with the currency panel")
	_assert_float_close(left_panel.get_global_rect().size.x, currency_panel.get_global_rect().size.x, 0.5, "Ticket and currency panels keep one consistent width")
	_assert_true(settings_button.get_global_rect().end.y <= upgrade_panel.get_global_rect().position.y, "Settings row remains detached above the upgrades panel")
	_assert_true(left_panel.get_global_rect().end.x <= machine_area.get_global_rect().position.x, "Ticket list %s stays left of machine %s at %dx%d" % [left_panel.get_global_rect(), machine_area.get_global_rect(), resolution.x, resolution.y])
	_assert_true(machine_area.get_global_rect().end.x <= upgrade_panel.get_global_rect().position.x + 20.0, "Machine stays clear of upgrades at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(machine_area.get_global_rect().get_center().x, resolution.x * 0.5, 0.5, "Machine presentation is centered at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(cabinet.get_global_rect().get_center().x, resolution.x * 0.5, 0.5, "Machine cabinet is centered at %dx%d" % [resolution.x, resolution.y])
	_assert_true(cabinet.size.y >= 460.0, "Cabinet art is enlarged to at least 460px tall at %dx%d" % [resolution.x, resolution.y])
	_assert_true(reel_strip.size.y >= 110.0, "Reel screen icons are enlarged along with the cabinet at %dx%d" % [resolution.x, resolution.y])
	_assert_float_close(payout.get_global_rect().get_center().x, resolution.x * 0.5, 0.5, "Payout counter follows the centered cabinet")
	_assert_float_close(spin.get_global_rect().get_center().x, resolution.x * 0.5, 0.5, "Spin button follows the centered cabinet")
	_assert_true(left_panel.get_global_rect().end.x + 8.0 <= left_arrow.get_global_rect().position.x, "Left arrow stays clear of the ticket panel")
	_assert_true(right_arrow.get_global_rect().end.x + 8.0 <= upgrade_panel.get_global_rect().position.x, "Right arrow stays clear of the upgrades panel")
	_assert_true(left_arrow.get_global_rect().end.x + 24.0 <= cabinet.get_global_rect().position.x, "Left arrow is spread away from the cabinet")
	_assert_true(cabinet.get_global_rect().end.x + 24.0 <= right_arrow.get_global_rect().position.x, "Right arrow is spread away from the cabinet")
	_assert_true(not phone.get_global_rect().intersects(cabinet.get_global_rect()), "Phone stays clear of the cabinet")
	_assert_true(not phone.get_global_rect().intersects(left_arrow.get_global_rect()), "Phone stays clear of the left arrow")
	_assert_true(not phone.get_global_rect().intersects(right_arrow.get_global_rect()), "Phone stays clear of the right arrow")
	settings_button.emit_signal("pressed")
	await _frames(1)
	var settings_layer: CanvasLayer = job.get_node("Hud/SettingsLayer")
	var settings_panel: Control = job.get_node("Hud/SettingsLayer/ModalRoot/SettingsPanel")
	var ticket_layer: CanvasLayer = job.get_node("TicketLayer")
	var selector_layer: CanvasLayer = job.get_node("SelectorLayer")
	_assert_true(settings_layer.visible, "Settings opens in machine mode")
	_assert_true(settings_layer.layer > ticket_layer.layer and settings_layer.layer > selector_layer.layer, "Settings canvas renders above machine UI")
	_assert_true(bounds.encloses(settings_panel.get_global_rect()), "Settings modal fits at %dx%d" % [resolution.x, resolution.y])
	job.get_node("Hud/SettingsLayer/ModalRoot/SettingsPanel/CloseButton").emit_signal("pressed")


func _assert_phone_layout(job: Control, resolution: Vector2i) -> void:
	get_tree().root.content_scale_size = resolution
	get_tree().root.size = resolution
	await _frames(3)
	var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
	var phone_button: Button = job.get_node("PhoneNotification/Overlay/PhoneButton")
	_assert_true(bounds.encloses(phone_button.get_global_rect()), "Phone fits at %dx%d" % [resolution.x, resolution.y])


func _mouse_press(job: Control, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	job._input(event)


func _click_gui(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	Input.parse_input_event(press)
	await _frames(1)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func _assert_float_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (expected %.3f, got %.3f)" % [message, expected, actual])
