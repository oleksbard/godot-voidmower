# Testing

Lightweight testing strategy for a Godot prototype using
[**gdUnit4**](https://github.com/godot-gdunit-labs/gdunit4) — an embedded
framework with test discovery, fluent assertions, mocking, a scene runner, and
headless CI support.

## What to test (and what not to)

Prototypes change fast, so test the **stable, pure, deterministic core** — the
logic that's easy to get subtly wrong and painful to eyeball:

- **Shape / math functions** — e.g. `IslandShape.radius(angle)` is bounded,
  periodic, deterministic.
- **Generators / RNG ranges** — given a fixed seed, blade heights stay within
  `[MIN_HEIGHT, MAX_HEIGHT]`; the colour-variance helper stays in `[0,1]`.
- **Geometry builders** — `MeshFactory.beveled_box` produces the expected vertex
  count and an AABB matching `size`.
- **State machines / counters** — mow count increments once per cut.

**Don't** unit-test rendering, exact pixel output, or "does it look good" — that
stays a manual check in the window. Keep determinism by always passing a seeded
`RandomNumberGenerator`.

## Setup

1. Install the `addons/gdUnit4/` plugin (AssetLib or git), enable it in
   *Project Settings → Plugins*.
2. Put suites under `test/`, mirroring `src/` (`test/lib/island_shape_test.gd`).
3. Name suites `*_test.gd`; each `extends GdUnitTestSuite`.

## Writing a test

```gdscript
extends GdUnitTestSuite

func test_island_radius_is_bounded() -> void:
    for i in 360:
        var r := IslandShape.radius(deg_to_rad(i))
        assert_float(r).is_between(IslandShape.BASE * 0.5, IslandShape.BASE * 1.5)

func test_color_variance_stays_in_gamut() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    var c := ColorUtil.vary(Color(0.3, 0.6, 0.2), rng)
    assert_float(c.s).is_between(0.0, 1.0)
    assert_float(c.v).is_between(0.0, 1.0)
```

## Node behavior — `scene_runner`

For things that need the tree (input, movement, signals), wrap a scene and drive
frames:

```gdscript
func test_player_stays_on_island() -> void:
    var runner := scene_runner("res://main.tscn")
    runner.simulate_key_pressed(KEY_W)
    await runner.simulate_frames(120)
    var p := runner.find_child("Player")
    var d := Vector2(p.position.x, p.position.z).length()
    assert_float(d).is_less_equal(IslandShape.radius(...))   # never walked off
```

Use `assert_signal(node).is_emitted("grass_mowed")` to verify the swing→cut→count
chain. Use `mock()` / `verify()` to isolate a unit from its collaborators.

## Running

```sh
# Local
GODOT_BIN=/path/to/godot ./addons/gdUnit4/runtest.sh -a res://test/

# CI / headless (add --ignoreHeadlessMode if a suite needs it)
GODOT_BIN=/path/to/godot ./addons/gdUnit4/runtest.sh -a res://test/ --continue
```

Wire this into CI so tests run on every push; keep them fast (the pure-logic
core runs in milliseconds).

## In this project

There are no tests yet. The refactor's final phase extracts pure helpers
(`IslandShape`, `ColorUtil`, `MeshFactory`, grass planting math) specifically so
they become testable, then adds suites for them plus one `scene_runner`
integration test for the move→mow loop.
