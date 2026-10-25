extends RefCounted
## Read-only presentation state. No credentials, network, writes or guessed progress.
const FILTERS := ["all","unlocked","locked","beaten","missable"]
const SORTS := ["ra","az","za","points","points_low","rarity","rarity_common","status","locked_first"]
var achievements: Array[Dictionary] = []
var filter := "all"
var sort := "ra"
var mode := "hardcore"

func set_records(records: Array) -> void:
 achievements.clear()
 var seen := {}
 for raw in records:
  if not raw is Dictionary: continue
  var id := str(raw.get("id",""))
  if id.is_empty() or seen.has(id): continue
  seen[id] = true
  var row: Dictionary = raw.duplicate(true)
  row["id"] = id
  row["title"] = str(raw.get("title","Sem título")).left(300)
  row["description"] = str(raw.get("description","")).left(3000)
  row["points"] = maxi(0,int(raw.get("points",0)))
  # Mode-specific only; a softcore unlock is never a hardcore unlock.
  row["unlocked_hardcore"] = raw.get("unlocked_hardcore",false) == true
  row["unlocked_softcore"] = raw.get("unlocked_softcore",false) == true
  achievements.append(row)

func unlocked(row: Dictionary) -> bool:
 return row.get("unlocked_hardcore" if mode == "hardcore" else "unlocked_softcore",false) == true

func visible_records() -> Array[Dictionary]:
 var result: Array[Dictionary] = []
 for row in achievements:
  if filter == "unlocked" and not unlocked(row): continue
  if filter == "locked" and unlocked(row): continue
  if filter == "beaten" and row.get("type","") not in ["progression","win_condition"]: continue
  if filter == "missable" and row.get("type","") != "missable": continue
  result.append(row)
 result.sort_custom(func(a: Dictionary,b: Dictionary):
  if filter == "beaten" and a.get("type","") != b.get("type",""): return a.get("type","") == "progression"
  match sort:
   "az": return a.title.naturalnocasecmp_to(b.title) < 0
   "za": return a.title.naturalnocasecmp_to(b.title) > 0
   "points":
    if a.points != b.points: return a.points > b.points
   "points_low":
    if a.points != b.points: return a.points < b.points
   "rarity","rarity_common":
    var av := float(a.get("rarity_"+mode,101))
    var bv := float(b.get("rarity_"+mode,101))
    if av == 101 and bv != 101: return false
    if bv == 101 and av != 101: return true
    if av != bv: return av < bv if sort == "rarity" else av > bv
   "status","locked_first":
    if unlocked(a) != unlocked(b): return unlocked(a) if sort == "status" else not unlocked(a)
  var ao := int(a.get("display_order",0))
  var bo := int(b.get("display_order",0))
  return ao < bo if ao != bo else str(a.id).naturalnocasecmp_to(str(b.id)) < 0
 )
 return result

func summary() -> Dictionary:
 var done := 0
 var points := 0
 var earned := 0
 for row in achievements:
  points += row.points
  if unlocked(row):
   done += 1
   earned += row.points
 return {"total":achievements.size(),"unlocked":done,"points":points,"earned":earned,
  "complete":not achievements.is_empty() and done == achievements.size(),
  "percentage":100.0*done/achievements.size() if not achievements.is_empty() else 0.0}
