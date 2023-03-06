 # Factorio Mod: Turn Spidertrons into automatic biter killing machines

## Introduction

 As I find it boring to play without biters and too annoying to deal with them
 manually, I created this mod.

 If you activate this mod, all spidertrons named *Killer* will find the nearest
 spawner or worm and perform a hit-and-run attack on it. That means your
 killers need to be armed with either lasers or rockets. Should they take
 damage or run low on ammo, they will automatically to the closest marker
 named *Homebase* and wait there until they have been repaired and rearmed.

## Roadmap / ChangeLog

- 0.1: Killer function
- 0.1.1: Fixes
    - [X] MIT License
    - [X] Bug fix retreat: Don't plan
    - [X] Bug fix: Don't delete autopilot path after attack, before retreat
- 0.2: Explorer
    - [ ] Ensure visibility around pollution: use idle killers
- 0.3: Optimisation
    - [ ] Select non-polluted targets close by
    - [ ] Hierarchical planner / Generate better paths
    - [ ] Planning cache / not all spiders plan the same target
    - [ ] Parameter / settings
    - [ ] Fine tuning default parameters
    - [ ] Call home button
    - [ ] Deal with landfill
- 0.4: Multiple killer/homebase groups
- 0.5: Hunter function

## How does the *Killer* operate?

The *Killer* spidertron works by what is known as a
[Finite State Machine](https://en.wikipedia.org/wiki/Finite-state_machine).

Each *Killer* is always in one of the following states. It remains in this
state and does something until the condition for a new state is fulfilled. The
state is indicated by the color of the spidertron.

The spawners and worms will be called *targets* in the following descriptions.

| State     | Action                                        | Color |
|-----------|-----------------------------------------------|-------|
| idle      | Wait for a spawner / work to become a target. | White |
| planning  | Waiting for the path planner to finish        | Yellow |
| Walking   | Going to where the autopilot leads it.        | Grey |
| approach  | Walk up to the target.                        | Orange |
| attack    | Go towards the target until it is destroyed.  | Red |
| retreat   | Go back to the latest safe position.          | Cyan |
| go-home   | Return to the nearest *Homebase*.             | Blue |
| re-arm    | Wait to be rearmed and repaired.              | Green |

The conditions to switch from one state to another are:

| From State | Condition(s)                                     | To State |
|------------|--------------------------------------------------|----------|
| idle       | A target is close enough to a polluted chunk.    | planning/attack |
| idle       | Health or ammo are low.                          | go-home |
| approach   | The selected target is destroyed.                | idle |
| approach   | Safe distance to target reached.                 | attack |
| attack     | Target destroyed, low health, or low ammo.       | retreat |
| attack     | Target reached.                                  | retreat |
| retreat    | Safe position reached, Health and ammo are ok.   | idle |
| retreat    | Safe position reached, Health or ammo are low.   | planning/go-home |
| go-home    | Homebase reaced.                                 | re-arm |
| re-arm     | Health and ammo are ok.                          | idle |
| planning   | Finding a path to the target                     | attack/go-home |
| planning   | Sent somewhere by remote.                        | walking |
| walking    | Arrived at target.                               | idle |

Since the built-in path finding algorithm doesn't seem to work for longer
distances, this mod implements its own. It exploits the fact that spidertrons
can walk everywhere but on water. To keep things fair, *Killer*s will not plan
a route through uncharted territory.

The planning takes time. Therefore, the spidertrons will walk in circles to
evade spitter fire. Planning itself is done in the background, at a pace of 500
tiles/cycle or 5000 tiles/second at full UPS. The computation is shared evenly
between all spidertrons in *planning* state. Also, the planner can become
distracted by pockets and peninsulas. Therefore, in practice, less than 100
tiles/seconds of progress towards the target is made.

If the target is destroyed during planning, the spidertron goes back to *idle*
state. This checked every few seconds.

## Limitations and Recommended Mods

Spidertrons, even those controlled by an "advanced" AI such as this mod, are not
very smart.

They like the scenic route along the edge of a lake and -- literally
-- go the extra mile to see it. A future version might fix this.

Spidertrons are also very single-minded. They approach a target with complete
disregard for other targets. They sometimes trample through big nests and get
badly damaged in the process.

In these situations you have to help the Spidertrons. Use the *Spidertron Squae
Control* or similar mods to redirect them.
