# Design System — Visual Fidelity

Shared chrome for the reference-fidelity pass.

## Theme (`resources/theme/riftwing_theme.tres`)
- Chamfer-leaning corner radii (sharp + opposite soft)
- Stronger neon borders / shadow glow
- Variations: ButtonPrimary / Secondary / Tertiary / **Reward**, ChipPanel, **NeonPanel**

## Components
- `scenes/ui/chrome/hex_chip.tscn` — currency/status chip
- `GameplayHUD` — `bottom_hud_frame` vitals, hex level/pause shells, heart/shield captions (XP is purple shield-slot chrome only)
- `BossHealthBar` — chip-safe width, segmented chrome plate under VOID TITAN
- `HudSegmentedBar` — neon segmented fill
- `AbilityButton` — orb + tick ring (≥112)
- `GlowController` — quality-gated WorldEnvironment bloom

## Chrome assets (`assets/ui/chrome/`)
- `hex_frame.svg`, `bottom_hud_frame.svg`, `currency_pod.svg`
- `map_node_active.svg`, `map_node_locked.svg`

## Key art (`assets/art/`)
- ships/vanguard_mk2.svg
- enemies/void_scout.svg, void_shooter.svg
- boss/void_titan.svg
- env/hangar_pad.svg, planet_accent.svg
