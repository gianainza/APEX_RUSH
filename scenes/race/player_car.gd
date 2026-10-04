extends CharacterBody2D

@export var player_id: int = 1

# --- Retro Animation Settings ---
@export var anim_fps: float = 8.0           # Lower = more choppy/animated (try 8.0, 10.0, or 12.0)
@export var snap_angles: int = 14          # Number of rotation steps (0 = smooth rotation, 16 or 24 = classic arcade)

# --- Speed Settings ---
@export var base_speed: float = 180.0       # Slower, controllable cruise speed
@export var boost_speed: float = 300.0      # Burst speed during Shift
@export var boost_duration: float = 1.0     # Seconds boost lasts per press
@export var acceleration: float = 350.0
@export var steering_speed: float = 3.5
@export var friction: float = 0.98
@export var traction_drift: float = 0.05
@export var drift_threshold: float = 0.06

@onready var drift_sfx: AudioStreamPlayer2D = get_node_or_null("DriftSFX")
@onready var crash_sfx: AudioStreamPlayer2D = $CrashSFX

const SKID_MARK_SCENE = preload("res://scenes/effects/skid_mark.tscn")
const SPARK_SCENE = preload("res://scenes/effects/impact_spark.tscn")

var current_speed: float = 0.0
var was_stopped: bool = true
var last_stamp_pos: Vector2 = Vector2.ZERO
var stamp_distance: float = 12.0
var spark_cooldown: float = 0.0

# Boost state
var boost_timer: float = 0.0
var is_boosting: bool = false

# Retro animation state
var anim_timer: float = 0.0
var stepped_pos: Vector2 = Vector2.ZERO
var stepped_rot: float = 0.0

# Controls
var action_up: String = "p1_up"
var action_down: String = "p1_down"
var action_left: String = "p1_left"
var action_right: String = "p1_right"
var action_boost: String = "p1_boost"

# --- Shield System ---
@onready var shield_effect: AnimatedSprite2D = get_node_or_null("ShieldEffect")

var is_shielded: bool = false
var shield_timer: float = 0.0

# --- Super Nitro Variables ---
@onready var boost_effect: AnimatedSprite2D = get_node_or_null("BoostEffect")
var boost_multiplier: float = 1.0

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var exhaust_smoke: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var left_tire: Marker2D = get_node_or_null("LeftTire")
@onready var right_tire: Marker2D = get_node_or_null("RightTire")

var is_slowed: bool = false

func _ready() -> void:
	# If a car was chosen in the car select menu, update player sprite
	if typeof(GameManager) != TYPE_NIL and GameManager.selected_car_texture != null and sprite:
		sprite.texture = GameManager.selected_car_texture
	
	if player_id == 2:
		action_up = "p2_up"
		action_down = "p2_down"
		action_left = "p2_left"
		action_right = "p2_right"
		action_boost = "p2_boost"

	# Make sure sprite renders ABOVE the track/road
	if sprite:
		sprite.top_level = false
		sprite.z_index = 5

func _process(_delta: float) -> void:
	if not sprite:
		return

	# 1. Calculate the snapped angle in world space
	# TAU is 360 degrees in radians (2 * PI)
	var step_size = TAU / float(snap_angles)
	var snapped_world_rot = round(global_rotation / step_size) * step_size

	# 2. Force the child sprite to display ONLY that snapped angle
	sprite.rotation = snapped_world_rot - global_rotation

func _physics_process(delta: float) -> void:
	# Block input and physics until "GO!" is triggered
	if typeof(GameManager) != TYPE_NIL and not GameManager.can_race:
		velocity = Vector2.ZERO
		current_speed = 0.0
		move_and_slide()
		return
		
	# --- 1. Boost Countdown & Target Speed ---
	if Input.is_action_just_pressed(action_boost) and boost_timer <= 0.0:
		boost_timer = boost_duration
		is_boosting = true
		play_exhaust_puff()

	if boost_timer > 0.0:
		boost_timer -= delta
		if boost_timer <= 0.0:
			is_boosting = false
			if boost_effect:
				boost_effect.stop()
				boost_effect.hide()

	var target_max_speed = (boost_speed if is_boosting else base_speed) * boost_multiplier

	# --- 2. Steering ---
	var steer_input = Input.get_axis(action_left, action_right)
	rotation += steer_input * steering_speed * delta * (current_speed / target_max_speed)

	# --- 3. Acceleration ---
	var forward_input = Input.get_axis(action_down, action_up)
	if forward_input > 0:
		if was_stopped and abs(current_speed) < 20.0:
			play_exhaust_puff()
			was_stopped = false
			
		var startup_power = clamp((abs(current_speed) / (target_max_speed * 0.5)), 0.3, 1.0)
		current_speed = move_toward(current_speed, target_max_speed, acceleration * startup_power * delta)
	elif forward_input < 0:
		current_speed = move_toward(current_speed, -target_max_speed * 0.4, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, acceleration * 0.6 * delta)
		if abs(current_speed) < 5.0:
			was_stopped = true

	# --- 4. Drift Physics & Slip Calculation ---
	var forward_velocity = transform.x * current_speed
	velocity = velocity.lerp(forward_velocity, traction_drift)
	velocity *= friction

	# Calculate lateral (sideways) slide relative to car heading
	var lateral_slip: float = 0.0
	if velocity.length() > 10.0:
		lateral_slip = abs(velocity.normalized().dot(transform.y))

# Play screech if the car is skidding OR if the player is holding/pressing Boost (Shift)
	var is_skidding: bool = (velocity.length() > 40.0 and (lateral_slip > drift_threshold or abs(steer_input) > 0.5))
	var should_screech: bool = is_skidding or is_boosting

	if is_skidding or is_boosting:
		check_and_spawn_skids()

	_update_drift_audio(should_screech)

	# --- 5. Movement & Collision Handling ---
	move_and_slide()
	handle_car_collisions()
	
	# Handle Shield Duration
	if is_shielded:
		shield_timer -= delta
		if shield_timer <= 0.0:
			deactivate_shield()

func activate_shield(duration: float = 6.0) -> void:
	is_shielded = true
	shield_timer = duration
	if shield_effect:
		shield_effect.show()
		shield_effect.play("default")
		shield_effect.scale = Vector2(0.2, 0.2)
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(shield_effect, "scale", Vector2.ONE, 0.25)
	print("Player Bumper Shield activated for ", duration, " seconds!")

func deactivate_shield() -> void:
	is_shielded = false
	if shield_effect:
		var tween = create_tween()
		tween.tween_property(shield_effect, "scale", Vector2.ZERO, 0.15)
		await tween.finished
		shield_effect.stop()
		shield_effect.hide()
	print("Player Bumper Shield expired.")

func activate_nitro_boost(duration: float = 2.5, speed_buff: float = 1.6) -> void:
	is_boosting = true
	boost_timer = duration
	boost_multiplier = speed_buff

	if boost_effect:
		boost_effect.show()
		boost_effect.play("default")
	print("Super Nitro activated! Zooming at ", speed_buff, "x speed!")

func end_nitro_boost() -> void:
	is_boosting = false
	boost_multiplier = 1.0
	if boost_effect:
		boost_effect.stop()
		boost_effect.hide()
	print("Super Nitro ended.")
	
func play_exhaust_puff() -> void:
	if exhaust_smoke:
		exhaust_smoke.visible = true
		exhaust_smoke.frame = 0
		exhaust_smoke.play("default")
		await exhaust_smoke.animation_finished
		exhaust_smoke.visible = false

func check_and_spawn_skids() -> void:
	if left_tire and right_tire:
		if global_position.distance_to(last_stamp_pos) >= stamp_distance:
			var rear_center = (left_tire.global_position + right_tire.global_position) * 0.5
			spawn_skid(rear_center)
			last_stamp_pos = global_position

func spawn_skid(pos: Vector2) -> void:
	var skid = SKID_MARK_SCENE.instantiate()
	skid.global_position = pos
	if velocity.length() > 5.0:
		skid.global_rotation = velocity.angle()
	else:
		skid.global_rotation = global_rotation
	skid.z_index = 1
	get_tree().current_scene.add_child(skid)

func handle_car_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider is CharacterBody2D and collider != self:
			var normal = collision.get_normal()
			current_speed *= 0.88
			velocity += normal * 20.0
			
			if "velocity" in collider:
				collider.velocity -= normal * 20.0
			if "current_speed" in collider:
				collider.current_speed *= 0.90

			var rival_vel = collider.velocity if "velocity" in collider else Vector2.ZERO
			var relative_speed = (velocity - rival_vel).length()

			var collider_cooldown = collider.spark_cooldown if "spark_cooldown" in collider else 0.0
			if spark_cooldown <= 0.0 and collider_cooldown <= 0.0:
				if relative_speed > 50.0:
					spawn_spark(collision.get_position())
					
					# --- Play the Crash SFX ---
					if crash_sfx:
						crash_sfx.pitch_scale = randf_range(0.9, 1.1)
						crash_sfx.play()

					spark_cooldown = 0.4
					if "spark_cooldown" in collider:
						collider.spark_cooldown = 0.4

func spawn_spark(pos: Vector2) -> void:
	var spark = SPARK_SCENE.instantiate()
	spark.global_position = pos
	get_tree().current_scene.add_child(spark)



func apply_oil_slowdown(duration: float = 3.0) -> void:
	if is_slowed or is_shielded:
		return
	
	is_slowed = true
	print("Player slipped on an oil trap!")
	
	# Visual cue: tint car dark/oily
	modulate = Color(0.4, 0.4, 0.4)
	
	var original_speed = base_speed
	base_speed = base_speed * 0.45
	
	await get_tree().create_timer(duration).timeout
	
	base_speed = original_speed
	modulate = Color.WHITE
	is_slowed = false
func _update_drift_audio(should_play: bool) -> void:
	if not drift_sfx:
		return

	if should_play:
		if not drift_sfx.playing:
			drift_sfx.play()
	else:
		if drift_sfx.playing:
			drift_sfx.stop()
