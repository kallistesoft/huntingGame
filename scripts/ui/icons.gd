extends RefCounted
## Simple vector icons drawn in code (no image files). draw() paints one icon
## centred on `c`, `s` pixels across, on any CanvasItem during its _draw().

const NAMES := [
	"health", "energy", "food", "water", "bag", "xp", "sleep", "shop", "menu", "close",
	"axe", "pick", "berries", "spear", "bow", "door", "build", "quest", "check", "pin",
	"rope", "leather", "hood", "tunic", "boots", "grass", "hunter", "bone",
]


static func draw(ci: CanvasItem, icon: String, c: Vector2, s: float, color: Color) -> void:
	var h := s / 2.0
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * h
	var w := maxf(2.0, s * 0.11) # stroke width
	match icon:
		"health":
			ci.draw_circle(p.call(-0.42, -0.3), h * 0.5, color)
			ci.draw_circle(p.call(0.42, -0.3), h * 0.5, color)
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.9, -0.15), p.call(0.9, -0.15), p.call(0, 0.9)]), color)
		"energy":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.2, -1.0), p.call(-0.6, 0.15), p.call(-0.05, 0.15),
				p.call(-0.25, 1.0), p.call(0.6, -0.2), p.call(0.05, -0.2), p.call(0.3, -1.0)]), color)
		"food":
			ci.draw_line(p.call(-0.1, 0.1), p.call(-0.7, 0.7), color.lightened(0.6), w * 1.3)
			ci.draw_circle(p.call(-0.75, 0.55), w * 0.75, color.lightened(0.6))
			ci.draw_circle(p.call(-0.55, 0.78), w * 0.75, color.lightened(0.6))
			ci.draw_circle(p.call(0.25, -0.25), h * 0.68, color)
		"water":
			ci.draw_circle(p.call(0, 0.3), h * 0.62, color)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0, -1.0), p.call(-0.56, 0.1), p.call(0.56, 0.1)]), color)
			ci.draw_circle(p.call(-0.22, 0.3), h * 0.14, Color(1, 1, 1, 0.55))
		"bag":
			ci.draw_arc(p.call(0, -0.45), h * 0.35, PI, TAU, 12, color, w)
			_round_rect(ci, Rect2(p.call(-0.75, -0.45), Vector2(1.5, 1.4) * h), h * 0.3, color)
			ci.draw_rect(Rect2(p.call(-0.75, -0.2), Vector2(1.5, 0.12) * h), color.darkened(0.3))
		"xp":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				var r := 1.0 if i % 2 == 0 else 0.45
				pts.append(p.call(cos(a) * r, sin(a) * r + 0.08))
			ci.draw_colored_polygon(pts, color)
		"sleep":
			ci.draw_colored_polygon(_crescent(c, h * 0.85, c + Vector2(0.38, -0.3) * h, h * 0.62), color)
		"shop":
			ci.draw_circle(c, h * 0.9, color)
			ci.draw_arc(c, h * 0.62, 0, TAU, 24, color.darkened(0.25), w * 0.8)
			ci.draw_rect(Rect2(p.call(-0.12, -0.4), Vector2(0.24, 0.8) * h), color.darkened(0.25))
		"menu":
			for y in [-0.55, 0.0, 0.55]:
				ci.draw_line(p.call(-0.75, y), p.call(0.75, y), color, w * 1.2)
		"close":
			ci.draw_line(p.call(-0.6, -0.6), p.call(0.6, 0.6), color, w * 1.3)
			ci.draw_line(p.call(0.6, -0.6), p.call(-0.6, 0.6), color, w * 1.3)
		"axe":
			ci.draw_line(p.call(-0.7, 0.9), p.call(0.3, -0.7), Color("a0703f"), w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.05, -0.85), p.call(0.9, -0.55),
				p.call(0.75, 0.1), p.call(0.3, -0.25)]), color)
		"pick":
			ci.draw_line(p.call(-0.6, 0.9), p.call(0.2, -0.45), Color("a0703f"), w * 1.2)
			ci.draw_arc(p.call(0.15, 0.15), h * 0.85, deg_to_rad(-150), deg_to_rad(-20), 12, color, w * 1.4)
		"berries":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0, -0.5), p.call(0.7, -0.95), p.call(0.35, -0.35)]), Color("7cc46b"))
			for q in [Vector2(-0.35, 0.05), Vector2(0.35, 0.05), Vector2(0, 0.6)]:
				ci.draw_circle(p.call(q.x, q.y), h * 0.36, color)
		"spear":
			ci.draw_line(p.call(-0.8, 0.8), p.call(0.45, -0.45), Color("a0703f"), w)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.9, -0.9), p.call(0.3, -0.6), p.call(0.6, -0.3)]), color)
		"bow":
			ci.draw_arc(p.call(-0.45, 0), h * 1.0, -PI / 2.6, PI / 2.6, 16, Color("a0703f"), w * 1.2)
			ci.draw_line(p.call(-0.45 + 0.92, -0.75), p.call(-0.45 + 0.92, 0.75), color, w * 0.5)
		"door":
			_round_rect(ci, Rect2(p.call(-0.55, -0.85), Vector2(1.1, 1.75) * h), h * 0.2, color)
			ci.draw_circle(p.call(0.25, 0.1), w * 0.7, color.darkened(0.5))
		"build":
			var hp := PackedVector2Array([p.call(-0.85, -0.55), p.call(0.15, -0.95), p.call(0.4, -0.35), p.call(-0.6, 0.05)])
			ci.draw_line(p.call(-0.1, -0.4), p.call(0.75, 0.9), Color("a0703f"), w * 1.2)
			ci.draw_colored_polygon(hp, color)
		"quest":
			_round_rect(ci, Rect2(p.call(-0.65, -0.85), Vector2(1.3, 1.7) * h), h * 0.15, color)
			for y in [-0.45, -0.05, 0.35]:
				ci.draw_line(p.call(-0.4, y), p.call(0.4, y), color.darkened(0.5), w * 0.6)
		"check":
			ci.draw_polyline(PackedVector2Array([p.call(-0.7, 0), p.call(-0.15, 0.55), p.call(0.75, -0.55)]), color, w * 1.4)
		"rope":
			# Coil seen from the side: three loops.
			for y in [-0.45, 0.0, 0.45]:
				ci.draw_arc(p.call(0, y), h * 0.62, 0, TAU, 20, color, w * 1.1)
		"leather":
			# A stretched hide: wide body with four little legs.
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.75, -0.55), p.call(-0.45, -0.85), p.call(0.45, -0.85), p.call(0.75, -0.55),
				p.call(0.9, 0.2), p.call(0.5, 0.85), p.call(-0.5, 0.85), p.call(-0.9, 0.2)]), color)
			ci.draw_circle(p.call(0, 0.05), h * 0.18, color.darkened(0.25))
		"hood":
			# Hood: a dome with a dark face opening.
			ci.draw_colored_polygon(_arc_poly(p.call(0, 0.2), h * 0.95, PI, TAU), color)
			ci.draw_rect(Rect2(p.call(-0.95, 0.2), Vector2(1.9, 0.6) * h), color)
			ci.draw_colored_polygon(_arc_poly(p.call(0, 0.35), h * 0.5, PI, TAU), color.darkened(0.6))
		"tunic":
			# Shirt outline: shoulders, short sleeves, straight body.
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.35, -0.9), p.call(0.35, -0.9), p.call(0.95, -0.55), p.call(0.75, -0.05),
				p.call(0.5, -0.15), p.call(0.5, 0.9), p.call(-0.5, 0.9), p.call(-0.5, -0.15), p.call(-0.75, -0.05), p.call(-0.95, -0.55)]), color)
			ci.draw_colored_polygon(_arc_poly(p.call(0, -0.9), h * 0.3, 0, PI), color.darkened(0.5))
		"boots":
			# One boot: shaft, foot and a thick sole.
			ci.draw_rect(Rect2(p.call(-0.55, -0.9), Vector2(0.7, 1.2) * h), color)
			ci.draw_rect(Rect2(p.call(-0.55, 0.1), Vector2(1.4, 0.6) * h), color)
			ci.draw_rect(Rect2(p.call(-0.6, 0.6), Vector2(1.5, 0.3) * h), color.darkened(0.45))
		"grass":
			# Three tall blades.
			for i in [-1, 0, 1]:
				ci.draw_line(p.call(i * 0.45, 0.95), p.call(i * 0.6, -0.9 + absf(i) * 0.3), color, w * 1.2)
		"hunter":
			# Head and shoulders.
			ci.draw_circle(p.call(0, -0.45), h * 0.42, color)
			ci.draw_colored_polygon(_arc_poly(p.call(0, 0.95), h * 0.9, PI, TAU), color)
		"bone":
			ci.draw_line(p.call(-0.5, 0.5), p.call(0.5, -0.5), color, w * 1.6)
			for e in [Vector2(-0.5, 0.5), Vector2(0.5, -0.5)]:
				ci.draw_circle(p.call(e.x - 0.18, e.y - 0.18), w * 0.9, color)
				ci.draw_circle(p.call(e.x + 0.18, e.y + 0.18), w * 0.9, color)
		"pin":
			# Push pin: round head, a flat collar, and the needle pointing down-left.
			ci.draw_circle(p.call(0.25, -0.45), h * 0.42, color)
			ci.draw_line(p.call(-0.35, 0.05), p.call(0.55, -0.85), color, w * 1.1)
			ci.draw_line(p.call(-0.55, -0.1), p.call(0.1, 0.55), color, w * 1.4)
			ci.draw_line(p.call(-0.25, 0.25), p.call(-0.85, 0.85), color, w * 0.8)


## Filled pie slice from angle a to b (radians), for domes and arcs.
static func _arc_poly(c: Vector2, r: float, a: float, b: float) -> PackedVector2Array:
	var pts := PackedVector2Array([c])
	for i in 17:
		pts.append(c + Vector2.from_angle(a + (b - a) * i / 16.0) * r)
	return pts


static func _round_rect(ci: CanvasItem, r: Rect2, radius: float, color: Color) -> void:
	ci.draw_rect(r.grow_individual(-radius, 0, -radius, 0), color)
	ci.draw_rect(r.grow_individual(0, -radius, 0, -radius), color)
	for corner in [r.position + Vector2(radius, radius), Vector2(r.end.x - radius, r.position.y + radius),
			Vector2(r.position.x + radius, r.end.y - radius), r.end - Vector2(radius, radius)]:
		ci.draw_circle(corner, radius, color)


## Outline of a moon crescent: the big circle minus the small one that bites into it.
static func _crescent(c1: Vector2, r1: float, c2: Vector2, r2: float) -> PackedVector2Array:
	var d := c1.distance_to(c2)
	var dir := (c2 - c1) / d
	var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
	var k := sqrt(maxf(0.0, r1 * r1 - a * a))
	var mid := c1 + dir * a
	var p1 := mid + Vector2(-dir.y, dir.x) * k
	var p2 := mid - Vector2(-dir.y, dir.x) * k
	var pts := PackedVector2Array()
	# Outer edge: the long way round, away from the bite.
	var o1 := (p1 - c1).angle()
	var o2 := (p2 - c1).angle()
	var sweep := wrapf(o2 - o1, 0.0, TAU)
	if (c1 + Vector2.from_angle(o1 + sweep / 2.0) * r1).distance_to(c2) < r2:
		sweep -= TAU
	for i in 25:
		pts.append(c1 + Vector2.from_angle(o1 + sweep * i / 24.0) * r1)
	# Inner edge: the bite's arc that lies inside the big circle, back to the start.
	var i2 := (p2 - c2).angle()
	var i1 := (p1 - c2).angle()
	var bite := wrapf(i1 - i2, 0.0, TAU)
	if (c2 + Vector2.from_angle(i2 + bite / 2.0) * r2).distance_to(c1) > r1:
		bite -= TAU
	for i in range(1, 24):
		pts.append(c2 + Vector2.from_angle(i2 + bite * i / 24.0) * r2)
	return pts
