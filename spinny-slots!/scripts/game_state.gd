extends Node

signal money_changed(value: int)
signal gems_changed(value: int)
signal music_volume_changed(value: float)

var money: int = 0:
	set(value):
		money = maxi(value, 0)
		money_changed.emit(money)

# TODO(gems): jackpot currency, see GAME_PLAN 7
var gems: int = 0:
	set(value):
		gems = maxi(value, 0)
		gems_changed.emit(gems)

var music_volume: float = 0.3:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		music_volume_changed.emit(music_volume)


var day_job_intro_seen := false
var day_job_tutorial_completed := false


func _ready() -> void:
	reset_for_new_game()


func reset_for_new_game() -> void:
	money = Economy.get_starting_balance()
	gems = 0
	day_job_intro_seen = false
	day_job_tutorial_completed = false


func add_money(amount: int) -> void:
	assert(amount >= 0, "Money awards cannot be negative.")
	money += amount
