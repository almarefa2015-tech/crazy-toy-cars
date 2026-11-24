class_name Track
extends Node3D
## Builds a closed race track from Kenney tiles on a 10m grid and
## provides a sampled centre line used for driving, AI and lap counting.

const TILE := 10.0
const HALF_W := 3.0          # max distance of a car centre from the centre line
const DIRS := {"R": Vector2i(1, 0), "L": Vector2i(-1, 0), "D": Vector2i(0, 1), "U": Vector2i(0, -1)}

var samples := PackedVector3Array()
var tangents := PackedVector3Array()
var N := 0
var cells: Array[Vector2i] = []
var item_spots: Array[Vector3] = []

var _straight := preload("res://models/track-straight.glb")
var _corner := preload("res://models/track-corner.glb")
var _finish := preload("res://models/track-finish.glb")
var _deco := [preload("res://models/decoration-forest.glb"), preload("res://models/decoration-empty.glb"), preload("res://models/decoration-tents.glb")]


static func _v3(v: Vector2i) -> Vector3:
	return Vector3(v.x, 0, v.y)


func build(moves_in: String, seed_value: int) -> void:
	var n := moves_in.length()
	var start := 0
	for i in n:
		if moves_in[i] == moves_in[(i - 1 + n) % n] and moves_in[i] == moves_in[(i - 2 + n) % n]:
			start = i
			break
	var m := moves_in.substr(start) + moves_in.substr(0, start)

	var c := Vector2i.ZERO
	cells = [c]
	for i in n - 1:
		c += DIRS[m[i]]
		cells.append(c)

	var pts_by_cell: Array = []
	for i in n:
		var d_in: Vector2i = DIRS[m[(i - 1 + n) % n]]
		var d_out: Vector2i = DIRS[m[i]]
		var side_prev := -d_in
		var side_next := d_out
		var centre := _v3(cells[i]) * TILE
		var tile_scene: PackedScene
		var base_a: Vector2i
		var base_b: Vector2i
		if d_in == d_out:
			tile_scene = _finish if i == 0 else _straight
			base_a = Vector2i(0, 1)
			base_b = Vector2i(0, -1)
		else:
			tile_scene = _corner
			base_a = Vector2i(-1, 0)
			base_b = Vector2i(0, 1)
		var rot := _find_rotation(base_a, base_b, side_prev, side_next)
		var tile: Node3D = tile_scene.instantiate()
		tile.position = centre
		tile.rotation.y = rot
		add_child(tile)

		# centre-line points from entry edge towards exit edge (exit excluded)
		var p_in := centre + _v3(side_prev) * TILE * 0.5
		var p_out := centre + _v3(side_next) * TILE * 0.5
		var pts: Array[Vector3] = []
		if d_in == d_out:
			for k in 10:
				pts.append(p_in.lerp(p_out, k / 10.0))
		else:
			var pivot := centre + (_v3(side_prev) + _v3(side_next)) * TILE * 0.5
			var a0 := atan2((p_in - pivot).z, (p_in - pivot).x)
			var a1 := atan2((p_out - pivot).z, (p_out - pivot).x)
			var da := wrapf(a1 - a0, -PI, PI)
			for k in 8:
				var a := a0 + da * k / 8.0
				pts.append(pivot + Vector3(cos(a), 0, sin(a)) * TILE * 0.5)
		pts_by_cell.append(pts)

	# Start line = centre of cell 0
	samples = PackedVector3Array()
	var first: Array = pts_by_cell[0]
	for k in range(5, first.size()):
		samples.append(first[k])
	for i in range(1, n):
		for p in pts_by_cell[i]:
			samples.append(p)
	for k in range(0, 5):
		samples.append(first[k])
	N = samples.size()
	tangents.resize(N)
	for i in N:
		tangents[i] = (samples[(i + 1) % N] - samples[(i - 1 + N) % N]).normalized()

	_build_scenery(seed_value)

	for f in [0.22, 0.52, 0.8]:
		var idx := int(N * f)
		item_spots.append(samples[idx])


func right_at(i: int) -> Vector3:
	return tangents[posmod(i, N)].cross(Vector3.UP)


func _find_rotation(a: Vector2i, b: Vector2i, want_a: Vector2i, want_b: Vector2i) -> float:
	for k in 4:
		var bas := Basis(Vector3.UP, k * PI / 2.0)
		var ra := bas * _v3(a)
		var rb := bas * _v3(b)
		var va := Vector2i(roundi(ra.x), roundi(ra.z))
		var vb := Vector2i(roundi(rb.x), roundi(rb.z))
		if (va == want_a and vb == want_b) or (va == want_b and vb == want_a):
			return k * PI / 2.0
	return 0.0


func _build_scenery(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mn := Vector2i(999, 999)
	var mx := Vector2i(-999, -999)
	var used := {}
	for c in cells:
		used[c] = true
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	for x in range(mn.x - 2, mx.x + 3):
		for z in range(mn.y - 2, mx.y + 3):
			var cell := Vector2i(x, z)
			if used.has(cell):
				continue
			var r := rng.randf()
			var scene: PackedScene = _deco[0] if r < 0.55 else (_deco[1] if r < 0.9 else _deco[2])
			var d: Node3D = scene.instantiate()
			d.position = _v3(cell) * TILE
			d.rotation.y = rng.randi_range(0, 3) * PI / 2.0
			add_child(d)
	# big ground plane under everything
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.62, 0.5)
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = Vector3((mn.x + mx.x) * TILE * 0.5, -0.02, (mn.y + mx.y) * TILE * 0.5)
	add_child(ground)


## Find nearest centre-line segment around a hint index.
## Returns [index, fraction, lateral_offset, point]
func locate(pos: Vector3, hint: int) -> Array:
	var best_d := INF
	var best_i := hint
	var best_t := 0.0
	var best_p := samples[posmod(hint, N)]
	for o in range(-10, 22):
		var i := posmod(hint + o, N)
		var a := samples[i]
		var b := samples[(i + 1) % N]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var p := a + ab * t
		var d := Vector2(pos.x - p.x, pos.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
			best_p = p
	var lateral := (pos - best_p).dot(right_at(best_i))
	return [best_i, best_t, lateral, best_p]


## Global search (used once at start)
func locate_global(pos: Vector3) -> int:
	var best_d := INF
	var best_i := 0
	for i in N:
		var d := samples[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


## Point behind the start line, `dist` metres back along the centre line.
func point_behind_start(dist: float) -> Array:
	var i := N - 1
	var acc := 0.0
	var p := samples[0]
	while acc < dist and i > 0:
		var seg := samples[(i + 1) % N].distance_to(samples[i])
		if acc + seg >= dist:
			var t := (dist - acc) / seg
			p = samples[(i + 1) % N].lerp(samples[i], t)
			acc = dist
			break
		acc += seg
		i -= 1
	return [p, tangents[i], i]
