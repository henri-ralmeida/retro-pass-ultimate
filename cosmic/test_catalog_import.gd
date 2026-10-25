extends SceneTree
## Public fixtures are synthetic metadata, not a personal collection. The only
## optional private input is RETROPASS_PRIVATE_CATALOG; it prints counts, never
## titles or paths. RETROPASS_PRIVATE_OUTPUT can export its adapted SMS metadata
## outside the project. Neither mode opens or decodes ROMs or media.

const Import = preload("res://cosmic/catalog_import.gd")
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
 run.call_deferred()

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func entry(path: String = "Sega - Master System/Synthetic (Region A).zip", status: String = "present", group: String = "Master System") -> Dictionary:
 return {"game_id": "shared_scraper_id", "name": "Synthetic record", "path": path, "file_status": status, "source_group": group, "region_hint": "synthetic", "language_hint": "synthetic", "filename_variant_hints": ["Region A"], "media": {}}

func media(path: String, status: String = "present") -> Dictionary:
 return {"path": path, "status": status, "extension": ".ignored"}

func run() -> void:
 _test_scoping_status_and_identity()
 _test_path_validation()
 _test_media_contract()
 _test_inventory_labels()
 _test_json_io_and_errors()
 _test_private_catalog()
 print("CATALOG_IMPORT: ", assertions, " assertions; ", failures.size(), " failures")
 quit(0 if failures.is_empty() else 1)

func _test_scoping_status_and_identity() -> void:
 var a := entry()
 var b := entry("Sega - Master System/Synthetic (Region B).zip")
 var missing := entry("Sega - Master System/Synthetic missing.zip", "missing")
 var unknown := entry("Sega - Master System/Synthetic unknown.zip", "unverified")
 var mark := entry("Sega - Mark III/Synthetic.zip", "present", "Mark III")
 var source := {"games": [a, b, missing, unknown, mark]}
 var snapshot := JSON.stringify(source)
 var result := Import.adapt(source)
 check(result.ok and result.items.size() == 4, "Default selects SMS only")
 check(JSON.stringify(source) == snapshot, "Adapting does not mutate caller metadata")
 check(result.counts.present == 2 and result.counts.missing == 1 and result.counts.unknown == 1, "All source statuses are counted, missing entries remain visible")
 check(result.counts.available_for_random == 2 and result.counts.filtered_groups == 1, "Only source-present SMS entries are random eligible")
 check(result.items[0].id != result.items[1].id, "Shared scraper IDs do not collapse regional variants")
 check(result.items[0].id.length() == 64, "Entry ID is a full SHA-256")
 check(not result.items[2].available_for_random and not result.items[2].eligible_for_random, "Missing entries explicitly excluded from random choice")
 check(not result.items[3].available_for_random, "Unknown source status is not assumed present")
 check(result.items[3].file_status == "unknown", "Unknown statuses use a bounded vocabulary")
 check(result.items[0].source_game_id == result.items[1].source_game_id, "Scraper reference preserved only as non-unique metadata")
 check(result.items[0].local_file_status == "not_checked" and not result.items[0].local_presence_verified, "Source inventory does not claim local existence")
 a.name = "Changed title"
 a.game_id = "changed_scraper_id"
 a.entry_index = 999
 var changed := Import.adapt({"games": [a]})
 check(changed.items[0].id == result.items[0].id, "Stable identity ignores name, external ID and XML ordering")
 var reversed: Array = source.games.duplicate(true)
 reversed.reverse()
 var reordered := Import.adapt({"games": reversed})
 check(reordered.items[3].id == result.items[0].id, "Reordered inventory retains stable identity")
 var other := Import.adapt(source, "Mark III")
 check(other.items.size() == 1 and other.items[0].source_group == "Mark III", "Mark III is an explicit separate scope")
 var same_path_other_system := a.duplicate(true)
 same_path_other_system.source_group = "Mark III"
 check(Import.adapt({"games": [same_path_other_system]}, "Mark III").items[0].id != result.items[0].id, "System namespace is part of entry identity")
 var duplicates := Import.adapt({"games": [a, a.duplicate(true), 123, {}]})
 check(duplicates.items.size() == 1 and duplicates.counts.duplicate_entries == 1, "Same system and relative path are deduplicated")
 check(duplicates.counts.invalid_entries == 1 and duplicates.counts.filtered_groups == 1, "Malformed and out-of-scope records have separate counts")
 check(not Import.adapt(source, "all").ok, "Implicitly mixed groups are not supported")
 check(Import.adapt({"games": []}).ok, "Empty catalog is a valid empty result")
 result.items[0].filename_variant_hints.append("mutation")
 check(a.filename_variant_hints.size() == 1, "Variant metadata does not alias caller arrays")

func _test_path_validation() -> void:
 var invalid := ["", "../escape.zip", "folder/../escape.zip", "/absolute.zip", "C:/absolute.zip", "C:\\absolute.zip", "https://host/a.zip", "file://a.zip", "//server/share.zip", "\\\\server\\share.zip", "folder//empty.zip", "folder/", "folder" + String.chr(1) + "/file.zip", "folder\n/file.zip", "~/file.zip", "folder/file.zip:stream", "folder/.. /x.zip", "folder/file.zip.", "folder/AUX.zip", "folder/nul.png", "folder/COM1/file.zip", "folder/x?.zip"]
 for path in invalid:
  check(Import.safe_relative_path(path).is_empty(), "Unsafe synthetic path rejected")
  check(Import.adapt({"games": [entry(path)]}).items.is_empty(), "Unsafe entry never becomes a runtime item")
 for raw in [null, 9, {}, []]:
  check(Import.safe_relative_path(raw).is_empty(), "Non-string path rejected")
 check(Import.safe_relative_path("./folder/./test.zip") == "folder/test.zip", "Harmless dot segments normalize without changing identity")
 check(Import.safe_relative_path("folder\\nested\\test.zip") == "folder/nested/test.zip", "Relative Windows separators normalize")
 check(Import.safe_relative_path("folder/test..zip") == "folder/test..zip", "Dots within a normal filename are not traversal")
 check(not Import.adapt({"games": []}, "Master System", "https://host/root").ok, "Network URI cannot be a local root")
 check(not Import.adapt({"games": []}, "Master System", "//server/share").ok, "UNC network share cannot be a local root")
 check(not Import.adapt({"games": []}, "Master System", "/root/../other").ok, "Root traversal rejected instead of silently simplified")
 check(not Import.adapt({"games": []}, "Master System", "relative/root").ok, "Local root must be explicit and absolute")

func _test_media_contract() -> void:
 var item := entry()
 item.media = {
  "boxart": media("images/synthetic-front.png"), "boxback": media("images/synthetic-back.jpg"),
  "wheel": media("images/synthetic-wheel.png"), "marquee": media("images/synthetic-marquee.png"),
  "manual": media("manuals/synthetic.pdf"), "cartridge": media("images/synthetic-whole-cartridge.png"),
  "image": media("images/synthetic-generic.png"), "screenshot": media("images/synthetic-gameplay.png")
 }
 var metadata_only := Import.adapt({"games": [item]})
 var record: Dictionary = metadata_only.items[0]
 for field in Import.SURFACE_TAGS:
  check(record[field] == "", "No runtime media path without an explicit local root")
 check(record.media_metadata.boxart.relative_path == "images/synthetic-front.png", "Validated source paths retained as metadata")
 check(record.media_metadata.boxart.local_status == "not_checked" and not record.media_metadata.boxart.bytes_provided, "Source-present art never implies copied bytes")
 check(record.media_mapping.cover_front == "boxart" and record.media_mapping.cover_back == "boxback", "Box front and back tags map to their own surfaces")
 check(record.media_mapping.wheel == "wheel" and record.media_mapping.manual_pdf == "manual", "Wheel preferred and manual is explicitly PDF metadata")
 check(not record.media_mapping.has("cartridge_label") and not record.media_mapping.has("cover_spine"), "Whole cartridge, generic image and screenshot are not labels or spines")
 check(record.manual_pages.is_empty(), "PDF metadata is not falsely advertised as decoded image pages")
 var rooted := Import.adapt({"games": [item]}, "Master System", "/nonexistent_synthetic_root")
 check(rooted.ok and rooted.items[0].cover_front == "/nonexistent_synthetic_root/images/synthetic-front.png", "Root only resolves paths without requiring or reading media")
 check(not rooted.local_presence_verified and not rooted.media_bytes_provided, "Resolved paths still do not establish existence or bytes")
 check(rooted.items[0].manual_pdf == "/nonexistent_synthetic_root/manuals/synthetic.pdf", "Manual remains a PDF, never opens externally")
 check(Import.adapt({"games": [item]}, "Master System", "C:/").items[0].cover_front == "C:/images/synthetic-front.png", "Windows drive root is preserved")
 check(Import.adapt({"games": [item]}, "Master System", "user://").items[0].cover_front == "user://images/synthetic-front.png", "Local Godot root is preserved")
 check(Import.adapt({"games": [item]}, "Master System", "/").items[0].cover_front == "/images/synthetic-front.png", "POSIX root is preserved")
 item.media.wheel = media("../invalid-wheel.png")
 item.media.cover_spine = media("images/synthetic-spine.png")
 item.media.cartridge_label = media("images/synthetic-label.png")
 item.media.cartridge_top = media("images/synthetic-top.png")
 var explicit := Import.adapt({"games": [item]}, "Master System", "/synthetic")
 check(explicit.counts.invalid_media_paths == 1, "Unsafe media paths counted but do not discard valid game")
 check(explicit.items[0].media_metadata.wheel.relative_path.is_empty(), "Unsafe original path is not propagated")
 check(explicit.items[0].media_mapping.wheel == "marquee", "Safe marquee fallback used after invalid wheel")
 check(explicit.items[0].cover_spine.ends_with("synthetic-spine.png") and explicit.items[0].cartridge_label.ends_with("synthetic-label.png"), "Explicit spine and label tags can populate their surfaces")
 item.media.wheel = media("images/synthetic-wheel.png", "missing")
 check(Import.adapt({"games": [item]}).items[0].media_mapping.wheel == "marquee", "Missing wheel can fall back to present marquee")
 item.media.boxart = media("images/synthetic-front.svg")
 item.media.manual = media("manuals/synthetic.png")
 item.media.boxback = media("images/synthetic-back.jpg", "missing")
 var unsupported: Dictionary = Import.adapt({"games": [item]}, "Master System", "/synthetic").items[0]
 check(unsupported.cover_front.is_empty() and unsupported.cover_back.is_empty() and unsupported.manual_pdf.is_empty(), "Unsupported extensions and source-missing media are not runtime-loadable")
 check(unsupported.media_metadata.boxback.status == "missing", "Missing artwork stays explicit in metadata")

func _test_inventory_labels() -> void:
 var first := entry("Synthetic folder/Synthetic (Europe, Brazil).zip")
 first.region_hint = "jp"
 first.filename_variant_hints = ["Europe, Brazil", "En"]
 var revision := first.duplicate(true)
 revision.path = "Synthetic folder/Synthetic (Europe, Brazil) (Rev 1).zip"
 revision.filename_variant_hints = ["Europe, Brazil", "En", "Rev 1"]
 var result := Import.adapt({"games": [first, revision]})
 check(result.items[0].title == result.items[1].title, "Original shared titles are never renamed to create variants")
 check(result.items[0].subtitle == "Arquivo · EU/BR · En", "Filename hints identify their source and compact region labels")
 check(result.items[1].subtitle == "Arquivo · Rev 1 · EU/BR · En", "Revision remains visible before lower-priority language details")
 check(not "JP" in result.items[0].subtitle, "Generic scraper region never overrides conflicting filename hints")
 var snapshot := JSON.stringify(result.items)
 Import.apply_inventory_subtitles(result.items)
 check(JSON.stringify(result.items) == snapshot, "Reapplying display labels to an exported manifest is idempotent")
 var no_hints := entry("Synthetic private folder/Synthetic Variant A.zip")
 no_hints.region_hint = ""
 no_hints.filename_variant_hints = []
 var fallback: Dictionary = Import.adapt({"games": [no_hints]}).items[0]
 check(fallback.subtitle == "Arquivo · Synthetic Variant A", "No-hint fallback exposes only the basename without extension")
 no_hints.region_hint = "us,eu"
 check(Import.adapt({"games": [no_hints]}).items[0].subtitle == "Região indicada · US/EU", "Metadata-only region fallback is explicitly an indication")
 var same_hints := first.duplicate(true)
 same_hints.path = "Another synthetic folder/Synthetic Alternate.zip"
 var tied := Import.adapt({"games": [first, same_hints]})
 check(tied.items[0].subtitle != tied.items[1].subtitle, "Equal-title equal-hint records use basename disambiguation")
 check(not "folder" in tied.items[0].subtitle and not "folder" in tied.items[1].subtitle, "Disambiguation never includes source directories")
 same_hints.path = "Another synthetic folder/Synthetic (Europe, Brazil).zip"
 tied = Import.adapt({"games": [first, same_hints]})
 check(tied.items[0].subtitle != tied.items[1].subtitle and tied.items[1].subtitle.ends_with("#2"), "Identical basenames remain distinct without revealing their folders")
 snapshot = JSON.stringify(tied.items)
 Import.apply_inventory_subtitles(tied.items)
 check(JSON.stringify(tied.items) == snapshot, "Basename and ordinal fallbacks never accumulate on reload")
 no_hints.filename_variant_hints = ["C:\\Synthetic private folder", "../Synthetic private folder", "https://synthetic.invalid", "bad\nlabel"]
 no_hints.region_hint = ""
 check(Import.adapt({"games": [no_hints]}).items[0].subtitle == "Arquivo · Synthetic Variant A", "Path-like or control-containing hints never become UI text")
 var local := {"id":"synthetic-local", "title":"Synthetic local", "subtitle":"LOCAL LABEL"}
 var verified := {"id":"synthetic-verified", "availability_basis":"source_inventory", "local_presence_verified":true, "subtitle":"VERIFIED LABEL"}
 Import.apply_inventory_subtitles([local, verified])
 check(local.subtitle == "LOCAL LABEL" and verified.subtitle == "VERIFIED LABEL", "Legacy local and explicitly verified labels are preserved")
 var unchanged: Dictionary = result.items[1].duplicate(true)
 unchanged.erase("subtitle")
 var rebuilt: Dictionary = Import.adapt({"games": [revision]}).items[0]
 rebuilt.erase("subtitle")
 check(JSON.stringify(unchanged) == JSON.stringify(rebuilt), "Display disambiguation never changes identity, media or random eligibility")

func _test_json_io_and_errors() -> void:
 for bad in [null, [], {}, {"games": null}, {"games": "not an array"}]:
  check(not Import.adapt(bad).ok, "Malformed schemas return structured failure")
 for path in ["https://host/catalog.json", "//server/catalog.json", "res://../catalog.json", "/synthetic/rom.zip"]:
  check(not Import.read_catalog(path).ok, "Read entrypoint refuses remote, traversal or non-JSON input")
 var path := "user://synthetic_catalog_import_%s.json" % Time.get_ticks_usec()
 var file := FileAccess.open(path, FileAccess.WRITE)
 check(file != null, "Synthetic JSON fixture writable")
 if file == null: return
 file.store_string(JSON.stringify({"games": [entry()]}))
 file.close()
 var result := Import.read_catalog(path)
 check(result.ok and result.items.size() == 1, "Explicit JSON read reaches pure adapter")
 file = FileAccess.open(path, FileAccess.WRITE)
 file.store_string("{broken synthetic JSON")
 file.close()
 check(Import.read_catalog(path).error == "invalid_json", "Malformed JSON has a bounded error, not copied private contents")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 check(Import.read_catalog(path).error == "json_unreadable", "Unreadable JSON reports failure without reading alternate files")

func _test_private_catalog() -> void:
 var path := OS.get_environment("RETROPASS_PRIVATE_CATALOG")
 if path.is_empty(): return
 var sms := Import.read_catalog(path)
 var mark := Import.read_catalog(path, "Mark III")
 check(sms.ok and mark.ok, "Optional private metadata JSON adapts both explicit scopes")
 if not sms.ok or not mark.ok: return
 var seen := {}
 for result in [sms, mark]:
  check(result.counts.invalid_entries == 0 and result.counts.duplicate_entries == 0, "Private inventory has no rejected or duplicate records")
  check(result.counts.items == result.counts.present + result.counts.missing + result.counts.unknown, "Private status counts account for every adapted item")
  for item in result.items:
   check(not seen.has(item.id), "Private IDs unique across both systems")
   seen[item.id] = true
   check(item.available_for_random == (item.file_status == "present"), "Private random eligibility follows source-present status only")
   check(not item.local_presence_verified and not item.media_bytes_provided, "Private metadata never claims cloud file or media availability")
   for field in Import.SURFACE_TAGS:
    check(str(item[field]).is_empty(), "Private metadata-only export leaves runtime media empty")
 check(sms.counts.items + mark.counts.items == sms.counts.input_records, "Explicit scopes together preserve every private inventory entry")
 print("PRIVATE_CATALOG_COUNTS: ", JSON.stringify({"master_system": sms.counts, "mark_iii": mark.counts}))
 var output := OS.get_environment("RETROPASS_PRIVATE_OUTPUT")
 if output.is_empty(): return
 var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
 var normalized := output.replace("\\", "/").simplify_path()
 var safe := output.is_absolute_path() and output.get_extension().to_lower() == "json" and normalized != ProjectSettings.globalize_path(path).simplify_path() and not normalized.begins_with(project_root + "/") and not output.begins_with("res://") and not output.begins_with("user://")
 check(safe, "Private output must be a separate JSON outside public project")
 if not safe: return
 var file := FileAccess.open(output, FileAccess.WRITE)
 check(file != null, "Private adapted catalog output writable")
 if file == null: return
 file.store_string(JSON.stringify(sms, "  "))
 file.close()
 print("PRIVATE_CATALOG_EXPORT: items=", sms.items.size(), "; media_bytes=0; runtime_media_paths=0")
