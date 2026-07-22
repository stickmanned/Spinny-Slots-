extends Control

signal map_requested(map_id: String)
signal spin_started(machine_id: StringName)
signal spin_completed(machine_id: StringName, payout: int)

const MACHINES: Array[MetropolisMachineDefinition] = [
	preload("res://resources/machines/neon_arcade.tres"),
	preload("res://resources/machines/drone_dispatch.tres"),
	preload("res://resources/machines/firewall_terminal.tres"),
	preload("res://resources/machines/billboard_jackpot.tres"),
	preload("res://resources/machines/quantum_vault.tres"),
]

const MIN_REEL_DURATION := 0.3
const CASCADE_TIER_REVEAL_DELAY := 0.55
# Same cell-phone gadget art and crop Junkyard uses, so the idle HUD phone
# icon is visually identical across both areas.
const PHONE_BASE_TEXTURE: Texture2D = preload("res://resources/gadgets/Cell Phone.png")
const PHONE_ATLAS_REGION := Rect2(710, 480, 610, 990)
const UPGRADE_PROVIDER := preload("res://scripts/metropolis_upgrade_provider.gd")

@onready var hud: CanvasLayer = %Hud
@onready var ticket_shop: PanelContainer = %TicketShopPanel
@onready var paytable_panel: PanelContainer = %PaytablePanel
@onready var selector: PanelContainer = %MachineSelectorPanel
@onready var result_label: Label = %ResultLabel
@onready var payout_label: Label = %PayoutLabel
@onready var spin_button: Button = %SpinButton
@onready var coin_collection_effect: CoinCollectionEffect = %CoinCollectionEffect
@onready var confetti_effect: ConfettiEffect = %ConfettiEffect
@onready var phone_notification: CanvasLayer = %PhoneNotification
@onready var surge_panel: Control = %SurgePanel
@onready var surge_value_label: Label = %SurgeValueLabel
@onready var surge_lock_button: Button = %SurgeLockButton
@onready var surge_reroll_button: Button = %SurgeRerollButton
@onready var hack_panel: Control = %HackPanel
@onready var hack_charge_label: Label = %HackChargeLabel
@onready var hack_reel_buttons: HBoxContainer = %HackReelButtons

var _selected_machine: MetropolisMachineDefinition
var _spin_in_progress := false
var _surge_current_value := 1.0
var _surge_locked := false
var _surge_rerolls_used := 0
var _hack_target_reel_index := -1


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.machine_tickets_changed.connect(_on_machine_tickets_changed)
	GameState.machine_mechanic_charges_changed.connect(_on_mechanic_charges_changed)
	GameState.machine_free_rerolls_changed.connect(_on_free_rerolls_changed)
	hud.map_requested.connect(func(id: String) -> void: map_requested.emit(id))
	ticket_shop.connect("purchase_requested", _on_purchase_requested)
	ticket_shop.connect("machine_selected", _on_ticket_machine_selected)
	selector.connect("selection_changed", _on_selection_changed)
	selector.call("set_select_button_visible", false)
	spin_button.pressed.connect(_on_spin_pressed)
	surge_lock_button.pressed.connect(_on_surge_lock_pressed)
	surge_reroll_button.pressed.connect(_on_surge_reroll_pressed)
	coin_collection_effect.balance_progressed.connect(Callable(hud, "set_presented_money"))
	coin_collection_effect.balance_pulse_requested.connect(Callable(hud, "pulse_coin_balance"))
	coin_collection_effect.coin_sound_requested.connect(AudioFx.play_coin_drop)

	selector.call("configure", MACHINES, GameState.selected_machine_id)
	ticket_shop.call("configure_machines", MACHINES, GameState.selected_machine_id)
	_selected_machine = selector.call("get_selected_machine")
	if _selected_machine != null:
		GameState.selected_machine_id = _selected_machine.machine_id
	hud.call("enter_machine_mode", 0.0)
	hud.call("set_area_name", "METROPOLIS")
	hud.call("set_current_map_id", MapConfig.METROPOLIS_ID)
	ticket_shop.call("set_extension_mode", true)
	# No Metropolis rival/boss is defined yet, so the phone shows only its
	# idle icon — the "incoming call" boss trigger is intentionally not wired.
	phone_notification.call("show_idle", _build_phone_texture())
	_refresh_for_selected_machine()


func _build_phone_texture() -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = PHONE_BASE_TEXTURE
	atlas.region = PHONE_ATLAS_REGION
	return atlas


func _on_money_changed(_value: int) -> void:
	ticket_shop.call("refresh")


func _on_machine_tickets_changed(_machine_id: StringName, _count: int) -> void:
	ticket_shop.call("refresh")
	_refresh_spin_button()


func _on_mechanic_charges_changed(machine_id: StringName, _count: int) -> void:
	if _selected_machine != null and machine_id == _selected_machine.machine_id:
		_refresh_hack_panel()


func _on_free_rerolls_changed(machine_id: StringName, _count: int) -> void:
	if _selected_machine != null and machine_id == _selected_machine.machine_id:
		_refresh_surge_panel()


func _on_purchase_requested(machine) -> void:
	if not MetropolisEconomy.purchase_ticket(machine):
		ticket_shop.call("refresh")
		return
	ticket_shop.call("refresh")


func _on_ticket_machine_selected(machine) -> void:
	selector.call("configure", MACHINES, machine.machine_id)
	_set_selected_machine(machine)


func _on_selection_changed(machine) -> void:
	_set_selected_machine(machine)


func _set_selected_machine(machine) -> void:
	_selected_machine = machine
	GameState.selected_machine_id = machine.machine_id
	ticket_shop.call("select_machine", machine.machine_id)
	result_label.text = ""
	payout_label.text = ""
	_refresh_for_selected_machine()


func _refresh_for_selected_machine() -> void:
	paytable_panel.call("configure", _selected_machine)
	_hack_target_reel_index = -1
	_surge_locked = false
	_surge_rerolls_used = 0
	_roll_surge_value()
	_refresh_surge_panel()
	_refresh_hack_panel()
	_refresh_spin_button()
	if _selected_machine == null:
		return
	# Point the shared upgrade panel at this machine's own per-machine track.
	hud.call("set_upgrade_provider", UPGRADE_PROVIDER.new(_selected_machine))
	var strip: Control = selector.call("get_active_reel_strip")
	var icons: Array[Texture2D] = []
	for symbol in _selected_machine.symbols:
		icons.append(symbol.icon)
	strip.call("set_idle_symbols", icons)


func _mechanic_kind() -> int:
	return (
		_selected_machine.get_mechanic_kind()
		if _selected_machine != null
		else MetropolisMechanicConfig.Kind.NONE
	)


## Rolls a fresh dial value. Only called when a new spin cycle begins (machine
## selected, or a spin resolved) or when the player rerolls — never from a
## generic UI refresh, so the displayed value stays stable between spins.
func _roll_surge_value() -> void:
	if _mechanic_kind() == MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER:
		_surge_current_value = MetropolisEconomy.roll_surge_multiplier_now(_selected_machine)
	else:
		_surge_current_value = 1.0


func _refresh_surge_panel() -> void:
	var is_surge := _mechanic_kind() == MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER
	surge_panel.visible = is_surge
	if not is_surge:
		return
	surge_value_label.text = "Surge %s" % _format_multiplier(_surge_current_value)
	var free_rerolls := GameState.get_machine_free_rerolls(_selected_machine.machine_id)
	var rerolls_left := _selected_machine.mechanic.surge_max_rerolls_per_spin - _surge_rerolls_used
	surge_reroll_button.disabled = _spin_in_progress or _surge_locked or rerolls_left <= 0
	surge_reroll_button.text = (
		"REROLL (FREE TOKEN)"
		if free_rerolls > 0
		else "REROLL ($%d)" % _selected_machine.mechanic.surge_reroll_cost
	)
	surge_lock_button.disabled = _spin_in_progress or _surge_locked


## GDScript's % formatter has no %g; format surge multipliers as x1 / x1.5 / x5
## without trailing zeros.
func _format_multiplier(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "x%d" % int(round(value))
	return "x%.1f" % value


func _on_surge_lock_pressed() -> void:
	_surge_locked = true
	_refresh_surge_panel()


func _on_surge_reroll_pressed() -> void:
	var result := MetropolisEconomy.reroll_surge_multiplier_now(_selected_machine, _surge_rerolls_used)
	if not bool(result.get("ok", false)):
		result_label.text = String(result.get("message", ""))
		return
	_surge_rerolls_used += 1
	_surge_current_value = float(result.get("value", 1.0))
	_refresh_surge_panel()


func _refresh_hack_panel() -> void:
	var is_hack := _mechanic_kind() == MetropolisMechanicConfig.Kind.HACK_CHARGE
	hack_panel.visible = is_hack
	if not is_hack:
		return
	var charges := GameState.get_machine_mechanic_charges(_selected_machine.machine_id)
	hack_charge_label.text = "Hack Charges: %d/%d" % [charges, _selected_machine.mechanic.hack_max_charges]
	for child in hack_reel_buttons.get_children():
		child.queue_free()
	for reel_index in range(_selected_machine.reel_count):
		var button := Button.new()
		button.text = "Reel %d" % (reel_index + 1)
		button.toggle_mode = true
		button.button_pressed = reel_index == _hack_target_reel_index
		button.disabled = _spin_in_progress or charges <= 0
		button.pressed.connect(_on_hack_reel_button_pressed.bind(reel_index))
		hack_reel_buttons.add_child(button)


func _on_hack_reel_button_pressed(reel_index: int) -> void:
	_hack_target_reel_index = -1 if _hack_target_reel_index == reel_index else reel_index
	_refresh_hack_panel()


func _refresh_spin_button() -> void:
	if _selected_machine == null:
		spin_button.disabled = true
		spin_button.text = "SPIN"
		return
	var ticket_count := GameState.get_machine_ticket_count(_selected_machine.machine_id)
	spin_button.text = "SPIN (%d)" % ticket_count
	spin_button.disabled = _spin_in_progress or ticket_count <= 0


func _on_spin_pressed() -> void:
	if _spin_in_progress or _selected_machine == null:
		return
	var spun_machine := _selected_machine

	var options := {}
	if _mechanic_kind() == MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER:
		options["surge_multiplier"] = _surge_current_value
	if _mechanic_kind() == MetropolisMechanicConfig.Kind.HACK_CHARGE and _hack_target_reel_index >= 0:
		options["spend_hack_charge_on_reel_index"] = _hack_target_reel_index

	var outcome := MetropolisEconomy.prepare_machine_spin(spun_machine, options)
	if outcome.is_empty():
		_refresh_spin_button()
		return

	_spin_in_progress = true
	spin_started.emit(spun_machine.machine_id)
	result_label.text = "SPINNING..."
	payout_label.text = ""
	_set_spin_interactions_enabled(false)
	_refresh_spin_button()

	var strip: Control = selector.call("get_active_reel_strip")
	var pool_icons: Array[Texture2D] = []
	for symbol in spun_machine.symbols:
		pool_icons.append(symbol.icon)

	var speed_multiplier := MetropolisEconomy.get_spin_speed_multiplier(spun_machine.machine_id)
	var total_duration: float = AudioFx.get_spin_duration_for_multiplier(speed_multiplier)
	var blink_duration: float = strip.call("get_blink_duration")
	var reel_duration := maxf(total_duration - blink_duration, MIN_REEL_DURATION)
	AudioFx.play_spin(speed_multiplier)
	selector.call("play_spin_flourish", reel_duration)

	var tiers: Array = outcome.get("tiers", [])
	var final_symbols: Array = outcome.get("symbols", [])
	if tiers.is_empty():
		strip.call(
			"play_spin", _icons_for_row(final_symbols), pool_icons, reel_duration,
			GameState.reduced_motion, _superposition_flags_for_row(final_symbols)
		)
		await get_tree().create_timer(total_duration).timeout
	else:
		# Cascade Match machines can produce more than one tier here; every
		# tier's row and payout was already fully computed by MetropolisEconomy
		# before this spin started, so this loop only plays results back.
		for tier_index in range(tiers.size()):
			if not is_inside_tree():
				return
			var tier: Dictionary = tiers[tier_index]
			var tier_row: Array = tier.get("row", [])
			var row_icons := _icons_for_row(tier_row)
			if tier_index == 0:
				strip.call(
					"play_spin", row_icons, pool_icons, reel_duration,
					GameState.reduced_motion, _superposition_flags_for_row(tier_row)
				)
				await get_tree().create_timer(total_duration).timeout
			var tier_payout := int(tier.get("payout", 0))
			if tier_payout > 0:
				payout_label.text = "TIER %d +$%d" % [tier_index + 1, tier_payout]
			var next_row: Array = (
				tiers[tier_index + 1].get("row", [])
				if tier_index + 1 < tiers.size()
				else final_symbols
			)
			await strip.call(
				"play_cascade_refill", _icons_for_row(next_row), GameState.reduced_motion
			)
			if not GameState.reduced_motion:
				await get_tree().create_timer(CASCADE_TIER_REVEAL_DELAY).timeout

	AudioFx.stop_spin()
	if not is_inside_tree():
		return

	var names: Array[String] = []
	for symbol in final_symbols:
		if symbol != null:
			names.append(symbol.display_name)
	result_label.text = "  •  ".join(names)
	var pending_payout := maxi(int(outcome.get("payout", 0)), 0)
	payout_label.text = "+%d COINS" % pending_payout
	if bool(outcome.get("jackpot_landed", false)):
		confetti_effect.play(GameState.reduced_motion)
	await coin_collection_effect.play(
		pending_payout,
		GameState.money,
		payout_label,
		hud.call("get_coin_balance_target"),
		GameState.reduced_motion
	)
	if not is_inside_tree():
		return
	var awarded_payout := MetropolisEconomy.award_machine_spin(spun_machine, outcome)
	_spin_in_progress = false
	_hack_target_reel_index = -1
	_surge_locked = false
	_surge_rerolls_used = 0
	_roll_surge_value()
	_set_spin_interactions_enabled(true)
	_refresh_surge_panel()
	_refresh_hack_panel()
	_refresh_spin_button()
	spin_completed.emit(spun_machine.machine_id, awarded_payout)


func _set_spin_interactions_enabled(enabled: bool) -> void:
	ticket_shop.call("set_purchase_enabled", enabled)
	selector.call("set_controls_enabled", enabled)
	hud.call("set_controls_enabled", enabled)
	hud.call("set_upgrades_enabled", enabled)


func _icons_for_row(row: Array) -> Array[Texture2D]:
	var icons: Array[Texture2D] = []
	for symbol in row:
		icons.append(symbol.icon if symbol != null else null)
	return icons


## Flags the reels whose settled symbol is Quantum Vault's Superposition Symbol
## (its jackpot-tier symbol) so the reel strip can play the collapse effect on
## exactly those positions. Empty/false for every non-Superposition machine.
func _superposition_flags_for_row(row: Array) -> Array:
	var flags: Array = []
	var is_superposition := _mechanic_kind() == MetropolisMechanicConfig.Kind.SUPERPOSITION
	for symbol in row:
		flags.append(
			is_superposition and symbol != null and symbol.tier == MetropolisSymbol.Tier.JACKPOT
		)
	return flags
