extends RefCounted
## Authored compact display routing, not a reconstruction of a factory coil shape.
## SEGA service manual, printed p.23 / PDF p.24, C-12 / 600-5306:
## https://www.smspower.org/uploads/Development/SegaMasterSystemServiceManual.pdf#page=24
## The documented assembly is nominally 2 m. External jacket length is approximate:
## the manual does not specify internal termination allowance or jacket diameter.
## This helper changes no controller, connector, material, camera, or other scene node.
## All input/output coordinates are in the caller's chosen common meter-based space.

const NOMINAL_ASSEMBLY_LENGTH := 2.0
const PROVISIONAL_RADIUS := 0.0015
const REFERENCE_NOTE := "Nominal 2 m cable assembly from SEGA service manual p.23; external length and 3 mm diameter are display approximations."
var points := PackedVector3Array()
var diagnostics: Dictionary = {}
var error := ""
var _start := Vector3.ZERO
var _start_tangent := Vector3.RIGHT
var _finish := Vector3.ZERO
var _finish_tangent := Vector3.FORWARD
var _center := Vector3.ZERO
var _basis := Basis.IDENTITY
var _turns := 2
var _aspect := 0.85
var _inner_ratio := 0.52
var _in_guides := PackedVector3Array()
var _out_guides := PackedVector3Array()
var _radius := PROVISIONAL_RADIUS
var _spacing := 0.002

## Options: coil_center (required); coil_basis (orthonormal, X/Z are coil plane);
## target_length, radius, outer_radius_min/max, turns_per_arm, coil_aspect,
## inner_radius_ratio, lead_in_guides, lead_out_guides, sample_spacing,
## minimum_bend_radius, minimum_centerline_separation, obstacles (Array[AABB]),
## endpoint_clearance_allowance. Invalid or colliding routes return false, no path.
func build(start: Vector3, start_tangent: Vector3, finish: Vector3, finish_outward: Vector3, options: Dictionary) -> bool:
 points.clear()
 diagnostics.clear()
 error = ""
 if not options.has("coil_center"):
  return _fail("An explicit coil center is required")
 _start = start
 _finish = finish
 _center = options["coil_center"]
 if not _start.is_finite() or not _finish.is_finite() or not _center.is_finite() or not start_tangent.is_finite() or not finish_outward.is_finite() or start_tangent.length_squared()<0.01 or finish_outward.length_squared()<0.01:
  return _fail("Finite endpoints and non-zero endpoint directions are required")
 _start_tangent = start_tangent.normalized()
 _finish_tangent = -finish_outward.normalized()
 _basis = options.get("coil_basis", Basis.IDENTITY)
 if not _basis.is_finite() or absf(_basis.determinant())<0.0001:
  return _fail("Coil orientation must be a finite non-degenerate basis")
 _basis = _basis.orthonormalized()
 _turns = int(options.get("turns_per_arm",2))
 _aspect = float(options.get("coil_aspect",0.85))
 _inner_ratio = float(options.get("inner_radius_ratio",0.52))
 _radius = float(options.get("radius",PROVISIONAL_RADIUS))
 _spacing = float(options.get("sample_spacing",0.002))
 _in_guides = options.get("lead_in_guides",PackedVector3Array())
 _out_guides = options.get("lead_out_guides",PackedVector3Array())
 var target := float(options.get("target_length",NOMINAL_ASSEMBLY_LENGTH))
 var low := float(options.get("outer_radius_min",0.055))
 var high := float(options.get("outer_radius_max",0.100))
 var min_bend := float(options.get("minimum_bend_radius",0.0075))
 var min_separation := float(options.get("minimum_centerline_separation",_radius*3.0))
 for value in [_aspect,_inner_ratio,_radius,_spacing,target,low,high,min_bend,min_separation]:
  if not is_finite(value): return _fail("All cable dimensions and tolerances must be finite")
 if min_bend<=0.0 or min_separation<_radius*2.0:
  return _fail("Bend and clearance limits must protect a non-intersecting tube")
 if _turns<1 or _turns>5 or _aspect<0.6 or _aspect>1.5 or _inner_ratio<0.30 or _inner_ratio>0.70 or _radius<=0 or _radius>0.004 or _spacing<0.0005 or _spacing>0.004 or target<0.1 or target>5.0 or low<0.02 or high<low or high>0.25:
  return _fail("Cable parameters are outside supported bounded display ranges")
 for guide in _in_guides+_out_guides:
  if not guide.is_finite(): return _fail("Lead guide positions must be finite")
 var low_length := path_length(_make_route(low))
 var high_length := path_length(_make_route(high))
 diagnostics = {"target_length":target,"minimum_reachable_length":low_length,"maximum_reachable_length":high_length,"radius":_radius,"diameter":_radius*2.0,"reference_note":REFERENCE_NOTE}
 if high_length<=low_length or target<low_length-0.0002 or target>high_length+0.0002:
  return _fail("Requested length cannot fit this coil radius range and lead routing")
 var outer := (low+high)*0.5
 for iteration in 20:
  outer = (low+high)*0.5
  if path_length(_make_route(outer))<target: low = outer
  else: high = outer
 var raw := _make_route(outer)
 var candidate := _resample(raw,_spacing)
 var actual := path_length(candidate)
 var bend := minimum_bend_radius(candidate)
 var separation := minimum_nonlocal_separation(candidate,_radius*8.0)
 var bounds := AABB(candidate[0],Vector3.ZERO)
 for point in candidate: bounds = bounds.expand(point)
 diagnostics.merge({"actual_length":actual,"length_error":actual-target,"outer_radius":outer,"inner_radius":outer*_inner_ratio,"sample_count":candidate.size(),"minimum_bend_radius":bend,"minimum_centerline_separation":separation,"minimum_surface_clearance":separation-_radius*2.0,"bounds":bounds.grow(_radius),"start_tangent_dot":(candidate[1]-candidate[0]).normalized().dot(_start_tangent),"finish_tangent_dot":(candidate[-1]-candidate[-2]).normalized().dot(_finish_tangent)},true)
 if absf(actual-target)>0.002:
  return _fail("Resampled route did not meet the 2 mm length tolerance")
 if bend<min_bend:
  return _fail("Lead routing or coil has a bend tighter than the configured minimum")
 if separation<min_separation:
  return _fail("The proposed routing overlaps itself or violates cable separation")
 if float(diagnostics.start_tangent_dot)<0.97 or float(diagnostics.finish_tangent_dot)<0.97:
  return _fail("Endpoint routing turns too quickly at a strain relief")
 var obstacles: Array = options.get("obstacles",[])
 var endpoint_allowance := float(options.get("endpoint_clearance_allowance",0.006))
 if not _obstacles_clear(candidate,obstacles,endpoint_allowance):
  return _fail("The proposed cable route intersects a protected scene object")
 points = candidate
 return true

func _fail(message: String) -> bool:
 error = message
 diagnostics["error"] = message
 points.clear()
 return false

func _map(point: Vector2) -> Vector3:
 return _center+_basis.x*point.x+_basis.z*point.y

func _spiral(t: float, outer: float, returning: bool) -> Vector2:
 var inner := outer*_inner_ratio
 var angle := TAU*_turns*t if not returning else TAU*_turns-PI-TAU*_turns*t
 var radius := lerpf(outer,inner,t) if not returning else lerpf(inner,outer,t)
 # Shared low-amplitude deviations keep lanes separated while avoiding mechanical
 # perfect circles. No randomization or dependence on the camera is involved.
 radius += outer*(0.025*sin(2.0*angle)+0.009*sin(5.0*angle))
 return Vector2(radius*cos(angle),radius*sin(angle)*_aspect)

func _spiral_tangent(t: float, outer: float, returning: bool) -> Vector3:
 var delta := _spiral(t+0.00001,outer,returning)-_spiral(t-0.00001,outer,returning)
 return (_basis.x*delta.x+_basis.z*delta.y).normalized()

func _make_route(outer: float) -> PackedVector3Array:
 var result := PackedVector3Array()
 var coil_start := _map(_spiral(0.0,outer,false))
 var coil_end := _map(_spiral(1.0,outer,true))
 _lead(result,_start,_start_tangent,coil_start,_spiral_tangent(0.0,outer,false),_in_guides)
 var segments := _turns*256
 for i in range(1,segments+1): result.append(_map(_spiral(float(i)/segments,outer,false)))
 # A broad central S uses two rounded lobes. The tangent remains continuous at
 # every join. Unlike a tiny U-turn between adjacent tracks, both lobes fit inside
 # the inner empty area, with radius approximately half the inner coil radius.
 var r := outer*_inner_ratio
 var p0 := _map(Vector2(r,0))
 var p1 := _map(Vector2(r*0.5,r*0.5*_aspect))
 var p2 := _map(Vector2.ZERO)
 var p3 := _map(Vector2(-r*0.5,-r*0.5*_aspect))
 var p4 := _map(Vector2(-r,0))
 var h := r*0.5*0.5522847498
 var right := _basis.x
 var down := -_basis.z
 _bezier(result,p0,p0+_spiral_tangent(1.0,outer,false)*h*_aspect,p1+right*h,p1)
 _bezier(result,p1,p1-right*h,p2-down*h*_aspect,p2)
 _bezier(result,p2,p2+down*h*_aspect,p3+right*h,p3)
 _bezier(result,p3,p3-right*h,p4-_spiral_tangent(0.0,outer,true)*h*_aspect,p4)
 for i in range(1,segments+1): result.append(_map(_spiral(float(i)/segments,outer,true)))
 _lead(result,coil_end,_spiral_tangent(1.0,outer,true),_finish,_finish_tangent,_out_guides)
 return result

func _lead(output: PackedVector3Array, begin: Vector3, begin_direction: Vector3, end: Vector3, end_direction: Vector3, guides: PackedVector3Array) -> void:
 var knots := PackedVector3Array([begin])
 knots.append_array(guides)
 knots.append(end)
 var directions := PackedVector3Array()
 var handles := PackedFloat32Array()
 for i in knots.size():
  var direction := begin_direction if i==0 else end_direction if i==knots.size()-1 else (knots[i+1]-knots[i-1]).normalized()
  var previous_length := knots[i].distance_to(knots[maxi(i-1,0)]) if i>0 else INF
  var next_length := knots[i].distance_to(knots[mini(i+1,knots.size()-1)]) if i<knots.size()-1 else INF
  directions.append(direction)
  handles.append(minf(previous_length,next_length)*0.36)
 for i in knots.size()-1:
  _bezier(output,knots[i],knots[i]+directions[i]*handles[i],knots[i+1]-directions[i+1]*handles[i+1],knots[i+1])

func _bezier(output: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
 var polygon_length := a.distance_to(b)+b.distance_to(c)+c.distance_to(d)
 var count := maxi(12,ceili(polygon_length/0.001))
 if output.is_empty(): output.append(a)
 for i in range(1,count+1):
  var t := float(i)/count
  var s := 1.0-t
  output.append(a*s*s*s+3.0*b*s*s*t+3.0*c*s*t*t+d*t*t*t)

static func path_length(path: PackedVector3Array) -> float:
 var total := 0.0
 for i in range(1,path.size()): total += path[i].distance_to(path[i-1])
 return total

static func _resample(raw: PackedVector3Array, spacing: float) -> PackedVector3Array:
 var total := path_length(raw)
 var steps := maxi(2,ceili(total/spacing))
 var result := PackedVector3Array([raw[0]])
 var at := 1
 var previous_distance := 0.0
 var next_distance := raw[0].distance_to(raw[1])
 for i in range(1,steps):
  var desired := total*float(i)/steps
  while at<raw.size()-1 and next_distance<desired:
   previous_distance = next_distance
   at += 1
   next_distance += raw[at-1].distance_to(raw[at])
  result.append(raw[at-1].lerp(raw[at],(desired-previous_distance)/maxf(next_distance-previous_distance,0.00000001)))
 result.append(raw[-1])
 return result

static func minimum_bend_radius(path: PackedVector3Array) -> float:
 var result := INF
 for i in range(1,path.size()-1):
  var a := path[i]-path[i-1]
  var b := path[i+1]-path[i]
  var cross := a.cross(b).length()
  if cross>0.0000000001: result = minf(result,a.length()*b.length()*(a+b).length()/(2.0*cross))
 return result

## Exact segment/segment distance, excluding only the adjacent local cable run.
static func minimum_nonlocal_separation(path: PackedVector3Array, excluded_arc: float = 0.012) -> float:
 var distances := PackedFloat64Array([0.0])
 for i in range(1,path.size()): distances.append(distances[-1]+path[i-1].distance_to(path[i]))
 var best := INF
 for i in path.size()-1:
  for j in range(i+2,path.size()-1):
   if distances[j]-distances[i+1]<excluded_arc: continue
   var reach := path[i].distance_to(path[i+1])+path[j].distance_to(path[j+1])
   if path[i].distance_to(path[j])>best+reach: continue
   var pair := Geometry3D.get_closest_points_between_segments(path[i],path[i+1],path[j],path[j+1])
   best = minf(best,pair[0].distance_to(pair[1]))
 return best

func _obstacles_clear(path: PackedVector3Array, obstacles: Array, endpoint_allowance: float) -> bool:
 var total := path_length(path)
 var travelled := 0.0
 for i in range(1,path.size()):
  travelled += path[i].distance_to(path[i-1])
  if travelled<endpoint_allowance or total-travelled<endpoint_allowance: continue
  for bounds in obstacles:
   if not bounds is AABB: return false
   var expanded: AABB = bounds.grow(_radius+0.00025)
   if expanded.has_point(path[i]) or expanded.intersects_segment(path[i-1],path[i])!=null:
    return false
 return true

## Useful to validate separately authored controller lanes after both paths exist.
static func minimum_between_paths(first: PackedVector3Array, second: PackedVector3Array) -> float:
 var best := INF
 for i in first.size()-1:
  for j in second.size()-1:
   var reach := first[i].distance_to(first[i+1])+second[j].distance_to(second[j+1])
   if first[i].distance_to(second[j])>best+reach: continue
   var pair := Geometry3D.get_closest_points_between_segments(first[i],first[i+1],second[j],second[j+1])
   best = minf(best,pair[0].distance_to(pair[1]))
 return best
