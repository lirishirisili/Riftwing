Implement only the projectile pooling system and a basic plasma weapon.

Requirements:
- Typed GDScript.
- ProjectileData and WeaponData custom Resources.
- Pool prewarms a configurable count and exposes active/free statistics.
- No instantiate/free cycle during normal firing.
- Auto-fire while the run state is active.
- Projectile lifetime, speed, damage, and visual are data-driven.
- Add a debug stress test that fires at least 300 projectiles while reporting FPS and pool growth.
- Do not implement enemies yet.
