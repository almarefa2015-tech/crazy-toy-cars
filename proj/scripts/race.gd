extends Node3D
## Race manager: world, cars, items, weapons, camera and HUD.

signal exit_to_menu
signal restart(track_index: int)

const NUM_CARS := 6
const ITEMS := ["rocket", "nails", "oil", "zap"]
const ITEM_NAMES := {"rocket": "ROCKET", "nails": "NAILS", "oil": "OIL SLICK", "zap": "ZAPPER"}
const AI_NAMES := ["Bolt", "Zoomy", "Turbo", "Sparky", "Dash", "Rusty", "Nitro"]

var track: Track
var cars: Array[Car] = []
var player: Car
var ranking: Array[Car] = []
var state := "countdown"   # countdown, racing, finished
var countdown := 3.6
var finish_order: Array[Car] = []

var boxes: Array = []        # [{node, pos, timer}]
var rockets: Array = []      # [{node, pos, dir, owner, target, life}]
var hazards: Array = []      # [{node, pos, kind, owner, life, safe}]
var rng := RandomNumberGenerator.new()

var cam: Camera3D
var hud: CanvasLayer
var lbl_place: Label
var lbl_lap: Label
var lbl_count: Label
var lbl_item: Label
var lbl_msg: Label
var item_view: SubViewport
var mirror_view: SubViewport
var mirror_cam: Camera3D
var item_holder: Node3D
var item_panel: Control
var pause_layer: CanvasLayer
var engine: AudioStreamPlayer
var sfx_hit: AudioStreamPlayer
var sfx_skid: AudioStreamPlayer

var _box_scene := preload("res://models/toy/item-box.glb")
var _shown_item := "-"
var _msg_time := 0.0


func _ready() -> void:
	rng.randomize()
	var tdata: Dictionary = Game.TRACKS[Game.track_index]
	_build_environment(tdata)
	track = Track.new()
	add_child(track)
	track.build(tdata["moves"], tdata["seed"])
	_build_boxes()
	_build_cars(tdata)
	_build_camera()
	_build_hud()
	_build_audio()


# ---------------------------------------------------------------- world

func _build_environment(t: Dictionary) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = t["sky_top"]
	sm.sky_horizon_color = t["sky_horizon"]
	sm.ground_horizon_color = t["sky_horizon"]
	sm.ground_bottom_color = Color(0.25, 0.45, 0.3)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.95).lerp(t["sky_top"], 0.15)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.8
	env.fog_enabled = true
	env.fog_light_color = t["sky_horizon"]
	env.fog_density = 0.0025
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = t["sun"] * 0.8
	sun.light_color = t["sun_color"]
	sun.rotation_degrees = Vector3(t["sun_angle"], -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_boxes() -> void:
	for spot in track.item_spots:
		var i := track.locate_global(spot)
		var r := track.right_at(i)
		for off in [-2.1, -0.7, 0.7, 2.1]:
			var b: Node3D = _box_scene.instantiate()
			b.scale = Vector3.ONE * 2.2
			var p: Vector3 = track.samples[i] + r * off
			b.position = p + Vector3.UP * 0.5
			add_child(b)
			boxes.append({"node": b, "pos": p, "timer": 0.0})


func _build_cars(t: Dictionary) -> void:
	var models := range(Game.CARS.size())
	if models.size() > 3:
		models.erase(Game.car_index)
	models.shuffle()
	var names := AI_NAMES.duplicate()
	names.shuffle()
	var player_slot := 4
	for k in NUM_CARS:
		var c := Car.new()
		c.race = self
		c.track = track
		var model_i: int
		if k == player_slot:
			c.is_player = true
			c.ai = false
			c.display_name = "YOU"
			c.max_speed = 17.5
			model_i = Game.car_index
			player = c
		else:
			c.display_name = names[k % names.size()]
			model_i = models[k % models.size()]
			c.max_speed = 17.5 * t["ai_speed"] * rng.randf_range(0.93, 1.0)
		add_child(c)
		c.setup(Game.CARS[model_i]["model"])
		var row := k / 2
		var col := k % 2
		var info := track.point_behind_start(2.5 + row * 3.4)
		var tan: Vector3 = info[1]
		var right := tan.cross(Vector3.UP)
		c.position = info[0] + right * (1.6 if col == 0 else -1.6)
		c.yaw = atan2(tan.x, tan.z)
		c.rotation.y = c.yaw
		c.idx = info[2]
		c.lap = 0
		cars.append(c)
	ranking = cars.duplicate()


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 400
	add_child(cam)
	cam.current = true
	_update_camera(1.0, true)


func _build_audio() -> void:
	engine = AudioStreamPlayer.new()
	var s: AudioStreamOggVorbis = load("res://audio/engine.ogg").duplicate()
	s.loop = true
	engine.stream = s
	engine.volume_db = -12
	add_child(engine)
	engine.play()
	sfx_hit = AudioStreamPlayer.new()
	sfx_hit.stream = load("res://audio/impact.ogg")
	add_child(sfx_hit)
	sfx_skid = AudioStreamPlayer.new()
	sfx_skid.stream = load("res://audio/skid.ogg")
	sfx_skid.volume_db = -6
	add_child(sfx_skid)


# ---------------------------------------------------------------- HUD

func _label(size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.02, 0.25))
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	return l


func _touch_button(tex_path: String, action: String, pos: Vector2, scale_f: float, icon_path := "") -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = load(tex_path)
	b.action = action
	b.position = pos
	b.scale = Vector2.ONE * scale_f
	b.modulate = Color(1, 1, 1, 0.85)
	if icon_path != "":
		var ic := Sprite2D.new()
		ic.texture = load(icon_path)
		ic.centered = true
		ic.position = b.texture_normal.get_size() * 0.5
		b.add_child(ic)
	return b


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	lbl_place = _label(72, Color(0.75, 1.0, 0.2))
	lbl_place.position = Vector2(28, 10)
	root.add_child(lbl_place)
	lbl_lap = _label(34)
	lbl_lap.position = Vector2(32, 100)
	root.add_child(lbl_lap)

	lbl_count = _label(150, Color(1.0, 0.85, 0.2))
	lbl_count.set_anchors_preset(Control.PRESET_CENTER)
	lbl_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_count.size = Vector2(600, 220)
	lbl_count.position = -lbl_count.size * 0.5
	lbl_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(lbl_count)

	lbl_msg = _label(44, Color(1, 1, 1))
	lbl_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.size = Vector2(800, 60)
	lbl_msg.position = Vector2(-400, 150)
	root.add_child(lbl_msg)

	# item slot (top centre) with a live 3D preview
	item_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.05, 0.35, 0.75)
	sb.border_color = Color(0.7, 1.0, 0.2)
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(24)
	item_panel.add_theme_stylebox_override("panel", sb)
	item_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	item_panel.size = Vector2(150, 150)
	item_panel.position = Vector2(-150 - 130, 14)
	item_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(item_panel)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(10, 6)
	svc.size = Vector2(130, 110)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_panel.add_child(svc)
	item_view = SubViewport.new()
	item_view.own_world_3d = true
	item_view.transparent_bg = true
	item_view.size = Vector2i(130, 110)
	svc.add_child(item_view)
	var vc := Camera3D.new()
	vc.position = Vector3(0, 0.6, 3.2)
	vc.fov = 40
	item_view.add_child(vc)
	vc.look_at(Vector3(0, 0.1, 0))
	var vl := DirectionalLight3D.new()
	vl.rotation_degrees = Vector3(-40, 30, 0)
	item_view.add_child(vl)
	var venv := WorldEnvironment.new()
	var ve := Environment.new()
	ve.background_mode = Environment.BG_CLEAR_COLOR
	ve.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ve.ambient_light_color = Color(0.8, 0.8, 0.9)
	venv.environment = ve
	item_view.add_child(venv)
	item_holder = Node3D.new()
	item_view.add_child(item_holder)
	lbl_item = _label(22, Color(0.75, 1.0, 0.2))
	lbl_item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_item.position = Vector2(0, 112)
	lbl_item.size = Vector2(150, 30)
	item_panel.add_child(lbl_item)

	# rear-view mirror (top centre)
	var mframe := Panel.new()
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.1, 0.1, 0.12)
	msb.border_color = Color(0.12, 0.12, 0.14)
	msb.set_border_width_all(8)
	msb.set_corner_radius_all(26)
	mframe.add_theme_stylebox_override("panel", msb)
	mframe.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mframe.size = Vector2(380, 120)
	mframe.position = Vector2(-190, 10)
	mframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mframe)
	mirror_view = SubViewport.new()
	mirror_view.size = Vector2i(364, 104)
	mirror_view.world_3d = get_viewport().world_3d
	mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mframe.add_child(mirror_view)
	mirror_cam = Camera3D.new()
	mirror_cam.fov = 55
	mirror_cam.far = 120
	mirror_view.add_child(mirror_cam)
	mirror_cam.current = true
	var mtex := TextureRect.new()
	mtex.texture = mirror_view.get_texture()
	mtex.flip_h = true
	mtex.position = Vector2(8, 8)
	mtex.size = Vector2(364, 104)
	mtex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mtex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mframe.add_child(mtex)

	# touch controls
	var controls := Node2D.new()
	controls.name = "Controls"
	hud.add_child(controls)
	controls.add_child(_touch_button("res://ui/direction_left.png", "steer_left", Vector2.ZERO, 1.25))
	controls.add_child(_touch_button("res://ui/direction_right.png", "steer_right", Vector2.ZERO, 1.25))
	controls.add_child(_touch_button("res://ui/button_circle.png", "fire", Vector2.ZERO, 1.45, "res://ui/icon_fire.png"))
	controls.add_child(_touch_button("res://ui/button_circle.png", "pause", Vector2.ZERO, 0.8, "res://ui/icon_pause.png"))
	get_viewport().size_changed.connect(_layout_controls)
	_layout_controls()


func _layout_controls() -> void:
	var vs := get_viewport().get_visible_rect().size
	var c: Node2D = hud.get_node("Controls")
	var bl: TouchScreenButton = c.get_child(0)
	var br: TouchScreenButton = c.get_child(1)
	var fire: TouchScreenButton = c.get_child(2)
	var pau: TouchScreenButton = c.get_child(3)
	var s := bl.texture_normal.get_size() * bl.scale
	bl.position = Vector2(30, vs.y - s.y - 30)
	br.position = Vector2(30 + s.x + 40, vs.y - s.y - 30)
	var fs := fire.texture_normal.get_size() * fire.scale
	fire.position = Vector2(vs.x - fs.x - 40, vs.y - fs.y - 40)
	var ps := pau.texture_normal.get_size() * pau.scale
	pau.position = Vector2(vs.x - ps.x - 24, 20)


func _show_item_preview(item: String) -> void:
	if item == _shown_item:
		return
	_shown_item = item
	for ch in item_holder.get_children():
		ch.queue_free()
	lbl_item.text = ITEM_NAMES.get(item, "")
	item_panel.modulate = Color(1, 1, 1, 1.0 if item != "" else 0.5)
	var n: Node3D
	match item:
		"rocket":
			n = FX.make_rocket()
			n.scale = Vector3.ONE * 1.4
			n.rotation = Vector3(0.2, PI / 2.0, 0.3)
		"nails":
			n = FX.make_nails(rng, 4, 0.35)
			n.scale = Vector3.ONE * 1.3
		"oil":
			n = FX.make_oil()
			n.scale = Vector3.ONE * 0.6
			n.rotation.x = 0.9
		"zap":
			n = FX.make_zap_icon()
		_:
			return
	item_holder.add_child(n)


func flash_message(text: String, t := 1.4) -> void:
	lbl_msg.text = text
	_msg_time = t


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	# HUD
	if player != null:
		lbl_place.text = Game.place_text(ranking.find(player) + 1) if not player.finished else Game.place_text(player.place)
		lbl_lap.text = "LAP %d/%d" % [clampi(player.lap, 1, Game.LAPS), Game.LAPS]
		_show_item_preview(player.item)
	item_holder.rotation.y += delta * 1.5
	if _msg_time > 0.0:
		_msg_time -= delta
		lbl_msg.modulate.a = clampf(_msg_time * 2.0, 0, 1)
	for b in boxes:
		b["node"].rotation.y += delta * 1.8
		b["node"].position.y = 0.5 + sin(Time.get_ticks_msec() * 0.003 + b["pos"].x) * 0.15
	# engine pitch
	if engine:
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.6 + absf(player.speed) / player.max_speed * 1.6, delta * 3)
	if Input.is_action_just_pressed("pause") and state != "finished":
		_toggle_pause()


func _physics_process(dt: float) -> void:
	if state == "countdown":
		countdown -= dt
		var n := int(ceil(countdown - 0.6))
		lbl_count.text = str(n) if n >= 1 else "GO!"
		if countdown <= 0.6 and lbl_count.text == "GO!" and state == "countdown":
			state = "racing"
			get_tree().create_timer(0.8).timeout.connect(func(): lbl_count.text = "")
	var racing := state != "countdown"

	# player input
	if not player.ai:
		player.steer = Input.get_axis("steer_left", "steer_right")
		player.brake = Input.is_action_pressed("brake")
		if racing and Input.is_action_just_pressed("fire"):
			use_item(player)

	# AI
	for i in ranking.size():
		var c := ranking[i]
		if c.ai and racing:
			var ahead: Car = ranking[i - 1] if i > 0 else null
			var behind: Car = ranking[i + 1] if i + 1 < ranking.size() else null
			c.think(dt, ahead, behind)
			# rubber band
			var base: float = 17.5 * (Game.TRACKS[Game.track_index]["ai_speed"] if not c.is_player else 1.0)
			var gap := c.progress() - player.progress()
			var mult := 1.0
			if not c.is_player:
				if gap < -25:
					mult = 1.08
				elif gap > 40:
					mult = 0.94
			c.max_speed = lerpf(c.max_speed, base * mult, dt * 0.5)

	for c in cars:
		c.step(dt, racing)

	_car_collisions()
	_update_boxes(dt)
	_update_rockets(dt)
	_update_hazards(dt)
	_update_ranking()
	_update_camera(dt)


func _car_collisions() -> void:
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			var a := cars[i]
			var b := cars[j]
			var d := b.position - a.position
			d.y = 0
			var dist := d.length()
			if dist < 1.5 and dist > 0.001:
				var push := d / dist * (1.5 - dist) * 0.5
				a.position -= push
				b.position += push
				if a.heading().dot(d) > 0:
					a.speed *= 0.97
				else:
					b.speed *= 0.97


func _update_ranking() -> void:
	ranking.sort_custom(func(a: Car, b: Car) -> bool:
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.place < b.place
		return a.progress() > b.progress())
	for c in cars:
		if not c.finished and c.lap > Game.LAPS:
			c.finished = true
			finish_order.append(c)
			c.place = finish_order.size()
			if c == player:
				_player_finished()
	if state == "racing" and player.lap >= 2 and player.lap <= Game.LAPS and player.get_meta("lap_shown", 0) != player.lap:
		player.set_meta("lap_shown", player.lap)
		flash_message("FINAL LAP!" if player.lap == Game.LAPS else "LAP %d" % player.lap)


func _update_camera(dt: float, snap := false) -> void:
	var h := player.heading()
	var target_pos := player.position - h * 6.5 + Vector3.UP * 3.4
	var look := player.position + h * 4.0 + Vector3.UP * 0.8
	if snap:
		cam.position = target_pos
	else:
		cam.position = cam.position.lerp(target_pos, clampf(dt * 5.0, 0, 1))
	cam.look_at(look)
	if mirror_cam != null:
		mirror_cam.position = player.position + h * 0.2 + Vector3.UP * 1.6
		mirror_cam.look_at(player.position - h * 12.0 + Vector3.UP * 0.6)


# ---------------------------------------------------------------- items

func _update_boxes(dt: float) -> void:
	for b in boxes:
		if b["timer"] > 0.0:
			b["timer"] -= dt
			if b["timer"] <= 0.0:
				b["node"].visible = true
				b["node"].scale = Vector3.ONE * 0.2
				b["node"].create_tween().tween_property(b["node"], "scale", Vector3.ONE * 2.2, 0.3)
			continue
		for c in cars:
			if c.position.distance_to(b["pos"]) < 1.5:
				b["node"].visible = false
				b["timer"] = 3.0
				FX.burst(self, b["pos"] + Vector3.UP * 0.8, FX.TEX_STAR, Color(1, 0.9, 0.4), 14, 0.8, 6.0, 0.5)
				if c.item == "" and not c.finished:
					c.item = _roll_item(c)
					c.item_timer = rng.randf_range(0.8, 3.0)
				break


func _roll_item(c: Car) -> String:
	var rank := ranking.find(c)
	if rank == 0:
		return ["nails", "oil"][rng.randi() % 2]
	if rank >= 3:
		return ["rocket", "rocket", "zap", "zap", "nails", "oil"][rng.randi() % 6]
	return ITEMS[rng.randi() % ITEMS.size()]


func use_item(c: Car) -> void:
	if c.item == "" or c.is_stunned():
		return
	var it := c.item
	var rank := ranking.find(c)
	if (it == "rocket" or it == "zap") and _car_ahead(c, 60.0) == null:
		if c == player:
			flash_message("NO CAR AHEAD!", 0.8)
		return
	c.item = ""
	match it:
		"rocket":
			var target: Car = _car_ahead(c, 60.0)
			var node := FX.make_rocket()
			add_child(node)
			var p := c.position + c.heading() * 1.8 + Vector3.UP * 0.7
			node.position = p
			rockets.append({"node": node, "pos": p, "dir": c.heading(), "owner": c, "target": target, "life": 4.0, "puff": 0.0})
		"nails", "oil":
			var node: Node3D = FX.make_nails(rng) if it == "nails" else FX.make_oil()
			add_child(node)
			var p := c.position - c.heading() * 2.6
			p.y = 0.0
			node.position = p
			node.scale = Vector3.ONE * 0.2
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 0.25)
			hazards.append({"node": node, "pos": p, "kind": it, "owner": c, "life": 25.0, "safe": 0.6})
		"zap":
			var target: Car = null
			var best := 45.0
			for o in cars:
				if o == c or o.finished:
					continue
				var d := o.position.distance_to(c.position)
				var ahead := o.progress() > c.progress()
				if d < best and ahead:
					best = d
					target = o
			if target != null:
				FX.zap_effect(self, c.position, target.position)
				if target.hit("zap"):
					_on_car_hit(target, "ZAPPED!")
			else:
				FX.burst(self, c.position + Vector3.UP, FX.TEX_SPARK, Color(0.5, 0.85, 1.0), 16, 1.2, 4.0, 0.5)


## Nearest car ahead on the track (by race progress) within max_dist metres.
func _car_ahead(c: Car, max_dist: float) -> Car:
	var best: Car = null
	var best_gap := INF
	for o in cars:
		if o == c or o.finished:
			continue
		var gap := o.progress() - c.progress()
		if gap > 0.0 and gap < best_gap and o.position.distance_to(c.position) < max_dist:
			best_gap = gap
			best = o
	return best


func _update_rockets(dt: float) -> void:
	for r in rockets.duplicate():
		r["life"] -= dt
		var target: Car = r["target"]
		if target != null and not target.is_stunned():
			var want: Vector3 = (target.position + Vector3.UP * 0.7 - r["pos"]).normalized()
			r["dir"] = (r["dir"] as Vector3).slerp(want, clampf(dt * 3.0, 0, 1)).normalized()
		r["pos"] += r["dir"] * 34.0 * dt
		var node: Node3D = r["node"]
		node.position = r["pos"]
		node.look_at(r["pos"] + r["dir"], Vector3.UP, true)
		r["puff"] -= dt
		if r["puff"] <= 0.0:
			r["puff"] = 0.05
			FX.burst(self, r["pos"] - r["dir"] * 0.8, FX.TEX_SMOKE, Color(1, 1, 1, 0.8), 2, 0.9, 0.5, 0.5, false)
		var done: bool = r["life"] <= 0.0
		for c in cars:
			if c == r["owner"]:
				continue
			if c.position.distance_to(r["pos"]) < 1.6:
				if c.hit("rocket"):
					_on_car_hit(c, "BOOM!")
				done = true
				break
		if not done:
			if absf(_rocket_lateral(r)) > Track.HALF_W + 2.5:
				done = true
		if done:
			FX.explosion(self, r["pos"])
			node.queue_free()
			rockets.erase(r)


func _rocket_lateral(r: Dictionary) -> float:
	if not r.has("idx"):
		r["idx"] = (r["owner"] as Car).idx
	var loc := track.locate(r["pos"], r["idx"])
	r["idx"] = loc[0]
	return loc[2]


func _update_hazards(dt: float) -> void:
	for h in hazards.duplicate():
		h["life"] -= dt
		h["safe"] -= dt
		var gone: bool = h["life"] <= 0.0
		var radius := 1.5 if h["kind"] == "nails" else 1.9
		for c in cars:
			if c == h["owner"] and h["safe"] > 0.0:
				continue
			if c.position.distance_to(h["pos"]) < radius:
				if c.hit(h["kind"]):
					_on_car_hit(c, "FLAT TIRES!" if h["kind"] == "nails" else "SLIPPED!")
					gone = true
					break
		if gone:
			var node: Node3D = h["node"]
			var tw := node.create_tween()
			tw.tween_property(node, "scale", Vector3.ONE * 0.05, 0.25)
			tw.tween_callback(node.queue_free)
			hazards.erase(h)


func _on_car_hit(c: Car, text: String) -> void:
	FX.burst(self, c.position + Vector3.UP * 1.0, FX.TEX_STAR, Color(1, 1, 0.6), 10, 0.7, 5.0, 0.6)
	if c == player:
		flash_message(text)
		sfx_hit.play()
		Input.vibrate_handheld(120)
	elif c.position.distance_to(player.position) < 25:
		sfx_hit.volume_db = -8
		sfx_hit.play()
		sfx_hit.volume_db = 0


# ---------------------------------------------------------------- end / pause

func _player_finished() -> void:
	state = "finished"
	player.ai = true
	player.item = ""
	var place := player.place
	Game.record_result(Game.track_index, place)
	lbl_count.text = ""
	flash_message("FINISH!", 2.0)
	get_tree().create_timer(1.8).timeout.connect(_show_results)


func _show_results() -> void:
	# rank remaining cars by progress
	var order: Array[Car] = finish_order.duplicate()
	for c in ranking:
		if not order.has(c):
			order.append(c)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.15, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := _panel(Vector2(560, 600))
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 30
	vb.offset_right = -30
	vb.offset_top = 20
	vb.offset_bottom = -20
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := _label(56, Color(0.75, 1.0, 0.2))
	title.text = "YOU WIN!" if player.place == 1 else "%s PLACE" % Game.place_text(player.place).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for i in order.size():
		var c := order[i]
		var l := _label(28, Color(1, 0.9, 0.3) if c == player else Color.WHITE)
		l.text = "%s   %s" % [Game.place_text(i + 1), c.display_name]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	var unlocked_next := player.place <= 3 and Game.track_index + 1 < Game.TRACKS.size()
	var info := _label(22, Color(0.8, 0.8, 1.0))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "New track unlocked!" if unlocked_next else ("Finish in the top 3 to unlock the next track" if Game.track_index + 1 < Game.TRACKS.size() else "")
	vb.add_child(info)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	hb.add_child(make_button("MENU", func(): exit_to_menu.emit(), Color(0.45, 0.2, 0.8)))
	hb.add_child(make_button("RETRY", func(): restart.emit(Game.track_index), Color(0.95, 0.5, 0.1)))
	if unlocked_next:
		hb.add_child(make_button("NEXT", func(): restart.emit(Game.track_index + 1), Color(0.35, 0.75, 0.1)))
	# rating request after a win
	if player.place == 1 and not Game.rated and Game.rate_asks < 3:
		Game.rate_asks += 1
		Game.save_data()
		get_tree().create_timer(0.9).timeout.connect(func(): _show_rate(layer))


func _show_rate(layer: CanvasLayer) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := _panel(Vector2(620, 380))
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 30
	vb.offset_right = -30
	vb.offset_top = 25
	vb.offset_bottom = -25
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := _label(44, Color(0.75, 1.0, 0.2))
	t.text = "Awesome race!"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 5:
		var s := TextureRect.new()
		s.texture = load("res://ui/icon_star.png")
		s.modulate = Color(1, 0.85, 0.2)
		stars.add_child(s)
	vb.add_child(stars)
	var m := _label(26)
	m.text = "Do you like Crazy Toy Cars?\nPlease rate us on Google Play!"
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(m)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var close := func():
		dim.queue_free()
		panel.queue_free()
	hb.add_child(make_button("LATER", close, Color(0.45, 0.2, 0.8)))
	hb.add_child(make_button("RATE NOW", func():
		Game.open_store_page()
		close.call(), Color(0.35, 0.75, 0.1)))


func _panel(sz: Vector2) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.05, 0.3, 0.96)
	sb.border_color = Color(0.7, 1.0, 0.2)
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(30)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = sz
	panel.position = -sz * 0.5
	return panel


static func make_button(text: String, cb: Callable, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 70)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.2))
	b.add_theme_constant_override("outline_size", 6)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.15) if st == "hover" else (col.darkened(0.2) if st == "pressed" else col)
		sb.set_corner_radius_all(22)
		sb.border_color = Color(1, 1, 1, 0.8)
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _toggle_pause() -> void:
	if pause_layer != null:
		pause_layer.queue_free()
		pause_layer = null
		get_tree().paused = false
		return
	get_tree().paused = true
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 6
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.15, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var panel := _panel(Vector2(480, 330))
	pause_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)
	var t := _label(52, Color(0.75, 1.0, 0.2))
	t.text = "PAUSED"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	hb.add_child(make_button("MENU", func():
		get_tree().paused = false
		exit_to_menu.emit(), Color(0.45, 0.2, 0.8)))
	hb.add_child(make_button("RESUME", _toggle_pause, Color(0.35, 0.75, 0.1)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and state != "finished":
		_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED and pause_layer == null and state == "racing":
		_toggle_pause()
