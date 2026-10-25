extends SceneTree
const Pdf = preload("res://cosmic/manual_pdf_service.gd")
const Manifest = preload("res://cosmic/manual_pdf_manifest.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const Association = preload("res://cosmic/media_result_association.gd")
const Service = preload("res://cosmic/media_processing_service.gd")
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func write(path: String, bytes: PackedByteArray) -> void:
 var file := FileAccess.open(path,FileAccess.WRITE)
 file.store_buffer(bytes)
 file.close()
func run() -> void:
 var folder := ProjectSettings.globalize_path("user://pdf_boundary_fixture")
 DirAccess.make_dir_recursive_absolute(folder)
 var source := folder.path_join("manual.pdf")
 write(source,"%PDF-1.7\nSynthetic header only: never decoded".to_utf8_buffer())
 var source_hash := FileAccess.get_sha256(source)
 var image := Image.create(24,16,false,Image.FORMAT_RGB8)
 image.fill(Color.WHITE)
 image.save_png(folder.path_join("cover.png"))
 var item := {"id":"pdf-fixture","system":"master_system","manual_pages":["original-page"],"media_metadata":{
  "manual":{"status":"present","relative_path":"manual.pdf"},"cover_front":{"status":"present","relative_path":"cover.png"}}}
 var plan := Planner.build(Config.choose("master_system",folder,["manual","covers"]),[item])
 check(not Pdf.capability().available and not Pdf.capability().filesystem_isolated and not Pdf.capability().network_isolated,"No false security claim")
 var service := Service.new()
 check(service.begin(plan,"user://pdf_denied.json",false) == ERR_UNAUTHORIZED,"No processing without exact consent")
 check(not FileAccess.file_exists("user://pdf_denied.json"),"No consent means no journal IO")
 service.shutdown()
 var queue := Queue.new()
 check(queue.start(plan,"user://pdf_boundary.json") == OK,"Explicit plan starts")
 for tick in 20:
  if queue.tick().status in ["done","completed_with_errors"]: break
 check(queue.state.status == "completed_with_errors","Unavailable PDF is not success")
 check(queue.progress().files_done == 1 and queue.progress().files_error == 1,"Independent image continues")
 for job in queue.state.files:
  if job.relative_path == "manual.pdf": check(job.error == "pdf_backend_unavailable" and job.bytes_read == 0 and job.sha256 == "","PDF never opened or hashed")
 var applied := Association.build(queue.state,[item])
 check(applied.applied == 1 and applied.items[0].manual_pages == ["original-page"],"Unavailable PDF leaves original manual, image applies")
 var overlay := item.duplicate(true)
 overlay.manual_pages = ["previous-overlay"]
 overlay.local_media_previous = {"manual_pages":["original-page"],"manual_item_id":null}
 overlay.local_media_validation = {"manual_pages":{"status":"decoded_current"}}
 applied = Association.build(queue.state,[overlay])
 check(applied.items[0].manual_pages == ["original-page"] and not applied.items[0].local_media_validation.has("manual_pages"),"Explicit PDF retry rolls stale overlay back")
 check(applied.remove_bindings.has(JSON.stringify(["master_system","pdf-fixture","manual_pages"])),"Stale persisted manual scheduled for removal")
 var wrong_identity := overlay.duplicate(true)
 wrong_identity.region_hint = "changed"
 var rejected := Association.build(queue.state,[wrong_identity])
 check(rejected.items[0].manual_pages == ["previous-overlay"] and rejected.remove_bindings.is_empty(),"Changed identity never removes unrelated prior binding")
 rejected = Association.build(queue.state,[overlay,overlay])
 check(rejected.remove_bindings.is_empty(),"Ambiguous identity never removes bindings")
 check(queue.restore(plan,"user://pdf_boundary.json") == OK,"Resume current plan")
 for tick in 20:
  if queue.tick().status in ["done","completed_with_errors"]: break
 check(queue.progress().files_error == 1,"Resume does not claim conversion or reuse old success")
 check(FileAccess.get_sha256(source) == source_hash,"Source immutable")
 check(Pdf.cache_key(source_hash,"poppler","26.05") != Pdf.cache_key(source_hash,"poppler","26.10"),"Backend version changes cache identity")
 check(Pdf.cache_key("invalid","poppler","26.10").is_empty(),"Invalid source hash rejected")
 check(Manifest.validate(source,folder,"poppler","26.05").pages.is_empty(),"Missing manifest yields no partial pages")
 check(Manifest.validate(source,folder,"poppler","26.05",func():return true).status == "cancelled","Cancellation yields no pages")
 for name in ["manual.pdf","cover.png"]: DirAccess.remove_absolute(folder.path_join(name))
 DirAccess.remove_absolute(folder)
 for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute("user://pdf_boundary.json" + suffix)
 print("MANUAL_PDF_BOUNDARY: ",assertions," assertions; ",failures," failures")
 quit(0 if failures == 0 else 1)
