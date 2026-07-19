extends Button


func configure(upgrade: Dictionary) -> void:
	text = str(upgrade.get("name", "Upgrade"))
	disabled = bool(upgrade.get("disabled", true))
	tooltip_text = str(upgrade.get("tooltip", "Coming in a later milestone"))
