# Glow UI Pass — Visual Review Notes

Captured at 1080×1920 via `tests/visual_review_probe.gd` (non-headless).

| Screen | Review PNG | Remaining diffs vs references |
|---|---|---|
| Main menu | `review_main_menu_1080x1920.png` | Licensed display font still pending; hero is PNG plate vs photoreal mockup. |
| Stage map | `review_stage_map_1080x1920.png` | Planet node art is SVG chrome, not painted planets from `02_stage_select`. |
| Hangar | `review_hangar_1080x1920.png` | Ship bay density lower than `03_hangar`; upgrade rows use compact glow CTAs. |
| Results | `review_results_1080x1920.png` | Celebration density lighter than reference victory screens. |
| Settings | `review_settings_1080x1920.png` | No dedicated reference — follows MetaShell + glow language. |

All listed screens use MetaScreenShell (or main-menu native chrome) and GlowCtaButton for primary actions. Branding: **RIFTWING** only.
