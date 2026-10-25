extends RefCounted
## Plans only explicit inventory media_metadata references. No filesystem access.
const Association = preload("res://cosmic/media_result_association.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const Inventory = preload("res://cosmic/catalog_import.gd")
const TAG_CATEGORY := {
 "cover_front":"covers", "boxart":"covers", "cover_back":"covers", "boxback":"covers",
 "cover_spine":"covers", "boxspine":"covers", "spine":"covers", "cover_edge":"covers",
 "cartridge_label":"covers", "cartridge_top":"covers", "image":"images", "thumbnail":"images",
 "fanart":"images", "cartridge":"images", "titleshot":"images", "screenshot":"images",
 "map":"images", "bezel":"images", "wheel":"wheel", "marquee":"wheel", "manual":"manual"}

static func build(config: Dictionary, items: Array) -> Dictionary:
 var result := {"ok": true, "operation": "local_processing", "files": [], "issues": [],
  "games_total": 0, "files_total": 0, "config": config.duplicate(true)}
 if config.get("decision", "") in ["skipped", "later"]: return result
 var checked := Config.choose(str(config.get("system", "")), str(config.get("root", "")), config.get("categories", []))
 if not checked.ok or config.get("decision", "") != "configured":
  return {"ok": false, "error": "invalid_config"}
 var files := {}
 var games := {}
 for item in items:
  if not item is Dictionary or item.get("system", "") != config.system: continue
  var game_id := str(item.get("id", ""))
  if game_id.is_empty(): continue
  var media: Variant = item.get("media_metadata", {})
  if not media is Dictionary: media = {}
  for category in config.categories:
   var associated := false
   for tag in media:
    if TAG_CATEGORY.get(tag, "") == category: associated = true
   if not associated:
    var issue := {"game_id":game_id, "tag":"", "category":category, "status":"not_associated"}
    if not issue in result.issues: result.issues.append(issue)
    games[game_id] = true
  for tag in media:
   if not TAG_CATEGORY.has(tag) or not TAG_CATEGORY[tag] in config.categories: continue
   var descriptor: Variant = media[tag]
   if not descriptor is Dictionary: descriptor = {}
   var relative := Inventory.safe_relative_path(descriptor.get("relative_path", ""))
   var extension := relative.get_extension().to_lower()
   var allowed := extension == "pdf" or extension in Inventory.IMAGE_EXTENSIONS if tag == "manual" else extension in Inventory.IMAGE_EXTENSIONS
   if relative.is_empty() or not allowed or descriptor.get("status", "") != "present":
    var issue := {"game_id": game_id, "tag": tag, "category": TAG_CATEGORY[tag], "status": "unavailable_or_unsupported"}
    if not issue in result.issues: result.issues.append(issue)
    games[game_id] = true
    continue
   # Exact spelling only: no basename, fuzzy, edition or external-ID inference.
   var path: String = str(config.root).path_join(relative)
   var id := path.sha256_text()
   if not files.has(id):
    files[id] = {"id": id, "relative_path": relative, "links": []}
   var link := {"game_id": game_id, "tag": tag, "identity_status": "unverified", "catalog_identity": Association.identity_signature(item)}
   if not link in files[id].links: files[id].links.append(link)
   games[game_id] = true
 result.files = files.values()
 result.files_total = files.size()
 result.games_total = games.size()
 return result
