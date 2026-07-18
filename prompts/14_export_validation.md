Validate cross-platform export readiness only after the vertical slice is stable.

Requirements:
- Keep one shared Godot project and shared gameplay codebase.
- Configure Android export preset for an unsigned local debug build and document release signing fields without storing secrets.
- Configure iOS export preset and document the Xcode/macOS signing steps without embedding certificates or credentials.
- Centralize provisional bundle/application identifiers so they can be changed before store submission.
- Verify portrait orientation, safe areas, pause/resume behavior, and asset inclusion settings.
- Produce a concise checklist for Google Play AAB and App Store/TestFlight preparation.
- Do not add billing, ads, analytics, notifications, Game Center, or Play Games SDKs in this milestone.

Acceptance: Android debug export succeeds when the local SDK is available; iOS export configuration is syntactically valid and all remaining macOS/Xcode manual steps are documented. Stop afterward.
