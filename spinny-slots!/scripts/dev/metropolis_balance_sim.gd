extends Node

## Throwaway balance simulation (not shipped). Runs N real spins per machine
## through MetropolisEconomy (same weights, payout tables, cascade/hack/luck
## resolution the game uses) and reports baseline RTP plus the RTP curve as the
## machine's per-machine Coin Multiplier / Luck upgrades are invested, then
## estimates grind time to the next machine's ticket once RTP passes 100%.
## Run headless:
##   godot --headless --path spinny-slots! res://scenes/dev/metropolis_balance_sim.tscn -- --spins=200000

const MACHINES: Array[MetropolisMachineDefinition] = [
	preload("res://resources/machines/neon_arcade.tres"),
	preload("res://resources/machines/drone_dispatch.tres"),
	preload("res://resources/machines/firewall_terminal.tres"),
	preload("res://resources/machines/billboard_jackpot.tres"),
	preload("res://resources/machines/quantum_vault.tres"),
]
const SECONDS_PER_SPIN := 2.2
const SIMULATION_SEED := 20260720

var _spins := 120000


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--spins="):
			_spins = maxi(int(argument.trim_prefix("--spins=")), 1000)

	var luck_config := MetropolisEconomy.get_upgrade_config(&"luck")
	var coin_config := MetropolisEconomy.get_upgrade_config(&"coin_multiplier")
	print("=== Metropolis balance simulation: %d spins/machine, seed %d ===" % [_spins, SIMULATION_SEED])
	print("Coin Multiplier: +%.0f%%/level, cap %d  |  Luck: +%.0f%%/level, cap %d\n" % [
		coin_config.effect_per_level * 100.0, coin_config.max_level,
		luck_config.effect_per_level * 100.0, luck_config.max_level,
	])

	for machine_index in range(MACHINES.size()):
		var machine := MACHINES[machine_index]
		var next_ticket := MACHINES[machine_index + 1].ticket_price if machine_index + 1 < MACHINES.size() else 0
		print("%s  (ticket $%d, %d reels)" % [machine.display_name, machine.ticket_price, machine.reel_count])

		# Baseline measured once. Coin Multiplier is a pure linear payout scalar,
		# so RTP at any Coin level is baseline_rtp * coin_mult — no re-sim needed.
		var baseline := _measure(machine, 1.0, 1.0)
		var baseline_rtp: float = baseline["rtp"]
		var coin_levels: Array[int] = [0, 4, 8, 12, coin_config.max_level]
		for coin_level in coin_levels:
			var coin_mult: float = 1.0 + coin_config.effect_per_level * float(coin_level)
			print("  Coin Lv %2d (x%.2f): RTP %6.1f%%   avg $%s   best(base) $%s" % [
				coin_level, coin_mult, baseline_rtp * coin_mult * 100.0,
				_fmt(float(baseline["avg"]) * coin_mult), _fmt(float(baseline["best"])),
			])

		# Luck changes weights (non-linear), so it must be simulated. Show its
		# ceiling stacked on a mid Coin investment.
		var luck_max_mult := 1.0 + luck_config.effect_per_level * luck_config.max_level
		var coin_mid := 1.0 + coin_config.effect_per_level * 8
		var maxed := _measure(machine, luck_max_mult, coin_mid)
		print("  Luck Lv %d (x%.2f) + Coin Lv 8: RTP %.1f%%" % [
			luck_config.max_level, luck_max_mult, float(maxed["rtp"]) * 100.0,
		])
		_report_mechanic_scenario(machine)

		_report_pacing(machine, coin_config, baseline_rtp, baseline["avg"], next_ticket)
		print("")

	get_tree().quit(0)


func _measure(
	machine: MetropolisMachineDefinition,
	luck_mult: float,
	coin_mult: float,
	extra_options: Dictionary = {}
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SIMULATION_SEED
	var options := extra_options.duplicate()
	options["luck_multiplier"] = luck_mult
	options["coin_multiplier"] = coin_mult
	var total := 0.0
	var best := 0
	for _spin_index in range(_spins):
		var outcome := MetropolisEconomy.calculate_machine_spin(machine, rng, options)
		var payout := int(outcome.get("payout", 0))
		total += payout
		if payout > best:
			best = payout
	var avg := total / float(_spins)
	return {"avg": avg, "rtp": avg / float(machine.ticket_price), "best": best}


func _report_mechanic_scenario(machine: MetropolisMachineDefinition) -> void:
	match machine.get_mechanic_kind():
		MetropolisMechanicConfig.Kind.SURGE_MULTIPLIER:
			var surged := _measure(machine, 1.0, 1.0, {"surge_multiplier": 3.0})
			print("  mechanic: locked Surge x3 -> RTP %.1f%%" % (float(surged["rtp"]) * 100.0))
		MetropolisMechanicConfig.Kind.HACK_CHARGE:
			var hacked := _measure(machine, 1.0, 1.0, {"spend_hack_charge_on_reel_index": 0})
			print("  mechanic: Hack Charge on reel 1 -> RTP %.1f%%" % (float(hacked["rtp"]) * 100.0))
		MetropolisMechanicConfig.Kind.CASCADE_MATCH:
			print("  mechanic: baseline includes the full precomputed Cascade chain")
		MetropolisMechanicConfig.Kind.SUPERPOSITION:
			print("  mechanic: Superposition is presentation-only; RTP unchanged")


func _report_pacing(
	machine: MetropolisMachineDefinition,
	coin_config: UpgradeConfig,
	baseline_rtp: float,
	baseline_avg: float,
	next_ticket: int
) -> void:
	if next_ticket <= 0:
		print("  pacing: final machine (no next ticket)")
		return
	# Smallest Coin level whose (linear) RTP clears 105%.
	for coin_level in range(1, coin_config.max_level + 1):
		var coin_mult := 1.0 + coin_config.effect_per_level * coin_level
		var rtp := baseline_rtp * coin_mult
		if rtp >= 1.05:
			var net_per_spin := baseline_avg * coin_mult - float(machine.ticket_price)
			var upgrade_cost := 0.0
			var base := float(machine.ticket_price) * coin_config.cost_fraction_of_ticket
			for level in range(coin_level):
				upgrade_cost += base * pow(coin_config.cost_growth, level)
			var spins_to_next := float(next_ticket) / net_per_spin
			print("  pacing: Coin Lv %d reaches RTP %.0f%% (net $%s/spin); ~$%s to buy those levels;" % [
				coin_level, rtp * 100.0, _fmt(net_per_spin), _fmt(upgrade_cost),
			])
			print("          then ~%d spins (~%.0f min) to bank the next ticket ($%s)" % [
				int(spins_to_next), spins_to_next * SECONDS_PER_SPIN / 60.0, _fmt(float(next_ticket)),
			])
			return
	print("  pacing: even Coin Lv %d stays under 105%% RTP" % coin_config.max_level)


func _fmt(value: float) -> String:
	if absf(value) >= 1_000_000.0:
		return "%.2fM" % (value / 1_000_000.0)
	if absf(value) >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	return "%.0f" % value
