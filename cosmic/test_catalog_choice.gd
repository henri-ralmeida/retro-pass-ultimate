extends SceneTree
## Synthetic metadata only. These fixtures are not the user's collection,
## do not read ROMs and do not assert game identity or artwork availability.
const Choice = preload("res://cosmic/catalog_choice.gd")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func fixture(count: int) -> Array[Dictionary]:
 var items: Array[Dictionary] = []
 for index in count:
  items.append({"id":"fixture_%04d" % index, "title":"Synthetic record %04d" % index})
 return items

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 _test_empty_single_and_filtering()
 _test_visit_and_explicit_selection()
 _test_catalog_changes()
 _test_rng_injection_and_order()
 _test_large_catalog_multiseed()
 _test_missing_records()
 print("CATALOG_CHOICE: ", assertions, " assertions; ", failures.size(), " failures")
 quit(0 if failures.is_empty() else 1)

func _test_empty_single_and_filtering() -> void:
 var rng := RandomNumberGenerator.new()
 rng.seed = 39
 var choice := Choice.new(rng)
 var original_state := rng.state
 check(choice.get_status() == "empty" and choice.get_selected_index() == -1, "New chooser has explicit empty fallback")
 check(choice.begin_visit().is_empty(), "Empty visit has no fabricated ID")
 check(choice.is_visit_active(), "Empty visits still have a lifecycle")
 check(choice.begin_visit().is_empty(), "Repeated empty visit is stable")
 check(not choice.select_explicit("absent"), "Unknown selection is rejected")
 var entries: Array[Dictionary] = [
  {}, {"id":""}, {"id":"  \t "}, {"id":null}, {"id":42},
  {"id":"unavailable"}, {"id":" UNAVAILABLE "},
  {"id":"placeholder_a", "placeholder":true},
  {"id":"placeholder_b", "is_placeholder":true},
  {"id":"only", "title":"No cover, still an eligible record"},
  {"id":"only", "title":"Duplicate must not gain another chance"}
 ]
 check(choice.update_catalog(entries) == "only", "Catalog filling during a visit uses deterministic fallback")
 check(choice.get_status() == "single" and choice.get_eligible_count() == 1, "Placeholder, blank, malformed and duplicate IDs excluded")
 check(choice.get_selected_index() == 9, "Selected index points to first eligible source occurrence")
 check(choice.begin_visit() == "only", "Unique entry is stable")
 for visit in 20:
  choice.end_visit()
  check(choice.begin_visit() == "only", "Unique record is reused rather than pretending not to repeat")
 check(rng.state == original_state, "Empty and single-record fallbacks consume no random draws")
 var exported := choice.get_eligible_ids()
 exported.clear()
 entries[9]["id"] = "mutated_outside"
 check(choice.get_eligible_count() == 1 and choice.get_selected_id() == "only", "Caller mutation cannot change chooser snapshot")
 choice.update_catalog([])
 check(choice.get_selected_id().is_empty() and choice.get_selected_index() == -1 and choice.get_status() == "empty", "Removing all records restores explicit empty fallback")

func _test_visit_and_explicit_selection() -> void:
 var rng := RandomNumberGenerator.new()
 rng.seed = 601
 var choice := Choice.new(rng)
 var entries := fixture(7)
 var original_state := rng.state
 choice.update_catalog(entries)
 check(choice.get_status() == "ready" and choice.get_selected_id().is_empty(), "Catalog loading before entry does not select a game")
 check(rng.state == original_state, "Catalog loading does not consume RNG")
 var selected: String = choice.begin_visit()
 var selected_state := rng.state
 check(choice.get_status() == "random" and not selected.is_empty(), "First multi-record visit draws one eligible record")
 for redraw in 100:
  check(choice.begin_visit() == selected, "Repeated entry/redraw calls retain selected ID")
  check(choice.get_selected_id() == selected and entries[choice.get_selected_index()].id == selected, "Read getters agree with source array")
 check(rng.state == selected_state, "Repeated entry, redraw and focus-style reads consume no RNG")
 check(not choice.select_explicit("unavailable") and not choice.select_explicit("missing"), "Invalid explicit IDs cannot replace selection")
 check(choice.get_selected_id() == selected, "Rejected explicit selection preserves current entry")
 check(choice.select_explicit("fixture_0003"), "Explicit navigation accepts a valid stable ID")
 check(choice.get_status() == "explicit" and choice.begin_visit() == "fixture_0003", "Explicit navigation stays stable in the current visit")
 check(rng.state == selected_state, "Explicit navigation consumes no RNG")
 choice.end_visit()
 check(not choice.is_visit_active(), "Host can finish the visit without clearing its history")
 check(choice.begin_visit() != "fixture_0003", "New random visit excludes the last explicitly displayed record")
 var previous: String = choice.get_selected_id()
 for visit in 500:
  choice.end_visit()
  var next: String = choice.begin_visit()
  check(next != previous, "Consecutive visits never repeat with multiple eligible IDs")
  previous = next
 var pair := Choice.new(null, 17)
 pair.update_catalog(fixture(2))
 previous = pair.begin_visit()
 for visit in 50:
  pair.end_visit()
  var next: String = pair.begin_visit()
  check(next != previous, "Two-record catalog alternates without retry loops")
  previous = next

func _test_catalog_changes() -> void:
 var rng := RandomNumberGenerator.new()
 rng.seed = 127
 var choice := Choice.new(rng)
 var entries := fixture(20)
 choice.update_catalog(entries)
 var selected: String = choice.begin_visit()
 var rng_state := rng.state
 entries.reverse()
 check(choice.update_catalog(entries) == selected, "Reordered catalog preserves selected ID")
 check(choice.get_status() == "preserved" and entries[choice.get_selected_index()].id == selected, "Reorder remaps source index without changing identity")
 entries.append({"id":"fixture_added", "title":"New synthetic record"})
 check(choice.update_catalog(entries) == selected, "Adding records does not reroll active selection")
 var current_index := choice.get_selected_index()
 entries.remove_at(current_index)
 var recovered: String = choice.update_catalog(entries)
 check(not recovered.is_empty() and recovered != selected, "Removing selected record chooses an existing fallback")
 check(choice.get_status() == "recovered", "Removal recovery is explicitly distinguished from a random draw")
 check(recovered == choice.get_eligible_ids()[0], "Removal fallback is deterministic canonical first ID")
 check(choice.begin_visit() == recovered and entries[choice.get_selected_index()].id == recovered, "Recovered selection is stable and references its own source record")
 check(rng.state == rng_state, "Reordering, addition and removal never consume RNG")
 choice.update_catalog([])
 check(choice.begin_visit().is_empty(), "Catalog emptied mid-visit stays empty")
 choice.update_catalog(entries)
 check(choice.get_selected_id() == recovered and rng.state == rng_state, "Refilling active visit recovers without a surprise draw")
 choice.end_visit()
 check(choice.begin_visit() != recovered, "Next visit excludes recovered last displayed ID")
 var single: Array[Dictionary] = [{"id":choice.get_selected_id()}]
 choice.update_catalog(single)
 check(choice.get_status() == "single" and choice.get_selected_index() == 0, "Shrinking catalog to its selected record handles one-item case")
 choice.end_visit()
 choice.update_catalog(fixture(3))
 check(rng.state != rng_state, "Completed next visit did advance RNG")
 var after_visit_state := rng.state
 choice.update_catalog([])
 choice.update_catalog(fixture(3))
 check(rng.state == after_visit_state and choice.get_selected_id().is_empty(), "Closed-visit catalog changes do not silently start a visit")
 choice.begin_visit()
 check(choice.get_status() == "random", "Next actual visit can select from changed catalog")

func _test_rng_injection_and_order() -> void:
 var entries := fixture(31)
 var reordered := entries.duplicate(true)
 reordered.reverse()
 var first := Choice.new(null, 2026)
 var second := Choice.new(null, 2026)
 var injected := RandomNumberGenerator.new()
 injected.seed = 2026
 var third := Choice.new(injected)
 first.update_catalog(entries)
 second.update_catalog(reordered)
 third.update_catalog(entries)
 for visit in 300:
  var id: String = first.begin_visit()
  check(second.begin_visit() == id, "Equal seed gives equal ID sequence independent of source order")
  check(third.begin_visit() == id, "Injected RNG preserves its caller-supplied seed")
  first.end_visit()
  second.end_visit()
  third.end_visit()

func _test_large_catalog_multiseed() -> void:
 var entries := fixture(1000)
 # Add duplicates at nonadjacent positions and a UI placeholder. Neither adds
 # random weight. Tests assert broad coverage, never exactly equal frequencies.
 entries.append(entries[15].duplicate(true))
 entries.append({"id":"unavailable", "title":"No catalog"})
 var total_visits := 0
 var union_seen := {}
 var counts := {}
 var minimum_coverage := 1000
 for seed_value in [0, 1, 7, 42, 901, 2026, 65537, 982451653]:
  var choice := Choice.new(null, seed_value)
  choice.update_catalog(entries)
  check(choice.get_eligible_count() == 1000, "Exactly 1,000 unique synthetic records remain eligible")
  var seen := {}
  var previous := ""
  for visit in 6000:
   var id: String = choice.begin_visit()
   check(id != previous and not id.is_empty(), "Large catalog selection is nonempty and never immediately repeats")
   var index := choice.get_selected_index()
   check(index >= 0 and index < 1000 and entries[index].id == id, "Large catalog always selects an original eligible record")
   seen[id] = true
   union_seen[id] = true
   counts[id] = int(counts.get(id, 0)) + 1
   previous = id
   total_visits += 1
   choice.end_visit()
  minimum_coverage = mini(minimum_coverage, seen.size())
  check(seen.size() >= 970, "Each seed covers at least 97% of 1,000 records in 6,000 visits")
 check(union_seen.size() == 1000, "Multiple deterministic seeds collectively reach every synthetic record")
 var minimum_hits := total_visits
 var maximum_hits := 0
 for hits in counts.values():
  minimum_hits = mini(minimum_hits, int(hits))
  maximum_hits = maxi(maximum_hits, int(hits))
 var expected := float(total_visits) / 1000.0
 check(minimum_hits >= expected * 0.25 and maximum_hits <= expected * 2.0, "Wide statistical bounds detect strong bias without requiring equal frequencies")
 print("CATALOG_CHOICE_COVERAGE: synthetic=1000 seeds=8 visits=", total_visits,
  " union=", union_seen.size(), " minimum_per_seed=", minimum_coverage,
  " min_hits=", minimum_hits, " max_hits=", maximum_hits)

func _test_missing_records() -> void:
 var choice := Choice.new(null,17)
 var items: Array[Dictionary] = [{"id":"present_a","file_status":"present","available_for_random":true},{"id":"missing_a","file_status":"missing","available_for_random":false},{"id":"present_b","file_status":"present"},{"id":"disabled","available_for_random":false}]
 choice.update_catalog(items)
 check(choice.get_eligible_count()==2,"Missing/disabled records stay out of random pool")
 for visit in 40:
  choice.end_visit()
  var selected: String = choice.begin_visit()
  check(selected in ["present_a","present_b"],"Random visit never picks missing or disabled record")
 check(choice.select_explicit("missing_a") and choice.get_selected_index()==1,"Missing record remains explicitly selectable for catalog inspection")
 check(choice.get_status()=="explicit_unavailable","Missing explicit selection is not labeled available")
 choice.begin_visit()
 check(choice.get_selected_id()=="missing_a","Redraw preserves explicit missing record without reroll")
 choice.end_visit()
 check(choice.begin_visit() in ["present_a","present_b"],"A new random visit returns to eligible records")
 var absent: Array[Dictionary] = [{"id":"only_missing","file_status":"missing"}]
 choice.update_catalog(absent)
 choice.end_visit()
 check(choice.begin_visit().is_empty() and choice.get_status()=="unavailable","All-missing collection reports no random candidate, not a fabricated game")
 check(choice.select_explicit("only_missing") and choice.get_selected_index()==0,"All-missing metadata can still be reviewed manually")
