# Refactor plan

Bring the prototype in line with [`docs/guidelines/`](guidelines/). Phases are
ordered **low-risk → high-risk** and each is **independently shippable**: every
phase ends with the headless validation (and, from Phase 5, the test suite)
green. No phase changes gameplay feel except where explicitly noted.

> **Safety net:** this isn't a git repo yet. Recommended before starting:
> `git init && git add -A && git commit -m "baseline"` so each phase is a commit
> you can revert. Gate after every phase:
> `Godot --headless --path . --quit-after 120` must exit 0 with no errors.

## Smell → rule → fix

| Smell (today) | Rule violated | Fix (phase) |
| --- | --- | --- |
| `Main.gd` is composition root **and** utility library **and** world builder | single responsibility; structure | split into `src/lib/*` + `src/world/*` (P2) |
| `Player`/`GrassField` do `preload("res://Main.gd")` for helpers | reuse/decoupling | call `class_name` utilities (P2) |
| Flat root, no `class_name` | structure; code-quality | feature folders + `class_name` (P1) |
| ~2,500 individual grass node-pairs | performance (MultiMesh) | MultiMesh grass (P4) |
| Mesh assembly mixed with control logic | single responsibility | split builders from controllers (P3) |
| No tests | testing | gdUnit4 suites on extracted logic (P5) |

---

## Phase 1 — Folders + `class_name` (mechanical, low risk) — ✅ DONE

**Goal:** the layout from [project-structure.md](guidelines/project-structure.md); no logic changes.

> **Note from execution:** bare `class_name` (`Player.new()`) does **not** resolve
> on a cold run — the global class cache is built by the editor scan, which a
> fresh `--path` / CI run hasn't done. So cross-script **loading stays on
> `preload()` consts** (order-independent, portable); `class_name` is kept for
> typing/editor only. This applies to the `src/lib/*` utilities too (P2).

Steps:
1. Create `src/{world,player,grass,ui,lib}/` and `test/`.
2. Move + rename (snake_case): `Main.gd → src/world/main.gd`, `Player.gd →
   src/player/player.gd`, `GrassField.gd → src/grass/grass_field.gd`,
   `Hud.gd → src/ui/hud.gd`. Rename `Main.tscn → main.tscn`.
3. Add `class_name` to each (`Main`, `Player`, `GrassField`, `Hud`).
4. Update references: `project.godot` `run/main_scene="res://main.tscn"`;
   `main.tscn`'s ext_resource path; in `main.gd` replace
   `preload("res://Player.gd").new()` with `Player.new()` (etc.).

**Verify:** headless run exits 0; game still launches and plays identically.
**Risk:** low (paths only). **Effort:** ~30 min.

---

## Phase 2 — Extract the shared library (kill the god-object) — ✅ DONE

**Goal:** stateless helpers leave `main.gd`; features stop depending on it.

Create `class_name` utilities in `src/lib/`:
- `color_util.gd` → `ColorUtil.vary(c, rng)`.
- `texture_factory.gd` → `TextureFactory.pixel/speckled/gradient/material(...)`.
- `mesh_factory.gd` → `MeshFactory.beveled_box(size, bevel)` (+ its `_bev_tri/_bev_quad`).
- `island_shape.gd` → `IslandShape.BASE`, `IslandShape.radius(angle)`,
  `IslandShape.ring_vertex(rs, y, i, seg)`.

Then:
1. Move the corresponding statics out of `main.gd` into those files.
2. Move island **mesh assembly** (rings, rocks, `_island_material`) into
   `src/world/island_builder.gd` (a node or static builder) that consumes
   `IslandShape` + `MeshFactory` + `ColorUtil` + `TextureFactory`.
3. In `player.gd` / `grass_field.gd`, delete `const Art := preload("res://Main.gd")`
   and call the utilities by `class_name` (`MeshFactory.beveled_box`,
   `ColorUtil.vary`, `IslandShape.radius`, `TextureFactory.*`).
4. `main.gd` shrinks to: environment, starfield, sun, camera, instantiate
   features, wire signals.

**Verify:** headless run exits 0; identical visuals. **Risk:** low–medium (pure
moves; watch for missed call sites). **Effort:** ~1–2 h.

---

## Phase 3 — Split responsibilities within features

**Goal:** each script does one job ([code-quality](guidelines/code-quality.md)).

- **Player:** extract the box-assembly into `player_rig.gd` (builds the beveled
  humanoid, exposes limb pivots); `player.gd` keeps input, movement, animation,
  edge clamp, and the `swing` signal. (Optional: promote `player.tscn`.)
- **GrassField:** separate concerns into clearly-named private regions or small
  helper objects: planting, bend+wind, cut+regrow, clipping FX. If
  `grass_field.gd` stays one file, at minimum group these into well-named
  methods with no cross-talk beyond the blade-state array.
- Promote remaining magic numbers (mesh offsets/sizes) to named constants.

**Verify:** headless run exits 0; identical behavior. **Risk:** medium. **Effort:** ~1–2 h.

---

## Phase 4 — Grass → MultiMesh (the performance phase)

**Goal:** the documented win — thousands of blades in **one draw call**.
([performance.md](guidelines/performance.md)). Highest risk; do it on its own.

Design:
- One `MultiMeshInstance3D` with `instance_count = N`. Per-blade state in
  parallel arrays: `base_pos`, `base_h`, `width`, `base_tilt`, `wind_phase`,
  `state` (alive/cut/regrowing), `regrow_at`.
- **Bend/wind:** each frame, update transforms only for instances within the
  player's bend radius, plus a cheap global wind pass (throttle the far field
  with `Engine.get_physics_frames() % N`). Write via `set_instance_transform`.
- **Cut:** scale a cut instance's transform to ~0 (hides it); keep the existing
  one-shot clipping particle burst; optionally a few transient "flying blade"
  nodes for the pop (can't tween a MultiMesh instance like a node). Regrow by
  scaling the instance back up over `GROW_TIME`.
- **Flowers stay as real nodes** (multi-part, rare) — split them into their own
  small `flower_field.gd` so grass is purely MultiMesh.

**Fallback if per-instance animation gets too fiddly:** keep nodes but cut count
(coarser `SPACING`) and add distance-based culling; revisit later. Document
whichever path is taken.

**Verify:** headless run exits 0; **measure** draw calls + frame time before/after
in the Profiler/Monitor; bend/cut/regrow still feel right in the window.
**Risk:** high. **Effort:** ~half a day.

---

## Phase 5 — Tests — ✅ DONE

**Goal:** lock down the now-extracted pure logic ([testing.md](guidelines/testing.md)).

> **Done with a zero-dependency runner, not gdUnit4.** On the brand-new Godot 4.7
> gdUnit4's addon/version-compat risk wasn't worth it for a prototype's pure-logic
> tests. `test/run_tests.gd` (`./test/run_tests.sh`) extends `SceneTree`, exits
> 0/1, and covers IslandShape, ColorUtil, MeshFactory, the player edge clamp,
> grass planting, and the swing→cut→count chain — **15 checks, all green**.
> gdUnit4 (steps below) stays the upgrade path for scene_runner / mocking.

1. Install `addons/gdUnit4/`, enable plugin.
2. `test/` mirrors `src/`. Suites:
   - `island_shape_test.gd` — `radius()` bounded/periodic/deterministic.
   - `color_util_test.gd` — `vary()` stays in `[0,1]`, hue wraps.
   - `mesh_factory_test.gd` — `beveled_box()` vertex count + AABB ≈ `size`.
   - `grass_planting_test.gd` — all planted points fall inside `IslandShape`;
     heights within `[MIN_HEIGHT, MAX_HEIGHT]`; seeded count is stable.
   - One `scene_runner` integration test: hold a key → player stays on island;
     swing → `grass_mowed` emitted and counter increments.
3. Add `runtest.sh` invocation to CI (headless).

**Verify:** `runtest.sh` green locally and in CI. **Risk:** low. **Effort:** ~half a day.

---

## Phase 6 — Cleanup

- Update `README.md` + `CLAUDE.md` "Architecture" to the new layout.
- Add `.gdignore` to `docs/`.
- Delete any dead code surfaced during extraction.

**Verify:** headless run exits 0; docs match reality.

---

## Suggested order & checkpoints

P1 → P2 → P3 are safe, behavior-preserving structure work — do them back to back,
each its own commit. **P5 (tests) can come right after P2** so the extracted
`lib/` is covered before the riskier P4. Do **P4 last** (or defer it) since it's
the only phase that changes the rendering path and carries real risk. Land
nothing without the headless gate passing.
