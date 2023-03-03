extends KinematicBody2D

onready var main := get_tree().get_current_scene()

export(bool) var	air_jump_has_ability := false
var 				air_jump_refresh_on_wall_latch := true
var					air_jump_speed := -800
var 				air_jump_used_ability := false

					# x, y corner correction
var					corner_correction := Vector2(8, 4)

var					dash_corner_correction := Vector2(12, 12)
var 				dash_can_only_used_when_on_solid := false
var					dash_direction := Vector2.ZERO
export(int) var		dash_directions := 8 # 2, 4, 8
var					dash_duration := .2
export(bool) var	dash_has_ability := true
var					dash_after_dash_has_reset_speed := true
var					dash_pause_time := .02
var					dash_refresh_time := .18
var 				dash_refresh_timer := dash_refresh_time
var 				dash_refresh_timer_update := true
var 				dash_refresh_timer_update_on_wall_latch := true
var 				dash_reset_speed_value := Vector2(400, 400)
var					dash_speed := 800
var 				dash_timer := .0

var 				facing_direction := 1.0 # -1 or 1

var					jump_buffer_time := .08
var 				jump_buffer_timer := .0

var					process_self := true

# ------------------------------------------------------------------------------

var 				max_hspeed := 400
var 				current_max_hspeed = 0
var 				acceleration := .3
# If hspeed is less than threshold and we're deaccelerating, set it to 0
var 				hspeed_reset_threshold := 1.0
var 				friction := .7

var 				max_vspeed := 1000
var					jump_speed := -800
var 				gravity := 2500
var 				peak_gravity := 1250
var 				peak_gravity_threshold = 200

var 				jump_cut := .2
var 				can_cut_speed := true
var 				jumping := false # Harder to do a method
var 				want_to_cut_speed := false

var 				coyote_time := .08 # .1
var 				coyote_timer := coyote_time

export(bool) var	has_wall_jump := true
var 				has_wall_latch := has_wall_jump
var 				wall_slide_latched := 0 # -1, 0, 1
var 				wall_slide_gravity := 1000
var 				wall_slide_max_vspeed := 150
var 				wall_slide_latch_on_pause := .1 # Don't process gravity
var 				wall_slide_latch_on_timer := 0.0
var					wall_jump_vertical_speed := -600
var					wall_jump_horizontal_speed := 500
var					wall_jump_lose_control_time := .2
var 				wall_jump_lose_control_timer := 0.0

# How do we want the player to act when close to an edge?
var wall_jump_edge_horizontal_speed := 500
var wall_jump_edge_lose_control_time := .10
onready var wall_jump_raycast1 = $"Close To Edge Raycast1"
onready var wall_jump_raycast2 = $"Close To Edge Raycast2"
onready var wall_jump_raycast_cast_to = Vector2(19, 0)

var velocity := Vector2.ZERO
var input_direction := Vector2.ZERO
# Points in direction of last solid touched
var last_solid := Vector2(0, 0)

signal player_jumped(last_solid, global_pos)
signal player_hit(global_pos)

var start_position := Vector2.ZERO

func _ready():
	start_position = global_position

func _process(_delta):
	if process_self:
		update()

func _physics_process(delta):
	if process_self:
		update_timers(delta)
		
		if velocity.y >= 0:
			jumping = false
		
		if not jumping:
			want_to_cut_speed = false
		
		if can_move() and (on_floor() or
		(wall_slide_latched != 0 and dash_refresh_timer_update_on_wall_latch)):
			dash_refresh_timer_update = true
		if can_move() and (on_floor() or
		(wall_slide_latched != 0 and air_jump_refresh_on_wall_latch)):
			air_jump_used_ability = false
		
		# Mainly update solids & coyote timer
		if on_floor():
			coyote_timer = coyote_time
			last_solid = Vector2.DOWN
		# If we're latched to a wall, update coyote time and last_solid
		if wall_slide_latched != 0 and not on_floor():
			coyote_timer = coyote_time
			last_solid = Vector2(wall_slide_latched, 0)
		# If we're not latched to a wall, not standing on ground, and we're hitting our head
		if wall_slide_latched == 0 and not on_floor() and not place_free(Vector2.UP):
			last_solid = Vector2.UP
		
		update_input_direction()
		
		update_facing_direction()
		dash(delta) # bf jump
		jump(delta) # after dash
		
		update_velocity(delta) # bf wall_latching
		wall_latching() # must be before process_movement and after update_velocity
		perform_movement(delta) #after wall_latching

func _draw():
	draw_line(Vector2(0, 0), last_solid*24, Color.yellow, 4)
	if against_wall() != 0 and wall_slide_latched == 0:
		draw_line(Vector2.ZERO, Vector2(20*against_wall(), 0), Color.red, 12)
	if wall_slide_latched != 0:
		draw_line(Vector2.ZERO, Vector2(20*wall_slide_latched, 0), Color.green, 12)

func against_wall():
	# Returns -1, 0, 1 if against wall left, none, right
	if test_move(transform, Vector2(-1, 0)):
		return -1
	if test_move(transform, Vector2(1, 0)):
		return 1
	return 0
	
func can_dash():
	if not dash_can_only_used_when_on_solid:
		return dash_refresh_timer <= 0
	if dash_can_only_used_when_on_solid:
		if coyote_timer > 0:
			return (dash_refresh_timer <= 0 )
		else:
			return false
	
func can_move():
	return not (wall_jump_lose_control_timer > 0 or is_dashing())
	
func check_corner_correction(movement_vector: Vector2):
	# Here we assume that there was a collission before
	assert (movement_vector.length() == 1 and movement_vector.x*movement_vector.y == 0, "ERROR: Must be a UP, DOWN, LEFT or RIGHT vector")
	var ccc = current_corner_correction()
	var mv = movement_vector
	if mv.y == -1 or (mv.y == 1 and is_dashing()):
		for i in range(ccc.x, 0, -1):
			if place_free(Vector2(i, mv.y)):
				return Vector2.RIGHT
		for i in range(ccc.x, 0, -1):
			if place_free(Vector2(-i, mv.y)):
				return Vector2.LEFT
	if abs(mv.x) == 1:
		for i in range(ccc.y, 0, -1):
			if place_free(Vector2(mv.x, -i)):
				return Vector2.UP
		if is_dashing(): # We only wanna go down if were dashing
			for i in range(ccc.y, 0, -1):
				if place_free(Vector2(mv.x, i)):
					return Vector2.DOWN
	return Vector2.ZERO
	
func collect_air_jump_refresh():
	pass
	
func collect_dash_refresh():
	dash_refresh_timer = 0
	# dash_refresh_timer_update = true

func current_corner_correction() -> Vector2:
	if is_dashing():
		return dash_corner_correction
	return corner_correction

func current_gravity():
	# Half gravity on jump peak
	if jumping == true and Input.is_action_pressed("ui_accept") and last_solid == Vector2.DOWN and velocity.y < 0 and abs(velocity.y) < peak_gravity_threshold:
		return peak_gravity
	else:
		return gravity
		
func current_max_vspeed():
	if wall_slide_latched:
		return wall_slide_max_vspeed
	if is_dashing():
		return dash_speed
	return max_vspeed
	
func dash(_delta):
	assert(dash_directions == 2 or dash_directions == 4 or dash_directions == 8, "ERROR: Variable dash_directions must be 2, 4 or 8")
	if Input.is_action_just_pressed("ui_dash"):
		if can_move() and dash_has_ability and can_dash():
			dash_direction = Vector2.ZERO
			if dash_directions == 8:
				dash_direction = input_direction.normalized()
			if dash_directions == 4:
				if input_direction.x == 0:
					dash_direction.y = input_direction.y
				elif input_direction.x != 0:
					dash_direction.x = input_direction.x
			if dash_directions == 2:
				dash_direction.x = input_direction.x
			if dash_direction == Vector2.ZERO:
				dash_direction.x = facing_direction
			dash_refresh_timer = dash_refresh_time
			dash_timer = dash_pause_time + dash_duration
			dash_after_dash_has_reset_speed = false
			dash_refresh_timer_update = false
			wall_slide_latched = 0
	if dash_after_dash_has_reset_speed == false and not is_dashing():
		velocity.y = clamp(velocity.y, -dash_reset_speed_value.y, dash_reset_speed_value.y)
		velocity.x = clamp(velocity.x, -dash_reset_speed_value.x, dash_reset_speed_value.x)
		dash_after_dash_has_reset_speed = true
		
func hit():
	if process_self:
		emit_signal("player_hit", global_position)
	else:
		print("hit, but not processing self")

func is_dashing():
	return dash_timer > 0

func jump(_delta):
	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = jump_buffer_time
	if coyote_timer > 0 and not is_dashing():
		if jump_buffer_timer > 0:
			if last_solid == Vector2.DOWN:
				velocity.y = jump_speed
				coyote_timer = 0
				jump_buffer_timer = 0
				jumping = true
			# Wall jumping
			if (last_solid == Vector2.LEFT or last_solid == Vector2.RIGHT) and has_wall_jump:
				velocity.y = wall_jump_vertical_speed
				wall_jump_raycast1.force_raycast_update()
				wall_jump_raycast2.force_raycast_update()
				if (!wall_jump_raycast1.is_colliding() or !wall_jump_raycast2.is_colliding()) and input_direction.x == last_solid.x:
					velocity.x = wall_jump_edge_horizontal_speed * -last_solid.x
					wall_jump_lose_control_timer = wall_jump_edge_lose_control_time
				else:
					velocity.x = wall_jump_horizontal_speed * -last_solid.x
					wall_jump_lose_control_timer = wall_jump_lose_control_time
				wall_slide_latched = 0
				coyote_timer = 0
				jump_buffer_timer = 0
				jumping = true
			emit_signal("player_jumped", last_solid, global_position)

	# Air jump
	elif coyote_timer <= 0 and jump_buffer_timer > 0 and not is_dashing():#Input.is_action_just_pressed("ui_accept"):
		if air_jump_has_ability and not air_jump_used_ability:
			velocity.y = air_jump_speed
			coyote_timer = 0
			jump_buffer_timer = 0
			jumping = true
			air_jump_used_ability = true
				
	if Input.is_action_just_released("ui_accept") and jumping:#(jump_buffer_timer > 0 or jumping):
		want_to_cut_speed = true
	if want_to_cut_speed and can_move():
		if velocity.y < 0 and can_cut_speed:
			velocity.y *= jump_cut
			want_to_cut_speed = false

func on_floor():
	return test_move(transform, Vector2.DOWN)

func place_free(relative_position: Vector2):
	assert(abs(relative_position.x) <= 1 or abs(relative_position.y) <= 1, "ERROR: One of the values must fulfil |n| <= 1")
	return not test_move(transform, relative_position)

func process_gravity():
	if wall_slide_latch_on_timer > 0 or is_dashing() == true:
		return false
	else:
		return true
		
func process_horizontal_movement():
	# If we're dash pausing
	if dash_timer > dash_duration and dash_timer <= dash_pause_time + dash_duration:
		return false
	return true
		
func process_vertical_movement():
	# Don't process physics if we just latched onto a wall
	if wall_slide_latch_on_timer > 0:
		return false
#	elif false:
#		process_vertical_movement = false
	else:
		return true

func perform_movement(delta):
	var step = Vector2(sign(velocity.x), sign(velocity.y))
	if process_vertical_movement():
		for _i in range(int(abs(velocity.y * delta))):
			if not place_free(Vector2(0, step.y)):
				var d = check_corner_correction(Vector2(0, step.y))
				if d.x != 0:
					while not place_free(Vector2(0, step.y)):
						position.x += d.x
			if place_free(Vector2(0, step.y)):
				position.y += step.y
			else:
				velocity.y = 0
	if process_horizontal_movement():
		for _i in range(int(abs(velocity.x * delta))):
			if not place_free(Vector2(step.x, 0)):
				var d = check_corner_correction(Vector2(step.x, 0))
				if d.y != 0:
					while not place_free(Vector2(step.x, 0)):
						position.y += d.y
			if place_free(Vector2(step.x, 0)):
				position.x += step.x
				
func update_facing_direction():
	var dir = sign(velocity.x)
	if velocity.x != 0:
		facing_direction = sign(velocity.x)
		wall_jump_raycast1.cast_to = wall_jump_raycast_cast_to * dir
		wall_jump_raycast2.cast_to = wall_jump_raycast_cast_to * dir

func update_timers(delta):
	wall_slide_latch_on_timer -= delta
	coyote_timer -= delta
	wall_jump_lose_control_timer -= delta
	jump_buffer_timer -= delta
	if dash_refresh_timer_update:
		dash_refresh_timer -= delta
	dash_timer -= delta
	
func update_input_direction():
	input_direction.x = (int(Input.is_action_pressed("ui_right"))-int(Input.is_action_pressed("ui_left")))
	input_direction.y = (int(Input.is_action_pressed("ui_down"))-int(Input.is_action_pressed("ui_up")))
	
func update_velocity(delta):
	if can_move() and input_direction.x != 0:
		velocity.x = lerp(velocity.x, input_direction.x * max_hspeed, acceleration)
		#velocity.x =  input_direction.x * max_hspeed
	elif can_move() and input_direction.x == 0:
		velocity.x = lerp(velocity.x, 0, friction)
		if abs(velocity.x) < hspeed_reset_threshold:
			velocity.x = 0
	elif dash_timer >= 0 and dash_timer <= dash_duration:
		velocity = dash_direction * dash_speed
	if process_gravity():
		velocity.y += current_gravity() * delta
	#if abs(velocity.y) > current_max_vspeed():
	velocity.y = clamp(velocity.y, -current_max_vspeed(), current_max_vspeed())
	
func wall_latching():
	if has_wall_latch and can_move():
		# If not on floor, against a wall, "walking toward" the wall I'm against
		if not on_floor() and (against_wall() != 0) and (against_wall() == sign(velocity.x)):
			if wall_slide_latched == 0 and velocity.y > 0:
				wall_slide_latched = against_wall()
				wall_slide_latch_on_timer = wall_slide_latch_on_pause
		if wall_slide_latched != 0 and (wall_slide_latched != against_wall()):
			wall_slide_latched = 0
			wall_slide_latch_on_timer = 0
		if on_floor():
			wall_slide_latched = 0
			wall_slide_latch_on_timer = 0
			
