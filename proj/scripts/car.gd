class_name Car
extends Node3D
## Arcade toy car. Movement is kinematic on a flat track; the race manager
## calls step() every physics frame.

const MODEL_SCALE := 2.0
const TURN_RATE := 2.2
const STUN_TIME := 3.0

var race: Node
var track: Track
var is_player := false
var ai := true
var display_name := ""
var color := Color.WHITE

var yaw := 0.0
var speed := 0.0
var max_speed := 17.0
var accel := 8.0
var steer := 0.0
var brake := false

var idx := 0
var frac := 0.0
var lateral := 0.0
var lap := 0
var finished := false
var place := 0

var item := ""
var stun := 0.0
var invuln := 0.0
var lane := 0.0
var lane_timer := 0.0
var item_timer := 0.0

var pivot: Node3D            # rotates for flips
var model: Node3D
var height := 0.8
var _blink := 0.0


func setup(model_path: String) -> void:
	pivot = Node3D.new()
	add_child(pivot)
	model = load(model_path).instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	pivot.add_child(model)
	height = 0.45 * MODEL_SCALE
	pivot.position.y = height * 0.5
	model.position.y = -height * 0.5
	lane = randf_range(-1.8, 1.8)
	item_timer = randf_range(1.5, 4.0)


func heading() -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))


func progress() -> float:
	return lap * track.N + idx + frac


func is_stunned() -> bool:
	return stun > 0.0


## Called when a weapon hits the car. Returns true if the hit counted.
func hit(kind: String) -> bool:
	if stun > 0.0 or invuln > 0.0:
		return false
	stun = STUN_TIME
	var base_y := height * 0.5
	pivot.position = Vector3(0, base_y, 0)
	pivot.rotation = Vector3.ZERO
	var side := 1.0 if randf() < 0.5 else -1.0
	var tw := create_tween()
	# 1) thrown up and flipped upside down
	tw.tween_property(pivot, "position:y", base_y + 1.8, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:z", PI * side, 0.65)
	if kind == "oil":
		tw.parallel().tween_property(pivot, "rotation:y", TAU * 2.0, 0.9)
	tw.tween_property(pivot, "position:y", base_y, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 2) lies upside down
	tw.tween_interval(1.05)
	# 3) hops and turns back over
	tw.tween_property(pivot, "position:y", base_y + 1.1, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:z", TAU * side, 0.55)
	tw.tween_property(pivot, "position:y", base_y, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): pivot.rotation = Vector3.ZERO)
	return true


func step(dt: float, racing: bool) -> void:
	if stun > 0.0:
		stun -= dt
		speed = move_toward(speed, 0.0, 40.0 * dt)
		if stun <= 0.0:
			invuln = 1.6
	else:
		if invuln > 0.0:
			invuln -= dt
			_blink += dt
			model.visible = invuln <= 0.0 or fmod(_blink, 0.2) < 0.13
		else:
			model.visible = true
		var target := max_speed if racing else 0.0
		if brake:
			target = max_speed * 0.35
		if speed > target:
			speed = move_toward(speed, target, accel * 2.5 * dt)
		else:
			speed = move_toward(speed, target, accel * dt)
		var grip := clampf(absf(speed) / 6.0, 0.0, 1.0)
		yaw -= steer * TURN_RATE * grip * dt

	position += heading() * speed * dt

	# keep on track
	var loc := track.locate(position, idx)
	var new_idx: int = loc[0]
	if idx > track.N * 3 / 4 and new_idx < track.N / 4:
		lap += 1
	elif idx < track.N / 4 and new_idx > track.N * 3 / 4:
		lap -= 1
	idx = new_idx
	frac = loc[1]
	lateral = loc[2]
	if absf(lateral) > Track.HALF_W:
		var r := track.right_at(idx)
		position -= r * (lateral - signf(lateral) * Track.HALF_W)
		lateral = signf(lateral) * Track.HALF_W
		speed *= pow(0.35, dt)
		# nudge heading along the wall
		var t := track.tangents[idx]
		var wall_yaw := atan2(t.x, t.z)
		if heading().dot(t) < 0:
			wall_yaw += PI
		yaw = lerp_angle(yaw, wall_yaw, clampf(4.0 * dt, 0, 1))
	position.y = 0.0
	rotation.y = yaw
	# body lean
	if stun <= 0.0:
		pivot.rotation.z = lerp_angle(pivot.rotation.z, steer * 0.08 * clampf(speed / max_speed, 0, 1), 8 * dt)


## Simple racing AI
func think(dt: float, rank_ahead: Car, rank_behind: Car) -> void:
	lane_timer -= dt
	if lane_timer <= 0.0:
		lane_timer = randf_range(2.0, 5.0)
		lane = randf_range(-1.8, 1.8)
	var look := 7 + int(speed * 0.25)
	var ti := (idx + look) % track.N
	var target := track.samples[ti] + track.right_at(ti) * lane
	var to := target - position
	var want := atan2(to.x, to.z)
	var diff := wrapf(want - yaw, -PI, PI)
	steer = clampf(-diff * 2.2, -1.0, 1.0)
	# slow down for sharp bends
	var t1 := track.tangents[(idx + 4) % track.N]
	var t2 := track.tangents[(idx + 14) % track.N]
	brake = t1.dot(t2) < 0.3 and speed > max_speed * 0.8
	# use items
	if item != "":
		item_timer -= dt
		if item_timer <= 0.0:
			var use := false
			match item:
				"rocket", "zap":
					use = rank_ahead != null and rank_ahead.position.distance_to(position) < 35.0
				"nails", "oil":
					use = rank_behind != null and rank_behind.position.distance_to(position) < 18.0
			if use or item_timer < -6.0:
				race.use_item(self)
				item_timer = randf_range(1.0, 3.5)
