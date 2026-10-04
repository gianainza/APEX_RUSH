extends Area2D

# The car that just dropped this puddle
var dropper: Node2D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	# Brief 0.4s grace period so the car dropping the oil doesn't 
	# immediately slip on its own rear bumper as it drives away
	await get_tree().create_timer(0.4).timeout
	dropper = null # After this, even the dropper could slip if they loop around!

func _on_body_entered(body: Node2D) -> void:
	# Resolve target car (supports root Car or child colliders)
	var target = body
	if not target.has_method("apply_oil_slowdown") and body.get_parent():
		target = body.get_parent()

	# 1. Ignore if it's the dropper during the initial 0.4s drop
	if target == dropper:
		return

	# 2. Check if the target has an active Bumper Shield halo!
	if "is_shielded" in target and target.is_shielded:
		print(target.name, " hit oil, but their Bumper Shield absorbed it!")
		queue_free()
		return

	# 3. If target has slowdown (PlayerCar or RivalCar), trigger the trap!
	if target and target.has_method("apply_oil_slowdown"):
		print(target.name, " got TRAPPED in oil!")
		target.apply_oil_slowdown(3.0)
		queue_free()
