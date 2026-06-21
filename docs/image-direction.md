# Image direction (2D pixel art)

The standing look-and-feel for **2D pixel-art images we make *outside* the engine** —
the mascot, character portraits, and item icons used in the README, branding, and
docs. Reuse this so every generated image reads as one family.

> **Scope.** This does **not** change the in-engine rule: the game itself is still
> procedural geometry, **zero imported art assets** (see [CLAUDE.md](../CLAUDE.md)).
> These PNGs live in `assets/` for branding/docs — they are **not** loaded as game
> textures or meshes.

## Visual identity

One consistent style across every image so the mascot, the captain, and any item
icons look like they belong together.

- **Pixel art**, hand-crafted feel, crisp high-detail pixels, **bold clean dark
  outline**.
- **Soft cel shading**, **3/4 view**.
- **Golden-hour-in-a-void palette** (echoes the game's lighting): warm **dusk-orange
  highlights**, cool **teal shadows**, subtle **rim light** and gentle **glow**.
- **Cozy storybook mood** — warm and inviting, never grim or menacing.

## Format conventions

- **Transparent background.**
- **Single subject, centered.**
- **Consistent scale across a set** — item icons sized to match each other.
- Characters/mascots may stand on a small grassy-island base; standalone items have
  no base.
- Export as **PNG into `assets/`**.

## Reusable prompt recipe

Compose every prompt as **`[subject] + [style block]`**. Keep the style block
identical across a set; vary only the subject line.

**Style block** (items):

```
pixel art game item icon, single object centered on a transparent background,
bold clean dark outline, soft cel shading, warm golden-hour lighting with
dusk-orange highlights and cool teal shadows, subtle rim light and gentle glow,
cozy storybook palette, 3/4 view, matching the Voidmower pixel-art mascot style,
crisp high-detail pixels
```

For **characters/mascots**, swap `game item icon` → `character mascot` and allow a
small grassy-island base.

**Negative prompt** (where supported):

```
blurry, photorealistic, 3d render, multiple objects, cluttered, background scene,
text, watermark, jpeg artifacts, dull gray palette, harsh shadows, low quality
```

## Seamless textures (variant)

Tileable ground/surface textures need a **different** format than the item icons
above — **full-frame, top-down, and flat-lit**. The directional rim light, glow, and
transparent background of the item block would break the tiling, so use this block
instead.

**Style block** (seamless texture):

```
seamless tileable pixel-art texture, top-down orthographic flat view, repeats
perfectly with no visible seams or borders, even diffuse lighting (no directional
shadows or vignette), full-frame edge-to-edge, no central focal point, warm cozy
storybook palette matching the Voidmower look, crisp high-detail pixels
```

**Subject line** — grass is the default (matches the island); swap for a matching set:

- **Grass** — `lush green meadow grass, short blades with subtle length and hue variation, a few tiny scattered wildflowers and clover, warm spring-green fading to golden tips, glimpses of dark soil between the blades`
- **Dirt path** — `packed earth, warm brown soil with small pebbles and fine cracks, sparse dry grass tufts`
- **Cobblestone** — `weathered flagstones with mossy gaps, warm grey stone flecked with golden lichen`
- **Sand** — `fine golden beach sand with gentle wind ripples and a few tiny shells`

**Negative prompt** (differs from the item one — no transparency, no central subject):

```
seam, hard edge, border, frame, vignette, single object, centered subject,
transparent background, directional shadow, harsh lighting, 3d render, blurry,
watermark, text, low quality
```

**Getting clean tiling:**

- In PixelLab, `create_topdown_tileset` is purpose-built for tiling ground; one-off
  textures work in most text-to-image models as long as the `tileable / no seams`
  terms stay in.
- Verify by tiling the result **2×2** — any visible repeat (a bright blade, a
  distinctive flower) is a seam to fix.

## Reference assets

- `assets/voidmower-mascot.png` — project mascot.
- `assets/captain.png` — Captain Goldwake (persona: [docs/persona-goldwake.md](persona-goldwake.md)).

## Tooling

Generated via the **PixelLab MCP** — `create_character` for mascots/portraits, the
object generators for items. It runs on a PixelLab subscription/credits, so check
the balance (`get_balance`) before queueing a set. The same recipe works in any
text-to-image model (Midjourney / DALL·E / Stable Diffusion).
