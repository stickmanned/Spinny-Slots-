extends Node

const DAY_JOB_ECONOMY: EconomyConfig = preload("res://resources/economy/day_job_economy.tres")


func get_starting_balance() -> int:
	return DAY_JOB_ECONOMY.starting_balance


func get_day_job_bag_payout() -> int:
	return DAY_JOB_ECONOMY.day_job_bag_payout


func award_day_job_bag() -> int:
	var payout := get_day_job_bag_payout()
	GameState.add_money(payout)
	return payout
