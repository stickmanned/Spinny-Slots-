extends Node

const JOB_SCENE: PackedScene = preload("res://scenes/junkyard_job.tscn")
const PROGRESSION: JunkyardProgressionConfig = preload("res://resources/story/junkyard_progression.tres")


func _ready() -> void:
	GameState.reset_for_new_game()
	GameState.day_job_intro_seen = true
	GameState.day_job_tutorial_completed = true
	GameState.phone_notification_received = true
	GameState.phone_call_started = true
	GameState.phone_call_completed = true
	GameState.ticket_purchase_tutorial_completed = true
	GameState.selected_machine_id = PROGRESSION.machines[0].machine_id
	GameState.unlock_machine(PROGRESSION.machines[0].machine_id)
	GameState.money = 500
	GameState.add_machine_ticket(PROGRESSION.machines[0].machine_id, 5)
	add_child(JOB_SCENE.instantiate())
