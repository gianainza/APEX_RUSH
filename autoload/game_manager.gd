# --- In game_manager.gd ---
extends Node

var can_race: bool = false
var selected_car_texture: Texture2D = null

# --- Race Results Data ---
var race_winner: String = "PLAYER"
var total_race_time: float = 0.0
var best_lap_time: float = 0.0

# --- Background Music ---
# Make sure this filename matches your exact mp3 name in FileSystem!
var bgm_stream = preload("res://assets/audio/music/Stock Car Racing Trailer 2026.mp3")
var bgm_player: AudioStreamPlayer

func _ready() -> void:
	# Persistent BGM Player across scenes
	bgm_player = AudioStreamPlayer.new()
	bgm_player.stream = bgm_stream
	bgm_player.bus = "Music" # Routes to the Music bus
	add_child(bgm_player)
	
	# Start playing right on launch (Main Menu)
	play_bgm()

func play_bgm() -> void:
	if bgm_player and not bgm_player.playing:
		bgm_player.play()

func stop_bgm() -> void:
	if bgm_player and bgm_player.playing:
		bgm_player.stop()

# --- Audio Bus Volume Control ---
func set_bus_volume(bus_name: String, linear_val: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		if linear_val <= 0.05:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear_val))

func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.--"
	var mins = int(seconds / 60.0)
	var secs = int(fmod(seconds, 60.0))
	var msecs = int(fmod(seconds, 1.0) * 100.0)
	return "%02d:%02d.%02d" % [mins, secs, msecs]
