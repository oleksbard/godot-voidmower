class_name DayNight
extends Node3D
## Drives a continuous day/night cycle: the sun rises/sets low across the back
## horizon, an invisible moon orbits and keys the night, night stays legible, and
## exactly one directional light casts shadows at a time. Owns the sun + moon
## lights, the emissive sun disk, and the starfield; animates the Environment's
## time-of-day properties. Cycle math is pure + static so it is unit-testable.

signal time_changed(day: int, hour: float)   # emitted when the displayed minute changes

const CYCLE_SECONDS := 60.0   # full day length (s); longer = calmer sun/shadow/clock motion

# Sun: kept low at the back; azimuth sweeps side-to-side, elevation gently rises.
# A gentle arc (small sweep) keeps shadows drifting slowly so a fast 1-min day
# still reads as a calm, steady golden hour rather than light whipping around.
const SUN_MAX_ELEV := deg_to_rad(18.0)
const SUN_AZIMUTH := deg_to_rad(32.0)
const SUN_ENERGY := 1.8
const SUN_DAY_COLOR := Color(0.965, 0.894, 0.792)   # warm cream
const SUN_DUSK_COLOR := Color(1.0, 0.50, 0.27)      # orange
# No visible sun disk: the sun is meant to be distant, and the orthographic
# top-down camera can't frame a far back-horizon sun without adding a sky dome
# (we keep the void). The warm directional light + glow/bloom carry the mood.

# Moon: invisible light orbiting the island.
const MOON_ELEV := deg_to_rad(35.0)
const MOON_ENERGY := 0.55
const MOON_COLOR := Color(0.62, 0.70, 0.88)         # cool blue

# Night legibility ("not too dark").
const DAY_EXPOSURE := 1.25
const NIGHT_EXPOSURE := 1.5
const DAY_AMBIENT_ENERGY := 0.7
const NIGHT_AMBIENT_ENERGY := 0.5
const DAY_AMBIENT_COLOR := Color(0.46, 0.52, 0.60)
const NIGHT_AMBIENT_COLOR := Color(0.30, 0.36, 0.52)
const DAY_BG := Color(0.02, 0.018, 0.025)
const NIGHT_BG := Color(0.01, 0.014, 0.03)

# Stars: dim by day, bright at night.
const STAR_DAY := 0.6
const STAR_NIGHT := 2.8

const SHADOW_MAX_DIST := 45.0

var environment: Environment    # set by Main before this node is added to the tree

var _elapsed := 0.0
var _last_minute := -1
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _star_mat: StandardMaterial3D


## Cycle phase in [0,1): 0 dawn, 0.25 midday, 0.5 dusk, 0.75 deep night.
static func phase_at(elapsed: float) -> float:
	return fposmod(elapsed / CYCLE_SECONDS, 1.0)


## Sun altitude driver: +1 at midday, 0 at dawn/dusk, -1 at deep night.
static func sun_height(t: float) -> float:
	return sin(t * TAU)


## 1 by day, 0 at night, with a soft band through dawn/dusk.
static func dayness(t: float) -> float:
	return smoothstep(-0.15, 0.30, sun_height(t))


## True when the sun is the dominant light (and thus the shadow caster).
static func sun_casts(t: float) -> bool:
	return dayness(t) >= 0.5


## Clock hours [0,24) for phase t: dawn 06:00, midday 12:00, dusk 18:00, midnight 00:00.
static func clock_hours(t: float) -> float:
	return fposmod(t * 24.0 + 6.0, 24.0)


## 1-based day count for elapsed seconds (a new day begins each dawn).
static func day_number(elapsed: float) -> int:
	return int(elapsed / CYCLE_SECONDS) + 1


func _ready() -> void:
	_build_sun()
	_build_moon()
	_build_starfield()
	_apply(phase_at(_elapsed))


func _process(delta: float) -> void:
	_elapsed += delta
	var t := phase_at(_elapsed)
	_apply(t)
	_emit_time(t)


## Announce day + time, but only when the displayed minute actually changes.
func _emit_time(t: float) -> void:
	var minute := int(clock_hours(t) * 60.0)
	if minute == _last_minute:
		return
	_last_minute = minute
	time_changed.emit(day_number(_elapsed), clock_hours(t))


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.light_color = SUN_DAY_COLOR
	_sun.light_energy = SUN_ENERGY
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = SHADOW_MAX_DIST
	add_child(_sun)


func _build_moon() -> void:
	_moon = DirectionalLight3D.new()
	_moon.light_color = MOON_COLOR
	_moon.light_energy = 0.0
	_moon.shadow_enabled = false
	_moon.shadow_blur = 1.0
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_moon.directional_shadow_max_distance = SHADOW_MAX_DIST
	add_child(_moon)


func _build_starfield() -> void:
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.6, 0.6, 0.6)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.albedo_color = Color(1.0, 1.0, 1.0)
	_star_mat.emission_enabled = true
	_star_mat.emission = Color(0.9, 0.93, 1.0)
	_star_mat.emission_energy_multiplier = STAR_NIGHT
	star_mesh.material = _star_mat

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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Apply the celestial + environment state for cycle phase `t`.
func _apply(t: float) -> void:
	var day := dayness(t)
	var night := 1.0 - day
	var sh := sun_height(t)

	# Sun: low arc across the back. Light shines from sun_dir toward the island.
	var az := SUN_AZIMUTH * cos(t * TAU)
	var elev := SUN_MAX_ELEV * sh
	var sun_dir := Basis(Vector3.UP, az) * (Basis(Vector3.RIGHT, elev) * Vector3(0.0, 0.0, -1.0))
	_sun.global_position = sun_dir
	_sun.look_at(Vector3.ZERO, Vector3.UP)
	var dusk := 1.0 - clampf(sh, 0.0, 1.0)
	_sun.light_color = SUN_DAY_COLOR.lerp(SUN_DUSK_COLOR, dusk)
	_sun.light_energy = SUN_ENERGY * day

	# Moon: invisible light orbiting the island.
	var moon_dir := Basis(Vector3.UP, t * TAU) * (Basis(Vector3.RIGHT, MOON_ELEV) * Vector3(0.0, 0.0, -1.0))
	_moon.global_position = moon_dir
	_moon.look_at(Vector3.ZERO, Vector3.UP)
	_moon.light_energy = MOON_ENERGY * night

	# Exactly one shadow caster.
	var sun_dom := sun_casts(t)
	_sun.shadow_enabled = sun_dom
	_moon.shadow_enabled = not sun_dom

	# Environment time-of-day.
	if environment != null:
		environment.tonemap_exposure = lerpf(DAY_EXPOSURE, NIGHT_EXPOSURE, night)
		environment.ambient_light_energy = lerpf(DAY_AMBIENT_ENERGY, NIGHT_AMBIENT_ENERGY, night)
		environment.ambient_light_color = DAY_AMBIENT_COLOR.lerp(NIGHT_AMBIENT_COLOR, night)
		environment.background_color = DAY_BG.lerp(NIGHT_BG, night)

	# Stars: fade in after dusk.
	if _star_mat != null:
		_star_mat.emission_energy_multiplier = lerpf(STAR_DAY, STAR_NIGHT, night)
