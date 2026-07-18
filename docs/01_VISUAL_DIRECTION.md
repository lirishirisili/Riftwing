# Visual Direction

## Visual identity
Premium neon science fiction with a dark navy base, cyan player energy, purple enemy void energy, and orange impact highlights. The game should feel modern and spectacular without becoming visually noisy.

## Reference priority
1. `references/04_gameplay.png` for gameplay hierarchy.
2. `references/05_upgrade_choice.png` for roguelite cards.
3. `references/06_boss_fight.png` for boss scale and spectacle.
4. `references/01_main_menu.png`, `02_stage_select.png`, and `03_hangar.png` for meta UI.
5. `references/07_victory.png` for reward presentation.

## Color roles
- Cyan and electric blue: player, shields, primary actions, selected states.
- Purple and magenta: enemy faction, epic rarity, danger energy.
- Orange and gold: impacts, legendary rarity, rewards, critical moments.
- Green: healing and positive recovery only.
- Red: unavoidable warning, low health, failure, and destructive boss telegraphs.

See `manifests/color_tokens.json`.

## Gameplay readability rules
- Player bullets are predominantly cyan/blue and move upward.
- Enemy bullets are purple, magenta, orange, or red and must never resemble pickups.
- Pickups use stable geometric icons and slower motion.
- The player ship has a strong white/orange silhouette and cyan engine trail.
- Background contrast is reduced behind dense projectile patterns.
- Damage flashes are brief and never cover the entire screen for more than 80 ms.

## Composition
- Player ship occupies approximately 12-16 percent of screen width during normal gameplay.
- The active dodge region covers the lower 60 percent of the screen.
- Standard enemies remain in the upper 55 percent unless executing a readable dive attack.
- Ability buttons sit near the lower corners but remain inside safe areas.
- Critical HUD information stays near the top edge and uses compact frames.

## UI style
- Dark translucent panels with thin cyan or purple outlines.
- Angular corners and hexagonal accents.
- Text must be real Godot UI text, never baked into images.
- Main action buttons use blue; secondary challenge/event actions use purple; high-value reward actions may use gold.
- Use subtle glow. Do not blur text.

## Motion language
- UI opens with short 140-220 ms transitions.
- Cards scale from 0.92 to 1.0 with easing.
- Strong attacks add 30-60 ms hit stop.
- Explosions combine sprite animation, particles, a radial ring, light flash, and restrained camera shake.
- Boss entrances use a warning banner, music transition, camera framing, and silhouette reveal.

## Typography
Recommended direction: Oxanium, Rajdhani, or another readable squared sci-fi family. Do not include font files in the repository unless licensing has been reviewed. Use a fallback sans-serif during prototype development.
