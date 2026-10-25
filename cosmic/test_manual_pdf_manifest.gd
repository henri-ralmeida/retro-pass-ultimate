extends SceneTree
## Schema/storage validation uses synthetic PNGs, not proof of PDF conversion.
## Real conversion is separately exercised by test_pdf_synthetic_conversion.py.
const Pdf = preload("res://cosmic/manual_pdf_service.gd")
const Manifest = preload("res://cosmic/manual_pdf_manifest.gd")
var assertions := 0
var failures := 0
var folder: String
var source: String
var manifest: Dictionary
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
func save(value: Dictionary) -> void: write(folder.path_join("manifest.json"),JSON.stringify(value).to_utf8_buffer())
func validate() -> Dictionary: return Manifest.validate(source,folder,"synthetic-test","1")
func run() -> void:
 folder = ProjectSettings.globalize_path("user://pdf_manifest_fixture")
 DirAccess.make_dir_recursive_absolute(folder)
 source = folder.path_join("source.pdf")
 write(source,"%PDF-1.7\nHeader-only fixture, not conversion proof".to_utf8_buffer())
 var hash := FileAccess.get_sha256(source)
 manifest = {"version":1,"complete":true,"source_sha256":hash,"backend":{"id":"synthetic-test","version":"1"},"options":Pdf.OPTIONS,"cache_key":Pdf.cache_key(hash,"synthetic-test","1"),"page_count":3,"pages":[]}
 for index in 3:
  var image := Image.create(24 if index != 2 else 32,32 if index != 2 else 24,false,Image.FORMAT_RGB8)
  image.fill(Color.WHITE)
  var name := "page-%04d.png" % (index+1)
  var bytes := image.save_png_to_buffer()
  write(folder.path_join(name),bytes)
  manifest.pages.append({"number":index+1,"file":name,"sha256":FileAccess.get_sha256(folder.path_join(name)),"bytes":bytes.size(),"width":image.get_width(),"height":image.get_height()})
 save(manifest)
 var result := validate()
 check(result.status == "valid" and result.pages.size() == 3,"Complete contiguous pages validate")
 check(not result.backend_security_verified,"Manifest never grants backend security")
 check(manifest.pages[0].sha256 == manifest.pages[1].sha256 and result.pages.size() == 3,"Identical blank hashes not deduplicated")
 check(result.pages.size() == 3 and result.pages[2].ends_with("page-0003.png"),"Landscape retained in order")
 var changed := manifest.duplicate(true)
 changed.complete = false
 save(changed)
 check(validate().pages.is_empty(),"Incomplete never exposes partial pages")
 changed = manifest.duplicate(true); changed.pages.pop_back(); save(changed)
 check(validate().status == "page_count_limit","Missing final page cannot hide behind contiguous prefix")
 changed = manifest.duplicate(true); changed.pages.reverse(); save(changed)
 check(validate().status == "invalid_page_sequence","Reordering rejected instead of silently sorted")
 changed = manifest.duplicate(true); changed.pages[1].file = "../outside.png"; save(changed)
 check(validate().status == "invalid_page_sequence","Traversal not used for IO")
 changed = manifest.duplicate(true); changed.pages[1].file = "page-0001.png"; save(changed)
 check(validate().status == "invalid_page_sequence","Duplicate path rejected")
 changed = manifest.duplicate(true); changed.backend.version = "2"; save(changed)
 check(validate().status == "backend_changed","Backend mismatch invalidates cache")
 changed = manifest.duplicate(true); changed.options.dpi = 72; save(changed)
 check(validate().pages.is_empty(),"Options fixed and cache scoped")
 changed = manifest.duplicate(true); changed.cache_key = "forged"; save(changed)
 check(validate().status == "cache_key_mismatch","Cache key checked")
 changed = manifest.duplicate(true); changed.pages[0].width = 31; save(changed)
 check(validate().status == "page_dimensions_mismatch","Declared dimensions checked")
 changed = manifest.duplicate(true); changed.pages.resize(65); changed.page_count = 65; save(changed)
 check(validate().status == "page_count_limit","No silent 64-page truncation")
 for field in ["version","complete","page_count"]:
  for bad in ["1",{},[],null]:
   changed = manifest.duplicate(true); changed[field] = bad; save(changed)
   check(validate().pages.is_empty(),"Wrong scalar type rejected: " + field)
 for field in ["number","bytes","width","height"]:
  for bad in ["1",{},[],null,true,1.5]:
   changed = manifest.duplicate(true); changed.pages[0][field] = bad; save(changed)
   check(validate().pages.is_empty(),"Wrong page type/integer rejected: " + field)
 save(manifest)
 check(Manifest.validate(source,folder,"synthetic-test","1",func():return true).status == "cancelled","Cancelled result exposes no pages")
 var count := [0]
 var cancelled := Manifest.validate(source,folder,"synthetic-test","1",func():count[0] += 1; return count[0] >= 3)
 check(cancelled.status == "cancelled" and cancelled.pages.is_empty(),"Mid-validation cancellation discards all pages")
 write(source,"%PDF-1.7\nChanged source".to_utf8_buffer())
 check(validate().status == "source_changed","Source byte change rejected")
 write(source,"%PDF-1.7\nHeader-only fixture, not conversion proof".to_utf8_buffer())
 var original_source := FileAccess.get_file_as_bytes(source)
 var huge_source := FileAccess.open(source,FileAccess.WRITE)
 huge_source.seek(Pdf.MAX_SOURCE_BYTES); huge_source.store_8(0); huge_source.close()
 check(validate().status == "invalid_source","Oversized source rejected before allocation")
 write(source,"wrong header".to_utf8_buffer())
 check(validate().status == "invalid_source","Bad source header rejected")
 write(source,original_source)
 changed = manifest.duplicate(true); changed.command = "never execute manifest text"; save(changed)
 check(validate().status == "invalid_manifest","Unknown manifest command rejected")
 save(manifest)
 var page := folder.path_join("page-0002.png")
 var original := FileAccess.get_file_as_bytes(page)
 var huge_page := FileAccess.open(page,FileAccess.WRITE)
 huge_page.seek(Pdf.MAX_PAGE_BYTES); huge_page.store_8(0); huge_page.close()
 check(validate().status == "page_size_mismatch","Oversized page rejected before allocation")
 write(page,"wrong".to_utf8_buffer())
 check(validate().pages.is_empty(),"Changed page rejects entire manifest")
 write(page,original)
 DirAccess.remove_absolute(page)
 check(validate().pages.is_empty(),"Missing page rejects entire manifest")
 write(page,original)
 # The symlink is owned by this test and points only to another fixture.
 DirAccess.remove_absolute(page)
 var directory := DirAccess.open(folder)
 var link_error := directory.create_link(folder.path_join("page-0001.png"),page)
 if link_error == OK:
  check(validate().status == "unsafe_path","Linked page rejected")
  DirAccess.remove_absolute(page)
 else: print("SKIP symlink fixture unsupported: ",link_error)
 for name in ["source.pdf","manifest.json","page-0001.png","page-0003.png"]: DirAccess.remove_absolute(folder.path_join(name))
 DirAccess.remove_absolute(folder)
 print("MANUAL_PDF_MANIFEST: ",assertions," assertions; ",failures," failures")
 quit(0 if failures == 0 else 1)
