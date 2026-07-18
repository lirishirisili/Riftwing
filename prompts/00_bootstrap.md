Read `CLAUDE.md`, every file in `docs/`, and `references/README.md` before doing anything.

Create the initial Godot 4.x typed-GDScript project for the portrait mobile game **Riftwing**.

Canonical identity:
- Godot project display name: `Riftwing`
- In-game brand text: `RIFTWING`
- Internal slug: `riftwing`
- Treat Starforge and Galaxy Rush text inside concept images as obsolete placeholder branding.

For this task only:
- Create the folder structure from `docs/04_ARCHITECTURE.md`.
- Configure a 1080x1920 logical portrait viewport and portrait orientation settings.
- Add safe-area support and expose the calculated safe rectangle in debug mode.
- Add an AppRoot scene, SceneRouter, and empty typed platform-service interfaces with no-op implementations.
- Add a VisualSandbox scene displaying the three parallax layers and the placeholder player SVG.
- Add a minimal reusable UI Theme foundation using the color tokens in `manifests/color_tokens.json`.
- Create a debug overlay showing FPS, viewport size, safe-area rectangle, active screen, and current platform.
- Add input actions for drag testing, pause, and debug toggles.
- Add an export-readiness placeholder for Android and iOS but do not add SDKs or signing data.
- Do not implement player movement, enemies, shooting, menus, upgrades, saves, stores, analytics, ads, or monetization.

Before implementation, list the exact files you will create or modify and the acceptance criteria. After implementation, run the project or available headless validation, fix parser errors caused by this milestone, update `docs/CHANGELOG.md`, report verification steps, and stop.
