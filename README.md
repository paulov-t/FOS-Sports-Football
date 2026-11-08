# FOS Sports Football

A physics-driven, real-time American football game. **Free and open source (MIT).**

No dice rolls. No scripted outcomes. No hidden "clutch" logic. Every play is decided by
momentum, leverage, angles, velocity, timing, positioning, weather, equipment, and the
physical condition of the player — the same way it works on a real field.

## Why

Modern football games are card games wearing a helmet. A 92% completion chance and a
"sack chance" table decide the result before the ball is snapped. FOS Sports Football
throws all of that out.

The result of a down is whatever the physics of the objects on the field produce.

## Pillars

| Pillar | Meaning |
| --- | --- |
| **Objects over tables** | The engine tracks players, the ball, and the field as physical objects. Outcomes come from their relationships, not success/failure charts. |
| **Measurables matter** | Players are defined by real combine numbers — 40 time, 10-yard split, 3-cone, shuttle, vertical, broad, bench, height, weight, wingspan, arm length, hand size. Everything else is derived. |
| **Physics decides** | Tackles, catches, blocks, breaks, and collisions come from mass, momentum, angles, and timing. |
| **One engine, three modes** | Player control, Coach Mode, and Full Game Sim all run on the exact same physics step. Sim is just accelerated time, not a second engine. |
| **Sim and Arcade are tuning sets** | Same rules. Different mass, acceleration, gravity, and restitution values. |
| **Environment is physical** | Rain, snow, wind, temperature, humidity, altitude, and field surface change traction, drag, and ball flight. |
| **Health is physical** | Stamina, hydration, soreness, and injury continuously scale output. No random injury failure rolls. |
| **Cross platform** | Windows, Linux, macOS, Steam Deck. No platform-locked APIs. |
| **Moddable from day one** | Playbooks, rosters, rulesets, uniforms, fields, and leagues are data. Drop them in `mods/`. |

## Status

Early scaffold. A greybox sandbox is in place to prove out movement feel:
measurables → acceleration, top speed, turn rate, cutting, and spinning are all live and
tunable from the inspector.

### Working now

- Physics-derived movement from combine measurables (no outcome tables)
- Cut/plant with real momentum loss based on angle, speed, agility, and traction
- Spin move that preserves momentum but locks steering
- Fatigue, hydration, soreness, and injury continuously scaling output
- Weather/surface/altitude affecting traction and air density
- Xbox, PlayStation, and keyboard input with automatic glyph switching

### Next

- Ball as a physics object, snap → dropback → throw
- Timing/placement passing windows
- Defender pursuit, tackling, and leverage
- Play calling and coach mode

## Requirements

- [Godot 4.7+](https://godotengine.org/download) (standard build, no C# needed)
- Any OS. Tested target: Windows, Linux, macOS, Steam Deck.

## Running

```bash
git clone https://github.com/NinjaActual0/FOS-Sports-Football.git
cd FOS-Sports-Football
godot --path . 
```

Or open `project.godot` in the Godot editor and press **F5**.

## Controls

Default bindings follow the **classic Madden scheme**. See [docs/CONTROLS.md](docs/CONTROLS.md)
for the full table and the planned passing/defense/pre-snap layouts.

| Action | Keyboard / Mouse | Xbox | PlayStation |
| --- | --- | --- | --- |
| Move | WASD | Left stick / D-pad | Left stick / D-pad |
| Sprint | Shift | RT | R2 |
| Spin | Q | B | Circle |
| Cut | sharp WASD change | sharp stick change | sharp stick change |
| Pass | Left click | X | Square |
| Tackle | F | A | Cross |
| Pause | Esc | Start | Options |

Glyphs swap automatically based on the last device used. Every action is remappable in
**Project Settings → Input Map**.

## Project layout

```
src/
  core/         game state, health, field scenes
  data/         measurables and other resource definitions
  entities/     players, ball, field objects
  environment/  weather, surface, atmosphere
  input/        device detection and glyph sets
  physics/      tuning sets and physics helpers
  sim/          coach mode + full game simulation
  ui/           menus, HUD, play call
data/           default playbooks, rosters, rulesets
mods/           drop-in community content (gitignored)
docs/           design and modding documentation
```

## License

MIT — see [LICENSE](LICENSE).
