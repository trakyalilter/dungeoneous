class_name CreatureView
extends Control
## Shows one Creature standing in a Control (start menu preview, camp).
## With campfire = true it also draws a crackling fire next to it.

var creature := Creature.new()
var campfire := false
var _fire: CPUParticles2D
var _t := 0.0


func _ready() -> void:
	add_child(creature)
	if campfire:
		_fire = CPUParticles2D.new()
		_fire.local_coords = true
		_fire.amount = 46
		_fire.lifetime = 0.9
		_fire.direction = Vector2(0, -1)
		_fire.spread = 18.0
		_fire.initial_velocity_min = 30.0
		_fire.initial_velocity_max = 80.0
		_fire.gravity = Vector2(0, -60)
		_fire.scale_amount_min = 4.0
		_fire.scale_amount_max = 9.0
		_fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_fire.emission_sphere_radius = 10.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color("#ffe070"))
		ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
		ramp.add_point(0.4, Color("#ff8a20"))
		_fire.color_ramp = ramp
		add_child(_fire)
	resized.connect(_layout)
	_layout()


func show_kind(kind: String) -> void:
	creature.setup(kind)
	_layout()


func _layout() -> void:
	var s := size.y / 200.0
	creature.position = Vector2(size.x * (0.38 if campfire else 0.5), size.y - 10)
	creature.scale = Vector2.ONE * s * creature.size_mult()
	if _fire:
		_fire.position = Vector2(size.x * 0.72, size.y - 22)


func _process(delta: float) -> void:
	_t += delta
	if campfire:
		queue_redraw()


func _draw() -> void:
	if not campfire:
		return
	var c := Vector2(size.x * 0.72, size.y - 14)
	var flicker := 0.9 + 0.1 * sin(_t * 11.0) * sin(_t * 7.3)
	draw_circle(c, 150 * flicker, Color(1, 0.55, 0.15, 0.06))
	draw_circle(c, 80 * flicker, Color(1, 0.55, 0.15, 0.08))
	for a in [-0.35, 0.35]:
		var d := Vector2(cos(a), sin(a)) * 34
		draw_line(c - d, c + d, Color("#14121a"), 14)
		draw_line(c - d, c + d, Color("#6b4a2a"), 10)
