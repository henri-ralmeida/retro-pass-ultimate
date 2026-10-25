extends SceneTree
## Synthetic catalog identity checks only. No personal inventory or ROM reads.
var assertions := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var path := "user://synthetic_catalog_choice_integration.json"
 var items: Array[Dictionary] = []
 for index in 11: items.append({"id":"synthetic-choice-%02d"%index,"title":"Synthetic catalog entry %02d"%index})
 var file := FileAccess.open(path,FileAccess.WRITE)
 file.store_string(JSON.stringify({"items":items}))
 file.close()
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST",path)
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 var view = scene.library_view
 view.set_process(false)
 var id: String = view.ITEMS[view.current_index].id
 check(view.catalog_choice.get_eligible_count()==11,"Only actual fixture catalog entries are eligible")
 check(view.catalog_choice.get_selected_id()==id,"Startup random selection maps to visible catalog index")
 check(scene.exhibit.selected_item.id==id,"HOME box/cartridge use the same initial random item")
 check(scene.exhibit.inserted_cartridge.get_meta("selected_game_id")==id,"Inserted cartridge identity matches background box")
 for repeat in 12:
  scene._layout()
  view.layout()
  scene._focus_lost()
  scene._focus_returned()
  check(view.ITEMS[view.current_index].id==id,"Redraw and focus never reroll")
 scene.toggle_inspection()
 scene.close_inspection()
 check(view.ITEMS[view.current_index].id==id,"Console inspection preserves selected item")
 scene.enter_library()
 check(view.ITEMS[view.current_index].id==id,"Opening menu preserves displayed HOME selection")
 var selected: int = (view.current_index+4)%view.ITEMS.size()
 view._select(selected)
 var explicit_id: String = view.ITEMS[selected].id
 check(view.catalog_choice.get_selected_id()==explicit_id,"Explicit navigation supersedes initial random choice")
 view.toggle_inspection()
 view.go_back()
 check(view.ITEMS[view.current_index].id==explicit_id,"Box inspection and Back do not reroll")
 scene.leave_library()
 check(scene.exhibit.selected_item.id==explicit_id,"Returning HOME retains explicit game and matching media")
 check(scene.exhibit.inserted_cartridge.get_meta("selected_game_id")==explicit_id,"Returned cartridge matches explicit choice")
 scene.enter_library()
 check(view.ITEMS[view.current_index].id==explicit_id,"Reopening menu stays within the same visit")
 view.begin_catalog_visit()
 var next_id: String = view.ITEMS[view.current_index].id
 check(next_id!=explicit_id,"A deliberate new visit avoids immediate repetition")
 check(view.catalog_choice.get_selected_id()==next_id,"New choice still maps to the current entry")
 view.catalog_choice.begin_visit()
 check(view.catalog_choice.get_selected_id()==next_id,"Repeated helper begin within visit is idempotent")
 scene.leave_library()
 check(scene.exhibit.selected_item.id==next_id,"New explicit visit propagates consistently to HOME")
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST","")
 print("CATALOG_CHOICE_INTEGRATION ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"fixture":"11 synthetic records, not user collection"}))
 quit(0 if failures.is_empty() else 1)
