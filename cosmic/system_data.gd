class_name CosmicSystemData
extends Resource
@export var system_id: String = ""
@export var display_name: String = ""
@export var subtitle: String = ""
@export var logo: Texture2D
@export var logo_source: String = ""
@export var model: PackedScene
@export var presentation_transform: Transform3D = Transform3D.IDENTITY
@export var camera_position := Vector3(0.34, 0.27, 0.52)
@export var camera_target := Vector3.ZERO
@export var framing_size := 0.55
@export_multiline var history_text: String = ""
@export_multiline var history_credits: String = ""
@export var history_sources: PackedStringArray = []
