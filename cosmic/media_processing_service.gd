extends RefCounted
## Main-thread API; worker owns queue/file/hash, shared snapshots use a mutex.
const Queue = preload("res://cosmic/media_local_queue.gd")
const Association = preload("res://cosmic/media_result_association.gd")
var _association: Dictionary = {}
var _thread: Thread
var _mutex := Mutex.new()
var _cancel_requested := false
var _snapshot: Dictionary = {"status":"idle", "operation":"local_processing"}
var _result: Dictionary = {}

func begin(plan: Dictionary, journal: String, confirmed: bool, resume: bool = false, inventory: Array = []) -> Error:
 if not confirmed: return ERR_UNAUTHORIZED
 if is_busy(): return ERR_BUSY
 reap()
 _mutex.lock()
 _cancel_requested = false
 _snapshot = {"status":"starting", "operation":"local_processing"}
 _result = {}
 _association = {}
 _mutex.unlock()
 _thread = Thread.new()
 var error := _thread.start(_work.bind(plan.duplicate(true), journal, resume, inventory.duplicate(true)))
 if error != OK:
  _publish({"status":"thread_error", "operation":"local_processing", "error":error})
 return error

func is_busy() -> bool:
 return _thread != null and _thread.is_alive()

func request_cancel() -> void:
 _mutex.lock()
 _cancel_requested = true
 _mutex.unlock()

func poll() -> Dictionary:
 _mutex.lock()
 var copy: Dictionary = _snapshot.duplicate(true)
 _mutex.unlock()
 reap()
 return copy

func result() -> Dictionary:
 _mutex.lock()
 var copy: Dictionary = _result.duplicate(true)
 _mutex.unlock()
 return copy

func association_result() -> Dictionary:
 _mutex.lock()
 var copy := _association.duplicate(true)
 _mutex.unlock()
 return copy

func reap() -> void:
 if _thread != null and _thread.is_started() and not _thread.is_alive():
  _thread.wait_to_finish()
  _thread = null

func shutdown() -> void:
 # Owner MUST call before freeing; cancellation is checked between bounded reads.
 request_cancel()
 if _thread != null and _thread.is_started(): _thread.wait_to_finish()
 _thread = null

func _cancelled() -> bool:
 _mutex.lock()
 var value := _cancel_requested
 _mutex.unlock()
 return value

func _publish(snapshot: Dictionary) -> void:
 _mutex.lock()
 _snapshot = snapshot.duplicate(true)
 _mutex.unlock()

func _work(plan: Dictionary, journal: String, resume: bool, inventory: Array) -> void:
 var queue := Queue.new()
 var error := queue.restore(plan, journal) if resume else queue.start(plan, journal)
 if error != OK:
  _publish({"status":"setup_error", "operation":"local_processing", "error":error})
  return
 while true:
  if _cancelled(): queue.cancel()
  var snapshot := queue.progress() if _cancelled() else queue.tick()
  _publish(snapshot)
  if snapshot.status in ["done", "completed_with_errors", "cancelled", "storage_error"]: break
 _mutex.lock()
 _result = queue.state.duplicate(true)
 _mutex.unlock()

 # Format validation and exact association stay off the main/render thread.
 if not _cancelled() and queue.state.status in ["done", "completed_with_errors"] and not inventory.is_empty():
  var validating := queue.progress()
  validating.status = "validating_images"
  _publish(validating)
  var associated: Dictionary = Association.build(queue.state, inventory, _cancelled)
  _mutex.lock()
  if not _cancel_requested: _association = associated
  _mutex.unlock()
  if _cancelled():
   queue.cancel()
   _mutex.lock()
   _result = queue.state.duplicate(true)
   _mutex.unlock()
  var final_snapshot := queue.progress()
  final_snapshot["links_validated"] = associated.get("applied", 0) if not _cancelled() else 0
  _publish(final_snapshot)
