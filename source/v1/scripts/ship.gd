extends Node3D
class_name HoldShip
## POV starship: locked forward rush + steering in all directions.
##
## Touch / mouse = "floating joystick anywhere": put your thumb down anywhere, then slide it.
## The ship moves in the direction you slide (up/down/left/right/diagonal), faster the further
## you slide. The joystick centre follows your thumb if you slide past full deflection, so
## reversing direction is instant. Let go = the ship coasts to a stop and then eases gently
## back toward the middle (it never drifts to an edge).
## Keyboard (PC bonus): arrows or WASD.
## Growth hook: ship_profile_id reserved for later handling variants.

## THE one steering tuning knob. Higher = less thumb travel for full speed + snappier response.
## 1.0 = relaxed, 1.6 = default (Daniel asked for more sensitive), 2.5 = twitchy.
const STEER_SENSITIVITY := 1.6

## How far (fraction of the screen's SHORT side) you slide for full speed at sensitivity 1.0.
const FULL_DEFLECT_FRAC := 0.17
const DEADZONE := 0.04             ## fraction of full deflection ignored (thumb jitter)

@export var max_lateral_speed: float = 34.0
@export var max_vertical_speed: float = 30.0
@export var steer_accel: float = 95.0      ## m/s^2 at sensitivity 1.0 (scaled by sensitivity)
@export var release_damp: float = 4.0      ## how quickly the ship stops after you let go
@export var recenter_rate: float = 0.45    ## gentle pull back to the middle when not steering (1/s)
@export var bank_amount: float = 0.6
@export var bounds := Vector2(14.0, 11.0)  ## hard limits (x, y)
@export var soft_edge := 4.0               ## metres before the limit where steering softens
@export var ship_profile_id: String = "default" ## growth stub

var velocity := Vector3.ZERO
var holding := false
var steer := Vector2.ZERO          ## current stick value, -1..1 each axis (+x right, +y up)
var _anchor := Vector2.ZERO
var _pointer := Vector2.ZERO
var _touch_index := -1
var _idle_t := 0.0
var enabled := false
## set by main.gd: returns true when a touch lands on a UI button (VIEW / camera picker),
## so tapping those never starts a steering drag
var ui_blocker: Callable

func _ready() -> void:
	add_to_group("player")

func _input(event: InputEvent) -> void:
	# Mouse is converted to touch by emulate_touch_from_mouse, and touch is NOT
	# converted to mouse, so we only listen to touch events: no double firing.
	if event is InputEventScreenTouch:
		if event.pressed:
			if ui_blocker.is_valid() and ui_blocker.call(event.position):
				return
			if _touch_index == -1: # first finger owns the stick; extra fingers are ignored
				_touch_index = event.index
				holding = true
				_anchor = event.position
				_pointer = event.position
		elif event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_pointer = event.position

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release() # never get stuck "holding" if the browser loses the touch-up

func _release() -> void:
	holding = false
	_touch_index = -1

func _full_deflect_px() -> float:
	var size := get_viewport().get_visible_rect().size
	return maxf(minf(size.x, size.y) * FULL_DEFLECT_FRAC / STEER_SENSITIVITY, 18.0)

func _read_stick() -> Vector2:
	var s := Vector2.ZERO
	if holding:
		var full := _full_deflect_px()
		var d := _pointer - _anchor
		if d.length() > full:
			# floating joystick: drag the anchor along so the opposite direction responds at once
			_anchor = _pointer - d.normalized() * full
			d = _pointer - _anchor
		s = d / full
		s.y = -s.y # screen y grows downward; slide up = fly up
		var l := s.length()
		if l < DEADZONE:
			s = Vector2.ZERO
		else:
			# remap out of the deadzone, light curve: fine control near centre, full speed at the rim
			var k := (l - DEADZONE) / (1.0 - DEADZONE)
			k = clampf(k * 0.45 + k * k * 0.55, 0.0, 1.0)
			s = s / l * k
	# keyboard (PC): arrows / WASD, adds on top of touch
	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
			- float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)))
	if kb != Vector2.ZERO:
		s += kb.normalized()
	return s.limit_length(1.0)

func _soften(pos: float, vel: float, limit: float) -> float:
	# Reduce speed that pushes further out once inside the soft edge zone.
	if signf(vel) != signf(pos) or vel == 0.0:
		return vel
	var into := absf(pos) - (limit - soft_edge)
	if into <= 0.0:
		return vel
	return vel * clampf(1.0 - into / soft_edge, 0.0, 1.0)

func _physics_process(delta: float) -> void:
	steer = _read_stick() if enabled else Vector2.ZERO
	var accel := steer_accel * STEER_SENSITIVITY
	if steer != Vector2.ZERO:
		_idle_t = 0.0
		var target := Vector2(steer.x * max_lateral_speed, steer.y * max_vertical_speed)
		# accelerate harder when reversing direction so it feels responsive
		var ax := accel * (1.8 if signf(target.x) != signf(velocity.x) else 1.0)
		var ay := accel * (1.8 if signf(target.y) != signf(velocity.y) else 1.0)
		velocity.x = move_toward(velocity.x, target.x, ax * delta)
		velocity.y = move_toward(velocity.y, target.y, ay * delta)
	else:
		_idle_t += delta
		# coast to a stop, then a gentle pull back toward the middle (no edge drift)
		var pull := Vector2(-position.x, -position.y) * recenter_rate * clampf(_idle_t - 0.35, 0.0, 1.0)
		var damp := clampf(release_damp * delta, 0.0, 1.0)
		velocity.x = lerpf(velocity.x, pull.x, damp)
		velocity.y = lerpf(velocity.y, pull.y, damp)

	velocity.x = _soften(position.x, velocity.x, bounds.x)
	velocity.y = _soften(position.y, velocity.y, bounds.y)
	position.x += velocity.x * delta
	position.y += velocity.y * delta
	if absf(position.x) > bounds.x:
		position.x = clampf(position.x, -bounds.x, bounds.x)
		velocity.x = 0.0
	if absf(position.y) > bounds.y:
		position.y = clampf(position.y, -bounds.y, bounds.y)
		velocity.y = 0.0

	var t := clampf(10.0 * delta, 0.0, 1.0)
	rotation.z = lerp_angle(rotation.z, -velocity.x / max_lateral_speed * bank_amount, t)
	rotation.x = lerp_angle(rotation.x, velocity.y / max_vertical_speed * 0.22, t)
