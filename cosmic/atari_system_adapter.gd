extends RefCounted
## Descriptor only. No registration into the existing SMS selector or its resource type.
const PrivateMedia = preload("res://cosmic/atari_private_media.gd")
const Exhibit = preload("res://cosmic/atari_exhibit.gd")

static func descriptor() -> Dictionary:
 return {
  "system_id": "atari2600",
  "display_name": "Atari 2600",
  "variant_label": "Heavy Sixer · reconstrução visual",
  "controller_id": "cx10",
  "controller_action_ids": ["up", "down", "left", "right", "fire"],
  "packaging_kind": "cardboard_tuck_flap",
  "requires_private_media_opt_in": true,
  "proof_scene": "res://cosmic/atari_proof.tscn",
  "emulation_available": false,
  "interactive_insertion_available": false,
  "manual_reader_connected": false,
 }

static func availability(manifest_path: String = "", opted_in: bool = false) -> Dictionary:
 var media := PrivateMedia.new()
 var configured := media.configure(manifest_path, opted_in)
 var missing: Array[String] = []
 for key in PrivateMedia.CORE_KEYS:
  if media.model_path(key).is_empty():
   missing.append(key)
 return {
  "configured": configured,
  "core_files_present": configured and missing.is_empty(),
  "runtime_validated": false, # File presence is not successful Godot import or visual QA.
  "missing": missing,
  "notices": media.errors.duplicate(),
 }

static func create_exhibit(manifest_path: String = "", opted_in: bool = false) -> Node3D:
 var exhibit := Exhibit.new()
 exhibit.configure(manifest_path, opted_in)
 return exhibit
