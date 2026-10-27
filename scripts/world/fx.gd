extends RefCounted
## One-shot 3D effects: floating text and particle bursts.

const Shapes := preload("res://scripts/world/shapes.gd")
const Style := preload("res://scripts/ui/style.gd")


## Text that pops up at `pos`, drifts up and fades out.
static func float_text(parent: Node3D, pos: Vector3, text: String, color: Color, delay := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Style.font_bold()
	l.font_size = 44
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.modulate = Color(color, 0.0)
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.position = pos
	l.scale = Vector3.ONE * 0.6
	parent.add_child(l)
	var t := l.create_tween()
	t.tween_interval(delay)
	t.tween_property(l, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(l, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "position:y", pos.y + 1.1, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.35)
	t.tween_callback(l.queue_free)


## A burst of small chunks flying out from `pos` (wood chips, sparks, dust…).
static func burst(parent: Node3D, pos: Vector3, color: Color, amount := 10, size := 0.07, speed := 2.5, gravity := -9.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.mesh = Shapes.box(Vector3.ONE * size)
	p.material_override = Shapes.material(color)
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(0.7, 1))
	fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
