extends PopupMenu
var profile
func _input(event: InputEvent) -> void:
 if not visible or profile == null: return
 var action: String = profile.action_for(event)
 if action == "back":
  hide()
  get_viewport().set_input_as_handled()
 elif action == "confirm":
  var index := get_focused_item()
  if index >= 0:
   index_pressed.emit(index)
   id_pressed.emit(get_item_id(index))
   hide()
  get_viewport().set_input_as_handled()
