# Performance

Pragmatic performance rules for a small–medium project. Don't pre-optimize —
but don't write code the docs explicitly warn against. Based on the
[optimization](https://docs.godotengine.org/en/stable/tutorials/performance/index.html)
and best-practice docs.

## Draw calls: instance, don't spawn thousands of nodes

Each `MeshInstance3D` is a separate draw submission. For **many identical
meshes** (grass, particles, debris, crowds) use **`MultiMesh`** — thousands of
instances in a single draw call, set per-instance transforms/colors via
`set_instance_transform()` / `set_instance_color()`.

> This is the single biggest win available in this project: the grass field is
> ~2,500 individual node pairs. The docs name grass as the canonical MultiMesh
> use case.

## The per-frame budget

`_process` / `_physics_process` run every frame for every node. In them:

- **No allocations in hot loops** where avoidable — reuse buffers; creating a
  few `Vector3`/`Quaternion` is fine, building arrays/dictionaries per frame for
  thousands of items is not.
- **No `get_node()` / string lookups in loops** — cache refs in `@onready` or
  `@export` once.
- **Throttle expensive work.** Run it every N frames:
  ```gdscript
  if Engine.get_physics_frames() % 4 == 0:
      _expensive()
  ```
- **Skip idle work.** If a subsystem has nothing to do (no items in a list,
  player far away), early-`return` before the loop.

## `_process` vs `_physics_process`

- `_physics_process(delta)` — fixed timestep; use for physics bodies, movement
  with collision, anything that must be frame-rate-independent and deterministic.
- `_process(delta)` — once per rendered frame; use for visuals, cameras,
  cosmetic animation.
- Disable processing you don't need: `set_process(false)` /
  `set_physics_process(false)`.

## Pooling

For objects created/destroyed rapidly (projectiles, pop effects), reuse a pool
instead of `new()`/`queue_free()` each time. For one-shot bursts, a single
reused emitter (`CPUParticles3D`/`GPUParticles3D` with `restart()`) beats
spawning nodes — we already do this for grass clippings.

## Materials & shading

- Share material resources; don't build a new `StandardMaterial3D` per instance
  when a small pool of variants (or MultiMesh instance colors) gives the same
  variety.
- Forward+ post (glow/SSAO) has a fixed screen-space cost — fine here, but keep
  emissive/transparent overdraw modest.

## Measure before chasing

Use the **Profiler** and **Monitor** (Debugger panel) and the on-screen FPS
before optimizing. Frame time and draw-call count are the numbers that matter;
optimize the top item, re-measure.

## In this project

- **Grass → MultiMesh** is the headline perf task (see refactor plan). It also
  means rethinking per-blade cut animation (instances can't be tweened like
  nodes) — plan a hybrid: MultiMesh for the static field + bend/wind via
  per-instance transforms, and a short-lived effect for cuts.
- The bend/wind loop already touches every blade each frame; with MultiMesh,
  update only instances within the player's radius plus a slow global wind pass.
- Flowers stay as a handful of real nodes (multi-part, rare) — node count is
  negligible there.
