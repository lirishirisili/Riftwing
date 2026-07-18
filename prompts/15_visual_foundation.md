# Milestone 15 — Visual Foundation and Mobile Layout

## Goal

Transform the current functional debug prototype into a clean visual
foundation for the production version of RIFTWING.

This milestone does not add new gameplay features.

## Reference material

Review every image inside `references/`.

The references define:

- visual hierarchy
- scale relationships
- spacing
- composition
- color direction
- HUD placement
- player and enemy visual proportions

The images are concept references, not textures that should be displayed
as flattened screenshots.

The obsolete names "Starforge" and "Galaxy Rush" must never appear in
the game. The only visible brand is RIFTWING.

## Current problems to fix

- The gameplay background is a flat placeholder or remains visually empty.
- Debug borders are visible during normal play.
- The debug overlay starts visible and hides gameplay.
- The player ship is much too small or visually weak.
- Enemies are too small and appear partially hidden at the top.
- Projectiles are thin placeholder lines.
- There is no clear visual separation between gameplay elements.
- The gameplay arena does not visually fill tall mobile screens.
- The screen does not resemble the supplied gameplay references.
- HUD and safe-area hierarchy are incomplete.

## Requirements

### Debug presentation

- The debug overlay must be hidden by default.
- Allow it to be toggled using F3 in desktop debug builds.
- Add an optional three-finger mobile debug toggle if it can be done safely.
- Cyan debug borders, collision shapes, safe-area lines, and spawn markers
  must not be visible during normal gameplay.
- Debug visualization must only appear when explicitly enabled.
- Keep all debug functionality available for development.

### Mobile viewport

Use a portrait reference resolution of:

- 1080 x 1920

Support:

- 9:16
- 19.5:9
- 20:9
- tall Android screens such as 1080 x 2400 and 1080 x 2478

Use an expand-based layout so the gameplay fills the full screen without
stretching sprites.

The additional vertical screen area must reveal more background and
gameplay space. It must not create large empty placeholder regions.

Respect display cutouts and safe areas.

### Gameplay scale

At a 1080-pixel screen width:

- Player ship visual width: approximately 170–210 pixels.
- Player collision area: approximately 30–40% of the visible sprite.
- Normal enemy visual width: approximately 100–150 pixels.
- Elite enemy visual width: approximately 180–240 pixels.
- Boss visual width: approximately 650–900 pixels depending on phase.
- Player projectile width: clearly visible, approximately 12–24 pixels.
- Enemy projectile diameter: approximately 18–32 pixels.
- Pickups: approximately 64–96 pixels.

These values may be adjusted slightly for readability, but the current
tiny scale is not acceptable.

### Placeholder visual direction

Until final production art is supplied, replace crude geometric
placeholders with polished temporary visuals built from:

- the existing separated assets
- clean Sprite2D composition
- gradients
- glow textures
- trails
- particles
- shaders
- subtle animation

Do not use plain rectangles or unstyled SVG wireframes as primary
gameplay artwork.

### Background

Create a temporary production-quality space background using multiple
independent layers:

1. Dark deep-space base.
2. Slow distant star layer.
3. Medium star layer.
4. Fast foreground particles or small debris.
5. Subtle blue and purple nebula layer.
6. Optional distant planet or structure layer.

Use Parallax2D or the appropriate Godot 4 equivalent.

The center gameplay lane must remain dark enough for projectiles to be
readable.

Do not use a flat placeholder background.

### Visual language

Use this gameplay color language:

- Player and friendly fire: cyan and electric blue.
- Basic enemies: violet with orange energy cores.
- Enemy projectiles: orange, magenta, or purple.
- Health pickups: green.
- Currency pickups: gold.
- Shield effects: blue.
- Critical or powerful effects: white and gold.

Friendly and hostile projectiles must be distinguishable by both shape
and color.

### Player presentation

The player ship must include:

- visible engine glow
- animated engine intensity
- subtle movement tilt
- hit flash
- shield feedback hook
- spawn animation hook
- clear silhouette

The engine effect must be a separate visual element and not permanently
painted into the hull texture.

### Enemy presentation

Enemies must include:

- readable silhouette
- visible energy core
- entrance animation
- hit flash
- destruction animation hook
- subtle hover or banking movement

### Projectile presentation

Player projectiles must no longer look like thin debug lines.

Add:

- bright projectile head
- softer trail
- controlled glow
- clear lifetime fade
- readable visual width

Enemy bullets must remain visible without excessive bloom.

### Performance

- Do not instantiate and free repeated effects during active gameplay.
- Reuse the existing object pools.
- Do not add large full-screen particle systems without limits.
- Default mobile frame rate should be 60 FPS.
- An optional 120 FPS setting may be supported separately.
- Do not force uncapped frame rate on mobile.

Review the current pool configuration. Do not change it blindly,
but document why the current pool sizes are necessary and reduce them if
they are unnecessarily preallocated.

## Validation scenes

Create or update a visual test scene that displays:

- player at correct scale
- three enemy sizes
- friendly projectile examples
- hostile projectile examples
- pickup examples
- background parallax
- hit flash
- engine effect
- explosion preview

## Acceptance criteria

- No flat placeholder background remains in normal gameplay.
- No debug border or debug overlay is visible by default.
- Gameplay fills the complete portrait screen.
- Player and enemies are readable on a real phone.
- Friendly and enemy fire can be distinguished immediately.
- The player ship is visually close in scale to the gameplay references.
- The background has visible depth and parallax.
- Tall screens do not contain empty placeholder regions.
- The game still runs and all existing gameplay remains functional.
- No unrelated gameplay systems are rewritten.
