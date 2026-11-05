extends StyleBox
## A StyleBox that paints a frosted-glass panel (glass.gdshader). Give it to
## a PanelContainer with Style.glass(): the panel's own canvas item gets the
## shader material, so labels and buttons inside it are drawn normally.
## The quad is grown by `inset` on every side to leave room for the shadow.

const SHADER := preload("res://scripts/ui/glass.gdshader")

static var _white: ImageTexture

var inset := 14.0
var material: ShaderMaterial


func _init(radius := 20.0, pad := 12.0, tint := Color(0.04, 0.07, 0.05, 0.55), blur := 3.0, border := 0.16) -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("border", border)
	material.set_shader_parameter("shadow", 0.0 if radius == 0.0 else 0.4) # full-screen sheets cast none
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("blur", blur)
	material.set_shader_parameter("inset", inset)
	set_content_margin_all(pad)


## Keeps the shader's idea of the panel size in sync with the control.
func attach(panel: Control) -> void:
	panel.material = material
	var update := func() -> void: material.set_shader_parameter("rect_size", panel.size)
	panel.resized.connect(update)
	update.call()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if _white == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	RenderingServer.canvas_item_add_texture_rect(to_canvas_item, rect.grow(inset), _white.get_rid(), false, Color.WHITE)


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(inset)
