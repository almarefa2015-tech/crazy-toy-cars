class_name FX
extends RefCounted
## Effect and item model helpers built from Kenney CC0 assets.

const TEX_SPARK := preload("res://fx/spark_04.png")
const TEX_BOLT := preload("res://fx/spark_05.png")
const TEX_SMOKE := preload("res://fx/smoke_04.png")
const TEX_FLAME := preload("res://fx/flame_01.png")
const TEX_STAR := preload("res://fx/star_04.png")
const TEX_GLOW := preload("res://fx/circle_05.png")

const NAILS_TEX := preload("res://fx/nails_decal.png")
const OIL_TEX := preload("res://fx/oil_decal.png")
const ROCKET_MODEL := preload("res://models/ai/rocket.glb")


static func sprite_mat(tex: Texture2D, col: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## One-shot burst of billboard particles.
static func burst(parent: Node, pos: Vector3, tex: Texture2D, col: Color, amount := 24, size := 1.2, spread := 5.0, life := 0.7, additive := true, gravity := 0.0) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	p.material_override = sprite_mat(tex, col, additive)
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = spread * 0.4
	p.initial_velocity_max = spread
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.angle_min = -180
	p.angle_max = 180
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


static func explosion(parent: Node, pos: Vector3) -> void:
	burst(parent, pos + Vector3.UP * 0.8, TEX_GLOW, Color(1.0, 0.75, 0.3), 4, 5.0, 0.5, 0.35)
	burst(parent, pos + Vector3.UP * 0.8, TEX_FLAME, Color(1.0, 0.55, 0.1), 26, 3.0, 8.0, 0.7)
	burst(parent, pos + Vector3.UP * 0.8, TEX_SMOKE, Color(0.85, 0.82, 0.88), 16, 3.2, 4.0, 1.2, false, 1.5)
	burst(parent, pos + Vector3.UP * 0.8, TEX_STAR, Color(1, 0.95, 0.5), 16, 1.1, 11.0, 0.6)


static func zap_effect(parent: Node, a: Vector3, b: Vector3) -> void:
	# a stretched lightning-bolt billboard between two points + crackle at target
	var root := Node3D.new()
	parent.add_child(root)
	var dist := a.distance_to(b)
	var count := maxi(1, int(dist / 5.0))
	for i in count:
		var s := Sprite3D.new()
		s.texture = TEX_BOLT
		s.modulate = Color(0.55, 0.85, 1.0)
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.shaded = false
		s.no_depth_test = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.pixel_size = 6.0 / 512.0
		root.add_child(s)
		var t := (i + 0.5) / count
		s.global_position = a.lerp(b, t) + Vector3.UP * 1.5
	burst(parent, b + Vector3.UP * 0.8, TEX_SPARK, Color(0.5, 0.85, 1.0), 26, 1.6, 6.0, 0.8)
	burst(parent, b + Vector3.UP * 0.8, TEX_GLOW, Color(0.4, 0.7, 1.0), 6, 3.0, 1.0, 0.5)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.light_energy = 6.0
	light.omni_range = 8.0
	root.add_child(light)
	light.global_position = b + Vector3.UP * 1.5
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	parent.get_tree().create_timer(0.5).timeout.connect(root.queue_free)


static func make_rocket() -> Node3D:
	## Khaled's firework rocket (AI-made 3D model). Model nose points -X; turn it to +Z.
	var holder := Node3D.new()
	var r: Node3D = ROCKET_MODEL.instantiate()
	r.rotation.y = PI / 2.0
	r.scale = Vector3.ONE * 0.7
	holder.add_child(r)
	return holder


static func make_nails(_rng: RandomNumberGenerator = null, _count := 6, _spread := 1.3) -> Node3D:
	## Khaled's nails art as an upright sticker on the road.
	var n := Node3D.new()
	var sp := Sprite3D.new()
	sp.texture = NAILS_TEX
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.pixel_size = 1.6 / 512.0
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.shaded = false
	sp.position.y = 0.7
	n.add_child(sp)
	return n


static func make_oil() -> Node3D:
	## Khaled's oil puddle art laid flat on the road.
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.6, 3.6)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = OIL_TEX
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position.y = 0.04
	mi.rotation.y = randf() * TAU
	n.add_child(mi)
	return n


static func make_zap_icon() -> Node3D:
	var n := Node3D.new()
	var s := Sprite3D.new()
	s.texture = TEX_BOLT
	s.modulate = Color(0.55, 0.85, 1.0)
	s.shaded = false
	s.pixel_size = 2.2 / 512.0
	n.add_child(s)
	var g := Sprite3D.new()
	g.texture = TEX_SPARK
	g.modulate = Color(0.4, 0.8, 1.0)
	g.shaded = false
	g.pixel_size = 2.4 / 512.0
	g.position.z = -0.1
	n.add_child(g)
	return n
