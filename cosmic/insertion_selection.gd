extends RefCounted
## Host-authenticated entries only. Never scan ROMs, infer filename identities,
## synthesize media, or reuse another game's assets. Empty means unavailable.
static func choose(entries: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
 var ready: Array[Dictionary] = []
 for entry in entries:
  if str(entry.get("system_id", "")) not in ["sms", "sega_master_system", "atari2600"]: continue
  if str(entry.get("game_id", "")).is_empty(): continue
  if not bool(entry.get("matching_media_present", false)): continue
  if not bool(entry.get("insertion_geometry_validated", false)): continue
  ready.append(entry)
 if ready.is_empty(): return {}
 return ready[rng.randi_range(0, ready.size() - 1)].duplicate(true)
