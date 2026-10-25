extends SceneTree
## Synthetic index/residency tests only. Never represents a real collection.
const CatalogWindow = preload("res://cosmic/library_window.gd")
var assertions := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
 assertions += 1
 if not value: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func validate(entries: Array[Dictionary], count: int, selected: int, cap: int, previous: Array[Dictionary]) -> void:
 check(entries.size() == mini(count,cap), "Residency count is bounded by actual catalog and pool")
 var indices := {}
 var slots := {}
 for entry in entries:
  check(entry.index >= 0 and entry.index < count, "Slot refers only to a real catalog index")
  check(not indices.has(entry.index) and not slots.has(entry.slot), "No duplicate catalog entries or recycled slot ownership")
  check(entry.slot >= 0 and entry.slot < cap, "Slot ID is bounded")
  check(entry.index == posmod(selected+entry.offset,count), "Relative position maps to exact selected neighbor, including wrap")
  for old in previous:
   if old.index == entry.index: check(old.slot == entry.slot, "Retained entry reuses the same slot")
  indices[entry.index] = true
  slots[entry.slot] = true
 check(selected < 0 or indices.has(selected), "The actual selected entry always remains resident")
func run() -> void:
 var window := CatalogWindow.new()
 for count in [0,1,2,3,4,5,1000]:
  window.configure(count)
  if count == 0:
   check(window.selected == -1 and window.card_slots().is_empty() and window.box_slots().is_empty(), "Empty catalog creates no invented box")
   check(not window.select_index(0), "Empty catalog rejects selection")
   continue
  var previous_cards: Array[Dictionary] = []
  var previous_boxes: Array[Dictionary] = []
  # Deterministic traversal tests pooling, not a random-choice feature.
  var sequence: Array[int] = [0,count-1,0]
  for index in count: sequence.append(index)
  for index in count: sequence.append(count-1-index)
  for selected in sequence:
   check(window.select_index(selected), "Existing index is accepted")
   var cards := window.card_slots()
   var boxes := window.box_slots()
   validate(cards,count,selected,3,previous_cards)
   validate(boxes,count,selected,5,previous_boxes)
   for index in range(1,cards.size()): check(cards[index-1].offset < cards[index].offset, "Cards remain previous/current/next, never globally index-sorted")
   previous_cards = cards
   previous_boxes = boxes
  var before := window.card_slots()
  check(not window.select_index(-1) and not window.select_index(count), "Invalid index cannot replace current selection")
  check(window.card_slots() == before, "Rejected selection does not mutate slot ownership")
  var exposed := window.card_slots()
  exposed[0].index = -999
  check(window.card_slots()[0].index >= 0, "Returned plans cannot corrupt internal identity")
 window.configure(1000,0)
 check(window.card_slots().map(func(e: Dictionary): return e.index) == [999,0,1], "Extreme wrap has correct visual order999/0/1")
 window.select_index(999)
 check(window.card_slots().map(func(e: Dictionary): return e.index) == [998,999,0], "Last entry retains preceding/current/following order")
 print("LIBRARY_WINDOW_TESTS ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"fixture":"1000 synthetic indices; no ROMs, media or user inventory"}))
 quit(0 if failures.is_empty() else 1)
