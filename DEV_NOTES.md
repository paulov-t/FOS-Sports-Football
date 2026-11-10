# FOS Sports Football - Dev Notes

Last worked on: Nov 5 2026
Repo: https://github.com/NinjaActual0/FOS-Sports-Football.git
Engine: Godot 4.7 (project uses 4.7 features)

## What we did recently
- Implemented QB slide (give-up slide) triggered by dive button (X) when moving
- Adjusted slide to be flatter/more butt-slide like (increased SLIDE_PITCH_RAD to 1.35, dampening to 0.65)
- Slide triggers whenever moving at >= SLIDE_MIN_SPEED regardless of sprint
- Added dive/slide mechanics earlier (feet-first slide, head-first dive when sprinting)

## Key files
- src/entities/PlayerEntity.gd - Player movement, dive/slide/hurdle/spin/juke logic
- src/input/InputManager.gd - Input mappings/glyphs
- src/core/ - Game managers

## To resume
1. Open project in Godot 4.7+
2. Main scene: res://src/ui/MainMenu.tscn
3. Test sliding with dive button (X) while moving

## Notes
- Slide is for QB give-up after scramble to avoid hits
- Visual tilt is dampened for slide vs dive
