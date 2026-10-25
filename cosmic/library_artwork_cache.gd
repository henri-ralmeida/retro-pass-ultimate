extends RefCounted
## Shared runtime-only artwork cache. Source files are read, never modified.
## Explicit paths are the only identity: no filename guessing or other-game
## fallback. Budgets cover retained textures, not peak source-image decoding,
## renderer allocation overhead, or references retained by caller materials.
const SELECTED_MAX_SIDE := 2048
const NEIGHBOR_MAX_SIDE := 512
const MAX_TEXTURES := 24
const MAX_BYTES := 192 * 1024 * 1024
const MAX_SOURCE_BYTES := 64 * 1024 * 1024
const MAX_SOURCE_PIXELS := 64 * 1024 * 1024
static var _shared_cache: RefCounted
var texture_limit := MAX_TEXTURES
var byte_limit := MAX_BYTES
var resident_bytes := 0
var peak_resident_bytes := 0
var hits := 0
var misses := 0
var decodes := 0
var evictions := 0
var last_status := "idle"
var _entries := {}
var _pinned_paths := {}
var _clock := 0

static func shared() -> RefCounted:
 if _shared_cache == null: _shared_cache = load("res://cosmic/library_artwork_cache.gd").new()
 return _shared_cache

func set_pinned_paths(paths: Array[String]) -> void:
 _pinned_paths.clear()
 for path in paths:
  if not path.is_empty(): _pinned_paths[_canonical(path)] = true

func clear() -> void:
 _entries.clear()
 _pinned_paths.clear()
 resident_bytes = 0
 last_status = "cleared"

func invalidate(path: String) -> void:
 var canonical := _canonical(path)
 for key in _entries.keys():
  if _entries[key].path == canonical: _remove(key)

func resident_count() -> int: return _entries.size()

func load_path(path: String, maximum_side: int = SELECTED_MAX_SIDE, revision: String = "") -> Texture2D:
 if path.is_empty() or maximum_side <= 0:
  last_status = "invalid_request"
  return null
 var canonical := _canonical(path)
 if not FileAccess.file_exists(canonical):
  last_status = "missing"
  return null
 var file := FileAccess.open(canonical,FileAccess.READ)
 if file == null:
  last_status = "unreadable"
  return null
 var source_bytes := file.get_length()
 if source_bytes > MAX_SOURCE_BYTES:
  file.close()
  last_status = "source_file_limit"
  return null
 # Reject oversized/unsupported images BEFORE decoding. Header parsing is
 # bounded to512KiB; it does not decompress pixels or trust file extensions.
 var header := file.get_buffer(mini(source_bytes,512*1024))
 file.close()
 var dimensions := _header_dimensions(header)
 if dimensions.x <= 0 or dimensions.y <= 0:
  last_status = "unsupported_or_invalid_header"
  return null
 if int(dimensions.x) * int(dimensions.y) > MAX_SOURCE_PIXELS:
  last_status = "source_pixel_limit"
  return null
 var side := mini(maximum_side,SELECTED_MAX_SIDE)
 # A caller replacing a file within one filesystem timestamp tick must supply
 # a changed revision or call invalidate(path), including its lower-LOD copies.
 var key := JSON.stringify([canonical,FileAccess.get_modified_time(canonical),source_bytes,side,revision])
 _clock += 1
 if _entries.has(key):
  hits += 1
  _entries[key].used = _clock
  last_status = "hit"
  return _entries[key].texture
 misses += 1
 var image := Image.new()
 if image.load(canonical) != OK or image.is_empty():
  last_status = "decode_failed"
  return null
 decodes += 1
 if image.get_width() * image.get_height() > MAX_SOURCE_PIXELS:
  last_status = "source_pixel_limit"
  return null
 var largest := maxi(image.get_width(),image.get_height())
 if largest > side:
  var ratio := float(side)/float(largest)
  image.resize(maxi(1,roundi(image.get_width()*ratio)),maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
 image.convert(Image.FORMAT_RGBA8)
 if image.generate_mipmaps() != OK:
  last_status = "mipmap_failed"
  return null
 var bytes := image.get_data_size()
 if bytes > byte_limit or texture_limit < 1:
  last_status = "resident_budget"
  return null
 var victims: Array[String] = []
 var candidates: Array = _entries.keys()
 candidates.sort_custom(func(a: String,b: String): return int(_entries[a].used) < int(_entries[b].used))
 var planned_bytes := resident_bytes
 var planned_count := _entries.size()
 for candidate in candidates:
  if planned_count < texture_limit and planned_bytes + bytes <= byte_limit: break
  if _pinned_paths.has(_entries[candidate].path): continue
  victims.append(candidate)
  planned_bytes -= int(_entries[candidate].bytes)
  planned_count -= 1
 if planned_count >= texture_limit or planned_bytes + bytes > byte_limit:
  last_status = "pinned_budget"
  return null
 var texture := ImageTexture.create_from_image(image)
 if texture == null:
  last_status = "texture_failed"
  return null
 for victim in victims:
  _remove(victim)
  evictions += 1
 _entries[key] = {"texture":texture,"bytes":bytes,"used":_clock,"path":canonical}
 resident_bytes += bytes
 peak_resident_bytes = maxi(peak_resident_bytes,resident_bytes)
 last_status = "decoded"
 return texture

func _remove(key: String) -> void:
 resident_bytes -= int(_entries[key].bytes)
 _entries.erase(key)

func _canonical(path: String) -> String:
 return ProjectSettings.globalize_path(path).simplify_path()

static func _header_dimensions(data: PackedByteArray) -> Vector2i:
 # PNG: fixed IHDR is the mandatory first chunk.
 if data.size() >= 24 and data.slice(0,8) == PackedByteArray([137,80,78,71,13,10,26,10]):
  if data.slice(12,16).get_string_from_ascii() != "IHDR" or _be32(data,8) != 13: return Vector2i.ZERO
  var width := _be32(data,16)
  var height := _be32(data,20)
  if width > 2147483647 or height > 2147483647: return Vector2i.ZERO
  return Vector2i(width,height)
 # WebP: dimensions are encoded in the first VP8X/VP8L/VP8 frame header.
 if data.size() >= 25 and data.slice(0,4).get_string_from_ascii() == "RIFF" and data.slice(8,12).get_string_from_ascii() == "WEBP":
  var format := data.slice(12,16).get_string_from_ascii()
  if format == "VP8X" and data.size() >= 30:
   return Vector2i(1+int(data[24])+(int(data[25])<<8)+(int(data[26])<<16),1+int(data[27])+(int(data[28])<<8)+(int(data[29])<<16))
  if format == "VP8L" and data[20] == 47:
   return Vector2i(1+int(data[21])+((int(data[22])&63)<<8),1+(int(data[22])>>6)+(int(data[23])<<2)+((int(data[24])&15)<<10))
  if format == "VP8 " and data.size() >= 30 and data[23] == 157 and data[24] == 1 and data[25] == 42:
   return Vector2i((int(data[26])+(int(data[27])<<8))&16383,(int(data[28])+(int(data[29])<<8))&16383)
  return Vector2i.ZERO
 # JPEG: segment lengths bound every read; stop before compressed scan data.
 if data.size() >= 4 and data[0] == 255 and data[1] == 216:
  var offset := 2
  var dimensions := Vector2i.ZERO
  while offset < data.size():
   if data[offset] != 255: return Vector2i.ZERO
   while offset < data.size() and data[offset] == 255: offset += 1
   if offset >= data.size(): return Vector2i.ZERO
   var marker := int(data[offset])
   offset += 1
   if marker == 218: return dimensions
   if marker == 217: return dimensions
   if marker in [1,208,209,210,211,212,213,214,215]: continue
   if offset+2 > data.size(): return Vector2i.ZERO
   var length := (int(data[offset])<<8)+int(data[offset+1])
   if length < 2 or offset+length > data.size(): return Vector2i.ZERO
   if marker in [192,193,194,195,197,198,199,201,202,203,205,206,207]:
    if length < 8 or dimensions != Vector2i.ZERO: return Vector2i.ZERO
    dimensions = Vector2i((int(data[offset+5])<<8)+int(data[offset+6]),(int(data[offset+3])<<8)+int(data[offset+4]))
   offset += length
  return Vector2i.ZERO
 return Vector2i.ZERO

static func _be32(data: PackedByteArray, offset: int) -> int:
 return (int(data[offset])<<24)+(int(data[offset+1])<<16)+(int(data[offset+2])<<8)+int(data[offset+3])
