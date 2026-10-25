extends RefCounted
## Restore validates source bytes in its own worker, never on the render thread.
const Bindings = preload("res://cosmic/media_binding_store.gd")
var _thread: Thread
var _mutex := Mutex.new()
var _cancelled := false
var _result: Dictionary = {}
func begin(bindings: Array, items: Array) -> Error:
 if _thread != null: return ERR_BUSY
 _cancelled = false
 _result = {}
 _thread = Thread.new()
 var error := _thread.start(_work.bind(bindings.duplicate(true),items.duplicate(true)))
 if error != OK: _thread = null
 return error
func is_busy() -> bool:
 return _thread != null and _thread.is_alive()
func take_result() -> Dictionary:
 if _thread == null or _thread.is_alive(): return {}
 _thread.wait_to_finish()
 _thread = null
 _mutex.lock()
 var result := _result.duplicate(true)
 _result = {}
 _mutex.unlock()
 return result
func _is_cancelled() -> bool:
 _mutex.lock()
 var result := _cancelled
 _mutex.unlock()
 return result
func _work(bindings: Array, items: Array) -> void:
 var result := Bindings.restore(bindings,items,_is_cancelled)
 _mutex.lock()
 if not _cancelled: _result = result
 _mutex.unlock()
func request_cancel() -> void:
 _mutex.lock()
 _cancelled = true
 _result = {}
 _mutex.unlock()
func shutdown() -> void:
 request_cancel()
 if _thread != null and _thread.is_started(): _thread.wait_to_finish()
 _thread = null
 _result = {}
