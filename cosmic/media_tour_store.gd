extends "res://cosmic/media_optin_store.gd"
## Tour metadata only. In-progress after an interrupted run is never an auto-prompt.
const TOUR_VERSION := 1
const STATES := ["unseen", "in_progress", "configured", "skipped", "later"]
func _init() -> void:
 path = "user://retropass_media_tour.json"
func state() -> String:
 return str(load_state().get("state", "unseen"))
func save_tour(value: String) -> Error:
 if not value in STATES: return ERR_INVALID_PARAMETER
 return _save({"version":TOUR_VERSION, "state":value})
func _read(file_path: String) -> Dictionary:
 var file := FileAccess.open(file_path, FileAccess.READ)
 if file == null: return {}
 if file.get_length() > 4096:
  file.close()
  return {}
 var parsed: Variant = JSON.parse_string(file.get_as_text())
 file.close()
 if not parsed is Dictionary or parsed.size() != 2 or parsed.get("version") != TOUR_VERSION or not parsed.get("state") in STATES: return {}
 return {"version":TOUR_VERSION,"state":parsed.state}
