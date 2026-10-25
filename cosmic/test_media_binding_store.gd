extends SceneTree
const Store = preload("res://cosmic/media_binding_store.gd")
const Association = preload("res://cosmic/media_result_association.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
const Restore = preload("res://cosmic/media_restore_service.gd")
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func completed(items: Array, folder: String, system: String = "master_system") -> Dictionary:
 var plan := Planner.build(Config.choose(system,folder,["covers","images","wheel","manual"]),items)
 var queue := Queue.new()
 check(queue.start(plan,"user://bindings_queue.json") == OK,"Synthetic queue starts")
 for n in 100:
  if queue.tick().status in ["done","completed_with_errors"]: break
 return Association.build(queue.state,items)
func write(path: String, value: String) -> void:
 var file := FileAccess.open(path,FileAccess.WRITE)
 file.store_string(value)
 file.close()
func run() -> void:
 var store := Store.new()
 store.path = "user://bindings_test.json"
 for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(store.path + suffix)
 var folder := ProjectSettings.globalize_path("user://bindings_fixture")
 DirAccess.make_dir_recursive_absolute(folder)
 var image := Image.create(20,16,false,Image.FORMAT_RGBA8)
 image.fill(Color.CORNFLOWER_BLUE)
 image.save_png(folder.path_join("page.png"))
 var item := {"id":"same-id", "system":"master_system", "edition":"EU", "cover_front":"original", "manual_pages":[], "media_metadata":{
  "cover_front":{"relative_path":"page.png","status":"present"},
  "manual":{"relative_path":"page.png","status":"present"},
  "screenshot":{"relative_path":"page.png","status":"present"}}}
 var base: Array = [item]
 var result := completed(base,folder)
 check(result.applied == 3 and result.bindings.size() == 3,"Only decoded exact links become bindings")
 check(result.items[0].manual_pages == [folder.path_join("page.png")] and result.items[0].manual_item_id == "same-id","Validated manual image has explicit identity, never a PDF conversion")
 check(result.items[0].media_screenshot == folder.path_join("page.png"),"Screenshot stored separately from cover")
 check(store.save_bindings(result.bindings) == OK,"Private overlay saves")
 check(store.load_state().bindings == result.bindings,"Canonical overlay roundtrip")
 var restored := Store.restore(store.load_state().bindings,base)
 check(restored.applied == 3 and restored.items == result.items,"Fresh base restores exact fields and original provenance")
 check(base[0].cover_front == "original" and base[0].manual_pages.is_empty(),"Source metadata immutable")
 var changed := base.duplicate(true)
 changed[0].edition = "US"
 check(Store.restore(result.bindings,changed).applied == 0,"Edition change rejects all stale links")
 changed = base.duplicate(true)
 changed[0].media_metadata.extra = {"status":"missing"}
 check(Store.restore(result.bindings,changed).applied == 0,"Catalog signature includes complete media metadata")
 changed = base.duplicate(true)
 changed.append(base[0].duplicate(true))
 check(Store.restore(result.bindings,changed).applied == 0,"Duplicate exact IDs reject ambiguity")
 changed = base.duplicate(true)
 changed[0].system = "mark_iii"
 check(Store.restore(result.bindings,changed).applied == 0,"Same game ID cannot cross systems")
 var bad: Array = result.bindings.duplicate(true)
 bad[0].relative_path = "../page.png"
 check(store.save_bindings(bad) == ERR_INVALID_PARAMETER and Store.restore(bad,base).applied == 0,"Traversal rejected before media reads")
 bad = result.bindings.duplicate(true)
 bad[0].sha256 = "z".repeat(64)
 check(store.save_bindings(bad) == ERR_INVALID_PARAMETER,"Nonhex digest rejected")
 bad = result.bindings.duplicate(true)
 bad[1].sha256 = "0".repeat(64)
 check(store.save_bindings(bad) == ERR_INVALID_PARAMETER and Store.restore(bad,base).applied == 0,"Shared path cannot reuse validation for conflicting hashes")
 bad = result.bindings.duplicate(true)
 bad[0].secret = "not-allowed"
 check(store.save_bindings(bad) == ERR_INVALID_PARAMETER,"Non-allowlisted data rejected")
 bad = result.bindings.duplicate(true)
 bad.append(bad[0].duplicate(true))
 check(store.save_bindings(bad) == ERR_INVALID_PARAMETER,"Conflicting/duplicate surface records rejected")
 check(store.save_bindings(result.bindings) == OK,"Second save creates backup")
 write(store.path,"{broken")
 check(store.load_state().bindings == result.bindings,"Corrupt primary recovers last valid backup")
 write(store.path + ".tmp","partial crash write")
 check(store.load_state().bindings == result.bindings,"Interrupted temporary file is ignored")
 DirAccess.remove_absolute(store.path)
 check(store.load_state().bindings == result.bindings,"Crash between rotation and rename restores backup")
 check(store.save_bindings(result.bindings) == OK,"Recovered backup can be saved again")
 image.fill(Color.RED)
 image.save_png(folder.path_join("page.png"))
 restored = Store.restore(result.bindings,base)
 check(restored.applied == 0 and restored.items == base,"Changed bytes never reapply stale binding")
 var rollback := Store.restore(result.bindings,result.items)
 check(rollback.applied == 0 and rollback.items[0].cover_front == "original" and rollback.items[0].manual_pages.is_empty() and not rollback.items[0].has("manual_item_id"),"Failed revalidation rolls back previously applied runtime surfaces")
 var new_result := completed(base,folder)
 var worker := Restore.new()
 check(worker.begin(new_result.bindings,base) == OK,"Restore worker starts")
 while worker.is_busy(): await process_frame
 check(worker.take_result().applied == 3,"Worker revalidation applies exact result")
 check(worker.take_result().is_empty(),"Worker result consumed once")
 check(worker.begin(new_result.bindings,base) == OK,"Late cancellation fixture starts")
 while worker.is_busy(): await process_frame
 worker.request_cancel()
 check(worker.take_result().is_empty(),"Cancel after publish but before consume discards result")
 check(worker.begin(new_result.bindings,base) == OK,"Restore worker reusable")
 worker.shutdown()
 check(worker.take_result().is_empty(),"Cancellation/shutdown cannot publish partial restore")
 var cancelled := Store.restore(new_result.bindings,base,func(): return true)
 check(cancelled.status == "cancelled" and cancelled.items == base,"Cancellation rolls back entire output")
 var atari := item.duplicate(true)
 atari.erase("system")
 atari.system_id = "atari2600"
 var atari_result := completed([atari],folder,"atari_2600")
 check(atari_result.applied == 3 and atari_result.bindings[0].config.system == "atari_2600","Explicit Atari system_id adapter plans exact metadata")
 check(Store.restore(atari_result.bindings,[atari]).applied == 3,"Atari identity survives restore")
 var contradictory := atari.duplicate(true)
 contradictory.system = "master_system"
 check(Association.canonical_system(contradictory).is_empty() and Store.restore(atari_result.bindings,[contradictory]).applied == 0,"Contradictory system fields reject exact binding")
 atari.system_id = "unknown_atari"
 check(Store.restore(atari_result.bindings,[atari]).applied == 0,"No fuzzy system aliases")
 var manual_bad := item.duplicate(true)
 manual_bad.manual_item_id = "other-game"
 var wrong_manual := completed([manual_bad],folder)
 check(wrong_manual.items[0].manual_pages.is_empty() and wrong_manual.applied == 2,"Contradictory manual identity never overwritten")
 var linkpath := folder.path_join("link.png")
 if DirAccess.open(folder).create_link(folder.path_join("page.png"),linkpath) == OK:
  var linked := item.duplicate(true)
  linked.media_metadata = {"cover_front":{"relative_path":"link.png","status":"present"}}
  check(completed([linked],folder).applied == 0,"Symlink source never applied")
  DirAccess.remove_absolute(linkpath)
 else: check(false,"Synthetic symlink fixture created")
 DirAccess.remove_absolute(folder.path_join("page.png"))
 var removed_result := completed(new_result.items,folder)
 check(removed_result.applied == 0 and removed_result.items[0].cover_front == "original" and removed_result.items[0].manual_pages.is_empty(),"Queue error after source removal rolls back prior runtime association")
 check(store.save_bindings(removed_result.bindings,removed_result.remove_bindings) == OK and store.load_state().bindings.is_empty(),"Failed explicitly revalidated links are removed from persisted overlay")
 for stem in [store.path,"user://bindings_queue.json"]:
  for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(stem + suffix)
 DirAccess.remove_absolute(folder.path_join("page.png"))
 DirAccess.remove_absolute(folder)
 print("MEDIA_BINDING_STORE: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
