# Visual Foundation Gap — Milestone 15

References define hierarchy/scale/color only. Brand = **RIFTWING**.

## Gaps vs `references/04_gameplay.png` / `06_boss_fight.png`

| Area | Current | Target |
|---|---|---|
| Background | Flat ColorRect | Layered parallax (stars / nebula / debris), dark center lane |
| Debug | Overlay + cyan core dots on by default | Hidden; F3 / optional 3-finger |
| Player scale | ~154 px | ~170–210 px + separate engine glow |
| Enemies | Small SVG, weak cores | Larger; violet hull + orange core read |
| Projectiles | Thin procedural lines (r≈7–9) | Wider head + trail; cyan vs magenta/orange |
| Boss | ~512 px Titan | Closer to 650–900 px |
| Arena fill | Fixed 1080×1920 ColorRect | Expand with viewport; tall phones show more sky |
| HUD debug readout | Always-on FPS block in run | Hidden unless debug |

## Plan (no gameplay rewrites)
1. Hide debug overlay; gate core markers; optional 3-finger toggle.
2. Reusable `ParallaxBackground` scene from existing `assets/backgrounds/*`.
3. Scale Resources + sprite composition (engine glow node, projectile draw, pickups).
4. Visual foundation sandbox scene + multi-res probe.
5. Cap FPS 60; trim excessive enemy-bolt prewarm on run host.

## Risks
- Scale changes must not alter authored damage / collision balance beyond visual hitbox ratio.
- Parallax must stay dim enough for bolt readability.
- Do not touch SaveManager / stage unlock / rewards.

## Pool note
- Enemy projectile prewarm on run/boss reduced **512 → 256** (cap still 2×). Peak boss rings + waves rarely need 512 warm instances at start; growth remains capped.
- Player 256 / enemies 48 / pickups 64 / effects defaults kept (still required under stress).
