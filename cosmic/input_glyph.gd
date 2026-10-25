extends Control
## Draw controller shapes directly so PlayStation symbols need no font fallback.
var symbol := "":
 set(value):
  symbol = value
  var text_size := 15 if symbol.length() <= 2 else 11
  var text_width := ThemeDB.fallback_font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
  custom_minimum_size.x = 32 if symbol in ["ps_square","ps_cross","ps_circle","ps_triangle","south","east","west","north"] else maxf(32,text_width+14)
  queue_redraw()
var family := "keyboard":
 set(value):
  family = value
  queue_redraw()

func _init() -> void:
 custom_minimum_size = Vector2(32,32)
 mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
 var center := size * 0.5
 var ink := Color("dbe5f5")
 if family == "keyboard":
  draw_style_box(_key_style(), Rect2(Vector2(1,center.y-12),Vector2(maxf(30,size.x-2),24)))
 else:
  draw_circle(center,14,Color(0.75,0.82,0.95,0.12))
  draw_arc(center,14,0,TAU,40,Color(0.75,0.82,0.95,0.5),1.0,true)
 match symbol:
  "ps_square": draw_rect(Rect2(center-Vector2(7,7),Vector2(14,14)),Color("e8a6d5"),false,2,true)
  "ps_cross":
   draw_line(center-Vector2(6,6),center+Vector2(6,6),Color("99bdf0"),2,true)
   draw_line(center+Vector2(-6,6),center+Vector2(6,-6),Color("99bdf0"),2,true)
  "ps_circle": draw_arc(center,8,0,TAU,32,Color("edaaa6"),2,true)
  "ps_triangle": draw_polyline(PackedVector2Array([center+Vector2(0,-8),center+Vector2(8,6),center+Vector2(-8,6),center+Vector2(0,-8)]),Color("9cddc8"),2,true)
  "south", "east", "west", "north":
   var positions := {"south":Vector2(0,6),"east":Vector2(6,0),"west":Vector2(-6,0),"north":Vector2(0,-6)}
   for position in positions:
    draw_circle(center+positions[position],2.8,ink if position==symbol else Color(0.7,0.8,0.9,0.22))
  _:
   var font := ThemeDB.fallback_font
   var text_size := 15 if symbol.length() <= 2 else 11
   if family == "xbox": ink = {"A":Color("9acb9b"),"B":Color("eda4a4"),"X":Color("8fbaf1"),"Y":Color("e5d08d")}.get(symbol,ink)
   var width := font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
   draw_string(font,center+Vector2(-width/2.0,5),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size,ink)

func _key_style() -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = Color(0.75,0.82,0.95,0.10)
 style.border_color = Color(0.75,0.82,0.95,0.5)
 style.set_border_width_all(1)
 style.set_corner_radius_all(4)
 return style
