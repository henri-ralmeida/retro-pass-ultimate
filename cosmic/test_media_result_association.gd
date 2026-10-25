extends SceneTree
const Association = preload("res://cosmic/media_result_association.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func processed(items: Array, folder: String) -> Dictionary:
 var plan := Planner.build(Config.choose("master_system", folder, ["covers", "wheel", "images", "manual"]), items)
 var queue := Queue.new()
 check(queue.start(plan, "user://association_test_queue.json") == OK, "Queue starts synthetic plan")
 for tick in range(100):
  if queue.tick().status in ["done", "completed_with_errors"]: break
 return queue.state.duplicate(true)
func write_bytes(path: String, bytes: PackedByteArray) -> void:
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_buffer(bytes)
 file.close()
func run() -> void:
 var folder := ProjectSettings.globalize_path("user://association_fixture")
 DirAccess.make_dir_recursive_absolute(folder)
 var png := Image.create(16, 12, false, Image.FORMAT_RGBA8)
 png.fill(Color.CORNFLOWER_BLUE)
 png.save_png(folder.path_join("front.png"))
 png.save_png(folder.path_join("other.png"))
 write_bytes(folder.path_join("fake.png"), "not an image".to_utf8_buffer())
 write_bytes(folder.path_join("manual.pdf"), "%PDF synthetic not decoded".to_utf8_buffer())
 var item := {"id":"exact-variant-eu", "system":"master_system", "relative_path":"game (EU).sms", "region_hint":"EU", "cover_front":"old-front", "wheel":"old-wheel", "manual_pages":["old-page"], "identity_status":"unverified", "media_metadata":{
  "cover_front":{"status":"present", "relative_path":"front.png"},
  "wheel":{"status":"present", "relative_path":"front.png"},
  "image":{"status":"present", "relative_path":"other.png"},
  "manual":{"status":"present", "relative_path":"manual.pdf"}}}
 var items: Array = [item, {"id":"exact-variant-us", "system":"master_system", "cover_front":"keep-us", "region_hint":"US"}]
 var result := processed(items, folder)
 var associated := Association.build(result, items)
 check(associated.applied == 2 and associated.validated_files == 1, "Actual front and wheel validated, shared file decoded once")
 check(associated.items[0].cover_front == folder.path_join("front.png"), "Exact front path applied")
 check(associated.items[0].wheel == folder.path_join("front.png"), "Explicit wheel applies")
 check(associated.items[0].local_media_previous.cover_front == "old-front", "Prior surface retained")
 check(associated.items[0].identity_status == "unverified", "Hash never confirms identity")
 check(associated.items[0].manual_pages == ["old-page"], "PDF never replaces pages")
 check(associated.items[1].cover_front == "keep-us", "Other variant untouched")
 check(items[0].cover_front == "old-front" and not items[0].has("local_media_previous"), "Input catalog unchanged")
 check(associated.issues.any(func(v): return v.get("tag") == "image"), "Generic image is not art fallback")
 var changed := items.duplicate(true)
 changed[0].region_hint = "BR"
 check(Association.build(result, changed).applied == 0, "Changed region under same ID rejected")
 changed = items.duplicate(true)
 changed[0].media_metadata.cover_front.relative_path = "other.png"
 check(Association.build(result, changed).items[0].cover_front == "old-front", "Changed descriptor cannot use stale result")
 changed = items.duplicate(true)
 changed.append(items[0].duplicate(true))
 check(Association.build(result, changed).applied == 0, "Duplicate exact identity rejected")
 var missing_signature := result.duplicate(true)
 for job in missing_signature.files:
  for link in job.links: link.erase("catalog_identity")
 check(Association.build(missing_signature, items).applied == 0, "Legacy links without identity snapshot rejected")
 png.fill(Color.RED)
 png.save_png(folder.path_join("front.png"))
 check(Association.build(result, items).applied == 0, "Current file replacement rejects stale hash")
 var invalid := item.duplicate(true)
 invalid.media_metadata.cover_front.relative_path = "fake.png"
 invalid.media_metadata.wheel.relative_path = "fake.png"
 var invalid_result := processed([invalid], folder)
 check(Association.build(invalid_result, [invalid]).applied == 0, "Hashed non-image never applied")
 var cancelled := Association.build(processed(items, folder), items, func(): return true)
 check(cancelled.status == "cancelled" and cancelled.applied == 0 and cancelled.items[0].cover_front == "old-front", "Cancel preserves whole prior catalog")
 var ambiguous := item.duplicate(true)
 ambiguous.media_metadata.boxart = {"status":"present", "relative_path":"other.png"}
 var ambiguous_result := Association.build(processed([ambiguous], folder), [ambiguous])
 check(ambiguous_result.items[0].cover_front == "old-front" and ambiguous_result.applied == 1, "Conflicting aliases rejected without blocking exact wheel")
 var huge := png.save_png_to_buffer()
 huge[16] = 0x7f
 huge[17] = 0xff
 write_bytes(folder.path_join("huge.png"), huge)
 var huge_hash := FileAccess.get_sha256(folder.path_join("huge.png"))
 check(Association._validate_image(folder.path_join("huge.png"), huge_hash).status == "unsupported_or_oversized_header", "Oversized header rejected before decode")
 write_bytes(folder.path_join("valid.jpg"), png.save_jpg_to_buffer())
 check(Association._validate_image(folder.path_join("valid.jpg"), FileAccess.get_sha256(folder.path_join("valid.jpg"))).status == "valid", "JPEG validates current same-buffer decode")
 write_bytes(folder.path_join("valid.webp"), png.save_webp_to_buffer())
 check(Association._validate_image(folder.path_join("valid.webp"), FileAccess.get_sha256(folder.path_join("valid.webp"))).status == "valid", "WebP validates current same-buffer decode")
 write_bytes(folder.path_join("truncated.png"), png.save_png_to_buffer().slice(0, 33))
 check(Association._validate_image(folder.path_join("truncated.png"), FileAccess.get_sha256(folder.path_join("truncated.png"))).status == "decode_failed", "Plausible header and hash alone do not prove a valid image")
 for path in ["front.png", "other.png", "fake.png", "manual.pdf", "huge.png", "valid.jpg", "valid.webp", "truncated.png"]: DirAccess.remove_absolute(folder.path_join(path))
 DirAccess.remove_absolute(folder)
 for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute("user://association_test_queue.json" + suffix)
 print("MEDIA_RESULT_ASSOCIATION: ", assertions, " assertions; ", failures, " failures")
 quit(0 if failures == 0 else 1)
