# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository. This file is
the **hub**: it states what the project is, how to run it, and the load-bearing
rules — the detail lives in the linked guideline docs under
[`docs/guidelines/`](docs/guidelines/).

## What this is

A small **Godot 4.7** (Forward+) 3D prototype: a blocky character with a scythe
mows grass on a procedurally-generated floating island in space. **Everything
visual is built in GDScript — there are no imported art assets.** The success
criterion is *feel*, not realism or mechanics depth.

## Commands

```sh
./play.sh    # run the game (auto-detects Godot; GODOT=/path overrides)
./edit.sh    # open in the editor

# Headless validation — load the project, run N frames, surface script errors:
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120

# Headless test suite (exit 0 = all pass; CI-friendly). See docs/guidelines/testing.md:
./test/run_tests.sh
```

**Always run the headless validation after editing `.gd` files** — it catches
parse errors and `_ready` runtime errors without opening a window.

## Creative direction (load-bearing)

- **Procedural geometry only, zero image assets.** Boxes (beveled), extruded
  meshes via `SurfaceTool`, and procedural `Image`/`NoiseTexture2D` maps. No
  PNGs, no fetches, no asset pipeline.
- **Golden-hour lighting in a void:** warm key light, cool ambient fill, ACES
  tone mapping + exposure 1.25, glow/bloom and SSAO (the reason we run Forward+).
- **Per-instance HSL + roughness variance** everywhere a material is made in a
  loop, so nothing looks stamped.
- **Orthographic, low-angle, fixed-rotation follow camera** (diorama look, no sway).

If a change forces breaking the procedural / Forward+ / warm-palette setup,
surface the tradeoff before implementing.

## Conventions (load-bearing summary)

Full rules in [`docs/guidelines/`](docs/guidelines/); the essentials:

- **Style** — `snake_case` members/functions, `PascalCase` types, `CONSTANT_CASE`
  constants, `_` prefix for private; use **static typing** everywhere; follow the
  member order (signals → enums → constants → exports → vars → `@onready` →
  methods). See [code-quality.md](docs/guidelines/code-quality.md).
- **Structure** — group by feature under `src/`; one responsibility per script;
  stateless helpers live in `src/lib/` utility classes (`class_name`), **not**
  in the composition root. See [project-structure.md](docs/guidelines/project-structure.md).
- **Reuse / decoupling** — depend on `class_name` utilities, not on sibling node
  scripts; communicate **down** via method calls and **up** via signals; never
  reach across the tree with hard-coded `get_node` paths. See
  [reusability.md](docs/guidelines/reusability.md).
- **Performance** — MultiMesh for thousands of identical meshes (grass!), cache
  node refs, no per-frame allocations or `get_node` in loops, `_physics_process`
  only for physics. See [performance.md](docs/guidelines/performance.md).
- **Testing** — gdUnit4; cover pure deterministic logic (shape math, RNG ranges,
  generators); `scene_runner` for node behavior. See
  [testing.md](docs/guidelines/testing.md).

## Architecture

Refactor [Phases 1–5](docs/refactor-plan.md) are **done**: feature folders,
`class_name`, the shared helpers extracted out of the old `Main` god-object, the
player's body-assembly split from its controller, the grass moved to a single
**MultiMesh** (one draw call), and the headless test suite.

```
main.tscn                         # composition-root scene -> src/world/main.gd
src/
  world/  main.gd                 # composition root: env, sun, camera, wiring
          island_builder.gd       # builds the island mesh + surface rocks
  player/ player.gd               # controller: input + movement + animation
          player_rig.gd           # builds the beveled humanoid + scythe; exposes pivots
  grass/  grass_field.gd          # MultiMesh grass: plant/bend/wind/cut/regrow
          flower_field.gd         # rare blooms as real nodes (wind sway, mowable)
  ui/     hud.gd                   # mowed counter
  lib/    color_util.gd           # HSL + roughness variance
          texture_factory.gd      # procedural pixel/speckle/gradient textures
          mesh_factory.gd         # beveled box
          island_shape.gd         # coastline radius() + ring topology (pure)
test/                             # zero-dependency headless runner (Phase 5)
```

Cross-script references load via `preload()` consts (robust on a cold clone / CI
— bare `class_name` needs the editor's global class cache). Features communicate
call-down / signal-up; the composition root is the only place that knows them all.

A headless test suite covers the deterministic core ([P5](docs/refactor-plan.md)
done — `./test/run_tests.sh`, 20 checks).

**Remaining** (see [`docs/refactor-plan.md`](docs/refactor-plan.md)): only P6
cleanup (`.gdignore` in `docs/`, dead-code sweep, doc polish).
