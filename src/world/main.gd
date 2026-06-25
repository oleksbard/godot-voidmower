class_name Main
extends Node3D
## Composition root for the floating-island mower prototype.
##
## Builds the world (environment, day/night cycle, island) and the follow camera,
## instantiates the features (player, grass, HUD) and wires them together.
## Stateless building blocks live in src/lib/*; the island mesh lives in
## src/world/island_builder.gd; the sun/moon/stars live in src/world/day_night.gd.
## This script only composes — it holds no helpers.
##
## Art direction (see CLAUDE.md): procedural geometry only; warm key + cool fill;
## ACES tone mapping + bloom + SSAO (Forward+); orthographic diorama camera.

const IslandBuilder := preload("res://src/world/island_builder.gd")

const CAM_OFFSET := Vector3(0.0, 13.0, 7.0)
const CAM_SIZE := 18.0             # orthographic vertical extent (smaller = closer)

var player: Node3D
var grass: Node3D
var day_night: Node3D
var camera: Camera3D


func _ready() -> void:
	var env := _build_environment()
	_build_day_night(env)
	add_child(IslandBuilder.build())

	var captain_visit := preload("res://src/captain/captain_visit.gd").new()
	add_child(captain_visit)

	# preload by path (not bare class_name) so loading doesn't depend on the
	# editor having built the global class cache — works on a cold clone / CI.
	player = preload("res://src/player/player.gd").new()
	add_child(player)

	grass = preload("res://src/grass/grass_field.gd").new()
	grass.player = player
	add_child(grass)

	var hud := preload("res://src/ui/hud.gd").new()
	add_child(hud)

	var drops := preload("res://src/drops/drop_field.gd").new()
	drops.player = player
	add_child(drops)

	var hotbar := preload("res://src/inventory/hotbar.gd").new()
	add_child(hotbar)

	player.swing.connect(grass.on_swing)
	day_night.time_changed.connect(hud.set_time)
	grass.item_dropped.connect(drops.spawn)
	drops.collected.connect(hotbar.add_item.bind(1))      # one item per collected token
	hotbar.active_tool_changed.connect(player.set_active_tool)
	day_night.time_changed.connect(captain_visit.on_time)
	captain_visit.presence_changed.connect(player.set_visit_block)

	_build_camera()


func _build_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)            # deep space
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.52, 0.60)          # cool fill (less blue)
	env.ambient_light_energy = 0.7                             # keep shadowed ground lit

	# Tone mapping + exposure — the single biggest "feel" lever.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25

	# Glow / bloom so emissive accents and bright highlights pop.
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.05
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.95
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 1.0)

	# SSAO grounds objects (grass into soil, player onto ground). Kept gentle so
	# dense grass doesn't crush the ground beneath a mowed patch to black.
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.1
	env.ssao_power = 1.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	return env


func _build_day_night(env: Environment) -> void:
	# Owns the sun + moon lights and the starfield; animates the environment's
	# time-of-day properties over a 60s cycle and emits day/time for the HUD.
	day_night = preload("res://src/world/day_night.gd").new()
	day_night.environment = env
	add_child(day_night)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL   # clean diorama look
	camera.size = CAM_SIZE
	camera.position = player.global_position + CAM_OFFSET
	camera.rotation = Vector3(-atan2(CAM_OFFSET.y, CAM_OFFSET.z), 0.0, 0.0)
	camera.current = true
	add_child(camera)


func _process(_delta: float) -> void:
	if player == null or camera == null:
		return
	camera.global_position = player.global_position + CAM_OFFSET
