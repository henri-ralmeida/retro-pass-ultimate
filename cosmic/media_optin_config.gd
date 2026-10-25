extends RefCounted
## Pure opt-in configuration: no directory or media reads.
const CATEGORIES := ["covers", "images", "wheel", "manual"]
const SYSTEMS := ["master_system", "mark_iii", "atari_2600"]

static func choose(system: String, root: String, categories: Array) -> Dictionary:
 if not system in SYSTEMS or not valid_root(root):
  return {"ok": false, "error": "invalid_system_or_root"}
 var selected: Array = []
 for category in categories:
  if not category in CATEGORIES: return {"ok": false, "error": "invalid_category"}
  if not category in selected: selected.append(category)
 selected.sort()
 var normalized := root.replace("\\", "/").simplify_path()
 if normalized.length() > 3: normalized = normalized.trim_suffix("/")
 return {"ok": true, "version": 1, "decision": "configured", "system": system,
  "root": normalized, "categories": selected}

static func defer_setup(skipped: bool = false) -> Dictionary:
 return {"ok": true, "version": 1, "decision": "skipped" if skipped else "later",
  "system": "", "root": "", "categories": []}

static func valid_root(root: String) -> bool:
 var p := root.replace("\\", "/")
 if p.begins_with("//") or "://" in p or p.strip_edges() != p: return false
 if p.length() < 2 or not p.is_absolute_path(): return false
 for c in p:
  if c.unicode_at(0) < 32: return false
 return true
