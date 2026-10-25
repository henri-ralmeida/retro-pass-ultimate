extends SceneTree
const Scanner = preload("res://cosmic/collection_scan.gd")
var failures: Array[String] = []
var assertions := 0
var fixture := ""
func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)
func write_file(path: String, data: String) -> void:
 DirAccess.make_dir_recursive_absolute(path.get_base_dir())
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_string(data)
 file.close()
func _initialize() -> void: run.call_deferred()
func run() -> void:
 fixture = ProjectSettings.globalize_path("user://retropass_collection_fixture_" + str(Time.get_ticks_usec()))
 DirAccess.make_dir_recursive_absolute(fixture)
 write_file(fixture.path_join("Alex (USA).SMS"), "synthetic-not-a-ROM")
 write_file(fixture.path_join("nested/Unknown.zip"), "synthetic-not-an-archive")
 write_file(fixture.path_join("nested/Third.7z"), "synthetic")
 write_file(fixture.path_join("ignore.txt"), "not included")
 write_file(fixture.path_join("media/front.png"), "synthetic-media")
 write_file(fixture.path_join("media/back.jpg"), "synthetic-media")
 write_file(fixture.path_join("media/spine.webp"), "synthetic-media")
 write_file(fixture.path_join("gamelist.xml"), '<gameList><game><path>./Alex (USA).SMS</path><name>Explicit Local Name</name><desc>Local description</desc><boxfront>./media/front.png</boxfront><boxback>./media/back.jpg</boxback><boxspine>./media/spine.webp</boxspine><cartridge_label>./media/front.png</cartridge_label><wheel>./media/back.jpg</wheel></game><game><path>./nested/Unknown.zip</path><name>Exact Archive</name><image>../../outside.png</image></game><game><path>./nested/Third.7z</path><name>Third</name><image>./media/front.png</image></game><game><path>./nested/Third.7z</path><name>Third</name><image>./media/front.png</image></game><game><path>./Alex.sms</path><name>Never Fuzzy Match</name></game></gameList>')
 var catalog_before := FileAccess.get_file_as_string(Scanner.CATALOG_PATH) if FileAccess.file_exists(Scanner.CATALOG_PATH) else ""
 var before := FileAccess.get_sha256(fixture.path_join("Alex (USA).SMS"))
 var scanner := Scanner.new()
 var result: Dictionary = scanner.scan_folder(fixture)
 check(result.status == "ok", "Scan completes")
 var catalog_after := FileAccess.get_file_as_string(Scanner.CATALOG_PATH) if FileAccess.file_exists(Scanner.CATALOG_PATH) else ""
 check(catalog_before == catalog_after, "Scanning alone never writes catalog")
 check(result.items.size() == 3, "Only SMS/ZIP/7Z files included; duplicate XML records never duplicate items")
 check(result.provider_status == "not_configured", "No fake online provider")
 var first: Dictionary = result.items[0]
 check(first.title == "Explicit Local Name", "Exact XML path matches; no fuzzy replacement")
 check(first.size_bytes == 19, "Byte size measured without interpretation")
 check(first.cover_front.ends_with("front.png") and first.cover_back.ends_with("back.jpg") and first.cover_spine.ends_with("spine.webp"), "Independent local face paths")
 check(first.cartridge_label.ends_with("front.png") and first.wheel.ends_with("back.jpg"), "Explicit same-entry cartridge label and wheel paths retained independently")
 check(not result.items[1].has("cartridge_label"), "Missing label never inherited from another entry")
 check(first.identity_status == "unverified", "Local metadata never claims verified online identity")
 var third: Dictionary = result.items[1]
 check(third.title == "Third" and third.cover_front == "", "Filename title retained; generic image is not used as a box face")
 check(third.media_image.ends_with("front.png"), "Generic gamelist image kept separately as unclassified media")
 check(result.items[2].cover_front == "", "Outside-root media rejected")
 var again: Dictionary = scanner.scan_folder(fixture)
 check(again.items[0].id == first.id, "Stable relative-path identifier")
 check(FileAccess.get_sha256(fixture.path_join("Alex (USA).SMS")) == before, "ROM bytes untouched")
 var bounded: Dictionary = scanner.scan_folder(fixture, {"max_files":1})
 check(bounded.status == "limited", "Entry bound stops oversized tree")
 check(scanner.save_catalog(bounded) == ERR_INVALID_DATA, "Incomplete inventory cannot overwrite catalog")
 var shallow: Dictionary = scanner.scan_folder(fixture, {"max_depth":0})
 check(shallow.status == "limited", "Depth bound reported as incomplete")
 var cancelled: Dictionary = scanner.scan_folder(fixture, {"cancelled":func() -> bool: return true})
 check(cancelled.status == "cancelled" and cancelled.items.is_empty(), "Cancellation before traversal")
 check(scanner.save_catalog(cancelled) == ERR_INVALID_DATA, "Cancellation never persists")
 check(scanner.scan_folder(fixture.path_join("absent")).status == "error", "Missing folder reports error")
 var link_error := DirAccess.open(fixture).create_link(fixture, fixture.path_join("loop"))
 if link_error == OK:
  var linked: Dictionary = scanner.scan_folder(fixture)
  check(linked.status == "ok" and linked.items.size() == 3, "Symlink loop not followed")
  check(scanner.scan_folder(fixture.path_join("loop")).status == "error", "Symlink root rejected")
  DirAccess.remove_absolute(fixture.path_join("loop"))
 else:
  check(false, "Fixture symlink must be created to exercise traversal protection")
 write_file(fixture.path_join("gamelist.xml"), '<gameList><game><path>./Alex (USA).SMS</path><name>Broken')
 var malformed: Dictionary = scanner.scan_folder(fixture)
 check(malformed.items[0].title == "Alex (USA)" and not malformed.warnings.is_empty(), "Truncated XML does not apply metadata")
 write_file(fixture.path_join("gamelist.xml"), '<!DOCTYPE gameList [<!ENTITY external SYSTEM "file:///definitely-not-readable">]><gameList><game><path>./Alex (USA).SMS</path><name>&external;</name></game></gameList>')
 var entity: Dictionary = scanner.scan_folder(fixture)
 check(entity.items[0].title == "Alex (USA)" and not entity.warnings.is_empty(), "DOCTYPE/entities rejected before parser; no external resolution")
 _remove_fixture(fixture)
 print("COLLECTION_SCAN: ", assertions, " assertions; ", failures.size(), " failures")
 quit(0 if failures.is_empty() else 1)
func _remove_fixture(path: String) -> void:
 var dir := DirAccess.open(path)
 if dir == null: return
 dir.list_dir_begin()
 var name := dir.get_next()
 while not name.is_empty():
  var child := path.path_join(name)
  if dir.current_is_dir() and not dir.is_link(name): _remove_fixture(child)
  else: DirAccess.remove_absolute(child)
  name = dir.get_next()
 dir.list_dir_end()
 DirAccess.remove_absolute(path)
