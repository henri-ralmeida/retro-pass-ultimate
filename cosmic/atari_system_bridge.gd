extends RefCounted
## Narrow integration hooks. The SMS branch remains owned by the existing main scene.
const SYSTEM_ID := "atari2600"
const Library = preload("res://cosmic/atari_library_view.gd")
static func handles(system: Resource) -> bool:
 return system != null and system.get("system_id") == SYSTEM_ID
static func create_library(parent: Node, host: Node) -> Control:
 var view := Library.new()
 view.name = "AtariPrivateLibrary"
 var shared_theme := Theme.new()
 shared_theme.default_font = host.chakra
 view.theme = shared_theme
 parent.add_child(view)
 view.configure(host)
 view.heading.add_theme_font_override("font",host.orbitron)
 view.begin_catalog_visit()
 return view
static func status_text() -> String:
 var path := OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST")
 return "Atari · mídia privada desabilitada · sem emulação" if path.is_empty() else "Atari · mídia privada explícita · sem emulação"
