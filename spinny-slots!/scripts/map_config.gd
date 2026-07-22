class_name MapConfig
extends RefCounted

const JUNKYARD_ID = "junkyard"
const METROPOLIS_ID = "metropolis"

static func get_maps() -> Array:
	return [
		{
			"id": JUNKYARD_ID,
			"name": "Junkyard",
			"background_path": "res://assets/art/junkyard/junkyard_background.png",
			"is_unlocked": true,
			"unlock_requirement": "",
		},
		{
			"id": METROPOLIS_ID,
			"name": "Metropolis",
			"background_path": "res://assets/art/metropolis/metropolis_background.png",
			"is_unlocked": GameState.metropolis_unlocked,
			"unlock_requirement": "Defeat the Junk King to unlock Metropolis.",
		}
	]
