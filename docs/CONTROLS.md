# Controls

## Decision: classic Madden scheme

Default bindings follow the classic Madden layout. It is the most familiar scheme for
most players, so it is the right starting point. Remapping stays fully supported, and
alternative schemes (including our own) can layer on later.

The important part: **the control scheme is only a mapping.** Cuts and spins are physics
events, not button-triggered animation states.

**Input is screen-relative, not body-relative.** Pushing the stick right moves the player
right *on screen*, whichever way the body happens to be facing. The same rule applies to the
right stick: a right flick jukes to screen-right, even if the player is running at the camera
and its own right shoulder is pointing the other way. Stick input is projected through the
active camera, so this stays true once the camera becomes adjustable. Anything the AI drives
uses world-space vectors and never needs this conversion.

## Ball carrier

| Action | Xbox | PlayStation | Keyboard | Status |
| --- | --- | --- | --- | --- |
| Move | Left stick | Left stick | WASD | Done |
| Sprint | RT | R2 | Shift | Done |
| Spin | B | Circle | Q | Done |
| Cut / plant | Left stick, sharp | Left stick, sharp | WASD, sharp | Done (emergent) |
| Juke | Right stick L/R | Right stick L/R | J / L | Done |
| Stiff arm | A | Cross | — | Planned |
| Dive | X | Square | X | Done |
| Hurdle | Y | Triangle | Space | Done |
| Cover ball | RB | R1 | — | Planned |
| Lateral | LB | L1 | — | Planned |

### Why "cut" has no button

A cut is not an action the player selects. It is what happens when momentum in one
direction gets asked to become momentum in another, faster than the body can do it. You
cut by moving the stick. The system then decides how much speed that costs, based on
angle, current speed, agility (3-cone, shuttle), and traction.

That is why a good player cuts better than a bad one without any dice involved.

### Spin

Spin has a button because it is a *decision*: keep your momentum, give up your steering,
and hope the defender's leverage breaks. It costs speed up front, locks your lateral
acceleration for the duration, and has a cooldown.

### Juke

A juke has a button because it is a *commitment*, not a change of direction: you push off
the outside foot and add sideways momentum **on top of** the speed you already have. Unlike
a cut, your drive is not killed — the turf scrubs the sideways push away over about half a
second. What you pay is a small forward cost, a beat where your steering is compromised, and
a cooldown.

That makes it a real choice: juke into open space and you gained a step; juke into traffic
and you burned a beat. The physical size of the push comes from agility, and eventually the
*deception* comes from defenders having to read your lean and momentum rather than your
destination.

### Hurdle

The hurdle is the most committal move in the set, and that is the point. The vertical impulse
is derived from the vertical jump measurement — a run only converts about half of your
standing power into height, the rest goes into keeping your speed — so clearance is a body
property, not a button roll.

Once the feet leave the turf there is no plant, no cut, no brake, and no juke or spin. Your
line is decided at takeoff. Air control is a fifth of ground acceleration, which is enough to
drift a yard and nowhere near enough to turn.

Landing is priced by the impact you actually carried into the turf: absorption time and drive
loss both scale with downward speed. A short hop on the run is nearly free; a long jump landed
flat is not. Nothing checks whether a defender was in the way — clearing a diving arm is
decided by your real clearance against his real height at the moment he arrives.

### Dive

The dive is the first move that changes the *shape* of the body. Standing is a tall capsule; diving
swaps in a short horizontal one, so the body is genuinely low and genuinely long instead of a
standing capsule tipped over. The origin never moves — the collision shape is offset instead — so
standing back up can never pop the player out of the turf.

The launch is momentum plus a push, with a floor so that a dive from a standstill is still a
lunge. It is a real hop — about a quarter of a metre of rise, with the body rotating through
the flight and only settling onto the turf on the way down, so the arc reads as travel rather
than as the body tipping over in place. In the air there is no control at all: the arc is
whatever you left with. Touchdown is not a landing; the slide is priced by turf friction acting
on the momentum you actually carried in, which is why a dive at full speed covers far less
ground than running would over the same beat.

Then you get up. That is the cost, and it is the whole cost: roughly a second from takeoff to
being a runner again at full speed, and about four fifths of a second from a jog, during which
juke, spin, hurdle and dive are all refused. Nothing about the outcome is rolled — a dive tackle
lands because the defender's body reached yours, not because a check passed.

Reach is real geometry: the downed body extends about 0.45 m further forward than the standing
capsule, so the last half-yard at the goal line is decided by the shape, not by a bonus.

The same `perform_dive()` will be the defensive dive tackle. The button is shared with the
quarterback slide in the passing set — both are "go to ground now", and which one you get is
resolved by what the player is holding.

## Quarterback / passing (planned)

| Action | Xbox | PlayStation | Keyboard |
| --- | --- | --- | --- |
| Throw to receiver | Receiver icon button | Receiver icon button | — |
| Pump fake | RB | R1 | — |
| Scramble | Left stick | Left stick | WASD |
| Slide | X | Square | — |

Passing will be timing and placement driven. The button selects the target; ball
trajectory, lead, and whether the window is actually open come from physics.

## Defense (planned)

| Action | Xbox | PlayStation | Keyboard |
| --- | --- | --- | --- |
| Move | Left stick | Left stick | WASD |
| Sprint | RT | R2 | Shift |
| Tackle | A | Cross | F |
| Dive | X | Square | X |
| Swat | X | Square | — |
| Intercept | Y | Triangle | — |
| Switch player | B | Circle | — |

## Pre-snap (planned)

| Action | Xbox | PlayStation |
| --- | --- | --- |
| Snap | A | Cross |
| Audible | Y | Triangle |
| Hot route | X | Square |
| Motion | B | Circle |

## Greybox sandbox

`src/core/GreyboxField.tscn` is the movement test bed. Everything below exists so you can
see what the physics is doing; none of it is a game system:

| Aid | What it is |
| --- | --- |
| Field markings | A real 120 x 53.3 yd field: 5-yard lines, 1-yard hash marks, mown stripes, painted numbers |
| Facing chevron | Floats above the head and points where the player is facing |
| Shoulder bar | Turns with the body, so torso alignment is readable from any angle |
| Spot readout | HUD line showing the nearest painted yard line |
| F1 | Toggles a 1-yard reference grid over the field |
| F2 | Cycles the CPU defender through CHASE, BRACE and STRAFE |
| F3 | Resets both players to their spawn spots and clears the collision counter |
| F4 | Cycles the surface (natural grass, turf, wet, mud, snow, ice) |

The field's long axis runs into the screen, so yard lines recede toward the horizon. That
is deliberate: it is the strongest cue for judging speed and distance travelled.

### Player-vs-player contact

The sandbox spawns a 108 kg MLB against the 88 kg receiver. Both are real `CharacterBody3D`
players; body-to-body contact is resolved after they move, not by `move_and_slide()`.

The HUD reports the closing speed, impulse, each player's velocity change and the effective
masses used for the exchange. Effective mass is not just weight: it includes footing
(braced, running, landing, airborne, diving), `break_tackle_force`, the angle between the
body's facing and the contact normal, current condition, and the surface's traction.

A strong hit briefly locks steering. That stagger is the readable consequence of the
impulse, not a separate tackle animation. The `F4` surfaces exist so you can see the same
hit behave differently when the turf cannot supply the same grip.

## Keyboard and mouse

Keyboard is a first-class input, not a fallback. Analog-only controls (sprint trigger,
right-stick juke) get digital equivalents. Gamepad glyphs swap automatically when you
switch devices.

## Adding a control

1. Add the action in **Project Settings → Input Map** (or `project.godot`).
2. Add the glyph string to each set in `src/input/InputManager.gd`.
3. Read it with `Input.is_action_pressed()` / `Input.is_action_just_pressed()`.
4. Update this file.

Never let a button directly decide an outcome. A button should change a physical input
(force, impulse, target point, timing window). The outcome comes out of the simulation.
