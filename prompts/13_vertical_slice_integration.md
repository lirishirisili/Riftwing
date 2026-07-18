Integrate the implemented systems into one complete prototype vertical slice without adding new major features.

Target flow:
Main Menu -> Start Run -> 3-minute stage -> upgrade choices -> first boss -> Victory or Failure -> Results -> Home.

Requirements:
- Use existing scenes and systems rather than duplicating them.
- Create one data-driven stage timeline following `docs/02_GAMEPLAY_SPEC.md`.
- Confirm reward granting is idempotent.
- Confirm pause, focus loss, retry, and returning home do not duplicate nodes or corrupt state.
- Capture a 1080x1920 screenshot for every major screen and store it in a local review folder excluded from production exports.
- Run the relevant stress/debug scenes and document FPS, peak active projectiles, and pool growth.
- Do not add ads, purchases, online accounts, cloud save, analytics SDKs, or new content beyond what is required for the vertical slice.

Acceptance: the complete flow can be played repeatedly from menu to results with no parser errors, no reproducible state leak, and no unbounded pool growth. Stop after reporting the remaining highest-priority gameplay and visual issues.
