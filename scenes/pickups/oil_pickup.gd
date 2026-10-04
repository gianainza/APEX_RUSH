extends Area2D

@export var respawn_time: float = 8.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collider: CollisionShape2D = $CollisionShape2D

var is_available: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not is_available:
		return

	var car = body
	if not car.is_in_group("player") and not car.name.begins_with("Rival") and body.get_parent():
		car = body.get_parent()

	# If PLAYER drives through it:
	if car.is_in_group("player") or car.name == "PlayerCar":
		var level = get_tree().current_scene
		if level.has_method("collect_powerup"):
			if level.current_powerup != "":
				return # Slot already full
			is_available = false
			level.collect_powerup("oil")
			_animate_pickup()

	# If RIVAL drives through it:
	elif car.has_method("store_powerup"):
		if car.has_stored_powerup():
			return # Slot already full
		is_available = false
		car.store_powerup("oil")
		_animate_pickup()

func _animate_pickup() -> void:
	collider.set_deferred("disabled", true)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.15)
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func _respawn() -> void:
	is_available = true
	collider.set_deferred("disabled", false)
	sprite.scale = Vector2.ZERO
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.25)
