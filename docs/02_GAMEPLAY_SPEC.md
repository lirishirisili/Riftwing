# Gameplay Specification

## Controls
- The player drags anywhere in the lower screen area.
- The ship follows the pointer with smoothing and a configurable vertical offset so it remains visible above the finger.
- Auto-fire is always active while gameplay is running.
- Ability buttons are optional active abilities and must not be required during the tutorial.

## First run timeline
- 0-5 seconds: simple formation, no hostile bullets.
- 5-15 seconds: first pickup and first enemy projectile.
- 15-20 seconds: first three-card upgrade choice.
- 30-45 seconds: first mixed wave and visible weapon growth.
- 60 seconds: mini-boss.
- 150 seconds: boss warning.
- 165-210 seconds: boss encounter and result screen.

## Initial weapons
1. Plasma Cannon: fast straight shots.
2. Arc Laser: chains between targets.
3. Homing Missiles: slower projectiles with area damage.
4. Guardian Drone: orbiting support fire.
5. Chain Lightning: group control.
6. Void Bomb: delayed high-damage blast.

## Upgrade system
- On level-up, pause combat and display three cards.
- Each card shows icon, name, concise effect, current level, and rarity.
- The player can reroll only after the core experience is proven; do not include reroll in the first prototype.
- Maximum active weapons in the initial build: four.
- Upgrade values must come from Resource files.

## Enemy archetypes
- Scout: enters in formation, no shooting at first.
- Shooter: stops, telegraphs, then fires a small burst.
- Diver: marks a path and dives toward the player.
- Tank: slow, high health, drops energy.
- Splitter: divides into smaller enemies.
- Elite: combines two patterns and drops a guaranteed reward.

## Damage and collision
- The player has a small collision core independent from the ship art.
- Graze mechanics are deferred until the basic game is stable.
- Enemy projectile damage must be consistent and readable.
- Invulnerability after a hit: approximately 0.8-1.2 seconds, configurable.

## Boss design rules
- Every attack has a telegraph.
- The player always has at least one viable safe route.
- Attack patterns test movement decisions, not random luck.
- Boss phases change visuals, music intensity, and projectile behavior.
- The first boss has three patterns and one phase transition.
