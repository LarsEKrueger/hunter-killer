# Factorio Mod: Turn Spidertrons into automatic biter killing machines

## Introduction

As I find it boring to play without biters and too annoying to deal with them
manually, I created this mod.

If you activate this mod, all spidertrons named *Killer* will find the nearest
spawner or worm and perform a hit-and-run attack on it. That means your
killers need to be armed with either lasers or rockets. Should they take
damage or run low on ammo, they will automatically to the closest marker
named *Homebase* and wait there until they have been repaired and rearmed.

To mark a *Homebase*, create a map marker with the name *Homebase*. Thanks
sOvr9000 for the better wording.

If there are no enemies to kill, your *Killer*s will walk around the map to
ensure that there is always an strech of unpolluted area between the explored
and the unknown. This ensures that biters have no reason to attack you.

Be aware that this is imperfect. Sometimes *Killer*s walk through the middle of
nests and get damaged faster than they can escape. Sometimes, they can't find a
way to reach an enemy.

## Roadmap / ChangeLog

- 0.1: Killer function
- 0.1.1: Fixes
- 0.2: Explorer
- 0.2.1: Bug fixes
- 0.2.2: Messages
- 0.2.3: Improvements
    - [X] Plan path around nests
    - [X] Don't print "wants to go home"
- 0.2.4: Fix packager script
- 0.3: Optimisation
    - [ ] Parameter / settings
    - [ ] Fine tuning default parameters
- 0.4: Optimisation
    - [ ] Support for spiders with repair drones
    - [ ] Support for spiders without rockets
- 0.5: Hunter function
- 0.6: Multiple killer/homebase groups

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
| walking   | Going to where the autopilot leads it.        | Grey |
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

The planning takes time. Therefore, the spidertrons will walk in circles to
evade spitter fire. Planning itself is done in the background, at a pace
deermined by the game engine. The computation is shared evenly between all
spidertrons in *planning* state. Also, the planner can become distracted by
pockets and peninsulas.

If the target is destroyed during planning, the spidertron goes back to *idle*
state. This checked every few seconds.

## Messages

The mod reports the number of active *Homebase*s and *Killer*s whenever they change.

After the completion of a scan, the number of nests and worms in the explored
part of the maps is reported as *enemies of the realm*. This includes enemies
on unreachable islands.

As soon as all enemies have been scanned to be in or close to the pollution --
and therefore a thread -- the mod scans the map to find places to explore. It
will always try to keep a gap of two chunks (Each chunk is 32x32 tiles and
corresponds to the blocks of identical pollution you see in the map.) around
the edge of the pollution. This allows the *Killer*s to keep up with the
growing cloud.

When the scan for places to explore has been completed, the mod reports the
number of enemies in the pollution and chucks at the edge of the pollution as
*places to visit*.

Enemies and places are only reported if the number increased since the last
scan. If you don't see a message, your *Killer*s keep up with the growth of the
pollution and the enemy explansion.

For all these four numbers, a history of the last 8 values is displayed. The
bars are normalized to minimum and maximum. The numerical value of oldest value
is displayed on the left, the newest value on the right. Thus a display of

123 ▁▂▃▄▁▆▇█ 456

indicates that you had 123 items at the beginning. The number rose
steadily until the 5th update, where it dropped to close to 123
again (if it had dropped a lot below 123, the first bar would be higher). After
that it resumed growing until it reached 456 with the current update.

## Limitations and Recommended Mods

Spidertrons, even those controlled by an "advanced" AI such as this mod, are not
very smart.

Spidertrons are also very single-minded. They approach a target with complete
disregard for other targets. They sometimes trample through big nests and get
badly damaged in the process.

In these situations you have to help the Spidertrons. Use the *Spidertron Squad
Control* or similar mods to redirect them.

The mod *Constructron Continued* is helpful to pave bridges to peninsulas.

If the pathfinder seems stuck (no activity from *Killer*s, at least one is
planning), issue the command `game.forces['player'].kill_all_units()` in the
console window. This will clear the pathfinder cache. Move the continuously
planning *Killer* a bit and you should see activity soon.
