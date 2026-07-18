# Asset Pipeline

## Status of this pack
- `references/`: final visual targets and composition references.
- `assets/concept/`: cropped concept references only; not clean sprites.
- `assets/placeholders/`: transparent SVG development assets that can be used immediately.
- `assets/ui/`: reusable SVG frames and controls.
- `assets/icons/`: reusable SVG icons.
- `assets/backgrounds/`: separated parallax layers generated for prototyping.
- `assets/effects/`: simple vector effects for prototyping.

## Production asset requirements
Each final ship or enemy asset should have:
- Transparent background.
- Top-down view.
- Consistent light direction.
- No baked projectile, shadow, text, or UI.
- Body separated from engine glow where practical.
- Sufficient internal contrast at mobile size.
- Master export at 2x or 4x expected in-game size.

## Suggested final exports
- Player ship body: 1024x1024 transparent PNG/WebP.
- Standard enemy: 512x512.
- Elite enemy: 768x768.
- Boss: 1536x1536 or modular pieces.
- Weapon icon: 256x256.
- UI icon: SVG or 256x256 PNG.
- Background layer: 1080x1920 or seamless vertical tile.

## Godot import rules
- Filter enabled for illustrated assets, disabled only for pixel-perfect graphics.
- Mipmaps for large menu artwork, usually not for small gameplay sprites.
- Use lossless compression for UI; test VRAM and APK size for gameplay art.
- Use texture atlases after the art set stabilizes.
- Do not merge player, enemies, bullets, and effects into full-screen screenshots.

## Nine-slice UI
Import the panel/button SVGs, convert to textures if needed, and use NinePatchRect so controls can resize without distortion.
