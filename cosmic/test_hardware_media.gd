extends SceneTree
const Media = preload("res://cosmic/hardware_media.gd")
var count := 0
func check(ok: bool) -> void:
 count += 1
 if not ok: push_error("Hardware media check failed %d" % count); quit(1)
func _initialize() -> void:
 var root := "user://hardware_test"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
 var manifest := root.path_join("manifest.json")
 check(Media.controller_path(root.path_join("absent.json")) == Media.FALLBACK_CONTROLLER)
 for value in ["../private.glb", "https://example.com/model.glb", "a/b.glb", "model.gd", "", "C:secret.glb"]:
  var f := FileAccess.open(manifest, FileAccess.WRITE)
  f.store_string(JSON.stringify({"controller_model":value})); f.close()
  check(Media.controller_path(manifest) == Media.FALLBACK_CONTROLLER)
 var f := FileAccess.open(root.path_join("local.glb"), FileAccess.WRITE)
 f.store_string("fixture"); f.close()
 f = FileAccess.open(manifest, FileAccess.WRITE)
 f.store_string(JSON.stringify({"controller_model":"local.glb"})); f.close()
 check(Media.controller_path(manifest) == root.path_join("local.glb"))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join("local.glb")))
 print("HARDWARE_MEDIA_PASS ", count)
 quit()
