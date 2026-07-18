# QA Checklist

## Visual
- UI remains inside safe areas on 9:16, 19.5:9, and 20:9.
- No important object is hidden by a finger during drag movement.
- Enemy bullets remain visible over every background region.
- Player bullets are not confused with enemy bullets.
- Upgrade descriptions fit at minimum supported resolution.
- Glow does not make text blurry.

## Gameplay
- Player cannot leave bounds.
- Touch cancellation does not lock movement.
- Pause stops timers, spawns, bullets, and audio transitions correctly.
- Every boss attack has a telegraph and a viable safe route.
- Upgrade application is deterministic and persists for the run.
- No duplicate reward grants after background/resume.

## Performance
- Stable frame pacing on mid-range Android device.
- Pools do not grow without limits.
- No repeated scene-tree lookup in projectile update loops.
- Effect quality can be reduced without changing gameplay logic.
- Resume after app background does not create duplicate nodes or audio.

## Save
- Atomic save writes.
- Corrupt save fallback.
- Schema migration test.
- Settings persist.
- Stage rewards are granted exactly once.
