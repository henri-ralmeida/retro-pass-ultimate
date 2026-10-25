extends RefCounted
## Source-native metres. Rendering scale is applied ONCE by captured native frame.
const Slot = preload("res://cosmic/sms_slot_contact_path.gd")
const REVEAL := 0.9
const OPEN := 0.9
const EXTRACT := 0.65
const CLEAR := 0.35
const ROTATE := 0.5
const TRANSFER := 0.8
const SLOT_BEGIN := REVEAL + OPEN + EXTRACT + CLEAR + ROTATE + TRANSFER
const TOTAL := SLOT_BEGIN + Slot.TOTAL_SECONDS
const CONSOLE_ORIGIN := Vector3(0.4,0,0)
const INSIDE := Vector3(0,0.0135,0.036)
static func _ease(t: float) -> float:
 var u := clampf(t,0,1)
 return u*u*(3-2*u)
static func sample(elapsed: float) -> Dictionary:
 var t := clampf(elapsed,0,TOTAL) if is_finite(elapsed) else 0.0
 var reveal := _ease(t/REVEAL)
 var opening := _ease((t-REVEAL)/OPEN)
 var pose := Transform3D(Basis(Vector3.RIGHT,-PI*0.5),INSIDE)
 var start := REVEAL+OPEN
 if t > start:
  pose.origin = INSIDE + Vector3(0,0.13*_ease((t-start)/EXTRACT),0)
 start += EXTRACT
 if t > start:
  pose.origin = (INSIDE+Vector3(0,0.13,0)).lerp(Vector3(0,0.20,0.036),_ease((t-start)/CLEAR))
 start += CLEAR
 if t > start:
  pose.basis = Basis(Vector3.RIGHT,lerpf(-PI*0.5,0,_ease((t-start)/ROTATE)))
 start += ROTATE
 var door := Transform3D.IDENTITY
 if t > start:
  pose.origin = Vector3(0,0.20,0.036).lerp(CONSOLE_ORIGIN+Slot.sample(0).cartridge_pose.origin,_ease((t-start)/TRANSFER))
 if t >= SLOT_BEGIN:
  var slot := Slot.sample(t-SLOT_BEGIN)
  pose = Transform3D(Basis.IDENTITY,CONSOLE_ORIGIN)*slot.cartridge_pose
  door = slot.door_delta
 return {"pose":pose,"reveal":reveal,"opening":opening,"door":door}
