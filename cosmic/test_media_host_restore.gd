extends SceneTree
const Host = preload("res://cosmic/media_optin_host.gd")
const Store = preload("res://cosmic/media_binding_store.gd")
const Association = preload("res://cosmic/media_result_association.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
var inventory: Array = []
var applied := 0
var failures := 0
var assertions := 0
var stable := false
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func host_new(prefix: String) -> Control:
 var host := Host.new()
 host.store.path = prefix
 host.restore_enabled = true
 host.can_apply = func(): return stable
 host.catalog_getter = func(): return inventory.duplicate(true)
 host.catalog_apply = func(result: Dictionary) -> int:
  applied += 1
  inventory = result.items.duplicate(true)
  return int(result.applied)
 root.add_child(host)
 host.set_process(false)
 return host
func run() -> void:
 var prefix := "user://host_restore_test_%s" % Time.get_ticks_usec()
 var folder := ProjectSettings.globalize_path(prefix+"_fixture")
 DirAccess.make_dir_recursive_absolute(folder)
 var image := Image.create(12,12,false,Image.FORMAT_RGBA8)
 image.fill(Color.CYAN)
 image.save_png(folder.path_join("front.png"))
 var item := {"id":"exact", "system":"master_system", "cover_front":"original", "media_metadata":{"cover_front":{"relative_path":"front.png","status":"present"}}}
 inventory = [item.duplicate(true)]
 var record := {"config":Config.choose("master_system",folder,["covers"]),"game_id":"exact","tag":"cover_front","relative_path":"front.png","sha256":FileAccess.get_sha256(folder.path_join("front.png")),"catalog_identity":Association.identity_signature(item)}
 var store := Store.new()
 store.path = prefix+".bindings"
 check(store.save_bindings([record]) == OK,"Synthetic persisted link prepared")
 var host := host_new(prefix)
 host._process(1)
 check(not host._restore_checked and applied == 0,"Restore waits for stable application state")
 stable = true
 host._process(0)
 check(host._restore_running and host.panel.start_button.disabled,"Restore serializes against new local processing")
 while host.restore_service.is_busy(): await process_frame
 host._process(0)
 check(applied == 1 and inventory[0].cover_front == folder.path_join("front.png"),"Background restore applies on main thread")
 host._process(1)
 check(applied == 1,"Restore runs once per host")
 host.free()
 inventory = [item.duplicate(true)]
 host = host_new(prefix)
 host._process(0)
 inventory[0].edition = "changed-while-worker-running"
 while host.restore_service.is_busy(): await process_frame
 host._process(0)
 check(applied == 1 and inventory[0].cover_front == "original" and "Catálogo mudou" in host._status,"Concurrent catalog mutation rejects complete pending restore")
 check(store.load_state().bindings == [record],"Rejected restore never rewrites consent binding")
 host.free()
 for stem in [prefix,prefix+".bindings",prefix+".tour"]:
  for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(stem+suffix)
 DirAccess.remove_absolute(folder.path_join("front.png"))
 DirAccess.remove_absolute(folder)
 print("MEDIA_HOST_RESTORE: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
