extends SceneTree
## Synthetic public metadata only. No private catalog, directory scan or ROMs.
## Checks real UI geometry and binding, not visual or physical-controller QA.
const Import = preload("res://cosmic/catalog_import.gd")
var assertions := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)

func card_for(view: Control, index: int) -> Button:
 for card in view.cards:
  if int(card.get_meta("catalog_index", -1)) == index: return card
 return null

func run() -> void:
 var games: Array[Dictionary] = []
 for index in 5:
  games.append({"source_group":"Master System", "path":"Synthetic source folder/Synthetic %d.zip" % index, "name":"Synthetic shared title", "file_status":"present", "region_hint":"jp", "filename_variant_hints":["Europe, Brazil", "En", "Rev %d" % index]})
 var manifest := Import.adapt({"games":games})
 # Simulate an older runtime export: the loader must rebuild its generic label.
 for item in manifest.items: item.subtitle = "MASTER SYSTEM · INVENTÁRIO"
 manifest.items.append({"id":"synthetic-local", "title":"Synthetic local entry", "subtitle":"LOCAL LABEL"})
 var path := "user://synthetic_inventory_labels.json"
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_string(JSON.stringify(manifest))
 file.close()
 var previous_manifest := OS.get_environment("RETROPASS_BOX_ART_MANIFEST")
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST", path)
 root.size = Vector2i(1152,648)
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.enter_library()
 var view = scene.library_view
 view.set_process(false)
 view._select(0)
 var selected_id: String = view.catalog_choice.get_selected_id()
 check(view.ITEMS.size() == 6 and view.cards.size() == 3, "Labels preserve all records and bounded card residency")
 check(view.ITEMS[0].title == view.ITEMS[1].title and view.ITEMS[0].subtitle != view.ITEMS[1].subtitle, "Loader distinguishes repeated titles in an old manifest")
 check(view.disclosure.text == "Inventário de origem · presença local não verificada · sem execução", "Header never claims source inventory is locally verified")
 check("INVENTÁRIO DE ORIGEM" in view.chapter.text and not "ACERVO LOCAL" in view.chapter.text, "Selected metadata chapter names the correct origin")
 check("Rev 0" in card_for(view,0).accessibility_name and "não verificada" in card_for(view,0).tooltip_text, "Accessible labels expose variant hints and their uncertainty")
 for window_size in [Vector2i(1152,648), Vector2i(1024,768), Vector2i(800,600)]:
  root.size = window_size
  await process_frame
  view.layout()
  for card in view.cards:
   if not card.is_visible_in_tree(): continue
   var index := int(card.get_meta("catalog_index"))
   var subtitle: Label = card.get_node("CardSubtitle")
   if Import.is_source_inventory(view.ITEMS[index]):
    check(subtitle.visible and subtitle.text == view.ITEMS[index].subtitle, "Recycled inventory tabs display their own variant")
    check(subtitle.clip_text and subtitle.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Long variant labels remain bounded")
    check(subtitle.get_global_rect().end.x <= card.get_global_rect().end.x and subtitle.get_global_rect().end.y <= card.get_global_rect().end.y, "Variant line remains inside its tab")
   check(card.get_global_rect().end.y <= view.help_label.get_global_rect().position.y, "Two-line tabs never overlap navigation help")
  check(view.catalog_choice.get_selected_id() == selected_id, "Resize never changes random or explicit selection")
 view._select(3)
 check("Rev 3" in card_for(view,3).get_node("CardSubtitle").text, "Recycled controls update variant labels after navigation")
 check("Rev 3" in card_for(view,3).tooltip_text, "Recycled tooltip never retains a previous variant")
 selected_id = view.catalog_choice.get_selected_id()
 view.toggle_inspection()
 check(not view.chapter.visible and not view.disclosure.visible, "Inspection still hides catalog chrome")
 for card in view.cards: check(not card.visible, "Inspection still hides every tab")
 view.go_back()
 check(view.catalog_choice.get_selected_id() == selected_id and card_for(view,3).get_node("CardSubtitle").visible, "Back restores labels without rerolling")
 view._select(5)
 check(view.disclosure.text == "Acervo local · sem execução" and "ACERVO LOCAL" in view.chapter.text, "Switching to a legacy local entry restores its existing origin labels")
 check(not card_for(view,5).get_node("CardSubtitle").visible and card_for(view,5).size.y == maxf(34, card_for(view,5).custom_minimum_size.y), "Legacy local tab retains its original compact layout")
 view.disclosure.text = "Synthetic local scan status"
 view._select(5)
 check(view.disclosure.text == "Synthetic local scan status", "Local navigation preserves completed scanner status")
 # A non-running sentinel simulates only the UI's busy state, never a scan.
 view.scan_thread = Thread.new()
 view.disclosure.text = "Synthetic scan in progress"
 view._select(0)
 check(view.disclosure.text == "Synthetic scan in progress", "Metadata selection cannot overwrite an active scanner disclosure")
 view.scan_thread = null
 view._select(0)
 check("Inventário de origem" in view.disclosure.text, "Returning to source metadata restores the honest header")
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST", previous_manifest)
 print("LIBRARY_INVENTORY_LABELS ", JSON.stringify({"assertions":assertions, "passed":failures.is_empty(), "failures":failures, "fixture":"synthetic public metadata only; no media or ROM reads"}))
 quit(0 if failures.is_empty() else 1)
