# Visual Gap Report — Milestone 12

Reference images are visual direction only. Production branding is **RIFTWING** only.
Legacy `Starforge` / `Galaxy Rush` text in references must never appear in UI.

Capture size for review: **1080×1920**. Also spot-check 19.5:9 and 20:9.

## Five largest differences (pre-fix)

| Rank | Category | Screen(s) | Gap | Planned fix |
|---:|---|---|---|---|
| 1 | Hierarchy | Results, Main menu | Primary / secondary / reward actions share one flat blue button style | Theme styles: cyan-primary, purple-secondary, gold-reward |
| 2 | Color / contrast | Gameplay | Enemy plasma bolts are orange — compete with impact/reward orange | Retint enemy plasma toward purple/magenta hazard role |
| 3 | Typography / readability | Upgrade choice | Card descriptions too long for three-up mobile layout | Shorten authored descriptions; tighten card type sizes |
| 4 | Spacing | Results | Equal stacked CTAs; reference pairs Upgrade + Next Sector | HBox primary pair (Upgrade / Next gold) + Home |
| 5 | Contrast / effects | Meta + combat | Weak panel borders; nebula can wash projectile readability | Stronger cyan/purple panel outlines; deeper combat dim |

## By category (remaining after this pass)

### Hierarchy
- Main menu: Start Run dominant; Daily secondary purple; Ships/Upgrades tertiary.
- Results: celebration title → score → stats → rewards → CTAs.
- Boss HUD already top-centered; ability buttons still deferred (no art).

### Spacing
- Safe-area insets exist on meta screens (milestone 11).
- Stage-map absolute node positions remain prototype-static.

### Typography
- Fallback sans (theme default). Licensed sci-fi fonts deferred.
- Upgrade titles/descriptions shortened for mobile.

### Color
- Tokens in `manifests/color_tokens.json` remain source of truth.
- Player bolts cyan; enemy bolts purple/magenta; impacts orange/gold.

### Contrast
- Dark translucent panels with cyan/purple borders.
- Combat background dim increased so purple hazards stay readable.

### Readability
- Effects layer stays below bullets (`EffectsLayer` z-index).
- Enemy bullet color role clarified vs pickups.

### Animation
- Upgrade cards already 0.92→1.0; selection pulse kept.
- Results title intro kept; no gameplay timing changes.

### Effects
- LOW/MED/HIGH budgets unchanged (hardening milestone).
- No full-screen flashes beyond existing hit-stop window.

### Mobile safe areas
- Unchanged logic from milestone 11; verified still applied.

## Applied in this milestone
- Theme: cyan primary glow, purple secondary, gold reward button styles
- Main menu: stronger RIFTWING hero type, purple event panel, purple Daily CTA
- Results: side-by-side Upgrade / Next Sector (gold), RIFTWING brand line
- Upgrade choice: “CHOOSE AN UPGRADE” cyan title, denser cards, shorter copy
- Enemy plasma retinted to purple/magenta hazard role
- Darker combat backgrounds for projectile contrast
- Stage map header: `SECTOR MAP` (avoids Galaxy Rush-adjacent label)
- Review captures via `tests/visual_review_probe.gd` → `user://review_*_1080x1920.png` and `docs/visual_review/`

## Intentionally not fixed (needs final art / later milestones)
- Photoreal ship / planet / station key art
- Hexagonal metallic button frames
- Bottom ability button chrome on gameplay HUD
- Reroll control on upgrade screen (explicitly out of prototype)
- Licensed display fonts
