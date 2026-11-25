extends Control
## Main menu: title art, car picker with 3D preview, track picker.

signal start_race

var car_holder: Node3D
var lbl_car: Label
var lbl_track: Label
var lbl_track_info: Label
var btn_race: Button
var lock_icon: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport().get_visible_rect().size)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var art := TextureRect.new()
	art.texture = load("res://title.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.anchor_left = 0.0
	art.anchor_right = 0.42
	art.anchor_top = 0.0
	art.anchor_bottom = 1.0
	add_child(art)

	var right := VBoxContainer.new()
	right.anchor_left = 0.44
	right.anchor_right = 0.98
	right.anchor_top = 0.04
	right.anchor_bottom = 0.96
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 10)
	add_child(right)

	var h1 := _label("CHOOSE YOUR CAR", 34, Color(0.75, 1.0, 0.2))
	right.add_child(h1)

	# car preview
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(row)
	row.add_child(_arrow("res://ui/direction_left.png", func(): _change_car(-1)))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(360, 240)
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 3.0)
	cam.fov = 40
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.25, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	light.light_energy = 1.2
	vp.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.7, 0.95)
	env.ambient_light_energy = 0.8
	we.environment = env
	vp.add_child(we)
	var turntable := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.05
	cyl.height = 0.08
	turntable.mesh = cyl
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.55, 0.25, 0.85)
	tm.emission_enabled = true
	tm.emission = Color(0.35, 0.9, 0.1)
	tm.emission_energy_multiplier = 0.35
	turntable.material_override = tm
	turntable.position.y = -0.04
	vp.add_child(turntable)
	car_holder = Node3D.new()
	vp.add_child(car_holder)
	row.add_child(_arrow("res://ui/direction_right.png", func(): _change_car(1)))

	lbl_car = _label("", 30)
	right.add_child(lbl_car)

	var h2 := _label("TRACK", 30, Color(0.75, 1.0, 0.2))
	right.add_child(h2)
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 14)
	right.add_child(trow)
	trow.add_child(_arrow("res://ui/direction_left.png", func(): _change_track(-1), 0.6))
	lock_icon = TextureRect.new()
	lock_icon.texture = load("res://ui/icon_lock.png")
	lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock_icon.custom_minimum_size = Vector2(44, 44)
	lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trow.add_child(lock_icon)
	lbl_track = _label("", 32)
	lbl_track.custom_minimum_size = Vector2(300, 0)
	trow.add_child(lbl_track)
	trow.add_child(_arrow("res://ui/direction_right.png", func(): _change_track(1), 0.6))
	lbl_track_info = _label("", 22, Color(0.8, 0.8, 1.0))
	right.add_child(lbl_track_info)

	btn_race = preload("res://scripts/race.gd").make_button("RACE!", func(): start_race.emit(), Color(0.35, 0.75, 0.1))
	btn_race.custom_minimum_size = Vector2(300, 90)
	btn_race.add_theme_font_size_override("font_size", 46)
	btn_race.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(btn_race)

	_change_car(0)
	_change_track(0)


func _process(delta: float) -> void:
	car_holder.rotation.y += delta * 0.9


func _label(text: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.3))
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	return l


func _arrow(tex: String, cb: Callable, s := 0.8) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = load(tex)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var sz: Vector2 = b.texture_normal.get_size() * s
	b.custom_minimum_size = sz
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b


func _change_car(d: int) -> void:
	Game.car_index = posmod(Game.car_index + d, Game.CARS.size())
	Game.save_data()
	for ch in car_holder.get_children():
		ch.queue_free()
	var m: Node3D = Game.make_car_model(Game.CARS[Game.car_index]["model"], 1.9)
	car_holder.add_child(m)
	lbl_car.text = Game.CARS[Game.car_index]["name"]


func _change_track(d: int) -> void:
	Game.track_index = posmod(Game.track_index + d, Game.TRACKS.size())
	var locked := Game.track_index >= Game.unlocked
	lbl_track.text = Game.TRACKS[Game.track_index]["name"]
	lock_icon.visible = locked
	btn_race.disabled = locked
	btn_race.modulate = Color(1, 1, 1, 0.45 if locked else 1.0)
	var key := str(Game.track_index)
	if locked:
		lbl_track_info.text = "Finish top 3 on the previous track to unlock"
	elif Game.best.has(key):
		lbl_track_info.text = "Best: %s place" % Game.place_text(int(Game.best[key]))
	else:
		lbl_track_info.text = "%d laps  -  6 racers" % Game.LAPS
	if not locked:
		Game.save_data()
