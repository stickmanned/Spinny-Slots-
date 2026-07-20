extends HBoxContainer

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %NameLabel
@onready var value_label: Label = %ValueLabel
@onready var percent_label: Label = %PercentLabel


func configure(symbol: SlotSymbol, probability: float) -> void:
	icon.texture = symbol.icon
	name_label.text = symbol.display_name
	value_label.text = "$%d" % symbol.payout
	percent_label.text = "%d%%" % roundi(probability * 100.0)
