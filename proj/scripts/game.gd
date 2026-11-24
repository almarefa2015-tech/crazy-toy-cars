extends Node
## Global game data: cars, tracks, save file, input setup.

const PACKAGE := "com.khaled.crazytoycars"
const SAVE_PATH := "user://save.cfg"
const LAPS := 3

const CARS := [
	{"name": "Racer", "model": "res://models/toy/vehicle-racer.glb"},
	{"name": "Speedster", "model": "res://models/toy/vehicle-speedster.glb"},
	{"name": "Monster Truck", "model": "res://models/toy/vehicle-monster-truck.glb"},
	{"name": "Drag Racer", "model": "res://models/toy/vehicle-drag-racer.glb"},
	{"name": "Vintage Racer", "model": "res://models/toy/vehicle-vintage-racer.glb"},
	{"name": "Low Racer", "model": "res://models/toy/vehicle-racer-low.glb"},
	{"name": "Toy SUV", "model": "res://models/toy/vehicle-suv.glb"},
	{"name": "Toy Truck", "model": "res://models/toy/vehicle-truck.glb"},
]

const TRACKS := [
	{"name": "Sunny Park", "moves": "RRRRRRRRDDDLLLDDDLLLLLUUUUUU", "seed": 11,
		"sky_top": Color(0.35, 0.6, 1.0), "sky_horizon": Color(0.75, 0.88, 1.0), "sun": 1.3, "sun_color": Color(1, 0.97, 0.9), "sun_angle": -50.0, "ai_speed": 0.93},
	{"name": "Twisty Town", "moves": "RRRRRDDRRRDDDLLDDLLLLLLUULUUUUUR", "seed": 23,
		"sky_top": Color(0.45, 0.4, 0.95), "sky_horizon": Color(1.0, 0.75, 0.6), "sun": 1.15, "sun_color": Color(1, 0.85, 0.7), "sun_angle": -30.0, "ai_speed": 0.97},
	{"name": "Dusk Speedway", "moves": "RRRRRRRRDDDDDLLLUULLLDDDDLLUUUUUUU", "seed": 37,
		"sky_top": Color(0.15, 0.12, 0.4), "sky_horizon": Color(0.95, 0.45, 0.45), "sun": 0.9, "sun_color": Color(1, 0.7, 0.55), "sun_angle": -22.0, "ai_speed": 1.0},
]

var car_index := 0
var track_index := 0
var unlocked := 1
var best := {}          # track index (String) -> best place
var rated := false
var rate_asks := 0


func _ready() -> void:
	_setup_input()
	load_data()


func _setup_input() -> void:
	var map := {
		"steer_left": [KEY_A, KEY_LEFT],
		"steer_right": [KEY_D, KEY_RIGHT],
		"fire": [KEY_SPACE, KEY_W, KEY_UP],
		"brake": [KEY_S, KEY_DOWN],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func load_data() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	car_index = int(cf.get_value("game", "car", 0))
	track_index = int(cf.get_value("game", "track", 0))
	unlocked = int(cf.get_value("game", "unlocked", 1))
	best = cf.get_value("game", "best", {})
	rated = bool(cf.get_value("game", "rated", false))
	rate_asks = int(cf.get_value("game", "rate_asks", 0))
	car_index = clampi(car_index, 0, CARS.size() - 1)
	unlocked = clampi(unlocked, 1, TRACKS.size())
	track_index = clampi(track_index, 0, unlocked - 1)


func save_data() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "car", car_index)
	cf.set_value("game", "track", track_index)
	cf.set_value("game", "unlocked", unlocked)
	cf.set_value("game", "best", best)
	cf.set_value("game", "rated", rated)
	cf.set_value("game", "rate_asks", rate_asks)
	cf.save(SAVE_PATH)


func record_result(track: int, place: int) -> void:
	var key := str(track)
	if not best.has(key) or place < int(best[key]):
		best[key] = place
	if place <= 3 and track + 1 < TRACKS.size():
		unlocked = maxi(unlocked, track + 2)
	save_data()


func open_store_page() -> void:
	rated = true
	save_data()
	if OS.get_name() == "Android":
		OS.shell_open("market://details?id=" + PACKAGE)
	else:
		OS.shell_open("https://play.google.com/store/apps/details?id=" + PACKAGE)


func place_text(p: int) -> String:
	match p:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % p
