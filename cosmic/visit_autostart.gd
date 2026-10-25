extends RefCounted
## One-shot intention owned by a real library entry, not by redraw or focus.
var generation := 0
var pending := false
var selected_id := ""
func arm(id: String) -> int:
 generation += 1
 selected_id = id
 pending = not id.is_empty() and id != "unavailable"
 return generation
func cancel() -> void:
 generation += 1
 pending = false
func consume(token: int, id: String) -> bool:
 if not pending or token != generation or id != selected_id: return false
 pending = false
 return true
