# Milestone 22 — VFX and Audio Polish Pass

## Goal

Polish the gameplay feel using visual effects and audio hooks while preserving readability and performance.

## Scope

Refine existing gameplay feedback only.
Do not add new gameplay systems.

## Requirements

### Player feedback

Improve or refine:

- engine exhaust
- muzzle flash
- projectile trails
- hit flash
- shield impact
- low-health feedback
- ability activation feedback

### Enemy feedback

Improve or refine:

- entrance effects
- hit feedback
- death / destruction effects
- boss telegraph clarity
- boss impact feedback

### Explosions and impacts

Create a more polished set of impact moments using:

- particles
- flashes
- small distortion or shockwave hooks where reasonable
- light / glow accents
- restrained screen shake

### Audio hooks

Improve audio structure and routing for:

- UI click
- fire
- hit
- pickup
- explosion
- upgrade choice
- boss warning
- victory / defeat stings

If some final audio assets are missing, create or preserve clean hooks and routing structure.

### Readability

- Enemy bullets must remain readable.
- Boss telegraphs must remain readable.
- Effects must not flood the screen.

### Performance

- Reuse object pools.
- Limit effect counts.
- Avoid large per-frame allocations.

## Acceptance criteria

- The game feels more satisfying and responsive.
- Effects are stronger without reducing clarity.
- Audio hooks are organized and useful.
- Performance remains stable on mobile targets.
