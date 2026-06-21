class_name Main
extends Node3D
## Composition root for the floating-island mower prototype.
##
## Builds the world (environment, starfield, sun, island) and the follow camera,
## instantiates the features (player, grass, HUD) and wires them together.
## Stateless building blocks live in src/lib/*; the island mesh lives in
## src/world/island_builder.gd. This script only composes — it holds no helpers.
##
## Art direction (see CLAUDE.md): procedural geometry only; warm key + cool fill;
## ACES tone mapping + bloom + SSAO (Forward+); orthographic diorama camera.

const IslandBuilder := preload("res://src/world/island_builder.gd")

const CAM_OFFSET := Vector3(0.0, 13.0, 7.0)
const CAM_SIZE := 18.0             # orthographic vertical extent (smaller = closer)

var player: Node3D
var grass: Node3D
var camera: Camera3D


func _ready() -> void:
	_build_environment()
	_build_starfield()
	_build_sun()
	add_child(IslandBuilder.build())

	# preload by path (not bare class_name) so loading doesn't depend on the
	# editor having built the global class cache — works on a cold clone / CI.
	player = preload("res://src/player/player.gd").new()
	add_child(player)

	grass = preload("res://src/grass/grass_field.gd").new()
	grass.player = player
	add_child(grass)

	var hud := preload("res://src/ui/hud.gd").new()
	add_child(hud)

	player.swing.connect(grass.on_swing)
	grass.mowed_changed.connect(hud.set_count)

	_build_camera()


func _build_environment() -> void:
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


func _build_starfield() -> void:
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.6, 0.6, 0.6)

	# Emissive + over-bright so the glow pass blooms them into twinkles.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.93, 1.0)
	mat.emission_energy_multiplier = 2.6
	star_mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 500

	var rng := RandomNumberGenerator.new()
	rng.seed = 20240620
	for i in mm.instance_count:
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var radius := rng.randf_range(80.0, 150.0)
		var s := rng.randf_range(0.4, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), dir * radius))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.965, 0.894, 0.792)   # warm cream (#f6e4ca)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	add_child(sun)


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
