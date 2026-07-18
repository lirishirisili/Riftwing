# Project Rules: Riftwing

## Canonical product identity
- Display name: `RIFTWING`.
- Working store title: `Riftwing: Space Survivor`.
- Internal slug: `riftwing`.
- The legacy words `Starforge` and `Galaxy Rush` may appear inside reference screenshots only. Never use them in production UI, code, project settings, identifiers, metadata, package IDs, filenames, or store text.
- Do not rename the product without explicit approval.

## Product
- Portrait mobile vertical shooter with roguelite upgrade choices.
- One shared Godot project for Android and iOS.
- Target session: 3-6 minutes.
- Target frame rate: stable 60 FPS on mid-range devices.
- First priority: satisfying movement, shooting, hit feedback, readable danger, and meaningful upgrade choices.

## Engine and language
- Use the current stable Godot 4.x release installed in the environment.
- Use typed GDScript only. Do not use C#.
- Base logical resolution: 1080x1920 portrait.
- Support 9:16, 19.5:9, and 20:9 while preserving composition.
- Do not install third-party plugins without explicit approval.

## Mandatory reading order
1. `docs/00_PRODUCT_VISION.md`
2. `docs/01_VISUAL_DIRECTION.md`
3. `docs/02_GAMEPLAY_SPEC.md`
4. `docs/03_SCREEN_SPEC.md`
5. `docs/04_ARCHITECTURE.md`
6. `docs/09_BRAND_AND_NAMING.md`
7. `docs/10_REFERENCE_IMPLEMENTATION_MATRIX.md`
8. The relevant milestone prompt.

## Architecture
- Prefer composition over deep inheritance.
- Gameplay configuration must use custom Resources, not hard-coded balance values.
- Use signals or typed event channels to reduce coupling.
- Bullets, enemies, pickups, damage numbers, and effects must use object pools.
- Platform-specific code must be hidden behind service interfaces.
- Gameplay code must not directly reference Android or iOS SDKs.
- Save data must be versioned, atomic, and migration-ready.
- Every system must have a small debug scene or deterministic verification path.

## Visual implementation
- Use `references/` only for composition, hierarchy, palette, density, and motion direction. Never use a full-screen reference image as the game UI.
- Build all text as real Godot controls. Do not bake UI text into images.
- Use the SVGs in `assets/` as prototype placeholders and reusable scalable UI sources.
- Build UI with Control nodes, Containers, anchors, size flags, reusable Themes, and safe-area margins.
- Do not position production UI with raw fixed coordinates when containers or anchors are appropriate.
- Player bullets, enemy bullets, pickups, and the background must remain distinguishable under peak effects.
- Decorative effects must never hide collision-critical projectiles or telegraphs.
- When exact final art is missing, preserve silhouette and color role with a clearly named placeholder rather than inventing a new style.

## Mobile requirements
- Respect safe areas, rounded corners, and camera cutouts.
- One-finger drag movement; the player ship remains visibly above the finger.
- Pause, save, and restore correctly during focus loss and app backgrounding.
- Handle touch cancellation and interruptions.
- Avoid allocations in high-frequency gameplay loops.
- Provide low, medium, and high effects profiles.
- Touch targets must be at least 48 logical pixels and should be visually smaller than their interaction rects when needed.

## Workflow rules
- At the start of each milestone, state the goal, relevant files, implementation plan, and acceptance criteria.
- Implement exactly one milestone. Do not silently begin later prompts.
- Inspect existing files before creating replacements.
- Do not rewrite unrelated systems.
- After implementation, run the project or the closest available automated/debug scene, report parser/runtime errors, and provide verification steps.
- Update `docs/CHANGELOG.md` and any architecture document affected by the change.
- Do not claim a screen matches the reference without producing a fresh 1080x1920 screenshot and listing remaining visual differences.
- Stop and ask for approval before adding SDKs, changing engine version, changing canonical naming, or altering the architecture boundary.

## Definition of done for every milestone
- No parser errors.
- No reproducible runtime errors in the milestone path.
- No orphan nodes, obvious signal leaks, or unbounded pool growth.
- Relevant debug scene runs with mouse and touch emulation.
- Acceptance criteria in the prompt are satisfied.
- Changed files and manual verification steps are reported.
- Changelog is updated.
