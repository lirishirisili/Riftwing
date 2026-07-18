Implement only the player movement milestone.

Requirements:
- One-finger drag movement plus mouse emulation for desktop.
- Configurable smoothing and vertical finger offset.
- Player remains inside a configurable gameplay rectangle.
- Input cancellation and app focus loss are handled safely.
- Player scene uses the placeholder ship SVG and a separate small collision core.
- Add a movement debug scene with visible bounds and touch target.
- Do not implement shooting.

Acceptance: movement feels immediate but not jittery, ship remains visible above the finger, and no input remains stuck after pause or focus loss.
