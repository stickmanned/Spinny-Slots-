extends Control

signal bag_deposited(payout: int)
signal hud_hide_requested
signal hud_currency_show_requested(duration: float)
signal hud_settings_show_requested
signal hud_controls_enabled_requested(enabled: bool)
signal hud_machine_mode_requested(duration: float)
signal ticket_purchase_confirmed(machine_id: StringName)
signal spin_started(machine_id: StringName)
signal spin_completed(machine_id: StringName, payout: int)
signal junk_king_challenge_confirmed
signal map_requested(map_id: String)

enum JobPhase {
	INTRO,
	TUTORIAL,
	PLAYING,
	PHONE_AVAILABLE,
	PHONE_CALL,
	TICKET_PURCHASE,
	MACHINE_SELECTOR,
	JUNK_KING_PHONE_AVAILABLE,
	JUNK_KING_PHONE_CALL,
	JUNK_KING_ARRIVAL,
	JUNK_KING_CONFIRMATION,
}

const BASE_VIEWPORT_HEIGHT := 720.0
const BAG_HIT_SIZE := Vector2(150.0, 190.0)
const DRAG_LIFT_SCALE := 1.06
const DRAG_LIFT_ROTATION := deg_to_rad(-2.0)
const DROP_DURATION := 0.22
const RETURN_DURATION := 0.24
const INTRO_FADE_DURATION := 0.26
const HUD_FADE_DURATION := 0.32
const TUTORIAL_FADE_IN_DURATION := 0.24
const TUTORIAL_FADE_OUT_DURATION := 0.4
const CALL_DIM_ALPHA := 0.55
const CALL_DIM_DURATION := 0.25
const CALL_FADE_OUT_DURATION := 0.22
const MACHINE_MODE_FADE_DURATION := 0.3
const MIN_REEL_DURATION := 0.3
const LEFT_PANEL_GAP := 16.0
const JUNK_KING_ARRIVAL_FALLBACK_SECONDS := 1.35
const DAY_JOB_INTRO: Resource = preload("res://resources/dialogue/day_job_intro.tres")
const JUNKYARD_PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")

@onready var dumpster: Node2D = $World/Dumpster
@onready var world: Node2D = $World
@onready var dumpster_sprite: Sprite2D = $World/Dumpster/DumpsterSprite
@onready var dumpster_highlight: Sprite2D = $World/Dumpster/DumpsterHighlight
@onready var drop_zone: Area2D = $World/Dumpster/DropZone
@onready var drop_shape: CollisionShape2D = $World/Dumpster/DropZone/DropShape
@onready var bag: Area2D = $World/TrashBag
@onready var bag_sprite: Sprite2D = $World/TrashBag/BagSprite
@onready var bag_shape: CollisionShape2D = $World/TrashBag/BagShape
@onready var hud: CanvasLayer = $Hud
@onready var tutorial_prompt: PanelContainer = %TutorialPrompt
@onready var dialogue_box: CanvasLayer = $DialogueBox
@onready var phone_notification: CanvasLayer = %PhoneNotification
@onready var call_dim: ColorRect = %CallDim
@onready var purchase_layer: CanvasLayer = %PurchaseLayer
@onready var spotlight_dim: ColorRect = %SpotlightDim
@onready var pulse_outline: Panel = %PulseOutline
@onready var ticket_layer: CanvasLayer = %TicketLayer
@onready var left_column: VBoxContainer = %LeftColumn
@onready var selector_layer: CanvasLayer = %SelectorLayer
@onready var machine_mode_overlay: Control = $SelectorLayer/Overlay
@onready var machine_selector: PanelContainer = %MachineSelectorPanel
@onready var machine_ticket_shop: PanelContainer = %MachineTicketShop
@onready var odds_panel: PanelContainer = %OddsPanel
@onready var reel_strip: Control = machine_selector.get_node("%ReelStrip")
@onready var spin_button: Button = %SpinButton
@onready var result_label: Label = %ResultLabel
@onready var payout_label: Label = %PayoutLabel
@onready var coin_collection_effect: CoinCollectionEffect = %CoinCollectionEffect
@onready var confetti_effect: ConfettiEffect = %ConfettiEffect
@onready var junk_king_presence: JunkKingPresence = %JunkKingPresence
@onready var junk_king_confirmation: CanvasLayer = %JunkKingConfirmation
@onready var machine_cabinet_art: Control = machine_selector.get_node("%CabinetArt") as Control
@onready var machine_left_arrow: Control = machine_selector.get_node("%LeftArrow") as Control

var _is_dragging := false
var _interaction_locked := false
var _bag_active := true
var _drag_enabled := false
var _grab_offset := Vector2.ZERO
var _ground_position := Vector2.ZERO
var _world_scale := 1.0
var _active_tween: Tween
var _tutorial_tween: Tween
var _call_tween: Tween
var _purchase_tween: Tween
var _highlight_tween: Tween
var _machine_mode_tween: Tween
var _phase := JobPhase.INTRO
var _music_player: AudioStreamPlayer = null
var _selected_machine: MachineDefinition
var _spin_in_progress := false


func _ready() -> void:
	set_process_input(true)
	resized.connect(_layout_world)
	resized.connect(_queue_left_column_layout)
	drop_zone.area_entered.connect(_on_drop_zone_area_entered)
	drop_zone.area_exited.connect(_on_drop_zone_area_exited)
	dialogue_box.connect("finished", _on_dialogue_finished)
	bag_deposited.connect(_on_bag_deposited)
	hud_hide_requested.connect(Callable(hud, "hide_all"))
	hud_currency_show_requested.connect(Callable(hud, "show_currency"))
	hud_settings_show_requested.connect(Callable(hud, "show_settings_button"))
	hud_controls_enabled_requested.connect(Callable(hud, "set_controls_enabled"))
	hud_machine_mode_requested.connect(Callable(hud, "enter_machine_mode"))
	phone_notification.connect("activated", _on_phone_activated)
	junk_king_presence.activated.connect(_on_junk_king_activated)
	junk_king_presence.arrival_completed.connect(_on_junk_king_arrival_completed)
	junk_king_confirmation.connect("accepted", _on_junk_king_challenge_accepted)
	junk_king_confirmation.connect("declined", _on_junk_king_challenge_declined)
	hud.map_requested.connect(func(id: String): map_requested.emit(id))
	hud.call("set_area_name", "JUNKYARD")
	hud.call("set_current_map_id", MapConfig.JUNKYARD_ID)
	machine_ticket_shop.connect("purchase_requested", _on_ticket_purchase_requested)
	machine_ticket_shop.connect("machine_selected", _on_ticket_machine_selected)
	machine_selector.connect("selection_changed", _on_machine_selection_changed)
	spin_button.pressed.connect(_on_spin_pressed)
	spin_button.mouse_entered.connect(func() -> void:
		_animate_button_hover(spin_button, Vector2(1.05, 1.05))
	)
	spin_button.mouse_exited.connect(func() -> void:
		_animate_button_hover(spin_button, Vector2.ONE)
	)
	coin_collection_effect.balance_progressed.connect(Callable(hud, "set_presented_money"))
	coin_collection_effect.balance_pulse_requested.connect(Callable(hud, "pulse_coin_balance"))
	coin_collection_effect.coin_sound_requested.connect(AudioFx.play_coin_drop)
	GameState.money_changed.connect(_on_money_changed)
	GameState.machine_tickets_changed.connect(_on_machine_tickets_changed)
	GameState.upgrade_levels_changed.connect(_on_upgrade_levels_changed)
	var primary_machine := _get_primary_machine()
	if primary_machine != null:
		_selected_machine = primary_machine
		machine_ticket_shop.call("configure_machines", _get_ticket_shop_machines(), primary_machine.machine_id)
		machine_ticket_shop.call("set_extension_mode", true)
	machine_selector.call("configure", JUNKYARD_PROGRESSION.machines, GameState.selected_machine_id)
	machine_selector.call("set_select_button_visible", false)
	junk_king_presence.configure_layout(left_column, machine_cabinet_art, machine_left_arrow)
	junk_king_presence.hide_presence()
	_layout_world()
	_queue_left_column_layout()
	_start_opening_sequence()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT and _is_dragging:
		_finish_drag(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _try_begin_drag(event.position):
				get_viewport().set_input_as_handled()
		elif _is_dragging:
			_finish_drag(_is_bag_in_drop_zone())
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _is_dragging:
		bag.global_position = event.position + _grab_offset
		_set_drop_highlight(_is_bag_in_drop_zone())
		get_viewport().set_input_as_handled()


func _try_begin_drag(mouse_position: Vector2) -> bool:
	if not _drag_enabled or _interaction_locked or not _bag_active or _is_dragging:
		return false

	var local_mouse := bag.to_local(mouse_position)
	var hit_rect := Rect2(-BAG_HIT_SIZE * 0.5, BAG_HIT_SIZE)
	if not hit_rect.has_point(local_mouse):
		return false

	_is_dragging = true
	_grab_offset = bag.global_position - mouse_position
	bag.z_index = 20
	bag.scale = Vector2.ONE * _world_scale * DRAG_LIFT_SCALE
	bag.rotation = DRAG_LIFT_ROTATION
	return true


func _finish_drag(valid_drop: bool) -> void:
	if not _is_dragging or _interaction_locked:
		return

	_is_dragging = false
	_interaction_locked = true
	_set_drop_highlight(false)
	if valid_drop:
		_complete_valid_drop()
	else:
		_return_bag_to_ground()


func _complete_valid_drop() -> void:
	_bag_active = false
	bag_shape.set_deferred("disabled", true)
	var payout := Economy.award_day_job_bag()
	_spawn_floating_reward(payout)
	bag_deposited.emit(payout)

	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(bag, "global_position", drop_zone.global_position, DROP_DURATION)
	_active_tween.tween_property(bag, "scale", Vector2.ONE * _world_scale * 0.58, DROP_DURATION)
	_active_tween.tween_property(bag, "rotation", deg_to_rad(8.0), DROP_DURATION)
	_active_tween.tween_property(bag_sprite, "modulate:a", 0.0, DROP_DURATION)
	await _active_tween.finished
	_spawn_next_bag()


func _return_bag_to_ground() -> void:
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(bag, "position", _ground_position, RETURN_DURATION)
	_active_tween.tween_property(bag, "scale", Vector2.ONE * _world_scale, RETURN_DURATION)
	_active_tween.tween_property(bag, "rotation", 0.0, RETURN_DURATION)
	await _active_tween.finished
	bag.z_index = 2
	_interaction_locked = false


func _spawn_next_bag() -> void:
	bag.position = _ground_position
	bag.scale = Vector2.ONE * _world_scale
	bag.rotation = 0.0
	bag.z_index = 2
	bag_sprite.modulate.a = 1.0
	bag_shape.set_deferred("disabled", false)
	_bag_active = true
	_interaction_locked = false


func _spawn_floating_reward(payout: int) -> void:
	var reward := Label.new()
	reward.text = "+%s" % NumberFormatter.currency(payout)
	reward.custom_minimum_size = Vector2(160.0, 60.0)
	reward.position = dumpster.position + Vector2(-80.0, -155.0) * _world_scale
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_font_size_override("font_size", 38)
	reward.add_theme_color_override("font_color", Color(1.0, 0.88, 0.22))
	reward.add_theme_color_override("font_outline_color", Color.BLACK)
	reward.add_theme_constant_override("outline_size", 8)
	reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward.z_index = 8
	add_child(reward)

	var reward_tween := reward.create_tween().set_parallel(true)
	reward_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reward_tween.tween_property(reward, "position:y", reward.position.y - 78.0, 0.72)
	reward_tween.tween_property(reward, "modulate:a", 0.0, 0.72).set_delay(0.18)
	reward_tween.chain().tween_callback(reward.queue_free)


func _layout_world() -> void:
	if not is_node_ready():
		return

	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	_world_scale = clampf(viewport_size.y / BASE_VIEWPORT_HEIGHT, 1.0, 1.35)
	dumpster.position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.53)
	dumpster.scale = Vector2.ONE * _world_scale
	_ground_position = Vector2(viewport_size.x * 0.22, viewport_size.y * 0.78)
	if not _is_dragging and not _interaction_locked:
		bag.position = _ground_position
		bag.scale = Vector2.ONE * _world_scale


func _is_bag_in_drop_zone() -> bool:
	if not _bag_active:
		return false
	var bag_size := BAG_HIT_SIZE * bag.global_transform.get_scale().abs()
	var zone_shape := drop_shape.shape as RectangleShape2D
	var zone_size := zone_shape.size * drop_shape.global_transform.get_scale().abs()
	var bag_bounds := Rect2(bag_shape.global_position - bag_size * 0.5, bag_size)
	var zone_bounds := Rect2(drop_shape.global_position - zone_size * 0.5, zone_size)
	return bag_bounds.intersects(zone_bounds)


func _on_drop_zone_area_entered(area: Area2D) -> void:
	if area == bag and _is_dragging:
		_set_drop_highlight(true)


func _on_drop_zone_area_exited(area: Area2D) -> void:
	if area == bag:
		_set_drop_highlight(false)


func _set_drop_highlight(is_highlighted: bool) -> void:
	dumpster_highlight.visible = is_highlighted and _is_dragging
	dumpster_sprite.modulate = Color(1.08, 1.08, 0.92) if is_highlighted and _is_dragging else Color.WHITE


func _start_opening_sequence() -> void:
	hud_hide_requested.emit()
	if GameState.day_job_tutorial_completed:
		_enter_playing()
	elif GameState.day_job_intro_seen:
		_enter_tutorial()
	else:
		_enter_intro()


func _enter_intro() -> void:
	_phase = JobPhase.INTRO
	_drag_enabled = false
	dialogue_box.call("use_standard_layout")
	dialogue_box.call("play", DAY_JOB_INTRO.get("lines"))


func _enter_tutorial() -> void:
	_phase = JobPhase.TUTORIAL
	_drag_enabled = true
	hud_currency_show_requested.emit(HUD_FADE_DURATION)
	_fade_tutorial_prompt(1.0, TUTORIAL_FADE_IN_DURATION)


func _enter_playing() -> void:
	_phase = JobPhase.PLAYING
	_drag_enabled = true
	hud_currency_show_requested.emit(HUD_FADE_DURATION)
	tutorial_prompt.modulate.a = 0.0
	_play_music()
	hud_settings_show_requested.emit()
	hud_controls_enabled_requested.emit(true)
	_restore_story_phase()


func _on_dialogue_finished() -> void:
	match _phase:
		JobPhase.INTRO:
			GameState.day_job_intro_seen = true
			dialogue_box.call("fade_out", INTRO_FADE_DURATION)
			_enter_tutorial()
		JobPhase.PHONE_CALL:
			_end_phone_call()
		JobPhase.JUNK_KING_PHONE_CALL:
			_end_junk_king_phone_call()


func _on_bag_deposited(_payout: int) -> void:
	if _phase != JobPhase.TUTORIAL:
		return
	GameState.day_job_tutorial_completed = true
	_fade_tutorial_prompt(0.0, TUTORIAL_FADE_OUT_DURATION)
	_enter_playing()


func _restore_story_phase() -> void:
	if GameState.ticket_purchase_tutorial_completed:
		_show_machine_selector(false)
	elif GameState.phone_call_completed:
		_enter_ticket_purchase()
	elif GameState.phone_call_started:
		_begin_phone_call()
	elif GameState.phone_notification_received:
		_show_phone_notification(false)
	else:
		_check_phone_threshold(GameState.money)


func _check_phone_threshold(balance: int) -> void:
	if (
		_phase != JobPhase.PLAYING
		or GameState.phone_notification_received
		or balance < JUNKYARD_PROGRESSION.phone_call_threshold
	):
		return
	GameState.mark_phone_notification_received()
	_show_phone_notification(true)


func _show_phone_notification(animate_pop: bool) -> void:
	_phase = JobPhase.PHONE_AVAILABLE
	_drag_enabled = true
	phone_notification.call(
		"show_notification",
		JUNKYARD_PROGRESSION.phone_texture,
		GameState.reduced_motion,
		animate_pop
	)


func _on_phone_activated() -> void:
	match _phase:
		JobPhase.PHONE_AVAILABLE:
			_begin_phone_call()
		JobPhase.JUNK_KING_PHONE_AVAILABLE:
			_begin_junk_king_phone_call()


func _begin_phone_call() -> void:
	_phase = JobPhase.PHONE_CALL
	GameState.mark_phone_call_started()
	phone_notification.call("hide_notification")
	_drag_enabled = false
	_cancel_active_drag()
	hud_controls_enabled_requested.emit(false)
	purchase_layer.visible = false
	ticket_layer.visible = false
	selector_layer.visible = false
	call_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_box.call(
		"use_phone_call_layout",
		JUNKYARD_PROGRESSION.phone_call_speaker,
		JUNKYARD_PROGRESSION.rich_kid_portrait
	)
	call_dim.color.a = 0.0
	if _call_tween and _call_tween.is_valid():
		_call_tween.kill()
	_call_tween = create_tween()
	_call_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_call_tween.tween_property(call_dim, "color:a", CALL_DIM_ALPHA, CALL_DIM_DURATION)
	_call_tween.tween_callback(func() -> void:
		dialogue_box.call("play", JUNKYARD_PROGRESSION.phone_call_dialogue.lines)
	)


func _end_phone_call() -> void:
	dialogue_box.call("fade_out", CALL_FADE_OUT_DURATION)
	if _call_tween and _call_tween.is_valid():
		_call_tween.kill()
	_call_tween = create_tween()
	_call_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_call_tween.tween_property(call_dim, "color:a", 0.0, CALL_DIM_DURATION)
	_call_tween.tween_callback(_finish_phone_call)


func _finish_phone_call() -> void:
	GameState.mark_phone_call_completed()
	call_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.call("use_standard_layout")
	hud_controls_enabled_requested.emit(true)
	_drag_enabled = true
	_enter_ticket_purchase()


func _show_junk_king_phone_notification(animate_pop: bool) -> void:
	if GameState.junk_king_intro_completed or GameState.junk_king_defeated:
		return
	_phase = JobPhase.JUNK_KING_PHONE_AVAILABLE
	_drag_enabled = false
	_cancel_active_drag()
	junk_king_presence.hide_presence()
	hud_controls_enabled_requested.emit(false)
	_refresh_machine_mode()
	phone_notification.call(
		"show_notification",
		JUNKYARD_PROGRESSION.phone_texture,
		GameState.reduced_motion,
		animate_pop
	)


func _begin_junk_king_phone_call() -> void:
	if GameState.junk_king_intro_completed or GameState.junk_king_defeated:
		return
	_phase = JobPhase.JUNK_KING_PHONE_CALL
	phone_notification.call("hide_notification")
	_drag_enabled = false
	_cancel_active_drag()
	hud_controls_enabled_requested.emit(false)
	purchase_layer.visible = false
	# The machine list is persistent progression UI. Keep it visible behind the
	# higher-layer boss dialogue so the call never dismantles the selector.
	ticket_layer.visible = true
	call_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_box.call(
		"use_phone_call_layout",
		JUNKYARD_PROGRESSION.junk_king_name,
		JUNKYARD_PROGRESSION.junk_king_portrait
	)
	dialogue_box.call("set_input_debounce", 0.16)
	call_dim.color.a = 0.0
	if _call_tween and _call_tween.is_valid():
		_call_tween.kill()
	_call_tween = create_tween()
	_call_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_call_tween.tween_property(call_dim, "color:a", CALL_DIM_ALPHA, CALL_DIM_DURATION)
	_call_tween.tween_callback(func() -> void:
		if _phase == JobPhase.JUNK_KING_PHONE_CALL:
			dialogue_box.call("play", JUNKYARD_PROGRESSION.junk_king_intro_dialogue.lines)
	)


func _end_junk_king_phone_call() -> void:
	dialogue_box.call("fade_out", CALL_FADE_OUT_DURATION)
	if _call_tween and _call_tween.is_valid():
		_call_tween.kill()
	_call_tween = create_tween()
	_call_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_call_tween.tween_property(call_dim, "color:a", 0.0, CALL_DIM_DURATION)
	_call_tween.tween_callback(_finish_junk_king_phone_call)


func _finish_junk_king_phone_call() -> void:
	if GameState.junk_king_intro_completed or GameState.junk_king_defeated:
		_show_machine_selector(false)
		return
	_phase = JobPhase.JUNK_KING_ARRIVAL
	call_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.call("use_standard_layout")
	phone_notification.call("show_idle", JUNKYARD_PROGRESSION.phone_texture)
	ticket_layer.visible = true
	selector_layer.visible = true
	machine_mode_overlay.modulate.a = 1.0
	junk_king_presence.show_arrival(GameState.reduced_motion, true)
	# The presence emits arrival_completed. This timer is a logic fallback so a
	# presentation interruption can never strand the save in a locked cutscene.
	get_tree().create_timer(JUNK_KING_ARRIVAL_FALLBACK_SECONDS).timeout.connect(
		_on_junk_king_arrival_fallback
	)


func _on_junk_king_arrival_fallback() -> void:
	if _phase == JobPhase.JUNK_KING_ARRIVAL:
		_on_junk_king_arrival_completed()


func _on_junk_king_arrival_completed() -> void:
	if _phase != JobPhase.JUNK_KING_ARRIVAL:
		return
	GameState.mark_junk_king_intro_completed()
	SaveManager.flush()
	_phase = JobPhase.MACHINE_SELECTOR
	hud_controls_enabled_requested.emit(true)
	junk_king_presence.set_interactable(true)
	_refresh_machine_mode()


func _enter_ticket_purchase() -> void:
	var primary_machine := _get_primary_machine()
	if primary_machine == null:
		return
	_phase = JobPhase.TICKET_PURCHASE
	_drag_enabled = true
	phone_notification.call("show_idle", JUNKYARD_PROGRESSION.phone_texture)
	selector_layer.visible = false
	purchase_layer.visible = true
	ticket_layer.visible = true
	spotlight_dim.visible = not GameState.ticket_purchase_tutorial_completed
	pulse_outline.visible = not GameState.ticket_purchase_tutorial_completed
	machine_ticket_shop.call("configure_machines", _get_ticket_shop_machines(), primary_machine.machine_id)
	_queue_left_column_layout()
	_animate_ticket_panel_open()
	_start_purchase_highlight()


func _animate_ticket_panel_open() -> void:
	if _purchase_tween and _purchase_tween.is_valid():
		_purchase_tween.kill()
	machine_ticket_shop.pivot_offset = Vector2(machine_ticket_shop.size.x * 0.5, 0.0)
	if GameState.reduced_motion:
		machine_ticket_shop.scale = Vector2.ONE
		machine_ticket_shop.modulate.a = 1.0
		return
	machine_ticket_shop.scale = Vector2(1.0, 0.08)
	machine_ticket_shop.modulate.a = 0.0
	_purchase_tween = create_tween().set_parallel()
	_purchase_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_purchase_tween.tween_property(machine_ticket_shop, "scale", Vector2.ONE, 0.34)
	_purchase_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_purchase_tween.tween_property(machine_ticket_shop, "modulate:a", 1.0, 0.22)


func _start_purchase_highlight() -> void:
	_stop_purchase_highlight()
	if GameState.ticket_purchase_tutorial_completed or GameState.reduced_motion:
		return
	pulse_outline.scale = Vector2.ONE
	pulse_outline.modulate.a = 0.72
	_highlight_tween = create_tween().set_loops()
	_highlight_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_highlight_tween.tween_property(pulse_outline, "scale", Vector2.ONE * 1.025, 0.55)
	_highlight_tween.parallel().tween_property(pulse_outline, "modulate:a", 1.0, 0.55)
	_highlight_tween.tween_property(pulse_outline, "scale", Vector2.ONE, 0.55)
	_highlight_tween.parallel().tween_property(pulse_outline, "modulate:a", 0.72, 0.55)


func _stop_purchase_highlight() -> void:
	if _highlight_tween and _highlight_tween.is_valid():
		_highlight_tween.kill()
	pulse_outline.scale = Vector2.ONE
	pulse_outline.modulate.a = 1.0


func _on_ticket_purchase_requested(machine: MachineDefinition) -> void:
	if machine == null or _phase not in [JobPhase.TICKET_PURCHASE, JobPhase.MACHINE_SELECTOR]:
		return
	var was_unlocked := GameState.is_machine_unlocked(machine.machine_id)
	if not Economy.purchase_ticket(machine):
		machine_ticket_shop.call("refresh")
		return
	var should_trigger_junk_king := (
		machine.machine_id == JUNKYARD_PROGRESSION.junk_king_machine_id
		and not was_unlocked
		and not GameState.junk_king_intro_triggered
		and not GameState.junk_king_defeated
	)
	if should_trigger_junk_king:
		# Persist the safe post-purchase checkpoint before presentation begins.
		# Reloading an interrupted intro resumes the call without buying again.
		GameState.mark_junk_king_intro_triggered()
		SaveManager.flush()
	if _phase == JobPhase.MACHINE_SELECTOR:
		ticket_purchase_confirmed.emit(machine.machine_id)
		machine_ticket_shop.call("refresh")
		_refresh_machine_mode()
		if should_trigger_junk_king:
			_show_junk_king_phone_notification(true)
		return
	GameState.mark_ticket_purchase_tutorial_completed()
	GameState.selected_machine_id = machine.machine_id
	ticket_purchase_confirmed.emit(machine.machine_id)
	_stop_purchase_highlight()
	spotlight_dim.visible = false
	pulse_outline.visible = false
	if _purchase_tween and _purchase_tween.is_valid():
		_purchase_tween.kill()
	_purchase_tween = create_tween()
	_purchase_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_purchase_tween.tween_property(machine_ticket_shop, "scale", Vector2.ONE * 1.035, 0.14)
	_purchase_tween.tween_property(machine_ticket_shop, "scale", Vector2.ONE, 0.16)
	_purchase_tween.tween_callback(_reveal_all_machines)


func _reveal_all_machines() -> void:
	# The tutorial only offered Cardboard Cash; now that it's bought, every
	# machine becomes available and the newly unlocked tickets animate in.
	_show_machine_selector(true, true)


func _show_machine_selector(animate_transition: bool = true, animate_ticket_reveal: bool = false) -> void:
	_phase = JobPhase.MACHINE_SELECTOR
	_drag_enabled = false
	_cancel_active_drag()
	purchase_layer.visible = false
	ticket_layer.visible = true
	phone_notification.call("show_idle", JUNKYARD_PROGRESSION.phone_texture)
	_hide_day_job_world(animate_transition)
	selector_layer.visible = true
	machine_mode_overlay.modulate.a = 0.0 if animate_transition else 1.0
	machine_selector.call("configure", JUNKYARD_PROGRESSION.machines, GameState.selected_machine_id)
	machine_selector.call("set_select_button_visible", false)
	_selected_machine = machine_selector.call("get_selected_machine") as MachineDefinition
	if _selected_machine != null:
		GameState.selected_machine_id = _selected_machine.machine_id
	machine_ticket_shop.call("configure_machines", _get_ticket_shop_machines(), GameState.selected_machine_id, animate_ticket_reveal)
	hud_machine_mode_requested.emit(MACHINE_MODE_FADE_DURATION if animate_transition else 0.0)
	_queue_left_column_layout()
	_refresh_machine_presentation()
	_refresh_machine_mode()
	_refresh_progression_presence()
	if animate_transition:
		if _machine_mode_tween and _machine_mode_tween.is_valid():
			_machine_mode_tween.kill()
		_machine_mode_tween = create_tween()
		_machine_mode_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_machine_mode_tween.tween_property(machine_mode_overlay, "modulate:a", 1.0, MACHINE_MODE_FADE_DURATION)


func _refresh_progression_presence() -> void:
	if GameState.junk_king_defeated:
		junk_king_presence.hide_presence()
		return
	if GameState.junk_king_intro_triggered and not GameState.junk_king_intro_completed:
		_show_junk_king_phone_notification(false)
		return
	if GameState.junk_king_available:
		junk_king_presence.show_idle(GameState.reduced_motion)
	else:
		junk_king_presence.hide_presence()


func _on_junk_king_activated() -> void:
	if (
		_phase != JobPhase.MACHINE_SELECTOR
		or not GameState.junk_king_available
		or GameState.junk_king_defeated
		or bool(junk_king_confirmation.call("is_open"))
		or _spin_in_progress
	):
		return
	_phase = JobPhase.JUNK_KING_CONFIRMATION
	hud_controls_enabled_requested.emit(false)
	_refresh_machine_mode()
	if not bool(junk_king_confirmation.call("open")):
		_phase = JobPhase.MACHINE_SELECTOR
		hud_controls_enabled_requested.emit(true)
		junk_king_presence.set_interactable(true)
		_refresh_machine_mode()


func _on_junk_king_challenge_declined() -> void:
	if _phase != JobPhase.JUNK_KING_CONFIRMATION:
		return
	junk_king_confirmation.call("close")
	_phase = JobPhase.MACHINE_SELECTOR
	hud_controls_enabled_requested.emit(true)
	junk_king_presence.set_interactable(true)
	_refresh_machine_mode()


func _on_junk_king_challenge_accepted() -> void:
	if _phase != JobPhase.JUNK_KING_CONFIRMATION:
		return
	junk_king_confirmation.call("close")
	junk_king_presence.disable_presence()
	hud_controls_enabled_requested.emit(false)
	_refresh_machine_mode()
	junk_king_challenge_confirmed.emit()


func _on_machine_selection_changed(machine: MachineDefinition) -> void:
	if _phase != JobPhase.MACHINE_SELECTOR or machine == null:
		return
	_set_selected_machine(machine)


func _on_ticket_machine_selected(machine: MachineDefinition) -> void:
	if _phase != JobPhase.MACHINE_SELECTOR or machine == null:
		return
	machine_selector.call("configure", JUNKYARD_PROGRESSION.machines, machine.machine_id)
	_set_selected_machine(machine)


func _set_selected_machine(machine: MachineDefinition) -> void:
	_selected_machine = machine
	GameState.selected_machine_id = machine.machine_id
	machine_ticket_shop.call("select_machine", machine.machine_id)
	result_label.text = ""
	payout_label.text = ""
	_refresh_machine_presentation()
	_refresh_machine_mode()


func _refresh_machine_presentation() -> void:
	odds_panel.call("configure", _selected_machine)
	if _selected_machine == null:
		return
	var icons: Array[Texture2D] = []
	for symbol in _selected_machine.symbols:
		icons.append(symbol.icon)
	reel_strip.call("set_idle_symbols", icons)


func _on_spin_pressed() -> void:
	if _phase != JobPhase.MACHINE_SELECTOR or _spin_in_progress or _selected_machine == null:
		return
	var outcome := Economy.prepare_machine_spin(_selected_machine)
	if outcome.is_empty():
		_refresh_machine_mode()
		return
	_spin_in_progress = true
	hud.call("set_upgrades_enabled", false)
	spin_started.emit(_selected_machine.machine_id)
	result_label.text = "SPINNING..."
	payout_label.text = ""
	_refresh_machine_mode()
	var symbols: Array[SlotSymbol] = outcome.get("symbols", [] as Array[SlotSymbol])
	var result_icons: Array[Texture2D] = []
	for symbol in symbols:
		result_icons.append(symbol.icon)
	var pool_icons: Array[Texture2D] = []
	for machine_symbol in _selected_machine.symbols:
		pool_icons.append(machine_symbol.icon)
	# The whole presentation (reels + landing blink) lasts exactly as long as
	# the slot-machine audio at the current spin-speed level.
	var total_duration: float = AudioFx.get_spin_duration()
	var blink_duration: float = reel_strip.call("get_blink_duration")
	var reel_duration := maxf(total_duration - blink_duration, MIN_REEL_DURATION)
	AudioFx.play_spin()
	reel_strip.call("play_spin", result_icons, pool_icons, reel_duration)
	machine_selector.call("play_spin_flourish", reel_duration)
	await get_tree().create_timer(total_duration).timeout
	if not is_inside_tree():
		return
	var names: Array[String] = []
	for symbol in symbols:
		names.append(symbol.display_name)
	result_label.text = "  •  ".join(names)
	var pending_payout := maxi(int(outcome.get("payout", 0)), 0)
	payout_label.text = NumberFormatter.reward(pending_payout)
	var rarest_hits := int(outcome.get("rarest_hits", 0))
	if rarest_hits > 0:
		confetti_effect.play(GameState.reduced_motion)
	var coin_target := hud.call("get_coin_balance_target") as Control
	await coin_collection_effect.play(
		pending_payout,
		GameState.money,
		payout_label,
		coin_target,
		GameState.reduced_motion
	)
	if not is_inside_tree():
		return
	# The visual balance is only presentation. Apply the authoritative payout
	# once, after every arrival, so callbacks can never duplicate the reward.
	var payout := Economy.award_machine_spin(outcome)
	if rarest_hits > 0:
		Economy.award_rarest_bonus(_selected_machine, outcome)
	spin_completed.emit(_selected_machine.machine_id, payout)
	_spin_in_progress = false
	hud.call("set_upgrades_enabled", true)
	_refresh_machine_mode()


func _refresh_machine_mode() -> void:
	machine_ticket_shop.call("refresh")
	if _selected_machine == null or _phase != JobPhase.MACHINE_SELECTOR:
		spin_button.disabled = true
		return
	var ticket_count := GameState.get_machine_ticket_count(_selected_machine.machine_id)
	spin_button.text = "SPIN (%d)" % ticket_count
	spin_button.disabled = _spin_in_progress or ticket_count <= 0


func _queue_left_column_layout() -> void:
	# Wait one frame so the HUD currency panel has computed its size first.
	call_deferred("_layout_left_column")


func _layout_left_column() -> void:
	if not is_instance_valid(left_column):
		return
	var currency_panel := hud.get("currency_panel") as Control
	if currency_panel == null:
		return
	# The left column starts one shared gap below the currency panel, so the
	# three left panels (currency, ticket shop, odds) are evenly spaced.
	left_column.offset_top = currency_panel.get_global_rect().end.y + LEFT_PANEL_GAP
	# The shop's rect settles on the next layout pass; track it one frame later.
	call_deferred("_position_pulse_outline")


func _position_pulse_outline() -> void:
	if not pulse_outline.visible:
		return
	var highlight_rect := machine_ticket_shop.get_global_rect().grow(6.0)
	pulse_outline.position = highlight_rect.position
	pulse_outline.size = highlight_rect.size


func _hide_day_job_world(animate_transition: bool) -> void:
	_drag_enabled = false
	_bag_active = false
	bag_shape.set_deferred("disabled", true)
	drop_shape.set_deferred("disabled", true)
	_set_drop_highlight(false)
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	if not animate_transition:
		world.modulate.a = 0.0
		world.visible = false
		return
	world.visible = true
	world.modulate.a = 1.0
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(world, "modulate:a", 0.0, MACHINE_MODE_FADE_DURATION)
	_active_tween.tween_callback(func() -> void: world.visible = false)


func _on_money_changed(balance: int) -> void:
	if is_instance_valid(machine_ticket_shop):
		machine_ticket_shop.call("refresh")
	_check_phone_threshold(balance)


func _on_upgrade_levels_changed(_upgrade_id: StringName, _level: int) -> void:
	# Luck changes the effective odds, so the odds panel must follow immediately.
	if _phase == JobPhase.MACHINE_SELECTOR:
		_refresh_machine_presentation()


func _on_machine_tickets_changed(_machine_id: StringName, _count: int) -> void:
	if is_instance_valid(machine_ticket_shop):
		machine_ticket_shop.call("refresh")
	if _phase == JobPhase.MACHINE_SELECTOR:
		_refresh_machine_mode()


func _get_primary_machine() -> MachineDefinition:
	if JUNKYARD_PROGRESSION.machines.is_empty():
		return null
	return JUNKYARD_PROGRESSION.machines[0]


func _get_ticket_shop_machines() -> Array[MachineDefinition]:
	# The ticket-purchase tutorial only ever offers Cardboard Cash; every
	# other machine's ticket stays hidden until that first purchase unlocks
	# the full lineup (see _reveal_all_machines).
	if GameState.ticket_purchase_tutorial_completed:
		return JUNKYARD_PROGRESSION.machines
	var primary_machine := _get_primary_machine()
	var machines: Array[MachineDefinition] = []
	if primary_machine != null:
		machines.append(primary_machine)
	return machines


func _cancel_active_drag() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	_interaction_locked = false
	bag.position = _ground_position
	bag.scale = Vector2.ONE * _world_scale
	bag.rotation = 0.0
	bag.z_index = 2
	_set_drop_highlight(false)


func _fade_tutorial_prompt(target_alpha: float, duration: float) -> void:
	if _tutorial_tween and _tutorial_tween.is_valid():
		_tutorial_tween.kill()
	_tutorial_tween = create_tween()
	_tutorial_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tutorial_tween.tween_property(tutorial_prompt, "modulate:a", target_alpha, duration)


func _play_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _music_player and _music_player.playing:
		return
	if not _music_player:
		_music_player = AudioStreamPlayer.new()
		var stream = load("res://assets/music/Spinny Slots! Music - 001 - (Official) Tower Defense Simulator OST - Never Broke Again.mp3") as AudioStreamMP3
		if not stream:
			_music_player = null
			return
		stream.loop = true
		_music_player.stream = stream
		_music_player.volume_db = linear_to_db(GameState.music_volume)
		add_child(_music_player)
		if not GameState.music_volume_changed.is_connected(_on_music_volume_changed):
			GameState.music_volume_changed.connect(_on_music_volume_changed)
	_music_player.play()


func _on_music_volume_changed(volume: float) -> void:
	if _music_player:
		_music_player.volume_db = linear_to_db(volume)


func _exit_tree() -> void:
	AudioFx.stop_spin()
	if GameState.music_volume_changed.is_connected(_on_music_volume_changed):
		GameState.music_volume_changed.disconnect(_on_music_volume_changed)
	if _music_player:
		_music_player.stop()
		_music_player.stream = null


func _animate_button_hover(button: Button, target_scale: Vector2) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, 0.12)
