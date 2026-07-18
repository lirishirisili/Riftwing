# Claude Code Workflow

## Start every milestone with
1. Read `CLAUDE.md` and the relevant specifications.
2. Inspect the existing project instead of assuming files or APIs.
3. Propose a small implementation plan.
4. List acceptance criteria.
5. Change only files needed for the milestone.

## End every milestone with
1. Run the project or automated scene test.
2. Report parser/runtime errors.
3. List changed files.
4. Explain how to verify on desktop and mobile.
5. Update `docs/CHANGELOG.md`.

## Screenshot review loop
After a visual milestone:
- Capture the target screen at 1080x1920.
- Compare it to the matching file in `references/`.
- Review hierarchy, scale, spacing, contrast, safe areas, and readability.
- Fix the three largest mismatches only, then capture again.

## Preventing uncontrolled rewrites
- Never ask for the entire game in one prompt.
- Never approve an architecture rewrite unless a concrete blocker is documented.
- Keep services and gameplay independent.
- Do not install third-party plugins without explicit approval and a reason.
- Use placeholder assets rather than delaying code for perfect art.
