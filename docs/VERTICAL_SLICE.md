# Vertical Slice (Milestone 13)

## Flow
Main Menu → Stage Selection → Run → Enemy Waves → XP / Upgrade Choices → Mini-boss (Void Wisp) → Mid Waves → Boss (Void Titan) → Victory or Defeat → Results → Rewards + Save → Home or Next Stage (map) or Hangar.

## Key files
- `scenes/gameplay/run_scene.tscn` / `scripts/gameplay/run_controller.gd`
- `resources/stages/vertical_slice_timeline.tres`
- `resources/waves/slice_wave_early.tres`, `slice_wave_mid.tres`
- `resources/bosses/void_wisp.tres`, `void_titan.tres`

## Debug keys (run)
| Key | Action |
|---|---|
| L | Force level-up / upgrade choice |
| K | Damage active boss |
| F6 | Skip to mini-boss |
| F7 | Skip to final boss |
| F8 | Force victory (current boss or end run) |
| F9 | Force defeat |
| Q | Cycle effects quality |

## Manual test
1. Launch the project (main scene).
2. Start Run → pick stage 1-1 → Launch.
3. Survive early waves; take the ~18s upgrade choice; fight Void Wisp; continue; fight Void Titan.
4. Confirm Results grants currency once; Home; Launch again; die; confirm defeat Results; reopen app and verify bank + cleared stages persist.
5. Optional fast QA: F6 → F8 → F7 → F8.

## Automated probe
```text
godot --path . --window-size 1080,1920 --script res://tests/vertical_slice_probe.gd
```
Headless also works (skips PNG capture). Expect `VERTICAL_SLICE_PROBE_OK`.

## Pool / performance notes (probe path)
- Enemy bolt pool prewarm 512, hard cap 2× prewarm (`ObjectPool.max_total`).
- Probe pool snapshot after skip-to-boss: `enemy_total=512` (at prewarm; not past cap).
- Full 3-minute live play should be profiled on-device; debug overlays show FPS + pool active/total/peak (F3 from mobile hardening).
- Review PNGs: `review/slice_*_1080x1920.png` (excluded from exports).

## Remaining highest-priority issues
1. Hangar permanent ship stats are not applied inside the run combat host.
2. Non-plasma acquired weapons still do not fire (loadout IDs only).
3. Wave density / XP pacing may need balance passes for a natural first upgrade without the guaranteed XP grant.
4. Ability button chrome on the gameplay HUD remains deferred.