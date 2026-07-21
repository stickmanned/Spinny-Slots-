class_name JunkyardProgressionConfig
extends Resource

@export_range(1, 1000000, 1) var phone_call_threshold: int = 30
@export var phone_call_speaker: String = "Rich Kid"
@export var phone_call_dialogue: DialogueData
@export var phone_texture: Texture2D
@export var rich_kid_portrait: Texture2D
@export var machines: Array[MachineDefinition] = []
@export var junk_king_machine_id: StringName = &"magnet_machine"
@export var junk_king_name: String = "Junk King"
@export var junk_king_intro_dialogue: DialogueData
@export var junk_king_portrait: Texture2D
@export var junk_king_texture: Texture2D
