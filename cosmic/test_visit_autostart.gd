extends SceneTree
const Intent = preload("res://cosmic/visit_autostart.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures.append(message)
func _initialize() -> void:
 var intent := Intent.new()
 var first := intent.arm("adventure_variant_a")
 check(not intent.consume(first,"other_variant"),"Wrong variant cannot consume")
 check(intent.consume(first,"adventure_variant_a"),"Matching visit consumed once")
 check(not intent.consume(first,"adventure_variant_a"),"Repeated callback ignored")
 var second := intent.arm("adventure_variant_a")
 check(second!=first and not intent.consume(first,"adventure_variant_a"),"Old callback cannot consume new visit")
 intent.cancel()
 check(not intent.consume(second,"adventure_variant_a"),"Focus/cancel invalidates pending intent")
 for id in ["", "unavailable"]:
  var token := intent.arm(id)
  check(not intent.consume(token,id),"No invented eligible title")
 for cycle in 100:
  var token := intent.arm("explicit_variant")
  check(intent.consume(token,"explicit_variant"),"New visit works")
  check(not intent.consume(token,"explicit_variant"),"New visit never repeats")
 for error in failures: push_error(error)
 print("VISIT AUTOSTART: ",checks," checks, ",failures.size()," failures")
 quit(0 if failures.is_empty() else 1)
