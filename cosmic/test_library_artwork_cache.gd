extends SceneTree
## Small synthetic raster fixtures, never substitutes for a real game's art.
const Cache = preload("res://cosmic/library_artwork_cache.gd")
var assertions := 0
var failures: Array[String] = []
var paths: Array[String] = []
func check(value: bool, message: String) -> void:
 assertions += 1
 if not value: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func fixture(name: String, color: Color, size: Vector2i = Vector2i(16,16)) -> String:
 var path := "user://cache_qa_"+name+".png"
 var image := Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
 image.fill(color)
 image.save_png(path)
 paths.append(path)
 return path
func run() -> void:
 var red := fixture("red",Color.RED,Vector2i(1024,512))
 var green := fixture("green",Color.GREEN)
 var blue := fixture("blue",Color.BLUE)
 var yellow := fixture("yellow",Color.YELLOW)
 var original := FileAccess.get_file_as_bytes(red)
 var cache := Cache.new()
 var texture := cache.load_path(red,256)
 check(texture != null and texture.get_width()==256 and texture.get_height()==128, "Runtime LOD preserves aspect and limits dimension")
 check(texture.get_image().has_mipmaps(), "Runtime texture receives mipmaps")
 check(texture.get_image().get_pixel(0,0).is_equal_approx(Color.RED), "Texture retains exact requested artwork identity")
 var decode_count := cache.decodes
 check(cache.load_path(red,256)==texture and cache.decodes==decode_count and cache.hits==1, "Repeated path+LOD reuses texture without decoding")
 var larger := cache.load_path(red,512)
 check(larger != texture and larger.get_width()==512, "Selected/detail LOD cannot silently reuse low-resolution neighbor texture")
 check(FileAccess.get_file_as_bytes(red)==original, "Runtime reduction never changes high-resolution source bytes")
 check(cache.load_path("user://absent_artwork.png")==null and cache.last_status=="missing", "Missing art stays unavailable, never another game's fallback")
 check(cache.load_path(green,2048).get_width()==16, "Small supplied artwork is not upscaled or advertised as more detail")
 check(cache.resident_bytes<=cache.byte_limit and cache.resident_count()<=cache.texture_limit, "Default residency obeys both budgets")
 cache.clear()
 var bytes: int = cache.load_path(green).get_image().get_data_size()
 cache.clear()
 cache.texture_limit = 2
 cache.byte_limit = 2*bytes
 cache.set_pinned_paths([green])
 var pinned := cache.load_path(green)
 cache.load_path(blue)
 cache.load_path(yellow)
 check(cache.resident_count()==2 and cache.resident_bytes==2*bytes and cache.evictions==1, "LRU enforces count and byte budgets")
 check(cache.load_path(green)==pinned, "Pinned selected artwork survives neighbor eviction")
 cache.set_pinned_paths([green,yellow])
 var before_bytes := cache.resident_bytes
 check(cache.load_path(blue)==null and cache.last_status=="pinned_budget", "Exhausted pinned budget fails explicitly rather than unbounding memory")
 check(cache.resident_bytes==before_bytes and cache.load_path(green)==pinned, "Failed admission preserves prior valid selected texture")
 cache.invalidate(green)
 check(cache.resident_count()==1, "Explicit source replacement invalidates all retained LODs for that path")
 check(cache.load_path(green)!=pinned, "Invalidated file is freshly decoded, not stale-cache substituted")
 cache.clear()
 cache.texture_limit = 24
 cache.byte_limit = 24*bytes
 for index in 1000:
  var result := cache.load_path(green,2048,str(index))
  check(result!=null and cache.resident_count()<=24 and cache.resident_bytes<=24*bytes, "1000 synthetic revisions retain bounded cache residency")
 check(cache.resident_count()==24, "Cache retention is independent of catalog history length")
 cache.clear()
 decode_count = cache.decodes
 var fake := "user://cache_qa_oversize.png"
 var header := PackedByteArray([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,1,0,0,0,1,0,0])
 var fake_file := FileAccess.open(fake,FileAccess.WRITE)
 fake_file.store_buffer(header)
 fake_file.close()
 paths.append(fake)
 check(cache.load_path(fake)==null and cache.last_status=="source_pixel_limit" and cache.decodes==decode_count, "Oversized PNG header is rejected before pixel decoding: " + cache.last_status)
 var junk := "user://cache_qa_junk.png"
 FileAccess.open(junk,FileAccess.WRITE).store_string("not an image")
 paths.append(junk)
 check(cache.load_path(junk)==null and cache.last_status=="unsupported_or_invalid_header" and cache.decodes==decode_count, "Malformed/unsupported header cannot enter decoder")
 var oversized_file := "user://cache_qa_oversized.bin"
 var file := FileAccess.open(oversized_file,FileAccess.WRITE)
 file.seek(Cache.MAX_SOURCE_BYTES)
 file.store_8(0)
 file.close()
 paths.append(oversized_file)
 check(cache.load_path(oversized_file)==null and cache.last_status=="source_file_limit" and cache.decodes==decode_count, "Source file byte limit is enforced before reading/decoding pixels")
 var jpeg := "user://cache_qa_header.jpg"
 var webp := "user://cache_qa_header.webp"
 var sample := Image.create(123,77,false,Image.FORMAT_RGBA8)
 sample.fill(Color.BLUE)
 sample.save_jpg(jpeg)
 sample.save_webp(webp)
 paths.append(jpeg)
 paths.append(webp)
 check(Cache._header_dimensions(FileAccess.get_file_as_bytes(jpeg))==Vector2i(123,77), "JPEG dimensions are validated from bounded segment header")
 check(Cache._header_dimensions(FileAccess.get_file_as_bytes(webp))==Vector2i(123,77), "WebP dimensions are validated before decode")
 check(cache.load_path(jpeg,64).get_width()==64 and cache.load_path(webp,64).get_width()==64, "JPEG and WebP obey runtime dimension limits")
 for length in range(0,header.size()):
  check(Cache._header_dimensions(header.slice(0,length))==Vector2i.ZERO, "Truncated headers are rejected safely")
 cache.clear()
 check(cache.resident_count()==0 and cache.resident_bytes==0, "Clear releases all cache ownership and accounting")
 for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("LIBRARY_ARTWORK_CACHE_TESTS ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"fixture":"synthetic pixel files only; retained texture accounting is not total renderer/RAM memory"}))
 quit(0 if failures.is_empty() else 1)
