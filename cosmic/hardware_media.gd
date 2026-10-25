extends RefCounted
## Explicit local hardware overrides. Never scans personal folders or downloads assets.
const LOCAL_ROOT := "res://assets/local_hardware_art/"
const MANIFEST := LOCAL_ROOT + "manifest.json"
const FALLBACK_CONTROLLER := "res://assets/exhibit_models/SMS_Controller_neutral.glb"

static func controller_path(manifest_path: String = MANIFEST) -> String:
 if not FileAccess.file_exists(manifest_path): return FALLBACK_CONTROLLER
 if FileAccess.get_file_as_bytes(manifest_path).size() > 16384: return FALLBACK_CONTROLLER
 var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
 if not data is Dictionary: return FALLBACK_CONTROLLER
 var value := str(data.get("controller_model", ""))
 # Only a filename explicitly placed next to this local manifest is accepted.
 if value.is_empty() or value != value.get_file() or value.contains(":") or value.get_extension().to_lower() != "glb": return FALLBACK_CONTROLLER
 var path := manifest_path.get_base_dir().path_join(value)
 if not FileAccess.file_exists(path): return FALLBACK_CONTROLLER
 return path
