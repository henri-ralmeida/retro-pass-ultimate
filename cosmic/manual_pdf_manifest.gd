extends RefCounted
## Versioned candidate-manifest contract, NOT an executable PDF backend.
## Read-only; currently used by synthetic QA only. No app path consumes this
## output or persists PDF bindings until a contained adapter is implemented.
const Pdf = preload("res://cosmic/manual_pdf_service.gd")
const Artwork = preload("res://cosmic/library_artwork_cache.gd")
const MAX_MANIFEST_BYTES := 64 * 1024

static func validate(source: String, folder: String, expected_backend: String, expected_version: String, cancelled: Callable = Callable()) -> Dictionary:
 var empty := {"status":"invalid_manifest", "pages":[], "backend_security_verified":false}
 if _cancelled(cancelled): return _error("cancelled")
 if not _safe(source) or not _safe(folder.path_join("manifest.json")): return _error("unsafe_path")
 var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.READ)
 if file == null or file.get_length() > MAX_MANIFEST_BYTES: return empty
 var parsed: Variant = JSON.parse_string(file.get_as_text())
 file.close()
 if not parsed is Dictionary: return empty
 var keys: Array = parsed.keys()
 keys.sort()
 if keys != ["backend", "cache_key", "complete", "options", "page_count", "pages", "source_sha256", "version"]: return empty
 if not _integer(parsed.version,1,1) or not parsed.complete is bool or not parsed.complete or not _options_valid(parsed.options): return empty
 if not parsed.backend is Dictionary or parsed.backend.size() != 2: return empty
 if not parsed.backend.get("id") is String or not parsed.backend.get("version") is String: return empty
 if parsed.backend.get("id") != expected_backend or parsed.backend.get("version") != expected_version: return _error("backend_changed")
 if not Pdf.valid_hash(parsed.source_sha256): return empty
 var key := Pdf.cache_key(parsed.source_sha256,expected_backend,expected_version)
 if not parsed.cache_key is String or key.is_empty() or parsed.cache_key != key: return _error("cache_key_mismatch")
 if not _integer(parsed.page_count,1,Pdf.MAX_PAGES): return _error("page_count_limit")
 if not parsed.pages is Array or parsed.pages.is_empty() or parsed.pages.size() > Pdf.MAX_PAGES or parsed.page_count != parsed.pages.size(): return _error("page_count_limit")
 var source_bytes := _read_bounded(source,Pdf.MAX_SOURCE_BYTES)
 if source_bytes.is_empty() or source_bytes.size() < 5 or source_bytes.slice(0,5).get_string_from_ascii() != "%PDF-": return _error("invalid_source")
 if _hash(source_bytes) != parsed.source_sha256: return _error("source_changed")
 source_bytes.clear()
 var total := 0
 var pages: Array[String] = []
 for index in parsed.pages.size():
  if _cancelled(cancelled): return _error("cancelled")
  var entry: Variant = parsed.pages[index]
  if not entry is Dictionary: return empty
  var fields: Array = entry.keys()
  fields.sort()
  if fields != ["bytes", "file", "height", "number", "sha256", "width"]: return empty
  # No path supplied by a manifest is used for IO. Names are derived solely
  # from contiguous sequence; never sort, deduplicate blanks, or skip failures.
  if not _integer(entry.number,1,Pdf.MAX_PAGES) or not entry.file is String: return empty
  if not _integer(entry.bytes,1,Pdf.MAX_PAGE_BYTES): return _error("page_size_mismatch")
  if not _integer(entry.width,1,Pdf.MAX_EDGE) or not _integer(entry.height,1,Pdf.MAX_EDGE): return _error("page_dimensions_limit")
  var name := "page-%04d.png" % (index + 1)
  if entry.number != index + 1 or entry.file != name or not Pdf.valid_hash(entry.sha256): return _error("invalid_page_sequence")
  var path := folder.path_join(name)
  if not _safe(path): return _error("unsafe_path")
  var bytes := _read_bounded(path,Pdf.MAX_PAGE_BYTES)
  if bytes.is_empty() or bytes.size() != entry.bytes: return _error("page_size_mismatch")
  total += bytes.size()
  if total > Pdf.MAX_TOTAL_BYTES: return _error("total_size_limit")
  if _hash(bytes) != entry.sha256: return _error("page_changed")
  var dimensions := Artwork._header_dimensions(bytes.slice(0,33))
  if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > Pdf.MAX_EDGE or dimensions.y > Pdf.MAX_EDGE: return _error("page_dimensions_limit")
  if dimensions.x != entry.width or dimensions.y != entry.height: return _error("page_dimensions_mismatch")
  var image := Image.new()
  if image.load_png_from_buffer(bytes) != OK or image.is_empty() or image.get_size() != dimensions: return _error("page_decode_failed")
  pages.append(path)
 if _cancelled(cancelled): return _error("cancelled")
 # Source is rechecked after all page validation, not only before it. This is
 # validation at a point in time, not continuous tamper immunity.
 if not _safe(source) or _hash(_read_bounded(source,Pdf.MAX_SOURCE_BYTES)) != parsed.source_sha256: return _error("source_changed")
 return {"status":"valid", "pages":pages, "cache_key":key, "backend_security_verified":false, "bytes":total}

static func _error(status: String) -> Dictionary:
 return {"status":status, "pages":[], "backend_security_verified":false}

static func _cancelled(callback: Callable) -> bool:
 return callback.is_valid() and bool(callback.call())

static func _safe(path: String) -> bool:
 if not path.is_absolute_path() or path.simplify_path() != path or ".." in path.split("/"): return false
 var cursor := path
 while cursor != cursor.get_base_dir():
  var parent := DirAccess.open(cursor.get_base_dir())
  if parent == null or parent.is_link(cursor.get_file()): return false
  cursor = cursor.get_base_dir()
 return true

static func _read_bounded(path: String, limit: int) -> PackedByteArray:
 var file := FileAccess.open(path,FileAccess.READ)
 if file == null: return PackedByteArray()
 var length := file.get_length()
 if length <= 0 or length > limit:
  file.close()
  return PackedByteArray()
 var bytes := file.get_buffer(length)
 var unchanged := file.get_length() == length
 file.close()
 return bytes if unchanged and bytes.size() == length else PackedByteArray()

static func _hash(bytes: PackedByteArray) -> String:
 var hash := HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(bytes)
 return hash.finish().hex_encode()

static func _options_valid(value: Variant) -> bool:
 if not value is Dictionary or value.size() != Pdf.OPTIONS.size(): return false
 for key in Pdf.OPTIONS:
  if not value.has(key) or not (value[key] is int or value[key] is float) or value[key] != Pdf.OPTIONS[key]: return false
 return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
 if not (value is int or value is float): return false
 return is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floorf(float(value))
