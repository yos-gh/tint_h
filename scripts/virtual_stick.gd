class_name TintVirtualStick
extends Node2D

const BASE_RADIUS := 56.0
const HANDLE_RADIUS := 23.0
const HANDLE_RANGE := 38.0
const ACTIVATION_RADIUS := 72.0
const DEADZONE := 0.16

var value := Vector2.ZERO
var touch_index := -1
var handle_position := Vector2.ZERO


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	set_process_input(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var local_position := to_local(event.position)
		if event.pressed and touch_index == -1 and local_position.length() <= ACTIVATION_RADIUS:
			touch_index = event.index
			_set_from_local_position(local_position)
		elif not event.pressed and event.index == touch_index:
			_release_stick()
	elif event is InputEventScreenDrag and event.index == touch_index:
		_set_from_local_position(to_local(event.position))


func _set_from_local_position(local_position: Vector2) -> void:
	handle_position = local_position.limit_length(HANDLE_RANGE)
	var raw := handle_position / HANDLE_RANGE
	var magnitude := raw.length()
	if magnitude <= DEADZONE:
		value = Vector2.ZERO
	else:
		value = raw.normalized() * ((magnitude - DEADZONE) / (1.0 - DEADZONE))
	queue_redraw()


func set_vector_for_test(new_value: Vector2) -> void:
	value = new_value.limit_length(1.0)
	handle_position = value * HANDLE_RANGE
	queue_redraw()


func _release_stick() -> void:
	touch_index = -1
	value = Vector2.ZERO
	handle_position = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var tint := Color("55d6be")
	draw_circle(Vector2.ZERO, BASE_RADIUS, Color(tint, 0.13))
	draw_arc(Vector2.ZERO, BASE_RADIUS, 0.0, TAU, 48, Color(tint, 0.58), 3.0, true)
	draw_line(Vector2(-29, 0), Vector2(29, 0), Color(tint, 0.20), 2.0, true)
	draw_line(Vector2(0, -29), Vector2(0, 29), Color(tint, 0.20), 2.0, true)
	draw_circle(handle_position, HANDLE_RADIUS, Color(tint, 0.46))
	draw_arc(handle_position, HANDLE_RADIUS, 0.0, TAU, 32, Color(tint, 0.92), 3.0, true)
