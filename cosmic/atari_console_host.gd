extends Node3D
## Selector model only; no synthetic replacement when the explicit local media is absent.
const Media = preload("res://cosmic/atari_private_media.gd")
var media = Media.new()
var available := false
func _ready() -> void:
 var path := OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST")
 if media.configure(path, not path.is_empty()):
  var console: Node3D = media.load_model("console")
  if console != null:
   add_child(console)
   available = true
 set_meta("atari_media_available", available)
