# Reference Implementation Matrix

## Global rule
Reference images describe visual hierarchy and quality. They are not shippable screen textures. Rebuild every panel, label, bar, button, icon placement, and interaction as reusable Godot UI.

| Reference | Purpose | Must preserve | Must change for production |
|---|---|---|---|
| `01_main_menu.png` | Home screen | Hero ship focus, one dominant action, event card, compact top resources | Replace all legacy title text with `RIFTWING`; reduce decorative noise if it hurts readability |
| `02_stage_select.png` | Campaign map | Connected sector nodes, strong selected state, mission detail hierarchy | Use data-driven nodes and real text; no baked panel image |
| `03_hangar.png` | Ship progression | Large selected ship, clear stats, five upgrade categories | Prototype art may be simplified; costs and levels come from Resources |
| `04_gameplay.png` | Standard combat | Player at lower center, upper enemy formation, readable projectile color roles, compact HUD | Reduce ship and button size if dodge space becomes cramped |
| `05_upgrade_choice.png` | Roguelite choice | Paused dimmed combat, three distinct rarity cards, immediate comparison | Descriptions must be much shorter on real devices; no reroll in prototype |
| `06_boss_fight.png` | Boss spectacle | Huge silhouette, clear health bar, symmetric attack readability, dramatic effects | Maintain a viable safe route; lower effect density on weak devices |
| `07_victory.png` | Results and reward | Celebration first, then stats, rewards, next action | Use real values and grant rewards exactly once |

## Screenshot review dimensions
Capture review images at 1080x1920. Also inspect at representative 19.5:9 and 20:9 viewport sizes before declaring a screen complete.

## Visual comparison order
1. Information hierarchy.
2. Player/enemy scale and usable gameplay space.
3. Safe area and touch reachability.
4. Contrast and projectile readability.
5. Spacing and alignment.
6. Color and glow intensity.
7. Decorative detail.

Fix higher items before lower items.
