extends Node2D

const StoneScene = preload("res://scripts/stone.gd")
const VirtualStickScene = preload("res://scripts/virtual_stick.gd")

const STONE_SIZE := 38.0
const FIELD_COLUMNS := 25
const FIELD_ROWS := 11
const FIELD_CENTER_X := 640.0
const FIELD_LEFT := FIELD_CENTER_X - STONE_SIZE * FIELD_COLUMNS * 0.5
const FIELD_RIGHT := FIELD_CENTER_X + STONE_SIZE * FIELD_COLUMNS * 0.5
const FIELD_TOP := 145.0
const REFERENCE_CLEAR_COLUMN_HEIGHT := STONE_SIZE * FIELD_ROWS
const CLEAR_COLUMN_HEIGHT := REFERENCE_CLEAR_COLUMN_HEIGHT * 0.8
const FIELD_HEIGHT := REFERENCE_CLEAR_COLUMN_HEIGHT * 1.5
const BOWL_DEPTH := 100.0
const BOWL_EDGE_Y := FIELD_TOP + FIELD_HEIGHT - BOWL_DEPTH
const FIELD_BOTTOM := FIELD_TOP + FIELD_HEIGHT
const PIECE_GAP := 42.0
const LEFT_DEADLINE_X := FIELD_LEFT + STONE_SIZE * 2.0
const RIGHT_DEADLINE_X := FIELD_RIGHT - STONE_SIZE * 2.0
const SPAWN_POS := Vector2(FIELD_CENTER_X, 80.0)
const PAIR_HEIGHT_TOLERANCE := STONE_SIZE * 0.55
const CLEAR_BAND_HALF_WIDTH := STONE_SIZE * 0.55

const HORIZONTAL_MOVE_SPEED := 240.0
const SOFT_DROP_EXTRA_SPEED := 300.0
const TARGET_ROTATION_SPEED := TAU # One full turn per second.
const GAMEPAD_DEADZONE := 0.28
const INPUT_MOVE_LEFT := "gamepad_move_left"
const INPUT_MOVE_RIGHT := "gamepad_move_right"
const INPUT_DROP := "gamepad_drop"
const INPUT_ROTATE_LEFT := "gamepad_rotate_left"
const INPUT_ROTATE_RIGHT := "gamepad_rotate_right"

# Shape springs use the upper end of Godot's practical stiffness range.
# The weaker all-pair support springs resist folding while still allowing
# the tetromino to squash a little under pressure.
const EDGE_SPRING_STIFFNESS := 64.0
const SUPPORT_SPRING_STIFFNESS := 48.0
const EDGE_SPRING_DAMPING := 12.0
const SUPPORT_SPRING_DAMPING := 8.0

# Springs provide local squash and bounce. This proportional-derivative shape
# memory prevents the whole tetromino from folding flat under a pile.
const SHAPE_MEMORY_STIFFNESS := 3400.0
const SHAPE_MEMORY_DAMPING := 55.0
# Keep small errors stiff, but saturate large collision errors before one
# physics tick can inject enough energy to launch a stone across the screen.
const SHAPE_MEMORY_MAX_FORCE := 20000.0
const FREE_ROTATION_MAX_FORCE := 42000.0
const SETTLED_SHAPE_STIFFNESS := 1100.0
const SETTLED_SHAPE_DAMPING := 38.0
const SETTLED_SHAPE_MAX_FORCE := 6000.0
const ROTATION_DEFORMATION_LIMIT := STONE_SIZE * 0.40
const MAX_ROTATION_TARGET_LEAD := 0.10
const LOCK_DELAY := 0.3
const GAME_OVER_GRACE_PERIOD := 5.0
const NEAR_CLEAR_SCAN_INTERVAL := 0.12
const COMBO_WINDOW := 1.0

const SHAPES := {
	"I": [Vector2(-1.5, 0), Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(1.5, 0)],
	"O": [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)],
	"T": [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
	"L": [Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	"J": [Vector2(-1, 1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0)],
	"S": [Vector2(-1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	"Z": [Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
}

const COLORS := [
	Color("55d6be"), Color("ff6b8a"), Color("ffd166"),
	Color("6c9cff"), Color("bd7cff"), Color("ff9f55"), Color("72e06a")
]

var stones: Array[Node] = []
var links: Array[Dictionary] = []
var shape_groups: Array[Dictionary] = []
var active_stones: Array[Node] = []
var active_group_id := -1
var active_age := 0.0
var settle_age := 0.0
var group_counter := 0
var score := 0
var cleared := 0
var last_height_multiplier := 1
var is_game_over := false
var game_over_exposure := 0.0
var elimination_cooldown := 0.0
var near_clear_cooldown := 0.0
var combo_count := 0
var combo_time_remaining := 0.0
var soft_drop_active := false
var soft_drop_natural_velocity := 0.0
var flash_lines: Array[Dictionary] = []

var score_label: Label
var status_label: Label
var help_label: Label
var left_limit_label: Label
var limit_label: Label
var combo_label: Label
var touch_stick: TintVirtualStick
var start_overlay: ColorRect
var is_started := false


func _ready() -> void:
	randomize()
	_configure_gamepad_input()
	_build_world()
	_build_ui()
	_build_touch_controls()
	_build_start_overlay()
	queue_redraw()


func _input(event: InputEvent) -> void:
	var keyboard_start: bool = event is InputEventKey and event.pressed and not event.echo
	var button_start: bool = event is InputEventJoypadButton and event.pressed
	var stick_start: bool = event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5
	var touch_start: bool = event is InputEventScreenTouch and event.pressed
	if not is_started and (keyboard_start or button_start or stick_start or touch_start):
		start_game()
		get_viewport().set_input_as_handled()
	elif is_game_over and touch_start:
		get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()


func _configure_gamepad_input() -> void:
	_add_gamepad_axis(INPUT_MOVE_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_add_gamepad_button(INPUT_MOVE_LEFT, JOY_BUTTON_DPAD_LEFT)
	_add_gamepad_axis(INPUT_MOVE_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	_add_gamepad_button(INPUT_MOVE_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_add_gamepad_axis(INPUT_DROP, JOY_AXIS_LEFT_Y, 1.0)
	_add_gamepad_button(INPUT_DROP, JOY_BUTTON_DPAD_DOWN)
	_add_gamepad_button(INPUT_ROTATE_LEFT, JOY_BUTTON_A)
	_add_gamepad_button(INPUT_ROTATE_LEFT, JOY_BUTTON_X)
	_add_gamepad_button(INPUT_ROTATE_RIGHT, JOY_BUTTON_B)
	_add_gamepad_button(INPUT_ROTATE_RIGHT, JOY_BUTTON_Y)


func _ensure_gamepad_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, GAMEPAD_DEADZONE)


func _add_gamepad_button(action: StringName, button: JoyButton) -> void:
	_ensure_gamepad_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and existing.button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _add_gamepad_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	_ensure_gamepad_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadMotion \
				and existing.axis == axis \
				and signf(existing.axis_value) == signf(direction):
			return
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	InputMap.action_add_event(action, event)


func start_game() -> void:
	if is_started:
		return
	is_started = true
	start_overlay.visible = false
	_spawn_piece()


func _build_world() -> void:
	var boundary := StaticBody2D.new()
	boundary.name = "Bowl"
	add_child(boundary)

	_add_wall(FIELD_LEFT, true)
	_add_wall(FIELD_RIGHT, false)

	var previous := Vector2(FIELD_LEFT, _bowl_y(FIELD_LEFT))
	for index in range(1, 25):
		var x := lerpf(FIELD_LEFT, FIELD_RIGHT, float(index) / 24.0)
		var current := Vector2(x, _bowl_y(x))
		_add_segment(boundary, previous, current)
		previous = current


func _add_wall(inner_x: float, is_left: bool) -> void:
	const WALL_THICKNESS := 48.0
	var body := StaticBody2D.new()
	body.name = "LeftWall" if is_left else "RightWall"
	var wall_material := PhysicsMaterial.new()
	wall_material.friction = 0.0
	wall_material.bounce = 0.0
	body.physics_material_override = wall_material
	add_child(body)
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	# Extend well beyond the viewport so a collision cannot launch a stone over
	# the wall's top endpoint and around the outside of the field.
	var top := FIELD_TOP - 2000.0
	var bottom := FIELD_BOTTOM + 2000.0
	rectangle.size = Vector2(WALL_THICKNESS, bottom - top)
	collision.shape = rectangle
	# Keep the visible field width unchanged; all wall thickness extends outward.
	collision.position = Vector2(
		inner_x + (-WALL_THICKNESS * 0.5 if is_left else WALL_THICKNESS * 0.5),
		(top + bottom) * 0.5
	)
	body.add_child(collision)


func _add_segment(body: StaticBody2D, from: Vector2, to: Vector2) -> void:
	var collision := CollisionShape2D.new()
	var segment := SegmentShape2D.new()
	segment.a = from
	segment.b = to
	collision.shape = segment
	body.add_child(collision)


func _build_ui() -> void:
	var title := Label.new()
	title.text = "T I N T   H O R I Z O N T A L"
	title.position = Vector2(28, 20)
	title.add_theme_font_size_override("font_size", 31)
	title.add_theme_color_override("font_color", Color("e8efff"))
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "stack narrow · clear vertical"
	subtitle.position = Vector2(31, 57)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("8292b8"))
	add_child(subtitle)

	score_label = Label.new()
	score_label.position = Vector2(835, 27)
	score_label.size = Vector2(410, 35)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 20)
	add_child(score_label)

	status_label = Label.new()
	status_label.position = Vector2(350, 290)
	status_label.size = Vector2(580, 100)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 28)
	status_label.add_theme_color_override("font_color", Color("fff3c4"))
	status_label.add_theme_constant_override("outline_size", 7)
	status_label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.06, 0.98))
	status_label.z_index = 100
	status_label.visible = false
	add_child(status_label)

	limit_label = Label.new()
	limit_label.text = "DEADLINE"
	limit_label.position = Vector2(RIGHT_DEADLINE_X - 90.0, FIELD_TOP - 33.0)
	limit_label.size = Vector2(180, 30.0)
	limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit_label.add_theme_font_size_override("font_size", 17)
	limit_label.add_theme_color_override("font_color", Color("ff8b98"))
	limit_label.add_theme_constant_override("outline_size", 5)
	limit_label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.06, 0.95))
	limit_label.z_index = 90
	limit_label.visible = true
	add_child(limit_label)

	left_limit_label = Label.new()
	left_limit_label.text = "DEADLINE"
	left_limit_label.position = Vector2(LEFT_DEADLINE_X - 90.0, FIELD_TOP - 33.0)
	left_limit_label.size = Vector2(180, 30.0)
	left_limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_limit_label.add_theme_font_size_override("font_size", 17)
	left_limit_label.add_theme_color_override("font_color", Color("ff8b98"))
	left_limit_label.add_theme_constant_override("outline_size", 5)
	left_limit_label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.06, 0.95))
	left_limit_label.z_index = 90
	left_limit_label.visible = true
	add_child(left_limit_label)

	combo_label = Label.new()
	combo_label.position = Vector2(500, 68)
	combo_label.size = Vector2(280, 34)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 18)
	combo_label.add_theme_color_override("font_color", Color("ffe08a"))
	combo_label.visible = false
	add_child(combo_label)

	help_label = Label.new()
	help_label.text = "KEYS  A/D  S  N/M     PAD  D-PAD/STICK  A/X  B/Y"
	help_label.position = Vector2(300, 866)
	help_label.size = Vector2(680, 24)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color("91a0c5"))
	add_child(help_label)
	_update_ui()


func _build_start_overlay() -> void:
	start_overlay = ColorRect.new()
	start_overlay.position = Vector2.ZERO
	start_overlay.size = Vector2(1280, 900)
	start_overlay.color = Color(0.025, 0.035, 0.06, 0.97)
	start_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_overlay.z_index = 200
	add_child(start_overlay)

	var start_title := _start_label("T I N T   H O R I Z O N T A L", Vector2(0, 190), Vector2(1280, 80), 50, Color("e8efff"))
	start_overlay.add_child(start_title)
	var start_subtitle := _start_label("STACK NARROW · CLEAR VERTICAL", Vector2(0, 268), Vector2(1280, 34), 18, Color("8292b8"))
	start_overlay.add_child(start_subtitle)
	var prompt := _start_label("PRESS ANY KEY, BUTTON, OR TAP", Vector2(0, 360), Vector2(1280, 50), 24, Color("fff3c4"))
	start_overlay.add_child(prompt)
	var controls := _start_label(
		"KEYS  A/D  S  N/M     PAD  D-PAD/STICK  A/X  B/Y",
		Vector2(0, 445), Vector2(1280, 30), 14, Color("91a0c5")
	)
	start_overlay.add_child(controls)


func _build_touch_controls() -> void:
	var touch_layer := Node2D.new()
	touch_layer.name = "TouchControls"
	touch_layer.z_index = 80
	add_child(touch_layer)
	touch_stick = VirtualStickScene.new()
	touch_stick.name = "VirtualStick"
	touch_stick.position = Vector2(92, 825)
	touch_layer.add_child(touch_stick)
	_add_touch_button(touch_layer, INPUT_ROTATE_LEFT, Vector2(1095, 825), "ccw", Color("ffd166"))
	_add_touch_button(touch_layer, INPUT_ROTATE_RIGHT, Vector2(1190, 825), "cw", Color("ffd166"))


func _add_touch_button(
	parent: Node, action: StringName, center: Vector2, icon: String, color: Color
) -> void:
	var button := TouchScreenButton.new()
	button.name = String(action)
	button.position = center
	button.action = action
	button.passby_press = true
	# TouchScreenButton's Web heuristic can report a pen tablet as a touch
	# display even when Godot's DisplayServer does not. Use the exact same
	# condition as the virtual stick so the two control groups stay in sync.
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	button.visible = DisplayServer.is_touchscreen_available()
	var touch_shape := CircleShape2D.new()
	touch_shape.radius = 37.0
	button.shape = touch_shape
	parent.add_child(button)

	var disc := Polygon2D.new()
	var points := PackedVector2Array()
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(Vector2.from_angle(angle) * 35.0)
	disc.polygon = points
	disc.color = Color(color, 0.24)
	button.add_child(disc)

	var ring := Line2D.new()
	ring.points = points
	ring.closed = true
	ring.width = 2.5
	ring.default_color = Color(color, 0.68)
	ring.antialiased = true
	button.add_child(ring)

	_add_rotation_touch_icon(button, icon == "cw", color)


func _add_rotation_touch_icon(button: TouchScreenButton, clockwise: bool, color: Color) -> void:
	var arc := Line2D.new()
	arc.width = 3.5
	arc.default_color = Color(color, 0.92)
	arc.antialiased = true
	var points := PackedVector2Array()
	var start_angle := -2.5 if clockwise else -0.64
	var end_angle := 2.2 if clockwise else -5.34
	for index in range(22):
		var amount := float(index) / 21.0
		points.append(Vector2.from_angle(lerpf(start_angle, end_angle, amount)) * 16.0)
	arc.points = points
	button.add_child(arc)

	var tip := points[points.size() - 1]
	var tangent_angle := end_angle + (PI * 0.5 if clockwise else -PI * 0.5)
	var direction := Vector2.from_angle(tangent_angle)
	var perpendicular := Vector2(-direction.y, direction.x)
	var arrowhead := Polygon2D.new()
	arrowhead.polygon = PackedVector2Array([
		tip + direction * 2.0,
		tip - direction * 9.0 + perpendicular * 5.0,
		tip - direction * 9.0 - perpendicular * 5.0,
	])
	arrowhead.color = Color(color, 0.92)
	button.add_child(arrowhead)


func _start_label(text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _physics_process(delta: float) -> void:
	if not is_started:
		return
	if Input.is_key_pressed(KEY_R) and is_game_over:
		get_tree().reload_current_scene()
		return
	if is_game_over:
		return

	active_age += delta
	elimination_cooldown -= delta
	near_clear_cooldown -= delta
	_update_combo(delta)
	_prune_invalid_stones()
	_update_game_over_state(delta)
	if is_game_over:
		return
	_control_active_piece(delta)
	_apply_shape_memory()
	_update_active_piece(delta)

	if elimination_cooldown <= 0.0 and active_stones.is_empty():
		elimination_cooldown = 0.35
		_check_for_elimination()
	if near_clear_cooldown <= 0.0:
		near_clear_cooldown = NEAR_CLEAR_SCAN_INTERVAL
		_update_near_clear_highlights()

	for flash in flash_lines:
		flash["life"] -= delta
	flash_lines = flash_lines.filter(func(item): return item["life"] > 0.0)
	queue_redraw()


func _control_active_piece(delta: float) -> void:
	if active_stones.is_empty():
		_reset_translation_control()
		return
	var horizontal := Input.get_axis(INPUT_MOVE_LEFT, INPUT_MOVE_RIGHT)
	if is_instance_valid(touch_stick):
		horizontal += touch_stick.value.x
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		horizontal -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		horizontal += 1.0
	horizontal = clampf(horizontal, -1.0, 1.0)
	if horizontal < 0.0 and active_stones.any(func(stone):
		return stone.touching_left_wall or stone.global_position.x - STONE_SIZE * 0.5 <= FIELD_LEFT + 2.0
	):
		horizontal = 0.0
	elif horizontal > 0.0 and active_stones.any(func(stone):
		return stone.touching_right_wall or stone.global_position.x + STONE_SIZE * 0.5 >= FIELD_RIGHT - 2.0
	):
		horizontal = 0.0
	var drop_strength := Input.get_action_strength(INPUT_DROP)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		drop_strength = 1.0
	if is_instance_valid(touch_stick):
		drop_strength = maxf(drop_strength, maxf(touch_stick.value.y, 0.0))
	var rotate_dir := 0.0
	if Input.is_key_pressed(KEY_M) or Input.is_action_pressed(INPUT_ROTATE_RIGHT):
		rotate_dir += 1.0
	if Input.is_key_pressed(KEY_N) or Input.is_action_pressed(INPUT_ROTATE_LEFT):
		rotate_dir -= 1.0

	# Keep the target slightly ahead of the piece instead of stopping rotation
	# whenever the physical stones lag behind it. The former on/off threshold
	# alternated every few frames during a held input and looked like twitching.
	for group in shape_groups:
		if group["id"] != active_group_id:
			continue
		if rotate_dir != 0.0:
			var current_target: float = group["target_rotation"]
			var shape_error := _shape_error(group)
			var rotation_scale := 1.0 - smoothstep(
				ROTATION_DEFORMATION_LIMIT * 0.85, ROTATION_DEFORMATION_LIMIT, shape_error
			)
			var next_target := current_target
			if rotation_scale > 0.0:
				var fitted_rotation := _fitted_group_rotation(group)
				var unwrapped_fitted := current_target + angle_difference(current_target, fitted_rotation)
				var desired_target := (
					current_target + rotate_dir * TARGET_ROTATION_SPEED * rotation_scale * delta
				)
				var target_lead := angle_difference(unwrapped_fitted, desired_target)
				next_target = unwrapped_fitted + clampf(
					target_lead, -MAX_ROTATION_TARGET_LEAD, MAX_ROTATION_TARGET_LEAD
				)
			group["target_rotation"] = next_target
			# Fade the rotational velocity over the same deformation range. A
			# blocked tip then slows smoothly instead of either tearing the piece
			# apart or toggling abruptly on and off.
			group["target_angular_velocity"] = rotate_dir * TARGET_ROTATION_SPEED * rotation_scale
		else:
			group["target_angular_velocity"] = 0.0
		break

	_apply_translation_control(horizontal, drop_strength, delta)

	# Rotation must not become translational lift. Remove only the shared upward
	# velocity of the piece; relative velocities that form the rotation remain.
	if rotate_dir != 0.0:
		var average_vertical_velocity := 0.0
		var valid_count := 0
		for stone in active_stones:
			if is_instance_valid(stone):
				average_vertical_velocity += stone.linear_velocity.y
				valid_count += 1
		average_vertical_velocity /= maxf(float(valid_count), 1.0)
		if average_vertical_velocity < 0.0:
			for stone in active_stones:
				if is_instance_valid(stone):
					stone.linear_velocity.y -= average_vertical_velocity


func _apply_translation_control(horizontal: float, drop_strength: float, delta: float) -> void:
	var valid_stones: Array[Node] = active_stones.filter(
		func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion()
	)
	if valid_stones.is_empty():
		_reset_translation_control()
		return

	# Control the piece's center-of-mass velocity, preserving the relative
	# velocities used by rotation and soft-body deformation.
	var average_velocity := Vector2.ZERO
	for stone in valid_stones:
		average_velocity += stone.linear_velocity
	average_velocity /= float(valid_stones.size())

	var target_horizontal_velocity := horizontal * HORIZONTAL_MOVE_SPEED
	var horizontal_correction := target_horizontal_velocity - average_velocity.x
	var vertical_correction := 0.0
	if drop_strength > 0.0:
		var supported: bool = valid_stones.any(func(stone): return stone.is_supported)
		if supported:
			# A held soft drop must stop being a drive force once the piece lands.
			# Otherwise the remembered free-fall velocity keeps growing while the
			# pile holds the piece still and keeps crushing the pile. Reset only the
			# input state: the physics solver's natural rebound must remain intact.
			soft_drop_natural_velocity = 0.0
			soft_drop_active = false
		elif not soft_drop_active:
			soft_drop_natural_velocity = average_velocity.y
			soft_drop_active = true
		else:
			var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity"))
			# Collisions may slow the piece before the support flag becomes visible
			# here. Never let the hidden natural-velocity baseline outrun the
			# velocity the physics solver actually produced.
			soft_drop_natural_velocity = minf(
				soft_drop_natural_velocity + gravity * delta, average_velocity.y
			)
		if not supported:
			var target_vertical_velocity := (
				soft_drop_natural_velocity + SOFT_DROP_EXTRA_SPEED * drop_strength
			)
			vertical_correction = target_vertical_velocity - average_velocity.y
	elif soft_drop_active:
		vertical_correction = soft_drop_natural_velocity - average_velocity.y
		soft_drop_active = false

	for stone in valid_stones:
		stone.linear_velocity += Vector2(horizontal_correction, vertical_correction)


func _average_active_velocity() -> Vector2:
	var valid_stones: Array[Node] = active_stones.filter(
		func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion()
	)
	var average_velocity := Vector2.ZERO
	for stone in valid_stones:
		average_velocity += stone.linear_velocity
	return average_velocity / maxf(float(valid_stones.size()), 1.0)


func _reset_translation_control() -> void:
	soft_drop_active = false
	soft_drop_natural_velocity = 0.0


func _shape_error(group: Dictionary) -> float:
	var group_stones: Array = group["stones"].filter(
		func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion()
	)
	if group_stones.is_empty():
		return 0.0
	var current_center := Vector2.ZERO
	var reference_center := Vector2.ZERO
	for stone in group_stones:
		current_center += stone.global_position
		reference_center += group["offsets"][stone.get_instance_id()]
	current_center /= float(group_stones.size())
	reference_center /= float(group_stones.size())
	var maximum_error := 0.0
	var target_rotation: float = group["target_rotation"]
	for stone in group_stones:
		var reference: Vector2 = group["offsets"][stone.get_instance_id()] - reference_center
		var target: Vector2 = current_center + reference.rotated(target_rotation)
		maximum_error = maxf(maximum_error, stone.global_position.distance_to(target))
	return maximum_error


func _fitted_group_rotation(group: Dictionary) -> float:
	var group_stones: Array = group["stones"].filter(
		func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion()
	)
	if group_stones.size() < 2:
		return float(group["target_rotation"])
	var current_center := Vector2.ZERO
	var reference_center := Vector2.ZERO
	for stone in group_stones:
		current_center += stone.global_position
		reference_center += group["offsets"][stone.get_instance_id()]
	current_center /= float(group_stones.size())
	reference_center /= float(group_stones.size())
	var dot_sum := 0.0
	var cross_sum := 0.0
	for stone in group_stones:
		var reference: Vector2 = group["offsets"][stone.get_instance_id()] - reference_center
		var current: Vector2 = stone.global_position - current_center
		dot_sum += reference.dot(current)
		cross_sum += reference.cross(current)
	return atan2(cross_sum, dot_sum)


func _update_active_piece(delta: float) -> void:
	if active_stones.is_empty():
		return

	# Start the lock delay as soon as any stone is supported by the bowl or by
	# a stone from an older piece. Side-wall and same-piece contacts do not lock.
	var supported := active_stones.any(func(stone): return stone.is_supported)
	if supported:
		settle_age += delta
	else:
		settle_age = 0.0

	if settle_age >= LOCK_DELAY:
		active_group_id = -1
		active_stones.clear()
		_reset_translation_control()
		settle_age = 0.0
		_check_for_elimination()
		if not is_game_over:
			_spawn_piece.call_deferred()


func _spawn_piece(shape_override: String = "") -> void:
	if is_game_over:
		return
	_reset_translation_control()
	group_counter += 1
	active_group_id = group_counter
	active_age = 0.0
	settle_age = 0.0
	var names := SHAPES.keys()
	var shape_name: String = shape_override if SHAPES.has(shape_override) else names[randi() % names.size()]
	var offsets: Array = SHAPES[shape_name]
	var color: Color = COLORS[randi() % COLORS.size()]
	var new_stones: Array[Node] = []
	var reference_offsets := {}

	for offset in offsets:
		var stone := StoneScene.new()
		stone.name = "Stone_%d_%d" % [group_counter, new_stones.size()]
		stone.position = SPAWN_POS + offset * PIECE_GAP
		stone.setup(color, group_counter)
		add_child(stone)
		stones.append(stone)
		new_stones.append(stone)
		reference_offsets[stone.get_instance_id()] = offset * PIECE_GAP

	# Every pair is softly connected. Edge springs carry most of the shape,
	# while weaker diagonal springs keep it recognizable without making it rigid.
	for first in range(new_stones.size()):
		for second in range(first + 1, new_stones.size()):
			var distance: float = new_stones[first].position.distance_to(new_stones[second].position)
			var adjacent := distance < PIECE_GAP * 1.15
			_add_spring(new_stones[first], new_stones[second], distance, adjacent)
	shape_groups.append({
		"id": group_counter,
		"stones": new_stones.duplicate(),
		"offsets": reference_offsets,
		"target_rotation": 0.0,
		"target_angular_velocity": 0.0,
	})
	active_stones = new_stones


func _apply_shape_memory() -> void:
	for group_index in range(shape_groups.size() - 1, -1, -1):
		var group := shape_groups[group_index]
		var group_stones: Array = group["stones"].filter(
			func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion()
		)
		group["stones"] = group_stones
		if group_stones.size() < 2:
			shape_groups.remove_at(group_index)
			continue

		var current_center := Vector2.ZERO
		var reference_center := Vector2.ZERO
		var average_velocity := Vector2.ZERO
		for stone in group_stones:
			current_center += stone.global_position
			reference_center += group["offsets"][stone.get_instance_id()]
			average_velocity += stone.linear_velocity
		current_center /= float(group_stones.size())
		reference_center /= float(group_stones.size())
		average_velocity /= float(group_stones.size())

		# Preserve rigid-body rotation while damping only motion that deforms the
		# remembered shape. Damping all center-relative velocity would fight the
		# player's rotation input and make the piece feel sluggish.
		var group_angular_velocity := 0.0
		var group_moment := 0.0
		for stone in group_stones:
			var current: Vector2 = stone.global_position - current_center
			group_angular_velocity += current.cross(stone.linear_velocity - average_velocity)
			group_moment += current.length_squared()
		group_angular_velocity /= maxf(group_moment, 0.001)

		# Find the rotation that best aligns the remembered layout with the
		# current one. The piece may rotate freely while retaining its silhouette.
		var dot_sum := 0.0
		var cross_sum := 0.0
		for stone in group_stones:
			var reference: Vector2 = group["offsets"][stone.get_instance_id()] - reference_center
			var current: Vector2 = stone.global_position - current_center
			dot_sum += reference.dot(current)
			cross_sum += reference.cross(current)
		var fitted_rotation := atan2(cross_sum, dot_sum)
		var controlled: bool = group["id"] == active_group_id
		var target_rotation: float = group["target_rotation"] if controlled else fitted_rotation
		var target_angular_velocity: float = group["target_angular_velocity"] if controlled else group_angular_velocity
		var supported: bool = group_stones.any(func(stone): return stone.is_supported)
		var use_settled_gains: bool = not controlled or supported
		var stiffness: float = SETTLED_SHAPE_STIFFNESS if use_settled_gains else SHAPE_MEMORY_STIFFNESS
		var damping: float = SETTLED_SHAPE_DAMPING if use_settled_gains else SHAPE_MEMORY_DAMPING
		var maximum_force: float = SETTLED_SHAPE_MAX_FORCE if use_settled_gains else SHAPE_MEMORY_MAX_FORCE
		var has_external_contact: bool = group_stones.any(func(stone): return stone.has_external_contact)
		if controlled and not has_external_contact:
			maximum_force = FREE_ROTATION_MAX_FORCE

		var pending_forces: Array[Vector2] = []
		var force_sum := Vector2.ZERO
		for stone in group_stones:
			var reference: Vector2 = group["offsets"][stone.get_instance_id()] - reference_center
			var target_relative := reference.rotated(target_rotation)
			var target: Vector2 = current_center + target_relative
			var position_error: Vector2 = target - stone.global_position
			var rigid_rotation_velocity := Vector2(-target_relative.y, target_relative.x) * target_angular_velocity
			var deformation_velocity: Vector2 = stone.linear_velocity - average_velocity - rigid_rotation_velocity
			var restoring_force: Vector2 = position_error * stiffness - deformation_velocity * damping
			pending_forces.append(restoring_force)
			force_sum += restoring_force

		# Shape memory is an internal constraint, so its net force must be zero.
		# Per-stone clamping broke that invariant and could turn rotation into lift.
		var mean_force := force_sum / float(group_stones.size())
		var strongest_force := 0.0
		for index in range(pending_forces.size()):
			pending_forces[index] -= mean_force
			strongest_force = maxf(strongest_force, pending_forces[index].length())
		var common_scale := minf(1.0, maximum_force / maxf(strongest_force, 0.001))
		for index in range(group_stones.size()):
			group_stones[index].apply_central_force(pending_forces[index] * common_scale)


func _add_spring(a: Node, b: Node, rest_distance: float, adjacent: bool) -> void:
	var joint := DampedSpringJoint2D.new()
	# DampedSpringJoint2D builds its two physical anchors from the joint's
	# position, rotation and length. Place those anchors at the stone centers;
	# leaving the joint at (0, 0) makes the visible cord and physical spring
	# disagree, which lets a piece appear to fall apart on impact.
	joint.position = a.position
	joint.rotation = (b.position - a.position).angle() - PI * 0.5
	joint.length = rest_distance
	joint.rest_length = rest_distance
	joint.stiffness = EDGE_SPRING_STIFFNESS if adjacent else SUPPORT_SPRING_STIFFNESS
	joint.damping = EDGE_SPRING_DAMPING if adjacent else SUPPORT_SPRING_DAMPING
	add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)

	var line := Line2D.new()
	line.width = 7.0 if adjacent else 3.0
	line.default_color = a.tint_color.darkened(0.28) if adjacent else Color(a.tint_color, 0.38)
	line.z_index = -1
	line.antialiased = true
	add_child(line)
	links.append({"a": a, "b": b, "joint": joint, "line": line, "adjacent": adjacent})


func _process(_delta: float) -> void:
	for link in links:
		if is_instance_valid(link["a"]) and is_instance_valid(link["b"]) and is_instance_valid(link["line"]):
			link["line"].points = PackedVector2Array([link["a"].global_position, link["b"].global_position])


func _check_for_elimination() -> void:
	_prune_invalid_stones()
	var columns := _find_vertical_columns(0)
	if not columns.is_empty():
		_eliminate_columns(columns)


func _update_near_clear_highlights() -> void:
	var highlighted := {}
	for column in _find_vertical_columns(-1):
		for stone in column["stones"]:
			highlighted[stone.get_instance_id()] = true

	for stone in stones:
		stone.set_near_clear(highlighted.has(stone.get_instance_id()))


func _edge_pair_is_level(first_x: float, second_x: float) -> bool:
	return absf(first_x - second_x) <= PAIR_HEIGHT_TOLERANCE


func _find_vertical_columns(required_offset: int) -> Array[Dictionary]:
	var top_stones: Array[Node] = []
	var bottom_stones: Array[Node] = []
	for stone in stones:
		if stone.global_position.y - STONE_SIZE * 0.5 <= _clear_line_y(stone.global_position.x) + 8.0:
			top_stones.append(stone)
		if stone.global_position.y + STONE_SIZE * 0.5 >= _bowl_y(stone.global_position.x) - 8.0:
			bottom_stones.append(stone)

	var candidates: Array[Dictionary] = []
	for top in top_stones:
		for bottom in bottom_stones:
			if not _edge_pair_is_level(top.global_position.x, bottom.global_position.x):
				continue
			var from: Vector2 = top.global_position
			var to: Vector2 = bottom.global_position
			var band := _stones_near_segment(from, to)
			var required := _required_stones_between(from, to)
			var count_matches := (
				band.size() >= required if required_offset == 0
				else band.size() == required + required_offset
			)
			if count_matches:
				candidates.append({"stones": band, "from": from, "to": to})

	# A deformed stone can fall inside two nearby bands. Keep the fullest,
	# non-overlapping interpretation so one stone is never scored twice.
	candidates.sort_custom(func(a, b): return a["stones"].size() > b["stones"].size())
	var selected: Array[Dictionary] = []
	var claimed := {}
	for candidate in candidates:
		var overlaps: bool = candidate["stones"].any(
			func(stone): return claimed.has(stone.get_instance_id())
		)
		if overlaps:
			continue
		selected.append(candidate)
		for stone in candidate["stones"]:
			claimed[stone.get_instance_id()] = true
	return selected


func _stones_near_segment(from: Vector2, to: Vector2) -> Array[Node]:
	var result: Array[Node] = []
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < 1.0:
		return result
	for stone in stones:
		var amount := clampf((stone.global_position - from).dot(segment) / length_squared, 0.0, 1.0)
		var closest := from + segment * amount
		if stone.global_position.distance_to(closest) <= CLEAR_BAND_HALF_WIDTH:
			result.append(stone)
	return result


func _required_stones_between(from: Vector2, to: Vector2) -> int:
	# Distance between centers counts intervals, not stones. Add both endpoint
	# occupancy correctly: a 10-stone-wide field has 9 center intervals but
	# requires 10 stones to clear.
	return maxi(5, ceili(from.distance_to(to) / STONE_SIZE) + 1)


func _eliminate_columns(columns: Array[Dictionary]) -> void:
	var targets: Array[Node] = []
	for column in columns:
		flash_lines.append({"from": column["from"], "to": column["to"], "life": 0.42})
		for stone in column["stones"]:
			if not targets.has(stone):
				targets.append(stone)

	combo_count += columns.size()
	combo_time_remaining = COMBO_WINDOW
	last_height_multiplier = maxi(combo_count, 1)
	cleared += targets.size()
	score += targets.size() * 100 * last_height_multiplier
	_show_multiplier_effect(last_height_multiplier, _center_of(targets))
	for stone in targets:
		_remove_stone_and_links(stone)
	_update_ui()
	elimination_cooldown = 0.55


func _show_multiplier_effect(multiplier: int, center: Vector2) -> void:
	var label := Label.new()
	label.name = "ScoreMultiplier"
	label.text = "x%d" % multiplier
	label.position = center - Vector2(70, 30)
	label.size = Vector2(140, 60)
	label.pivot_offset = label.size * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 140
	label.scale = Vector2(0.65, 0.65)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color("ffe08a"))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.06, 0.96))
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.32)
	tween.tween_property(label, "position:y", label.position.y - 52.0, 0.85)
	tween.tween_property(label, "modulate:a", 0.0, 0.38).set_delay(0.47)
	tween.tween_callback(label.queue_free).set_delay(0.9)


func _update_combo(delta: float) -> void:
	if combo_time_remaining <= 0.0:
		combo_label.visible = false
		return
	combo_time_remaining = maxf(combo_time_remaining - delta, 0.0)
	combo_label.text = "CHAIN x%d  %.1f" % [maxi(combo_count, 1), combo_time_remaining]
	combo_label.visible = true
	if combo_time_remaining <= 0.0:
		combo_count = 0
		last_height_multiplier = 1
		_update_ui()


func _remove_stone_and_links(stone: Node) -> void:
	for index in range(links.size() - 1, -1, -1):
		var link := links[index]
		if link["a"] == stone or link["b"] == stone:
			if is_instance_valid(link["joint"]):
				link["joint"].queue_free()
			if is_instance_valid(link["line"]):
				link["line"].queue_free()
			links.remove_at(index)
	stones.erase(stone)
	active_stones.erase(stone)
	stone.queue_free()


func _prune_invalid_stones() -> void:
	stones = stones.filter(func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion())
	active_stones = active_stones.filter(func(stone): return is_instance_valid(stone) and not stone.is_queued_for_deletion())


func _stones_exceed_deadline() -> bool:
	return _left_deadline_exceeded() or _right_deadline_exceeded()


func _left_deadline_exceeded() -> bool:
	return stones.any(func(stone):
		return (is_instance_valid(stone) and stone is TintStone
			and stone.global_position.x - STONE_SIZE * 0.5 <= LEFT_DEADLINE_X)
	)


func _right_deadline_exceeded() -> bool:
	return stones.any(func(stone):
		return (is_instance_valid(stone) and stone is TintStone
			and stone.global_position.x + STONE_SIZE * 0.5 >= RIGHT_DEADLINE_X)
	)


func _update_game_over_state(delta: float) -> void:
	var left_exceeded := _left_deadline_exceeded()
	var right_exceeded := _right_deadline_exceeded()
	if not left_exceeded and not right_exceeded:
		game_over_exposure = 0.0
		left_limit_label.text = "DEADLINE"
		limit_label.text = "DEADLINE"
		return
	game_over_exposure = minf(game_over_exposure + delta, GAME_OVER_GRACE_PERIOD)
	var remaining := maxf(GAME_OVER_GRACE_PERIOD - game_over_exposure, 0.0)
	left_limit_label.text = "DEADLINE  %.1f" % remaining if left_exceeded else "DEADLINE"
	limit_label.text = "DEADLINE  %.1f" % remaining if right_exceeded else "DEADLINE"
	if game_over_exposure >= GAME_OVER_GRACE_PERIOD:
		_game_over()


func _game_over() -> void:
	is_game_over = true
	status_label.text = "DEADLINE CROSSED\nPress R or tap to restart"
	status_label.visible = true
	help_label.text = "R  RESTART"


func _center_of(nodes: Array[Node]) -> Vector2:
	var center := Vector2.ZERO
	var count := 0
	for node in nodes:
		if is_instance_valid(node):
			center += node.global_position
			count += 1
	return center / maxf(float(count), 1.0)


func _bowl_y(x: float) -> float:
	var half_width := (FIELD_RIGHT - FIELD_LEFT) * 0.5
	var normalized := clampf((x - FIELD_CENTER_X) / half_width, -1.0, 1.0)
	return BOWL_EDGE_Y + BOWL_DEPTH * (1.0 - normalized * normalized)


func _clear_line_y(x: float) -> float:
	return _bowl_y(x) - CLEAR_COLUMN_HEIGHT


func _update_ui() -> void:
	score_label.text = "%06d  ·  chain x%d  ·  %d stones" % [score, last_height_multiplier, cleared]


func _draw() -> void:
	var field_polygon := PackedVector2Array([
		Vector2(FIELD_LEFT, FIELD_TOP),
		Vector2(FIELD_RIGHT, FIELD_TOP),
	])
	for index in range(24, -1, -1):
		var x := lerpf(FIELD_LEFT, FIELD_RIGHT, float(index) / 24.0)
		field_polygon.append(Vector2(x, _bowl_y(x)))
	draw_colored_polygon(field_polygon, Color("101a2c"))

	for row in range(1, ceili(FIELD_HEIGHT / STONE_SIZE)):
		var y := FIELD_TOP + STONE_SIZE * row
		if y < BOWL_EDGE_Y:
			draw_dashed_line(Vector2(FIELD_LEFT + 8, y), Vector2(FIELD_RIGHT - 8, y), Color(0.35, 0.44, 0.65, 0.10), 1.0, 8.0)
	for column in range(1, FIELD_COLUMNS):
		var x := FIELD_LEFT + STONE_SIZE * column
		draw_dashed_line(Vector2(x, FIELD_TOP + 8), Vector2(x, _bowl_y(x) - 8), Color(0.35, 0.44, 0.65, 0.07), 1.0, 8.0)

	var clear_points := PackedVector2Array()
	var bowl_points := PackedVector2Array()
	for index in range(25):
		var x := lerpf(FIELD_LEFT, FIELD_RIGHT, float(index) / 24.0)
		clear_points.append(Vector2(x, _clear_line_y(x)))
		bowl_points.append(Vector2(x, _bowl_y(x)))
	draw_polyline(clear_points, Color(0.35, 0.85, 0.75, 0.30), 2.0, true)

	# The warning strips and checks share the exact same coordinates.
	_draw_deadline(LEFT_DEADLINE_X, _left_deadline_exceeded(), true)
	_draw_deadline(RIGHT_DEADLINE_X, _right_deadline_exceeded(), false)

	draw_line(Vector2(FIELD_LEFT, FIELD_TOP), Vector2(FIELD_LEFT, BOWL_EDGE_Y), Color("52658e"), 6.0, true)
	draw_line(Vector2(FIELD_RIGHT, FIELD_TOP), Vector2(FIELD_RIGHT, BOWL_EDGE_Y), Color("52658e"), 6.0, true)
	draw_polyline(bowl_points, Color("52658e"), 7.0, true)
	draw_rect(Rect2(FIELD_LEFT, FIELD_TOP - 3, FIELD_RIGHT - FIELD_LEFT, 13), Color(0.35, 0.85, 0.75, 0.07))

	for flash in flash_lines:
		var alpha: float = clampf(flash["life"] / 0.42, 0.0, 1.0)
		draw_line(flash["from"], flash["to"], Color(1.0, 0.95, 0.65, alpha), 18.0 * alpha, true)


func _deadline_glow_alpha(exceeded: bool) -> float:
	if not exceeded:
		return 0.0
	var pulse := 0.5 + sin(game_over_exposure * 8.0) * 0.5
	return 0.10 + pulse * 0.16


func _draw_deadline(line_x: float, exceeded: bool, is_left: bool) -> void:
	var bottom_y := _bowl_y(line_x)
	var glow_alpha := _deadline_glow_alpha(exceeded)
	if glow_alpha > 0.0:
		var zone_left := FIELD_LEFT if is_left else line_x
		var zone_right := line_x if is_left else FIELD_RIGHT
		var glow_polygon := PackedVector2Array([
			Vector2(zone_left, FIELD_TOP),
			Vector2(zone_right, FIELD_TOP),
		])
		for index in range(12, -1, -1):
			var x := lerpf(zone_left, zone_right, float(index) / 12.0)
			glow_polygon.append(Vector2(x, _bowl_y(x)))
		draw_colored_polygon(glow_polygon, Color(1.0, 0.10, 0.16, glow_alpha))
	draw_rect(
		Rect2(line_x - 5.0, FIELD_TOP, 10.0, bottom_y - FIELD_TOP),
		Color(1.0, 0.36, 0.45, 0.07 + glow_alpha * 0.32)
	)
	draw_dashed_line(
		Vector2(line_x, FIELD_TOP),
		Vector2(line_x, bottom_y),
		Color(1.0, 0.48, 0.55, 0.52 + glow_alpha),
		2.0,
		10.0
	)
