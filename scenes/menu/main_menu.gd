extends Control

# --- Main Menu Buttons ---
@onready var play_btn: Button = get_node_or_null("PlayButton")
@onready var settings_btn: Button = get_node_or_null("SettingsButton")
@onready var credits_btn: Button = get_node_or_null("CreditsButton")
@onready var help_btn: Button = get_node_or_null("HelpButton")

# --- Modals & Dimmer ---
@onready var dim_overlay: ColorRect = get_node_or_null("DimOverlay")

@onready var help_modal: TextureRect = get_node_or_null("DimOverlay/HelpModal")
@onready var help_back_btn: Button = get_node_or_null("DimOverlay/HelpModal/BackButton")

@onready var credits_modal: TextureRect = get_node_or_null("DimOverlay/CreditsModal")
@onready var credits_back_btn: Button = get_node_or_null("DimOverlay/CreditsModal/BackButton")

@onready var settings_modal: TextureRect = get_node_or_null("DimOverlay/SettingsModal")
@onready var settings_back_btn: Button = get_node_or_null("DimOverlay/SettingsModal/BackButton")

# --- Settings Sliders ---
@onready var music_slider: HSlider = $DimOverlay/SettingsModal/MusicSlider
@onready var volume_slider: HSlider = $DimOverlay/SettingsModal/VolumeSlider
@onready var sfx_slider: HSlider = $DimOverlay/SettingsModal/SFXSlider


@onready var click_sfx: AudioStreamPlayer = get_node_or_null("ClickSound")

func _ready() -> void:
	_close_modals()

	# Connect Main Menu Buttons
	if play_btn:
		play_btn.pressed.connect(_on_play_pressed)
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	if credits_btn:
		credits_btn.pressed.connect(_on_credits_pressed)
	if help_btn:
		help_btn.pressed.connect(_on_help_pressed)

	# Connect Modal Back Buttons
	if help_back_btn:
		help_back_btn.pressed.connect(_close_modals)
	if credits_back_btn:
		credits_back_btn.pressed.connect(_close_modals)
	if settings_back_btn:
		settings_back_btn.pressed.connect(_close_modals)

	# Connect Volume Sliders
	if music_slider:
		music_slider.value_changed.connect(_on_music_volume_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_volume_changed)

# --- Setup Audio Sliders ---
	_setup_audio_slider(music_slider, "Music")
	_setup_audio_slider(volume_slider, "Master")
	_setup_audio_slider(sfx_slider, "SFX")

func _setup_audio_slider(slider: HSlider, bus_name: String) -> void:
	if not slider:
		return
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		# Set slider's initial position based on current bus volume
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
		
	# Connect value changed signal
	slider.value_changed.connect(func(new_val: float):
		if typeof(GameManager) != TYPE_NIL:
			GameManager.set_bus_volume(bus_name, new_val)
	)
	
# --- Modal Open / Close Helpers ---

func _open_modal(modal: TextureRect) -> void:
	if click_sfx:
		click_sfx.play()

	if dim_overlay:
		dim_overlay.show()

	# Hide all modals first so they never overlap
	if help_modal: help_modal.hide()
	if credits_modal: credits_modal.hide()
	if settings_modal: settings_modal.hide()

	if modal:
		modal.show()
		modal.pivot_offset = modal.size / 2.0
		modal.scale = Vector2(0.85, 0.85)
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(modal, "scale", Vector2.ONE, 0.15)

func _close_modals() -> void:
	if click_sfx:
		click_sfx.play()

	if dim_overlay:
		dim_overlay.hide()
	if help_modal:
		help_modal.hide()
	if credits_modal:
		credits_modal.hide()
	if settings_modal:
		settings_modal.hide()

# --- Button Handlers ---

func _on_play_pressed() -> void:
	if click_sfx: click_sfx.play()
	get_tree().change_scene_to_file("res://scenes/menu/car_select.tscn")

func _on_help_pressed() -> void:
	_open_modal(help_modal)

func _on_credits_pressed() -> void:
	_open_modal(credits_modal)

func _on_settings_pressed() -> void:
	_open_modal(settings_modal)

# --- Audio Slider Logic ---

func _on_music_volume_changed(val: float) -> void:
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx != -1:
		# Convert linear 0.0 - 1.0 to decibels
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val))
		# Mute if dragged all the way to 0
		AudioServer.set_bus_mute(bus_idx, val <= 0.01)

func _on_sfx_volume_changed(val: float) -> void:
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(val))
		AudioServer.set_bus_mute(bus_idx, val <= 0.01)

# Escape key closes whichever modal is open
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if dim_overlay and dim_overlay.visible:
			_close_modals()
