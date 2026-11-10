# Greybox Playtest Notes

Current checklist for movement feel and player-vs-player contact. This is a test
document, not a game mode.

## Run the sandbox

From the repository root:

```bash
godot --path . res://src/core/GreyboxField.tscn
```

Or open `project.godot` in Godot 4.7+ and run that scene directly.

## Controls

### Player

| Action | Keyboard | Xbox | PlayStation |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Left stick |
| Sprint | Shift | RT | R2 |
| Spin | Q | B | Circle |
| Cut / plant | Sharp WASD change | Sharp stick change | Sharp stick change |
| Juke | J / L | Right stick L/R | Right stick L/R |
| Hurdle | Space | Y | Triangle |
| Dive / slide | X | X | Square |

- **Sprint + dive** = head-first dive.
- **Dive while moving without sprint** = QB slide.
- **Dive from a standstill** = head-first dive.

### Sandbox

| Key | Action |
| --- | --- |
| F1 | Toggle the 1-yard reference grid |
| F2 | Cycle CPU mode: CHASE -> BRACE -> STRAFE |
| F3 | Reset both players, clear the collision count, hold the CPU for 3 seconds |
| F4 | Cycle surface: natural grass -> turf -> wet -> mud -> snow -> ice |
| F5 | Reset the CPU only and toggle an indefinite hold; press again to release |

### Reset behavior

- `F3` is the full reset. Both players return to spawn. The CPU holds for 3 seconds
  before resuming its current mode.
- `F5` is the CPU-only test control. It puts the CPU back on its spawn and freezes it
  indefinitely. Your player stays where they are. Press `F5` again to release it.
- **Auto-reset:** if contact becomes a sustained lean for 3 seconds, the CPU resets to
  spawn and holds for 2 seconds. Breaking contact before that cancels the timer.

## Quick test setup

1. Press `F5` to freeze the CPU at its spawn.
2. Move to the angle or distance you want to test.
3. Press `F5` again to release the CPU.
4. Use `F2` to change its behavior.
5. Use `F3` for a clean reset of both players.

## Playtest checklist

### Movement

- [ ] Sprint, cut, spin, juke, hurdle, and dive still feel correct.
- [ ] Sprint + dive is a head-first dive.
- [ ] Moving without sprint + dive is a QB slide.
- [ ] Dive from a standstill is a head-first dive.

### Contact

- [ ] **Baseline chase:** let the CPU chase you. It closes distance and turns toward you.
- [ ] **Head-on hit:** sprint straight into the chasing CPU. Compare your delta-v to its delta-v.
- [ ] **Braced hit:** set `F2` to BRACE, reset with `F3`, then run into the planted CPU. This should cost you more.
- [ ] **Side hit:** hit the CPU's shoulder instead of its chest. The impulse and delta-v should change.
- [ ] **Dive contact:** sprint + dive into the CPU. You should trade footing for reach.
- [ ] **Stagger:** after a strong hit, try to steer immediately. Steering should feel reduced, the HUD should say `STAGGERED`, and the body should flash red.
- [ ] **Juke/spin contact:** hit while juking or spinning. The CPU's footing value should be lower, and the result should reflect the lost grip.
- [ ] **Airborne contact:** hurdle into or land next to the CPU. An airborne body should behave differently from a planted one.
- [ ] **Surface comparison:** repeat the same hit on natural grass and on ice (`F4`). The same collision should move you more on ice.
- [ ] **Strafe mode:** set `F2` to STRAFE. The CPU should circle at medium range and back off when too close.
- [ ] **Separation:** walk slowly into the CPU and stop. The bodies should separate instead of overlapping or jittering.
- [ ] **Reset controls:** `F3`, `F5`, and the auto-reset should all leave you in control of the next test.

## Reading the HUD

| Field | Meaning |
| --- | --- |
| `closing` | How fast the bodies were approaching at contact, in m/s |
| `impulse` | Raw momentum exchange, in N*s |
| `delta-v you / cpu` | Velocity change each body received |
| `effective mass` | Mass after footing, strength, facing angle, condition, and traction |
| `cpu footing` | About 1.20 braced/standing, 1.0 running, lower airborne/diving |
| `traction` / `surface` | Current ground grip and the `F4` surface |
| `state` | Current player state: grounded, PLANTING, SPINNING, STAGGERED, etc. |
| `collisions` | Number of discrete impacts since the last reset |

## Current baseline

A headless straight-line hit between the 88 kg receiver and the 108 kg CPU produced:

- closing speed: **7.67 m/s**
- impulse: **401.7 N*s**
- delta-v on the receiver: **5.70 m/s**
- delta-v on the CPU: **2.98 m/s**

Treat this as a reference point, not a target. The useful question is whether the
relative result feels right for the angle, footing, and surface you tested.

## What the collision model uses

- Real body mass for the impulse
- Closing speed along the contact normal
- Low restitution
- Footing: braced/planting, running, landing, airborne, diving
- `break_tackle_force` for strength
- Facing angle at contact
- Current condition/stamina modifier
- Surface traction folded into effective mass
- A short steering lock after strong impacts

## Known limits

- The CPU is a collision test dummy. It chases, braces, and strafes; it does not tackle or dive yet.
- There is no tackle animation. The hit is a velocity change plus a stagger.
- Sustained leaning is handled by positional separation; the collision counter only counts discrete impacts.
- The auto-reset is a test aid, not game behavior.

## Feedback to send

When something feels wrong, note:

1. CPU mode (`CHASE`, `BRACE`, `STRAFE`)
2. Surface (`F4`)
3. What you were doing (sprint, dive, juke, spin, hurdle)
4. Whether the CPU was moving, braced, or strafing
5. The HUD numbers if visible
6. Whether it felt too strong, too weak, too fast, or too slidey
