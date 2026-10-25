## Synthetic local pages; no real manual or private catalog needed.
extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await create_timer(0.5).timeout
 scene.auto_history_armed = false
 scene.reduced_motion = true
 scene._focus_returned()
 scene.enter_library()
 var view = scene.library_view
 var selected := 0
 var fixture_path := "user://synthetic_viewport_manual.png"
 var image := Image.create(160,240,false,Image.FORMAT_RGBA8)
 image.fill(Color(0.2,0.45,0.65))
 image.save_png(fixture_path)
 var entry: Dictionary = view.ITEMS[0].duplicate(true)
 entry.id = "synthetic_viewport_manual"
 entry.title = "Synthetic manual geometry fixture"
 entry.manual_item_id = entry.id
 entry.erase("manual_game_id")
 entry.manual_pages = [fixture_path,fixture_path]
 view.ITEMS.clear()
 view.ITEMS.append(entry)
 var results: Array[Dictionary] = []
 for dimensions in [Vector2i(1152,648),Vector2i(1024,768)]:
  root.size = dimensions
  await process_frame
  await process_frame
  for amount in [1.0,1.4]:
   view.close()
   view.open()
   view._select(selected)
   view.confirm_selected()
   view.zoom_inspection(amount-1.0)
   view._open_manual()
   if not view.manual_reader.visible: failures.append("Open failed %s zoom%s: %s" % [dimensions,amount,view.manual_status])
   var diagnostic: Dictionary = view.manual_release_diagnostics.back() if not view.manual_release_diagnostics.is_empty() else {}
   if not diagnostic.get("clear",false) or not diagnostic.get("inside",false): failures.append("Endpoint not clear/inside")
   view.go_back()
   if absf(view.zoom-amount)>0.001: failures.append("Original inspection zoom not restored")
   if not view.box.manual_book.root.visible: failures.append("Source missing")
   results.append({"size":dimensions,"requested_zoom":amount,"restored_zoom":view.zoom,"endpoint":diagnostic})
 scene.reduced_motion = false
 view.zoom_inspection(1.4-view.zoom)
 view._open_manual()
 if not view.manual_framing_active: failures.append("Expected automatic framing at4:3 max zoom")
 view._advance_manual_framing(0.1)
 var before: float = view.zoom
 scene._focus_lost()
 view._process(1.0)
 if not is_equal_approx(view.zoom,before): failures.append("Framing must pause while unfocused")
 scene._focus_returned()
 view.go_back()
 view._advance_manual_framing(1.0)
 if view.manual_reader.visible or not is_equal_approx(view.zoom,1.4): failures.append("Cancel framing must restore zoom without opening")
 print("MANUAL_VIEWPORT_TESTS ",JSON.stringify({"passed":failures.is_empty(),"failures":failures,"results":results}))
 view.close()
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
 quit(0 if failures.is_empty() else 1)
