extends SceneTree
## Requires the reviewed virtual-card integration patch. Synthetic metadata
## only; 1000 is a QA size, never a statement about the user's collection.
var assertions := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
 assertions += 1
 if not value: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func card_for(view: Control, index: int) -> Button:
 for card in view.cards:
  if int(card.get_meta("catalog_index",-1))==index: return card
 return null
func visual_order(view: Control) -> Array[int]:
 var sorted: Array = view.cards.duplicate()
 sorted.sort_custom(func(a: Button,b: Button): return a.position.x < b.position.x)
 var indices: Array[int] = []
 for card in sorted: indices.append(int(card.get_meta("catalog_index",-1)))
 return indices
func run() -> void:
 var items: Array[Dictionary] = []
 for index in 1000: items.append({"id":"synthetic_qa_%04d"%index,"title":"QA synthetic item %04d"%index,"subtitle":"SYNTHETIC SCALE TEST · NO ROM"})
 var path := "user://synthetic_virtual_cards_1000.json"
 var file := FileAccess.open(path,FileAccess.WRITE)
 file.store_string(JSON.stringify({"items":items}))
 file.close()
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST",path)
 var build_start := Time.get_ticks_usec()
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.enter_library()
 var view = scene.library_view
 view._select(0) # Explicit deterministic fixture choice after random startup.
 view.set_process(false)
 var build_ms := float(Time.get_ticks_usec()-build_start)/1000.0
 check(view.ITEMS.size()==1000, "Synthetic fixture retains all1000 metadata entries")
 check(view.cards.size()==3, "1000 entries instantiate only3 reusable card controls")
 if view.cards.size()!=3:
  scene.queue_free()
  await process_frame
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
  push_error("Virtualization integration patch is not installed")
  quit(1)
  return
 check(view.neighbor_boxes.size()==4, "3D residency remains selected plus4distinct neighbors")
 check(visual_order(view)==[999,0,1], "First selected entry displays true previous/current/next wrap")
 for card in view.cards:
  var index := int(card.get_meta("catalog_index"))
  check(card.get_node("CardTitle").text==items[index].title, "Recycled card text is bound to its actual catalog entry")
 var retained := card_for(view,1)
 retained.grab_focus()
 view._select(1)
 await process_frame
 check(root.gui_get_focus_owner()==retained and card_for(view,1)==retained, "Focus follows retained entry without allocating another control")
 view._select(0)
 await process_frame
 var recycled := card_for(view,999)
 recycled.grab_focus()
 view._select(2)
 await process_frame
 check(root.gui_get_focus_owner()==card_for(view,2), "Evicted focused entry transfers focus safely to selected card")
 check(int(recycled.get_meta("catalog_index"))!=999, "Old button instance is genuinely recycled for another entry")
 var target := int(recycled.get_meta("catalog_index"))
 recycled.pressed.emit()
 await process_frame
 check(view.current_index==target and view.current_index!=999, "Recycled pointer callback uses current metadata, never a captured stale index")
 view._select(999)
 await process_frame
 check(visual_order(view)==[998,999,0], "Last entry preserves relative wrap order rather than sorting catalog indices")
 var mapped := card_for(view,0)
 mapped.grab_focus()
 view._activate_focused()
 await process_frame
 check(view.current_index==0 and view.presentation.state==&"presented", "Focused recycled card confirms its own item and presents the same box")
 view.go_back()
 await process_frame
 check(view.current_index==0 and not view.inspect_mode, "Returning from presentation keeps selected catalog identity")
 for texture in view.card_textures: check(texture.texture==null, "Hidden thumbnail slots never retain decoded artwork")
 var selection_ms: Array[float] = []
 for target_index in [0,999,432,1,998,500,499,2,997,0]:
  var selection_start := Time.get_ticks_usec()
  view._select(target_index)
  selection_ms.append(float(Time.get_ticks_usec()-selection_start)/1000.0)
  check(view.current_index==target_index and view.cards.size()==3 and view.neighbor_boxes.size()<=4, "Measured navigation preserves index and bounded residency")
  await process_frame
 var card_count: int = view.cards.size()
 var button_count: int = view.all_buttons.size()
 var resident_box_count: int = view.neighbor_boxes.size()+1
 var start := Time.get_ticks_usec()
 for repeat in 20: view.layout()
 var layout_ms := float(Time.get_ticks_usec()-start)/20000.0
 check(view.cards.size()==3 and view.all_buttons.size()<=15, "UI-control residency remains constant after navigation and inspection")
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST","")
 print("LIBRARY_VIRTUALIZATION_TESTS ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"layout_mean_ms":layout_ms,"total_scene_build_ms":build_ms,"selection_ms":selection_ms,"card_controls":card_count,"all_button_count":button_count,"resident_boxes":resident_box_count,"fixture":"1000 synthetic metadata entries, not real inventory; synthetic input only"}))
 quit(0 if failures.is_empty() else 1)
