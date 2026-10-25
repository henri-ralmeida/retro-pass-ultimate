extends RefCounted
## Fail-closed production boundary. A PDF decoder is NOT built into Godot.
## No executable discovery, shell, subprocess, PDF parsing or network occurs here.
## A future adapter must prove containment + supported version before enabling it.
const MAX_SOURCE_BYTES := 64 * 1024 * 1024
const MAX_PAGES := 64
const DPI := 144
const MAX_EDGE := 4096
const MAX_PAGE_BYTES := 8 * 1024 * 1024
const MAX_TOTAL_BYTES := 128 * 1024 * 1024
const OPTIONS := {"dpi":DPI, "max_edge":MAX_EDGE, "max_pages":MAX_PAGES,
 "max_page_bytes":MAX_PAGE_BYTES, "max_total_bytes":MAX_TOTAL_BYTES}

static func capability() -> Dictionary:
 # Never enable by user-editable preferences, environment variables or an
 # executable existing on PATH. A temp folder/JobObject is not a sandbox.
 return {"available":false, "status":"pdf_backend_unavailable",
  "reason":"contained_backend_not_configured", "backend":"", "version":"",
  "filesystem_isolated":false, "network_isolated":false}

static func description() -> String:
 return "PDF: conversão indisponível. Falta um conversor com isolamento de arquivos/rede e versão verificada. O PDF não será aberto nem convertido; imagens de manual já suportadas continuam disponíveis."

static func cache_key(source_sha256: String, backend: String, version: String) -> String:
 if not valid_hash(source_sha256) or backend.is_empty() or version.is_empty(): return ""
 return JSON.stringify([source_sha256.to_lower(),backend,version,OPTIONS]).sha256_text()

static func valid_hash(value: Variant) -> bool:
 return value is String and value.length() == 64 and value.is_valid_hex_number(false)
