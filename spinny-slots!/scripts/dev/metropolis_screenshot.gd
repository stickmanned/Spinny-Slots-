extends Node

## Dev-only: loads the Metropolis job scene, gives it a few Metropolis tickets
## and cash so every panel is populated, waits for layout to settle, then saves
## a screenshot to user:// and quits. Not shipped; used to eyeball UI bugs.

const JOB_SCENE: PackedScene = preload("res://scenes/metropolis_job.tscn")
const MACHINES: Array[MetropolisMachineDefinition] = [
	preload("res://resources/machines/neon_arcade.tres"),
	preload("res://resources/machines/drone_dispatch.tres"),
	preload("res://resources/machines/firewall_terminal.tres"),
	preload("res://resources/machines/billboard_jackpot.tres"),
	preload("res://resources/machines/quantum_vault.tres"),
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var target_index := 0
	var scroll_tickets := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--machine="):
			target_index = clampi(int(argument.trim_prefix("--machine=")), 0, MACHINES.size() - 1)
		elif argument == "--scroll-tickets":
			scroll_tickets = true
	GameState.reset_for_new_game()
	GameState.metropolis_unlocked = true
	GameState.money = 5_000_000
	for machine in MACHINES:
		GameState.add_machine_ticket(machine.machine_id, 5)
	GameState.selected_machine_id = MACHINES[target_index].machine_id

	var job := JOB_SCENE.instantiate()
	add_child(job)
	# Cycle the selector to the requested machine so mechanic panels show.
	var selector := job.get_node("%MachineSelectorPanel")
	for _frame in range(6):
		await get_tree().process_frame
	selector.call("configure", MACHINES, MACHINES[target_index].machine_id)
	if job.has_method("_on_selection_changed"):
		job.call("_on_selection_changed", MACHINES[target_index])
	for _frame in range(10):
		await get_tree().process_frame
	if scroll_tickets:
		var ticket_scroll := job.get_node("%TicketShopPanel").get_node("Content/TicketScroll") as ScrollContainer
		ticket_scroll.scroll_vertical = 100000
		for _frame in range(3):
			await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var window_size := DisplayServer.window_get_size()
	var out_path := "user://metropolis_shot_%d_%dx%d.png" % [
		target_index, window_size.x, window_size.y,
	]
	image.save_png(out_path)
	print("Saved screenshot to: ", ProjectSettings.globalize_path(out_path))
	get_tree().quit(0)
