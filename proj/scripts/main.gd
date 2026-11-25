extends Node
## Switches between the menu and a race.

var current: Node


func _ready() -> void:
	get_tree().set_auto_accept_quit(true)
	get_tree().quit_on_go_back = false
	show_menu()
	var args := OS.get_cmdline_user_args()
	if args.has("--autotest"):
		_autotest(args)


## Development helper: saves screenshots (not used in normal play).
func _autotest(args: PackedStringArray) -> void:
	var out := "/tmp/ctc"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(out + "/menu.png")
	var ti := 0
	for a in args:
		if a.begins_with("--track="):
			ti = int(a.substr(8))
	Game.unlocked = 3
	start_race(ti)
	var r = current
	if args.has("--aiplayer"):
		r.player.ai = true
	var shots := [[4.5, ""], [2.0, "rocket"], [0.25, ""], [0.5, "nails"], [0.7, ""], [1.0, ""], [1.0, "zap"], [0.15, ""], [3.0, "oil"], [0.3, ""], [6.0, "finish"], [3.5, ""], [1.5, ""]]
	if args.has("--fx"):
		shots = [[4.5, "freeze"], [0.5, "give"], [0.6, ""], [0.1, "rocket"], [0.1, ""], [0.1, ""], [0.15, ""], [0.3, ""], [0.3, "nails"], [0.25, ""], [0.3, ""], [0.5, ""], [0.8, ""], [0.5, ""], [0.6, "oil"], [0.5, "zap"], [0.1, ""]]
	var k := 0
	for sdef in shots:
		await get_tree().create_timer(sdef[0]).timeout
		match sdef[1]:
			"rocket":
				r.player.item = "rocket"; r.use_item(r.player)
			"nails":
				r.player.hit("nails")
			"zap":
				r.player.item = "zap"; r.use_item(r.player)
			"oil":
				r.player.item = "oil"; r.use_item(r.player)
			"freeze":
				for c in r.cars:
					c.max_speed = 0.0
					c.speed = 0.0
					c.ai = false
					c.item = ""
				r.boxes.clear()
				r.player.position += r.player.heading() * -6.0
			"give":
				r.player.item = "rocket"
			"finish":
				r.player.lap = Game.LAPS + 1
		get_viewport().get_texture().get_image().save_png(out + "/shot_%02d_%s.png" % [k, sdef[1]])
		k += 1
	get_tree().quit()


func _swap(n: Node) -> void:
	if current != null:
		current.queue_free()
	current = n
	add_child(n)


func show_menu() -> void:
	get_tree().paused = false
	var m: Control = preload("res://scripts/menu.gd").new()
	m.start_race.connect(start_race)
	_swap(m)


func start_race(track_i := -1) -> void:
	if track_i >= 0:
		Game.track_index = track_i
		Game.save_data()
	get_tree().paused = false
	var r: Node3D = preload("res://scripts/race.gd").new()
	r.exit_to_menu.connect(show_menu)
	r.restart.connect(start_race)
	_swap(r)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and current != null and current is Control:
		get_tree().quit()
