# Riftwing - Claude Code Starter Kit v2

This repository starter pack is the implementation brief for an original portrait mobile roguelite space shooter built with Godot 4 and typed GDScript.

## Canonical identity

- Game brand: **RIFTWING**
- Working store title: **Riftwing: Space Survivor**
- Internal project slug: `riftwing`
- Engine: Godot 4.x
- Platforms: Android and iOS from one shared project

The words **Starforge** and **Galaxy Rush** visible inside some concept screenshots are legacy placeholder text. They are not the product name and must never be copied into production UI, code identifiers, package metadata, or store listings.

## Included

- Seven visual reference screens and a contact sheet.
- Separated development placeholders for the player, enemies, boss, UI, icons, effects, and parallax backgrounds.
- Product, gameplay, visual, naming, architecture, asset, implementation, and QA specifications.
- A strict `CLAUDE.md` contract.
- Small milestone prompts that must be executed one at a time.
- An exact first message in `CLAUDE_FIRST_MESSAGE.txt`.

## Important asset status

The full-screen concept images and crops are visual references, not production-ready sprites. The SVG files are clean prototype placeholders that Godot can import. Replace detailed ship, enemy, boss, and effect art later with properly separated transparent PNG/WebP or sprite sheets without changing gameplay architecture.

## Start here

1. Extract this entire folder into a new Git repository.
2. Open the repository root in Claude Code.
3. Attach the seven images in `references/` if your Claude interface does not expose local files automatically.
4. Paste the complete contents of `CLAUDE_FIRST_MESSAGE.txt`.
5. Let Claude complete only `prompts/00_bootstrap.md`.
6. Run and verify the project before moving to `prompts/01_player_movement.md`.
7. Continue in numeric order. Never ask Claude to build the full game in one pass.

## Prototype priority

The first target is a polished three-minute vertical slice: movement, auto-fire, two enemy archetypes, XP, one upgrade choice, a mini-boss or boss, a result screen, and stable 60 FPS on a real phone. Do not add monetization, analytics, accounts, multiplayer, or cloud infrastructure before this loop is fun.
