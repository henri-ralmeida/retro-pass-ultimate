extends RefCounted
## Release only; never dispatches actions. Include every observed input device so
## a held non-default joypad/axis cannot become a second modal activation.
static func neutral(snapshot: RefCounted, host: Object = null) -> bool:
 if snapshot == null: return true
 var devices: Array = []
 if is_instance_valid(host):
  var active: Variant = host.get("active_pad")
  if active is int and active >= 0: devices.append(active)
 for device in snapshot.buttons.keys():
  if device not in devices: devices.append(device)
 for device in snapshot.axes.keys():
  if device not in devices: devices.append(device)
 if devices.is_empty(): return snapshot.neutral()
 for device in devices:
  if not snapshot.neutral(int(device)): return false
 return true
