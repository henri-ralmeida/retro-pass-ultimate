extends RefCounted
## Display-only reversible timeline. No scene, camera, input, ROM or asset access.
const DURATIONS := [0.8, 0.65, 0.9, 0.55]
const TOTAL := 2.9
var time := 0.0
var target := 0.0
var reduced_motion := false

func request_insert() -> void:
 target = TOTAL
 if reduced_motion: time = target

func request_return() -> void:
 target = 0.0
 if reduced_motion: time = target

func tick(delta: float, focused: bool = true) -> void:
 if focused and is_finite(delta) and delta > 0.0:
  time = move_toward(time, target, delta)

func sample() -> Dictionary:
 var start := 0.0
 var result := {}
 var labels := ["open", "extract", "align", "insert"]
 for i in 4:
  var p := clampf((time - start) / DURATIONS[i], 0.0, 1.0)
  result[labels[i]] = p * p * (3.0 - 2.0 * p)
  start += DURATIONS[i]
 return result

func state() -> String:
 if time == 0.0: return "opening" if target > time else "closed"
 if time == TOTAL: return "returning" if target < time else "seated"
 if target < time: return "returning"
 var p := sample()
 if p.open < 1.0: return "opening"
 if p.extract < 1.0: return "extracting"
 if p.align < 1.0: return "aligning"
 return "inserting"
