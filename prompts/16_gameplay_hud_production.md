# Milestone 16 — Production Gameplay HUD

## Goal

Upgrade the gameplay HUD from a functional prototype into a polished,
readable, production-quality mobile HUD that matches the reference direction.

Do not change the core gameplay loop.

## Scope

Apply this only to the in-run gameplay HUD.

This includes:

- top HUD information
- boss bar / wave information
- score and currency presentation
- health / shield / level display
- ability buttons
- pause button
- pickup feedback hooks

This does not include:

- main menu
- hangar
- galaxy map
- monetization

## Requirements

### Branding and text

- Use only `RIFTWING`.
- Never display `Starforge` or `Galaxy Rush`.
- Keep text concise and readable.

### Layout

- Respect top and bottom safe areas.
- Keep the center gameplay lane visually open.
- The HUD must not block enemy projectiles or player navigation.
- Support 1080x1920, 1080x2400, and 1080x2478.

### Visual structure

Create a coherent HUD using reusable UI components:

- sci-fi panel frames
- icon badges
- segmented bars
- consistent corner radii
- controlled glow
- readable typography hierarchy

### Top-left section

Include a production-quality presentation for:

- score
- premium / run currency if used during the run

Avoid oversized panels.

### Top-center section

Support:

- boss name + boss health bar when a boss is active
- wave or phase info when a boss is not active

The boss bar should feel important, but not overly tall.

### Top-right section

Include:

- pause button
- optional secondary compact info if already supported

Pause must remain easy to press.

### Bottom section

Include:

- health bar
- shield / energy bar if applicable
- current level or run level
- left and right ability buttons
- clear cooldown / charge states
- clear counts for consumables if supported

### Visual readability

- HUD colors must not conflict with hostile bullet colors.
- Bars must remain legible over the background.
- Small text must remain readable on a phone.
- Avoid excessive bloom.

### Interaction feedback

Add or improve hooks for:

- button press feedback
- cooldown feedback
- full-charge feedback
- damage feedback on bars
- low-health state

### Reusability

- Create reusable theme/component building blocks where practical.
- Do not hard-code the entire HUD as one-off spaghetti layout.

## Acceptance criteria

- Gameplay HUD looks significantly more polished than the prototype.
- The center of the screen stays readable during combat.
- HUD respects portrait safe areas.
- Boss bar, health bars, and ability buttons are easy to read on a phone.
- Existing gameplay still works.
- No unrelated menus or screens are redesigned in this milestone.
