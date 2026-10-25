extends SceneTree
## Deferred engine test. Run only after the shared engine window is explicitly released.
const Media = preload("res://cosmic/atari_private_media.gd")
const Adapter = preload("res://cosmic/atari_system_adapter.gd")
const Exhibit = preload("res://cosmic/atari_exhibit.gd")
var failures: Array[String] = []

func _initialize() -> void:
 _run.call_deferred()

func _expect(condition: bool, message: String) -> void:
 if not condition:
  failures.append(message)

func _run() -> void:
 var media := Media.new()
 _expect(not media.configure("", false), "Default must remain disabled")
 _expect(media.model_path("console").is_empty(), "Disabled adapter exposes no path")
 _expect(not media.configure("res://absent_manifest.json", true), "Missing manifest is absent")
 _expect(not Media.validate_glb(PackedByteArray([0, 1, 2])), "Truncated GLB rejected")
 var descriptor: Dictionary = Adapter.descriptor()
 _expect(descriptor.display_name == "Atari 2600", "Correct Atari identification")
 _expect(descriptor.packaging_kind == "cardboard_tuck_flap", "No SMS case semantics")
 _expect(not descriptor.emulation_available, "No emulation claim")
 var empty := Exhibit.new()
 _expect(not empty.configure("", false), "Empty exhibit stays absent")
 _expect(empty.get_child_count() == 0, "No invented replacement geometry")
 _expect(not empty.set_cartridge_seated(true), "Absent cartridge cannot be seated")
 empty.free()
 var manifest_path := OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST")
 if not manifest_path.is_empty():
  _private_tests(manifest_path)
 else:
  print("PRIVATE ASSET TESTS: not run (explicit opt-in manifest absent)")
 for failure in failures:
  push_error(failure)
 print("ATARI TEST FAILURES: ", failures.size())
 quit(0 if failures.is_empty() else 1)

func _private_tests(path: String) -> void:
 var exhibit := Exhibit.new()
 root.add_child(exhibit)
 _expect(exhibit.configure(path, true), "Five supplied models import successfully")
 _expect(exhibit.asset_roots.size() == 5, "Exactly five model roots")
 _expect(exhibit.manual_page_paths().all(func(value): return not value.is_empty()), "Eight manual pages resolve")
 var media = exhibit.media
 var original_entry: Dictionary = media.manifest.models.console.duplicate()
 media.manifest.models.console.file = "../outside.glb"
 _expect(media.model_path("console").is_empty(), "Traversal path rejected")
 media.manifest.models.console.file = "https://example.invalid/model.glb"
 _expect(media.model_path("console").is_empty(), "Remote URL rejected")
 media.manifest.models.console = original_entry.duplicate()
 media.imported_model_count = 0
 media.manifest.models.console.sha256 = "0".repeat(64)
 _expect(media.load_model("console") == null, "Mismatched hash rejects model before import")
 media.manifest.models.console = original_entry
 _expect(media.manual_page_path(-1).is_empty(), "Negative page index absent")
 _expect(media.manual_page_path(8).is_empty(), "Out-of-range page absent")
 var cartridge: Node3D = exhibit.canonical_cartridge
 if is_instance_valid(cartridge):
  var cartridge_id := cartridge.get_instance_id()
  for repeat in 3:
   _expect(exhibit.set_carton_open(true), "Original cardboard flap pivots found")
   _expect(exhibit.set_cartridge_seated(true), "Source-contract pose available")
   _expect(exhibit.canonical_cartridge.get_instance_id() == cartridge_id, "Same canonical cartridge seated")
   _expect(exhibit.set_cartridge_seated(false), "Cartridge returns to isolated pose")
   _expect(exhibit.set_carton_open(false), "Original carton closes")
   _expect(exhibit.canonical_cartridge.get_instance_id() == cartridge_id, "Same canonical cartridge returned")
  _expect(cartridge.scale.is_equal_approx(Vector3.ONE), "Native cartridge scale preserved")
 for repeat in 2:
  _expect(not exhibit.configure("", false), "Reconfigure clears private display")
  _expect(exhibit.get_child_count() == 0, "Repeated clear has no stale model roots")
  _expect(exhibit.configure(path, true), "Repeated opt-in reconfigures bounded model set")
 _expect(exhibit.media.imported_model_count == 5, "Resident import budget resets, not accumulated")
 exhibit.free()
