class_name ButtonHover
extends RefCounted

## Shared hover feedback so every button grows the same way the Junkyard spin
## button and upgrade rows already do.

const HOVER_SCALE := Vector2(1.05, 1.05)
const DURATION := 0.12


## Connects hover enter/exit scaling to one button. Safe to call once per
## button during setup; the tween is created on the button itself so it dies
## with the node.
static func attach(button: BaseButton, hover_scale: Vector2 = HOVER_SCALE) -> void:
	if button == null:
		return
	button.mouse_entered.connect(_animate.bind(button, hover_scale))
	button.mouse_exited.connect(_animate.bind(button, Vector2.ONE))


## Connects every BaseButton found under a node, including nested containers.
static func attach_tree(root: Node, hover_scale: Vector2 = HOVER_SCALE) -> void:
	if root == null:
		return
	if root is BaseButton:
		attach(root, hover_scale)
	for child in root.get_children():
		attach_tree(child, hover_scale)


static func _animate(button: BaseButton, target_scale: Vector2) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	if GameState.reduced_motion:
		button.scale = target_scale
		return
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, DURATION)
