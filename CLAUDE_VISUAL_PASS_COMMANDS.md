# Claude commands for the visual production pass

## Generic command template

Use this for each milestone, replacing the prompt filename each time.

```text
Read `CLAUDE.md`, the relevant files in `docs/`, and inspect the relevant
reference images in `references/`.

Execute only `prompts/XX_FILENAME.md`.

The current implementation is functionally complete but visually below the
required quality bar.

Before making changes:
- Compare the current implementation to the relevant references.
- Write a concise gap report.
- Explain the implementation plan.
- List every file you intend to create or modify.
- Identify any risks.
- Confirm that you will preserve existing working gameplay and navigation.

During implementation:
- Do not add unrelated features.
- Do not break save/progression systems.
- Do not use obsolete names like Starforge or Galaxy Rush.
- Use only RIFTWING.
- Prioritize readability and mobile usability.

After implementation:
- Run the project.
- Fix all parser and runtime errors caused by your changes.
- Validate at 1080x1920, 1080x2400, and 1080x2478 where relevant.
- Update `docs/CHANGELOG.md`.
- List all changed files.
- Explain exactly how I can test the result.
- Report each acceptance criterion as PASS or FAIL.
- Stop when this milestone is complete.

Do not begin the next milestone.
```

## Recommended usage order

Use the template above with:

- `prompts/15_visual_foundation.md`
- `prompts/16_gameplay_hud_production.md`
- `prompts/17_main_menu_production.md`
- `prompts/18_hangar_production.md`
- `prompts/19_galaxy_map_production.md`
- `prompts/20_upgrade_cards_production.md`
- `prompts/21_results_screen_production.md`
- `prompts/22_vfx_audio_polish.md`
- `prompts/23_final_mobile_visual_qa.md`
