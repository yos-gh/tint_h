class_name TintStone
extends RigidBody2D

const SIZE := 38.0
const MAX_LINEAR_SPEED := 600.0
const MAX_ANGULAR_SPEED := 12.0

var tint_color := Color.WHITE
var group_id := 0
var is_supported := false
var touching_left_wall := false
var touching_right_wall := false
var has_external_contact := false
var near_clear := false
var glow_time := 0.0


func setup(new_color: Color, new_group_id: int) -> void:
	tint_color = new_color
	group_id = new_group_id
	mass = 1.0
	linear_damp = 0.35
	angular_damp = 1.8
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = CCD_MODE_CAST_SHAPE

	var material := PhysicsMaterial.new()
	material.friction = 0.72
	material.bounce = 0.06
	physics_material_override = material

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIZE - 3.0, SIZE - 3.0)
	collision.shape = shape
	add_child(collision)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(-SIZE * 0.5, -SIZE * 0.5), Vector2(SIZE, SIZE))
	var pulse := 0.0
	if near_clear:
		pulse = 0.5 + sin(glow_time * 7.0) * 0.5
		for layer in range(3, 0, -1):
			var glow_alpha := (0.11 + pulse * 0.13) * (4.0 - float(layer)) / 3.0
			draw_style_box(
				_make_box(Color(1.0, 0.82, 0.18, glow_alpha), 13.0 + layer * 3.0),
				rect.grow(layer * 7.0)
			)
	draw_style_box(_make_box(tint_color.darkened(0.20), 12.0), rect)
	var inner := rect.grow(-3.0)
	draw_style_box(_make_box(tint_color, 10.0), inner)
	if near_clear:
		draw_style_box(_make_box(Color(1.0, 0.88, 0.25, 0.12 + pulse * 0.16), 10.0), inner)
		draw_style_box(_make_outline(Color(1.0, 0.94, 0.52, 0.72 + pulse * 0.28), 3), rect.grow(2.0))
	# A small highlight makes the stones easier to read while rotating.
	draw_circle(Vector2(-10.0, -11.0), 5.0, Color(1, 1, 1, 0.24))
	if near_clear:
		var sparkle_radius := 2.0 + pulse * 2.2
		draw_circle(Vector2(13.0, -13.0), sparkle_radius, Color(1.0, 1.0, 0.82, 0.9))


func _process(delta: float) -> void:
	if near_clear:
		glow_time = fmod(glow_time + delta, TAU)
		queue_redraw()


func set_near_clear(value: bool) -> void:
	if near_clear == value:
		return
	near_clear = value
	if value:
		glow_time = 0.0
	queue_redraw()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Last-resort guardrail for stacked spring systems. Collisions can briefly
	# combine several constraints; capping velocity keeps numerical errors from
	# escalating into an off-screen launch while leaving normal play untouched.
	state.linear_velocity = state.linear_velocity.limit_length(MAX_LINEAR_SPEED)
	state.angular_velocity = clampf(state.angular_velocity, -MAX_ANGULAR_SPEED, MAX_ANGULAR_SPEED)
	is_supported = false
	touching_left_wall = false
	touching_right_wall = false
	has_external_contact = false

	for contact_index in range(state.get_contact_count()):
		var normal := state.get_contact_local_normal(contact_index)
		var collider := state.get_contact_collider_object(contact_index)
		if collider is StaticBody2D or (collider is TintStone and collider.group_id != group_id):
			has_external_contact = true

		# The normal points into this stone. An upward-facing normal therefore
		# means the floor or another piece is supporting it from below.
		if normal.y < -0.45:
			if collider is StaticBody2D:
				is_supported = true
			elif collider is TintStone and collider.group_id != group_id:
				is_supported = true

		if collider is StaticBody2D:
			if normal.x > 0.65:
				touching_left_wall = true
			elif normal.x < -0.65:
				touching_right_wall = true


func _make_box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = int(radius)
	box.corner_radius_top_right = int(radius)
	box.corner_radius_bottom_left = int(radius)
	box.corner_radius_bottom_right = int(radius)
	return box


func _make_outline(color: Color, width: int) -> StyleBoxFlat:
	var box := _make_box(Color.TRANSPARENT, 13.0)
	box.border_color = color
	box.border_width_left = width
	box.border_width_top = width
	box.border_width_right = width
	box.border_width_bottom = width
	return box
