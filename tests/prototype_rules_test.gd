extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var centered_ok: bool = is_equal_approx(game.FIELD_LEFT, 1280.0 - game.FIELD_RIGHT)
	var field_height_ok: bool = is_equal_approx(
		game.FIELD_HEIGHT, game.REFERENCE_CLEAR_COLUMN_HEIGHT * 1.5
	)
	var clear_height_ok: bool = is_equal_approx(
		game.CLEAR_COLUMN_HEIGHT, game.REFERENCE_CLEAR_COLUMN_HEIGHT * 0.8
	)
	var bowl_ok: bool = is_equal_approx(
		game._bowl_y(game.FIELD_CENTER_X) - game._bowl_y(game.FIELD_LEFT),
		game.BOWL_DEPTH
	)
	var tolerance_ok: bool = (
		game._edge_pair_is_level(300.0, 300.0 + game.STONE_SIZE * 0.55 - 0.1)
		and not game._edge_pair_is_level(300.0, 300.0 + game.STONE_SIZE * 0.55 + 0.1)
		and is_equal_approx(game.CLEAR_BAND_HALF_WIDTH, game.STONE_SIZE * 0.55)
	)
	var gravity_ok: bool = is_equal_approx(
		float(ProjectSettings.get_setting("physics/2d/default_gravity")), 152.0
	)
	game._spawn_piece("T")
	var spawn_ok: bool = (
		is_equal_approx(game._center_of(game.active_stones).x, game.FIELD_CENTER_X)
		and game.active_stones.all(func(stone): return (
			stone.global_position.y + game.STONE_SIZE * 0.5 <= game.FIELD_TOP
		))
	)
	for stone in game.active_stones:
		stone.linear_velocity = Vector2(70.0, 80.0)
	game._apply_translation_control(1.0, 0.0, 0.0)
	var move_held_ok: bool = is_equal_approx(
		game._average_active_velocity().x, game.HORIZONTAL_MOVE_SPEED
	)
	game._apply_translation_control(0.0, 0.0, 0.0)
	var move_release_ok: bool = is_zero_approx(game._average_active_velocity().x)
	game._apply_translation_control(0.0, 1.0, 0.0)
	var drop_held_ok: bool = is_equal_approx(
		game._average_active_velocity().y, 80.0 + game.SOFT_DROP_EXTRA_SPEED
	)
	game._apply_translation_control(0.0, 0.0, 0.0)
	var drop_release_ok: bool = is_equal_approx(game._average_active_velocity().y, 80.0)
	for stone in game.active_stones:
		stone.is_supported = true
		stone.linear_velocity.y = 0.0
	for _iteration in range(120):
		game._apply_translation_control(0.0, 1.0, 1.0 / 60.0)
	var supported_drop_ok: bool = (
		is_zero_approx(game._average_active_velocity().y)
		and is_zero_approx(game.soft_drop_natural_velocity)
	)
	for stone in game.active_stones:
		stone.linear_velocity.y = -180.0
	game._apply_translation_control(0.0, 1.0, 1.0 / 60.0)
	var supported_bounce_ok: bool = is_equal_approx(game._average_active_velocity().y, -180.0)
	game._apply_translation_control(0.0, 0.0, 1.0 / 60.0)
	var released_bounce_ok: bool = is_equal_approx(game._average_active_velocity().y, -180.0)
	var direct_control_ok: bool = (
		move_held_ok and move_release_ok and drop_held_ok and drop_release_ok
		and supported_drop_ok and supported_bounce_ok and released_bounce_ok
	)
	for stone in game.active_stones.duplicate():
		game._remove_stone_and_links(stone)
	game.shape_groups.clear()

	_add_column(game, 250.0, 100)
	_add_column(game, 250.0 + game.STONE_SIZE * 1.25, 200)
	var columns: Array[Dictionary] = game._find_vertical_columns(0)
	var columns_ok: bool = columns.size() == 2
	game._check_for_elimination()
	var clear_stone_count: int = ceili(game.CLEAR_COLUMN_HEIGHT / game.STONE_SIZE)
	var score_ok: bool = (
		game.score == clear_stone_count * 2 * 100 * 2
		and game.cleared == clear_stone_count * 2
		and game.combo_count == 2
		and is_equal_approx(game.combo_time_remaining, game.COMBO_WINDOW)
	)
	game._update_combo(game.COMBO_WINDOW + 0.1)
	var combo_expiry_ok: bool = game.combo_count == 0 and game.last_height_multiplier == 1

	var deadline_stone: TintStone = game.StoneScene.new()
	deadline_stone.setup(Color.WHITE, 999)
	deadline_stone.gravity_scale = 0.0
	deadline_stone.position = Vector2(
		game.RIGHT_DEADLINE_X - game.STONE_SIZE * 0.5,
		game.FIELD_BOTTOM - game.STONE_SIZE * 0.5
	)
	game.add_child(deadline_stone)
	game.stones.append(deadline_stone)
	var right_boundary_ok: bool = game._right_deadline_exceeded() and game._stones_exceed_deadline()
	deadline_stone.position.x = game.LEFT_DEADLINE_X + game.STONE_SIZE * 0.5
	var left_boundary_ok: bool = game._left_deadline_exceeded() and game._stones_exceed_deadline()
	game._update_game_over_state(2.0)
	var deadline_glow_ok: bool = (
		game._deadline_glow_alpha(true) > 0.0
		and is_zero_approx(game._deadline_glow_alpha(false))
	)
	deadline_stone.position.x = game.FIELD_CENTER_X
	game._update_game_over_state(0.1)
	var grace_reset_ok: bool = not game.is_game_over and game.game_over_exposure == 0.0
	deadline_stone.position.x = game.RIGHT_DEADLINE_X - game.STONE_SIZE * 0.5
	game._update_game_over_state(game.GAME_OVER_GRACE_PERIOD - 0.1)
	var grace_safe_ok: bool = not game.is_game_over
	game._update_game_over_state(0.2)
	var game_over_ok: bool = game.is_game_over

	if centered_ok and field_height_ok and clear_height_ok and bowl_ok and tolerance_ok and gravity_ok and spawn_ok and direct_control_ok and columns_ok and score_ok and combo_expiry_ok and left_boundary_ok and right_boundary_ok and deadline_glow_ok and grace_reset_ok and grace_safe_ok and game_over_ok:
		print("PASS: direct movement, soft-drop release, deadline glow, clears, and grace work")
		quit(0)
	else:
		push_error(
			"FAIL: centered=%s height=%s clear_height=%s bowl=%s tolerance=%s gravity=%s spawn=%s direct_control=%s columns=%s score=%s combo=%s left=%s right=%s glow=%s reset=%s safe=%s game_over=%s"
			% [centered_ok, field_height_ok, clear_height_ok, bowl_ok, tolerance_ok, gravity_ok, spawn_ok, direct_control_ok, columns_ok, score_ok, combo_expiry_ok, left_boundary_ok, right_boundary_ok, deadline_glow_ok, grace_reset_ok, grace_safe_ok, game_over_ok]
		)
		quit(1)


func _add_column(game: Node, x: float, first_group_id: int) -> void:
	var clear_top: float = game._clear_line_y(x)
	var floor_y: float = game._bowl_y(x)
	var stone_count: int = ceili(game.CLEAR_COLUMN_HEIGHT / game.STONE_SIZE)
	for row in range(stone_count):
		var stone: TintStone = game.StoneScene.new()
		stone.setup(Color("55d6be"), first_group_id + row)
		stone.gravity_scale = 0.0
		stone.position = Vector2(x, lerpf(
			clear_top + game.STONE_SIZE * 0.5,
			floor_y - game.STONE_SIZE * 0.5,
			float(row) / float(stone_count - 1)
		))
		game.add_child(stone)
		game.stones.append(stone)
