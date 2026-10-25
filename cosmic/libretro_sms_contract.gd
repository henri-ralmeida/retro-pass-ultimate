extends RefCounted
## Pure future-adapter contract. No core, emulator, ROM, FFI or process is loaded.
## These IDs are for the documented Genesis Plus GX two-button configuration only.
const PAD_IDS := {"up": 4, "down": 5, "left": 6, "right": 7, "button_1": 0, "button_2": 8}
const PAUSE_ID := 3

static func joypad_mask(held_actions: Array, port: int, gameplay_enabled: bool) -> int:
 if not gameplay_enabled or port not in [0, 1]: return 0
 var result := 0
 for action in PAD_IDS:
  if action in held_actions: result |= 1 << int(PAD_IDS[action])
 # Opposite directions neutralize. Genuine diagonals remain two active cardinals.
 if "up" in held_actions and "down" in held_actions: result &= ~((1 << 4) | (1 << 5))
 if "left" in held_actions and "right" in held_actions: result &= ~((1 << 6) | (1 << 7))
 if port == 0 and "pause" in held_actions: result |= 1 << PAUSE_ID
 return result
