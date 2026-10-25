extends RefCounted
## Pure catalog selection, independent of nodes, rendering, focus and ROM access.
## The host starts a visit on entry and ends it on exit. Repeated begin_visit()
## calls while active are harmless: only a new visit draws a random entry.
## IDs identify catalog records, not verified releases or the presence of media.

var _rng: RandomNumberGenerator
var _ids: Array[String] = []
var _source_indexes: Dictionary = {}
var _sorted_indexes: Dictionary = {}
var _selected_id := ""
var _last_selected_id := ""
var _visit_active := false
var _status := "empty"

func _init(random_source: RandomNumberGenerator = null, seed_value: Variant = null) -> void:
 _rng = random_source if random_source != null else RandomNumberGenerator.new()
 if seed_value != null:
  _rng.seed = int(seed_value)
 elif random_source == null:
  _rng.randomize()

func update_catalog(items: Array[Dictionary]) -> String:
 ## Copy only stable IDs and source indexes. Caller mutations cannot silently
 ## change this snapshot; submit them explicitly with another update_catalog().
 ## Updating never consumes RNG. Removal during a visit uses the first valid ID
 ## in canonical order; an empty catalog returns "", never a fake game ID.
 _ids.clear()
 _source_indexes.clear()
 _sorted_indexes.clear()
 for index in items.size():
  var item: Dictionary = items[index]
  var raw_id: Variant = item.get("id", "")
  if not (raw_id is String or raw_id is StringName): continue
  var id := str(raw_id)
  if id.strip_edges().is_empty() or id.strip_edges().to_lower() == "unavailable": continue
  if item.get("placeholder", false) == true or item.get("is_placeholder", false) == true: continue
  if _source_indexes.has(id): continue
  _source_indexes[id] = index
  # Missing records remain explicitly selectable for catalog inspection, but
  # never gain a chance in the random exhibit pool.
  if item.get("available_for_random",true) != true or str(item.get("file_status","")) == "missing": continue
  _ids.append(id)
 _ids.sort()
 for index in _ids.size(): _sorted_indexes[_ids[index]] = index
 if _ids.is_empty():
  if not _source_indexes.has(_selected_id): _selected_id = ""
  _status = "empty" if _source_indexes.is_empty() else "unavailable"
 elif _source_indexes.has(_selected_id):
  _status = "explicit_unavailable" if not _sorted_indexes.has(_selected_id) else ("single" if _ids.size() == 1 else "preserved")
 elif _visit_active:
  _selected_id = _ids[0]
  _last_selected_id = _selected_id
  _status = "single" if _ids.size() == 1 else "recovered"
 else:
  _selected_id = ""
  _status = "ready"
 return _selected_id

func begin_visit() -> String:
 ## Idempotent until end_visit(). With >1 eligible record, the last displayed
 ## record is excluded in one bounded draw, including after explicit navigation.
 if _visit_active: return _selected_id
 _visit_active = true
 if _ids.is_empty():
  _selected_id = ""
  _status = "empty" if _source_indexes.is_empty() else "unavailable"
  return _selected_id
 if _ids.size() == 1:
  _selected_id = _ids[0]
  _status = "single"
 else:
  var excluded_index := int(_sorted_indexes.get(_last_selected_id, -1))
  var candidate_count := _ids.size() - (1 if excluded_index >= 0 else 0)
  var selected_index := _rng.randi_range(0, candidate_count - 1)
  if excluded_index >= 0 and selected_index >= excluded_index:
   selected_index += 1
  _selected_id = _ids[selected_index]
  _status = "random"
 _last_selected_id = _selected_id
 return _selected_id

func end_visit() -> void:
 ## Retain the last displayed ID for the next visit's no-repeat rule.
 _visit_active = false

func select_explicit(id: String) -> bool:
 ## Navigation is intentional, not a new random draw. Invalid or stale IDs
 ## leave the current selection unchanged. Selection starts a visit if needed.
 if not _source_indexes.has(id): return false
 _visit_active = true
 _selected_id = id
 _last_selected_id = id
 _status = "explicit_unavailable" if not _sorted_indexes.has(id) else ("single" if _ids.size() == 1 else "explicit")
 return true

func get_selected_id() -> String:
 return _selected_id

func get_selected_index() -> int:
 ## Index of the first eligible occurrence in the latest source Array; -1 empty.
 return int(_source_indexes.get(_selected_id, -1))

func get_status() -> String:
 ## empty, unavailable, ready, single, random, explicit, explicit_unavailable, preserved or recovered.
 return _status

func get_eligible_count() -> int:
 return _ids.size()

func get_eligible_ids() -> Array[String]:
 return _ids.duplicate()

func is_visit_active() -> bool:
 return _visit_active
