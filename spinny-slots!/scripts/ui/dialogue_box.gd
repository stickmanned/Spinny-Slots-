extends CanvasLayer

signal finished
signal character_revealed(character: String)
signal faded_out

@export_range(1.0, 120.0, 1.0) var chars_per_second := 32.0
@export_range(0.0, 1.0, 0.01) var fade_in_duration := 0.18
@export_range(0.0, 1.0, 0.01) var input_debounce_seconds := 0.0

@onready var dialogue_panel: PanelContainer = %DialoguePanel
@onready var message: RichTextLabel = %Message
@onready var continue_indicator: Label = %ContinueIndicator
@onready var portrait: TextureRect = %Portrait
@onready var speaker_name: Label = %SpeakerName

var _lines: Array[String] = []
var _line_index := -1
var _character_progress := 0.0
var _total_characters := 0
var _is_playing := false
var _is_typing := false
var _finish_emitted := false
var _fade_tween: Tween
var _indicator_tween: Tween
var _last_input_advance_msec := -1


func _ready() -> void:
	dialogue_panel.modulate.a = 0.0
	_hide_continue_indicator()
	set_process(false)


func _process(delta: float) -> void:
	if not _is_typing:
		return

	_character_progress += chars_per_second * delta
	var target_count := mini(floori(_character_progress), _total_characters)
	var previous_count := maxi(message.visible_characters, 0)
	if target_count > previous_count:
		message.visible_characters = target_count
		for character_index in range(previous_count, target_count):
			character_revealed.emit(_lines[_line_index].substr(character_index, 1))

	if target_count >= _total_characters:
		_finish_current_line()


func _input(event: InputEvent) -> void:
	if not _is_playing:
		return

	var should_advance := false
	if event is InputEventMouseButton:
		should_advance = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventKey:
		should_advance = (
			event.pressed
			and not event.echo
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
		)

	if should_advance:
		var now_msec := Time.get_ticks_msec()
		var debounce_msec := ceili(input_debounce_seconds * 1000.0)
		if _last_input_advance_msec >= 0 and now_msec - _last_input_advance_msec < debounce_msec:
			get_viewport().set_input_as_handled()
			return
		_last_input_advance_msec = now_msec
		advance()
		get_viewport().set_input_as_handled()


func play(lines: Array[String]) -> void:
	_stop_active_tweens()
	_lines = lines.duplicate()
	_line_index = -1
	_last_input_advance_msec = -1
	_finish_emitted = false
	_is_playing = not _lines.is_empty()
	dialogue_panel.modulate.a = 0.0

	if not _is_playing:
		_emit_finished_once()
		return

	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(dialogue_panel, "modulate:a", 1.0, fade_in_duration)
	_show_next_line()


func set_input_debounce(seconds: float) -> void:
	input_debounce_seconds = clampf(seconds, 0.0, 1.0)
	_last_input_advance_msec = -1


func use_standard_layout() -> void:
	portrait.visible = false
	speaker_name.visible = false
	dialogue_panel.custom_minimum_size = Vector2(860.0, 92.0)
	dialogue_panel.anchor_left = 0.5
	dialogue_panel.anchor_top = 0.0
	dialogue_panel.anchor_right = 0.5
	dialogue_panel.anchor_bottom = 0.0
	dialogue_panel.offset_left = -430.0
	dialogue_panel.offset_top = 12.0
	dialogue_panel.offset_right = 430.0
	dialogue_panel.offset_bottom = 104.0
	message.offset_left = 0.0
	message.offset_top = 0.0
	message.offset_right = -24.0
	message.offset_bottom = 0.0
	message.add_theme_font_size_override("normal_font_size", 22)


func use_phone_call_layout(call_speaker: String, call_portrait: Texture2D) -> void:
	portrait.texture = call_portrait
	portrait.visible = call_portrait != null
	speaker_name.text = call_speaker
	speaker_name.visible = not call_speaker.is_empty()
	dialogue_panel.custom_minimum_size = Vector2(1040.0, 296.0)
	dialogue_panel.anchor_left = 0.5
	dialogue_panel.anchor_top = 1.0
	dialogue_panel.anchor_right = 0.5
	dialogue_panel.anchor_bottom = 1.0
	dialogue_panel.offset_left = -520.0
	dialogue_panel.offset_top = -320.0
	dialogue_panel.offset_right = 520.0
	dialogue_panel.offset_bottom = -24.0
	portrait.offset_left = 0.0
	portrait.offset_top = 32.0
	portrait.offset_right = 232.0
	portrait.offset_bottom = 256.0
	speaker_name.offset_left = 0.0
	speaker_name.offset_top = 0.0
	speaker_name.offset_right = 232.0
	speaker_name.offset_bottom = 36.0
	speaker_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.offset_left = 260.0
	message.offset_top = 24.0
	message.offset_right = -28.0
	message.offset_bottom = -20.0
	message.add_theme_font_size_override("normal_font_size", 38)


func advance() -> void:
	if not _is_playing:
		return
	if _is_typing:
		_finish_current_line()
	elif _line_index + 1 < _lines.size():
		_show_next_line()
	else:
		_finish_dialogue()


func skip() -> void:
	if _is_playing:
		_finish_dialogue()


func fade_out(duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(dialogue_panel, "modulate:a", 0.0, duration)
	_fade_tween.tween_callback(faded_out.emit)


func is_typing() -> bool:
	return _is_typing


func get_line_index() -> int:
	return _line_index


func _show_next_line() -> void:
	_line_index += 1
	message.text = _lines[_line_index]
	message.visible_characters = 0
	_total_characters = message.get_total_character_count()
	_character_progress = 0.0
	_is_typing = _total_characters > 0
	_hide_continue_indicator()
	set_process(_is_typing)
	if not _is_typing:
		_finish_current_line()


func _finish_current_line() -> void:
	_is_typing = false
	set_process(false)
	message.visible_characters = -1
	_show_continue_indicator()


func _finish_dialogue() -> void:
	_is_playing = false
	_is_typing = false
	set_process(false)
	_hide_continue_indicator()
	_emit_finished_once()


func _emit_finished_once() -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	finished.emit()


func _show_continue_indicator() -> void:
	if _indicator_tween and _indicator_tween.is_valid():
		_indicator_tween.kill()
	continue_indicator.visible = true
	continue_indicator.modulate.a = 0.0
	_indicator_tween = create_tween().set_loops()
	_indicator_tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.3)
	_indicator_tween.tween_property(continue_indicator, "modulate:a", 0.28, 0.8)
	_indicator_tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.8)



func _hide_continue_indicator() -> void:
	if _indicator_tween and _indicator_tween.is_valid():
		_indicator_tween.kill()
	continue_indicator.visible = false
	continue_indicator.modulate.a = 0.0


func _stop_active_tweens() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _indicator_tween and _indicator_tween.is_valid():
		_indicator_tween.kill()
