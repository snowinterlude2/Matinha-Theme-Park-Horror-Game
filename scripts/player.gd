extends CharacterBody3D
## Simple first-person walker for exploring the map.
## WASD to move, mouse to look, Shift to run, Space to jump, Esc to free the mouse.

const WALK_SPEED := 4.0
const RUN_SPEED := 7.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025

@onready var head: Node3D = $Head

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()
