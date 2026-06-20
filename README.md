# Floating Island Mower

A plain, quick **Godot 4** 3D prototype: a blocky little character with a scythe
mows grass on a floating island in space. Pixelated, Minecrafty aesthetics, all
built procedurally in GDScript — **no external assets to import**.

## What's in it

- **High top-down camera** that smoothly follows the player.
- **Floating island** (grass → dirt → stone) drifting in a starry void.
- **Blocky character + scythe**, made of boxes with crisp pixel-noise textures.
- **Grass that reacts to movement** — blades bend away as you walk near and
  spring back upright once you pass.
- **Mowing** — swing the scythe to cut blades in the arc ahead of you.
- **Regrow** — cut grass grows back after ~8 seconds.
- **HUD** — a `Mowed: N` counter.

## Controls

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` or Arrow keys | Move / turn |
| `Space` | Swing the scythe (mow) |

## How to run

From this project directory, use the helper scripts:

```sh
./play.sh    # run the prototype as a game
./edit.sh    # open it in the Godot editor
```

Both auto-detect Godot (Downloads, /Applications, or `godot` on PATH). To use a
specific build: `GODOT=/path/to/godot ./play.sh`.

Or run the engine directly / launch `Godot.app`, click **Import**, and select
this folder's `project.godot`.

## Files

| File | Responsibility |
| --- | --- |
| `project.godot` | Project config; main scene + GL-Compatibility renderer. |
| `Main.tscn` / `Main.gd` | World setup: space environment, starfield, sun, island, follow-camera, and wiring the player ↔ grass ↔ HUD together. Also holds the shared pixel-texture/material helpers. |
| `Player.gd` | Blocky character + scythe; input, movement, swing animation. Emits a `swing` signal. |
| `GrassField.gd` | Grid of grass blades; bend-to-player, cutting, and regrow. Emits `mowed_changed`. |
| `Hud.gd` | `Mowed: N` counter and a controls hint. |

## Tuning

Most of the feel lives in the constants near the top of each script:

- `Player.gd`: `SPEED`, `TURN_SPEED`, `SWING_DURATION`.
- `GrassField.gd`: `SPACING` (grass density), `BEND_RADIUS`, `MAX_LEAN`,
  `CUT_RADIUS`, `ARC_HALF_DEG`, `REGROW_DELAY`.
- `Main.gd`: `ISLAND_SIZE`, `CAM_OFFSET` (camera angle/height).
