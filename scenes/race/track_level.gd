extends Node2D

# --- HUD Nodes ---
@onready var countdown_label: Label = $HUD/CountdownLabel
@onready var powerup_slot: TextureRect = $HUD/PowerupSlot
@onready var lap_value: Label = $HUD/HBoxContainer/LapCard/LabelValue
@onready var place_value: Label = $HUD/HBoxContainer/PlaceCard/PlaceValue
@onready var player_marker: Control = $HUD/HBoxContainer/ProgressCard/PlayerMarker
@onready var rival_marker: Control = $HUD/HBoxContainer/ProgressCard/RivalMarker
@onready var pause_button: BaseButton = $HUD/PauseButton
@onready var pause_menu: Control = $HUD/PauseMenu
@onready var resume_button: BaseButton = $HUD/PauseMenu/MenuPanel/ResumeButton
@onready var restart_button: BaseButton = $HUD/PauseMenu/MenuPanel/RestartButton
@onready var car_select_button: BaseButton = $HUD/PauseMenu/MenuPanel/CarSelectionButton
@onready var countdown_sfx: AudioStreamPlayer = $CountdownSFX
# --- Track Triggers ---
@onready var finish_line: Area2D = $FinishLine
@onready var mid_checkpoint: Area2D = $MidCheckpoint

# Scenes
const OIL_SLICK_SCENE = preload("res://scenes/pickups/oil_slick.tscn")
const OIL_PICKUP_SCENE = preload("res://scenes/pickups/oil_pickup.tscn")
const OIL_ICON = preload("res://assets/sprites/powerups/oil_icon.png")
const SHIELD_ICON = preload("res://assets/sprites/powerups/shield_icon.png")
const NITRO_ICON = preload("res://assets/sprites/powerups/booster_icon.png")

const TOTAL_LAPS: int = 3

# Visual Bar Pixel Offsets on Track Progress Card
@export var bar_start_x: float = 14.0
@export var bar_width: float = 331.0

# Entities & Paths
var player_car: CharacterBody2D = null
var rival_car: CharacterBody2D = null
var rival_follower: PathFollow2D = null
var track_path: Path2D = null
var track_length: float = 1.0

# Lap & Position State
var player_lap: int = 1
var rival_lap: int = 1
var player_passed_mid: bool = false
var rival_passed_mid: bool = false
var race_finished: bool = false

var current_powerup: String = ""

# --- Time Tracking ---
var total_race_time: float = 0.0
var current_lap_time: float = 0.0
var best_lap_time: float = 999999.0
var race_timer_active: bool = false

func _setup_marker_textures() -> void:
	if typeof(GameManager) == TYPE_NIL:
		return

	# 1. Update Player Marker to the chosen car texture
	if GameManager.selected_car_texture and player_marker is TextureRect:
		player_marker.texture = GameManager.selected_car_texture

	# 2. Update Rival Marker to an opposing car
	if rival_marker is TextureRect:
		# If player picked the red car (Rival_Car), set rival to teal (playerr), or vice versa
		var rival_default_tex = preload("res://assets/sprites/cars/rival_car.png")
		if GameManager.selected_car_texture == rival_default_tex:
			rival_marker.texture = preload("res://assets/sprites/cars/player_car.png")
		else:
			rival_marker.texture = rival_default_tex
			
func _ready() -> void:	
# Lock both cars immediately upon loading the track
# Lock both cars immediately upon loading or restarting
	if typeof(GameManager) != TYPE_NIL:
		GameManager.can_race = false
		
	# Apply selected car to track progress bar
	_setup_marker_textures()
	if typeof(GameManager) != TYPE_NIL:
		GameManager.can_race = false

	if powerup_slot:
		powerup_slot.hide()

	# 1. Resolve Car References
	player_car = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if not player_car:
		player_car = find_child("PlayerCar", true, false) as CharacterBody2D

	rival_car = find_child("RivalCar", true, false) as CharacterBody2D
	rival_follower = find_child("RivalPathFollow", true, false) as PathFollow2D
	if not rival_follower:
		rival_follower = find_child("PathFollow2D", true, false) as PathFollow2D

	# 2. Resolve Path2D
	track_path = find_child("RivalPath", true, false) as Path2D
	if not track_path and rival_follower and rival_follower.get_parent() is Path2D:
		track_path = rival_follower.get_parent() as Path2D

	if track_path and track_path.curve:
		track_length = track_path.curve.get_baked_length()
		print("Track path loaded successfully! Length: ", track_length)
	else:
		print("Warning: Track Path2D could not be found!")

	# 3. Connect Gate Signals
	if finish_line:
		if not finish_line.body_entered.is_connected(_on_finish_line_entered):
			finish_line.body_entered.connect(_on_finish_line_entered)
	else:
		print("Warning: FinishLine node not found!")

	if mid_checkpoint:
		if not mid_checkpoint.body_entered.is_connected(_on_mid_checkpoint_entered):
			mid_checkpoint.body_entered.connect(_on_mid_checkpoint_entered)
	else:
		print("Warning: MidCheckpoint node not found!")

# --- Pause System Signal Connections ---
	if pause_button:
		pause_button.pressed.connect(pause_game)
	if resume_button:
		resume_button.pressed.connect(resume_game)
	if restart_button:
		restart_button.pressed.connect(restart_race)
	if car_select_button:
		car_select_button.pressed.connect(goto_car_selection)
		
	_update_hud_text()
	_start_countdown()
	
	

func _process(_delta: float) -> void:
	if race_finished:
		return
# Accumulate race time only while racing is active
	if race_timer_active:
		total_race_time += _delta
		current_lap_time += _delta
		
	# --- 1. Player Progress along Curve ---
	var p_ratio: float = 0.0
	var p_offset: float = 0.0
	if player_car and track_path and track_path.curve and track_length > 0.0:
		var p_local = track_path.to_local(player_car.global_position)
		p_offset = track_path.curve.get_closest_offset(p_local)
		p_ratio = clamp(p_offset / track_length, 0.0, 1.0)

	# --- 2. Rival Progress along Curve ---
	var r_ratio: float = 0.0
	var r_offset: float = 0.0
	if rival_follower:
		r_ratio = clamp(rival_follower.progress_ratio, 0.0, 1.0)
		r_offset = rival_follower.progress
	elif rival_car and track_path and track_path.curve and track_length > 0.0:
		var r_local = track_path.to_local(rival_car.global_position)
		r_offset = track_path.curve.get_closest_offset(r_local)
		r_ratio = clamp(r_offset / track_length, 0.0, 1.0)

	# --- 3. Update Progress Bar Markers ---
	if player_marker:
		player_marker.position.x = bar_start_x + (p_ratio * bar_width)

	if rival_marker:
		rival_marker.position.x = bar_start_x + (r_ratio * bar_width)

	# --- 4. Update Place Card (1st vs 2nd) ---
	_update_race_position(p_offset, r_offset)

func _update_race_position(p_offset: float, r_offset: float) -> void:
	if not place_value:
		return

	# Total distance traveled = (laps completed * full lap length) + distance along current lap
	var player_total_dist = (float(player_lap - 1) * track_length) + p_offset
	var rival_total_dist = (float(rival_lap - 1) * track_length) + r_offset

	# Check position
	if player_total_dist >= rival_total_dist:
		if place_value.text != "1 / 2":
			place_value.text = "1 / 2"
			print("Player took 1st Place!")
	else:
		if place_value.text != "2 / 2":
			place_value.text = "2 / 2"
			print("Player dropped to 2nd Place!")

# --- Lap Gate Triggers ---
func _on_mid_checkpoint_entered(body: Node2D) -> void:
	var target = _resolve_car(body)
	if target == player_car:
		player_passed_mid = true
	elif target == rival_car:
		rival_passed_mid = true

func _on_finish_line_entered(body: Node2D) -> void:
	var target = _resolve_car(body)

	if target == player_car and player_passed_mid:
		player_passed_mid = false

		# Calculate best lap for the player
		if current_lap_time < best_lap_time:
			best_lap_time = current_lap_time
		current_lap_time = 0.0 # Reset for the next lap

		player_lap += 1
		print("Player completed lap! Current lap: ", player_lap)

		_update_hud_text()

		if player_lap > TOTAL_LAPS:
			_finish_race(true)

	elif target == rival_car and rival_passed_mid:
		rival_passed_mid = false
		rival_lap += 1
		print("Rival completed lap! Current lap: ", rival_lap)

		if rival_lap > TOTAL_LAPS:
			_finish_race(false)

func _resolve_car(body: Node2D) -> CharacterBody2D:
	if body == player_car or body.is_in_group("player") or "Player" in body.name:
		return player_car
	if body == rival_car or "Rival" in body.name:
		return rival_car
	if body.get_parent() is CharacterBody2D:
		var parent_body = body.get_parent() as CharacterBody2D
		if parent_body == player_car or parent_body.is_in_group("player") or "Player" in parent_body.name:
			return player_car
		if parent_body == rival_car or "Rival" in parent_body.name:
			return rival_car
	return null

func _update_hud_text() -> void:
	var display_lap = clamp(player_lap, 1, TOTAL_LAPS)
	var text_to_show = str(display_lap) + " / " + str(TOTAL_LAPS)
	
	if lap_value:
		lap_value.text = text_to_show
		print("HUD Lap Label successfully updated to: ", text_to_show)
	else:
		print("ERROR: lap_value reference is null when trying to update text!")

func _finish_race(player_won: bool) -> void:
	race_finished = true
	race_timer_active = false
	
	if typeof(GameManager) != TYPE_NIL:
		GameManager.can_race = false
		GameManager.race_winner = "PLAYER CAR" if player_won else "RIVAL CAR"
		GameManager.total_race_time = total_race_time
		GameManager.best_lap_time = best_lap_time if best_lap_time < 999999.0 else total_race_time

# Wait for the current physics frame to safely finish before changing scenes
	await get_tree().process_frame

	if player_won:
		print("VICTORY! Player wins!")
		get_tree().change_scene_to_file("res://scenes/results/victory_scene.tscn")
	else:
		print("DEFEAT! Rival finished first!")
		get_tree().change_scene_to_file("res://scenes/results/defeat_scene.tscn")

# --- Powerup Collection & Deployment ---
func collect_powerup(powerup_name: String) -> void:
	current_powerup = powerup_name
	if powerup_slot:
		# Set the correct icon on the HUD
		if powerup_name == "oil":
			powerup_slot.texture = OIL_ICON
		elif powerup_name == "shield":
			powerup_slot.texture = SHIELD_ICON
		elif powerup_name == "nitro":
			powerup_slot.texture = NITRO_ICON

		powerup_slot.show()
		powerup_slot.pivot_offset = powerup_slot.size / 2.0
		powerup_slot.scale = Vector2(0.2, 0.2)
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(powerup_slot, "scale", Vector2.ONE, 0.2)

func _unhandled_input(event: InputEvent) -> void:
	# Toggle pause on Escape key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if get_tree().paused:
				resume_game()
			else:
				pause_game()
			return

		# Your existing 'E' key powerup deployment
		if event.keycode == KEY_E and current_powerup != "":
			if current_powerup == "oil":
				_drop_oil_trap()
				_consume_powerup()
			elif current_powerup == "shield":
				_activate_player_shield()
				_consume_powerup()
			elif current_powerup == "nitro":
				_activate_player_nitro()
				_consume_powerup()
				
func _activate_player_nitro() -> void:
	if player_car and player_car.has_method("activate_nitro_boost"):
		player_car.activate_nitro_boost(2.5, 1.6)
		
func pause_game() -> void:
	if pause_menu:
		pause_menu.show()
	get_tree().paused = true

func resume_game() -> void:
	if pause_menu:
		pause_menu.hide()
	get_tree().paused = false

func restart_race() -> void:
	# Unpause before changing/reloading scenes to prevent frozen physics
	get_tree().paused = false
	get_tree().reload_current_scene()

func goto_car_selection() -> void:
	# Unpause before navigating back
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu/car_select.tscn") # Adjust path to your car select scene
func _drop_oil_trap() -> void:
	if not OIL_SLICK_SCENE or not player_car:
		return

	var slick = OIL_SLICK_SCENE.instantiate()
	# Spawn 24 pixels behind player rear bumper
	slick.global_position = player_car.global_position - (player_car.transform.x * 24.0)
	
	# Mark Player as dropper so you don't slip on it instantly!
	slick.dropper = player_car
	
	get_tree().current_scene.add_child(slick)
	print("Player dropped oil slick!")
func _activate_player_shield() -> void:
	if player_car and player_car.has_method("activate_shield"):
		player_car.activate_shield(6.0)

func _consume_powerup() -> void:
	current_powerup = ""
	if powerup_slot:
		var tween = create_tween()
		tween.tween_property(powerup_slot, "scale", Vector2.ZERO, 0.15)
		await tween.finished
		powerup_slot.hide()
		
# --- Countdown Sequence ---
# --- Countdown Sequence ---
func _start_countdown() -> void:
	if countdown_label:
		countdown_label.show()

	await get_tree().create_timer(0.4).timeout

	if countdown_sfx:
		countdown_sfx.play()

	# 1. READY (Both cars remain stationary)
	await _animate_countdown_word("READY", Color("#FF3B30"))

	# 2. SET (Both cars remain stationary)
	await _animate_countdown_word("SET", Color("#FFCC00"))

	# 3. GO! (Unlock cars here)
	if typeof(GameManager) != TYPE_NIL:
		GameManager.can_race = true

	race_timer_active = true
	current_lap_time = 0.0
	total_race_time = 0.0

	await _animate_countdown_word("GO!", Color("#34C759"))

	if countdown_label:
		countdown_label.hide()
		
func _animate_countdown_word(word_text: String, text_color: Color) -> void:
	if not countdown_label:
		return
	countdown_label.text = word_text
	countdown_label.modulate = text_color
	countdown_label.pivot_offset = countdown_label.size / 2.0
	countdown_label.scale = Vector2(0.3, 0.3)
	
	# Pop-in bounce animation
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.2)
	
	# Wait for the next beep tone (adjust between 0.8s - 0.9s if you need to fine-tune to the audio beat)
	await get_tree().create_timer(0.85).timeout
