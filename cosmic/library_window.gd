extends RefCounted
## Pure bounded residency plan. This does not scan, invent entries, select at
## random, instantiate models, or modify artwork. Slot IDs are reusable UI/3D
## handles, not catalog indices. Preserve catalog identity separately.
const MAX_CARD_SLOTS := 3
const MAX_BOX_SLOTS := 5
var count := 0
var selected := -1
var _cards: Array[Dictionary] = []
var _boxes: Array[Dictionary] = []

func configure(item_count: int, initial_index: int = 0) -> void:
 count = maxi(0,item_count)
 selected = clampi(initial_index,0,count-1) if count > 0 else -1
 _cards.clear()
 _boxes.clear()
 if selected >= 0: _update()

func select_index(index: int) -> bool:
 if index < 0 or index >= count: return false
 selected = index
 _update()
 return true

func card_slots() -> Array[Dictionary]: return _cards.duplicate(true)
func box_slots() -> Array[Dictionary]: return _boxes.duplicate(true)

func _update() -> void:
 _cards = _allocate(_cards,[0,-1,1],MAX_CARD_SLOTS)
 _cards.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.offset) < int(b.offset))
 _boxes = _allocate(_boxes,[0,-1,1,-2,2],MAX_BOX_SLOTS)

func _allocate(previous: Array[Dictionary], offsets: Array, capacity: int) -> Array[Dictionary]:
 var wanted: Array[Dictionary] = []
 var seen := {}
 for offset in offsets:
  var index := posmod(selected+int(offset),count)
  if seen.has(index): continue
  seen[index] = true
  wanted.append({"index":index,"offset":int(offset),"slot":-1})
 var used := {}
 for entry in wanted:
  for old in previous:
   if old.index == entry.index:
    entry.slot = old.slot
    used[old.slot] = true
    break
 for entry in wanted:
  if entry.slot >= 0: continue
  for slot in capacity:
   if not used.has(slot):
    entry.slot = slot
    used[slot] = true
    break
 return wanted
