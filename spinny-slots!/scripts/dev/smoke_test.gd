extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const EXPECTED_PROJECT_NAME := "Spinny Slots!"
const EXPECTED_HACKATIME_PROJECT := "Spinny-Slots-"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: PackedStringArray = []

	if ProjectSettings.get_setting("application/config/name") != EXPECTED_PROJECT_NAME:
		failures.append("Unexpected application/config/name.")

	if ProjectSettings.get_setting("application/run/main_scene") != MAIN_SCENE:
		failures.append("The configured main scene is not %s." % MAIN_SCENE)

	if ProjectSettings.get_setting("hackatime/project_name") != EXPECTED_HACKATIME_PROJECT:
		failures.append("The canonical Hackatime project name is incorrect.")

	if int(ProjectSettings.get_setting("display/window/size/viewport_width")) != 1280:
		failures.append("Viewport width must be 1280.")

	if int(ProjectSettings.get_setting("display/window/size/viewport_height")) != 720:
		failures.append("Viewport height must be 720.")

	var packed_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		failures.append("The main scene could not be loaded.")
	else:
		var instance := packed_scene.instantiate()
		if instance == null:
			failures.append("The main scene could not be instantiated.")
		else:
			instance.free()
			await process_frame

	if failures.is_empty():
		print("FOUNDATION_SMOKE_TEST: PASS")
		quit(0)
		return

	for failure in failures:
		push_error("FOUNDATION_SMOKE_TEST: %s" % failure)
	quit(1)
