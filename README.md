# Factorio Mod: Turn Spidertrons into automatic biter killing machines

**Help wanted! Inquire within!**

This mod is looking for contributors and/or a new maintainer. If you are
interested, send an [email](email:lars_e_krueger@gmx.de).

## Introduction

As I find it boring to play without biters and too annoying to deal with them
manually, I created this mod.

If you activate this mod, all spidertrons named *Killer* will find the nearest
spawner or worm and perform a hit-and-run attack on it. That means your
killers need to be armed with lasers and/or rockets. Should they take
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

**If you see modified defaults on a new save, go to the *Main Menu*, then
*Settings*, then *Mod Settings*, then *Map* and finally reset all the *Hunter
and Killer Spidertrons* settings to the default values.**

## Roadmap / ChangeLog

- 0.1: Killer function
- 0.1.1: Fixes
- 0.2: Explorer
- 0.2.1: Bug fixes
- 0.2.2: Messages
- 0.2.3: Improvements
- 0.2.4: Fix packager script
- 0.3: Settings
- 0.4: Different Loadouts
- 0.5: Multiple killer groups
- 0.5.1: Bug fixes
- 0.5.3: Bug fix
- 0.6: Update to Factorio 2.0
- 0.6.1: Bug fix
- 0.6.2: Search And Destroy Mode
- 0.6.3: Bug fix
- 0.6.4: Bug fix
- 0.7.0: Flying Hunters
- 0.7.1: Copy-paste fixes
  - ☑ Faster updates of vehicle list
- 0.8.0: Multi-surface fixes
  - ☐ Check surfaces with killers on them
  - ☐ Send killers to targets on their surface
  - ☐ Test with finite maps. Special mode to find all targets if map is finite.
- 0.8.1: Group improvements
  - ☐ Different group size for exploration target
- 0.9: Hunter function

## How does the *Killer* operate?

The *Killer* spidertron works by what is known as a
[Finite State Machine](https://en.wikipedia.org/wiki/Finite-state_machine).

Each *Killer* is always in one of the following states. It remains in this
state and does something until the condition for a new state is fulfilled. The
state is indicated by the color of the spidertron.

The spawners, worms, and places to explore will be called *targets* in the following descriptions.

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
| leader    | Wait for assembling an attack group.          | Dark Red |
| follower  | Wait for assembling an attack group.          | Dark Green |

The conditions to switch from one state to another are:

| From State | Condition(s)                                     | To State |
|------------|--------------------------------------------------|----------|
| idle       | A target is close enough to a polluted chunk.    | planning/attack |
| idle       | Health or ammo are low.                          | go-home |
| idle       | Group attack: Go to assembly position.           | leader |
| idle       | Group attack: Go to assembly position.           | follower |
| approach   | The selected target is destroyed.                | idle |
| approach   | Safe distance to target reached.                 | attack |
| attack     | Target destroyed, low health, or low ammo.       | retreat |
| attack     | Target reached.                                  | retreat |
| retreat    | Safe position reached, Health and ammo are ok.   | idle |
| retreat    | Safe position reached, Health or ammo are low.   | planning/go-home |
| go-home    | Homebase reaced.                                 | re-arm |
| go-home    | Health and ammo are ok.                          | idle |
| re-arm     | Health and ammo are ok.                          | idle |
| planning   | Finding a path to the target                     | attack/go-home |
| planning   | Sent somewhere by remote.                        | walking |
| walking    | Arrived at target.                               | idle |
| leader     | Group is assembled.                              | approach |
| follower   | Group is assembled.                              | approach |
| leader     | Group is disbanded.                              | idle |
| follower   | Group is disbanded.                              | idle |

The planning takes time. Therefore, the spidertrons will walk in circles to
evade spitter fire (except when assembling a group). Planning itself is done in
the background, at a pace determined by the game engine. The computation is
shared evenly between all spidertrons in *planning* state. Also, the planner
can become distracted by pockets and peninsulas.

If the target is destroyed during planning, the spidertron goes back to *idle*
state. This is checked every few seconds (configurable, see settings below).

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
number of chunks at the edge of the pollution as
*places to visit*.

Enemies and places are only reported if the number increased since the last
scan. If you don't see a message, your *Killer*s keep up with the growth of the
pollution and the enemy expansion.

For all these four numbers, a history of the last 8 (different) values is displayed. The
bars are normalized to minimum and maximum. The numerical value of oldest value
is displayed on the left, the newest value on the right. Thus a display of

123 ▁▂▃▄▁▆▇█ 456

indicates that you had 123 items at the beginning. The number rose
steadily until the 5th update, where it dropped to close to 123
again (if it had dropped a lot below 123, the first bar would be higher). After
that it resumed growing until it reached 456 with the current update.

## Loadout Variations / Repair Drones

Beginning version 0.4, the mod supports different loadouts, incl. laser-only
and repair drones.

Re-arming stops when the minimum number of requested items is loaded into
trunk, fuel, and ammo slots.

Spidertrons return home for refueling when at least one requested item is
depleted in trunk, fuel, and ammo slots together.

If a roboport is present, it will be turned off before attacking and turned on
again after the spidertron retreated. This is done to save the construction bots.
If the construction bots repair a spider on the way home, and it still has ammo
and fuel, it will pick up the nearest target as usual.

## Attack Groups

Beginning version 0.5, the mod supports attack groups. The size of the group is
determined by the setting *Number of Killers to group for an attack*. The
default value is two as it's dangerous out there and you should never go alone.

If you send our your poor spidertrons alone, their behaviour will be almost the
same as in version 0.4. You will see less time spent in the mod, usually. This
might degrade your FPS less than before if you have a large base.

After increasing the group size, the behaviour changes a bit. If a killer picks
out a target, it will move into position at a distance to the target. This
distance is configure by the setting *Distance to target when assembling before
attack*, default 300 tiles. This first killer in a group becomes the leader and
is shown in dark red.

As soon a leader has been selected, killers will choose between picking a
target (and becoming the leader of a new group) or joining an existing group.
The chose the closer option. If they join a group, they become a follower and
are drawn in dark green.

The followers will go to the assembly spot close to the target. Once the whole
group is there, it will attack as usual. At the moment, the approach phase of
the attack begins (orange colour), the group is disbanded and the spidertrons
act individually towards the same target. If one gets damaged, the other carry on.

It also means that spidertrons walk at their own pace during attack. It's
recommended to give all of the same number of exoskeletons and reactors.
Otherwise the faster killer will be attacked first and you will lose a large
part of the advantage of the group attack.

You can change the size of the groups at any time. If you experience problems
with drastic changes, send some killers a few steps aside with a spidertron
remote. This will disband the group and the leader/follower ratio will stabilize.

## Aircraft

Some mods (e.g. Lex' Aircraft) provide air vehicles based on the spidertron
prototype. They can be also controlled by this mod. As aircraft are not bound
to navigate on land, a second set of pathfinding rules were created.

This second set can be activated by naming a vehicle *Predator*. Be aware that
naming an aircraft *Killer* will just lead to slower routes being planned,
while naming a land vehicle *Predator* will get it stuck at the coast.

## Settings

Beginning version 0.3, the mod has some tunable parameters.

**If you see modified defaults on a new save, go to the *Main Menu*, then
*Settings*, then *Mod Settings*, then *Map* and finally reset all the *Hunter
and Killer Spidertrons* settings to the default values.**

### Number of enemies to check per scan cycle

Every scan cycle ("Number of ticks between scans for enemy/pollution gap") a
fixed number of detected enemies is scanned if they are close to the pollution.
The more enemies are scanned, the faster the list of dangerous nests is updated
and the earlier the spidertrons can pay them a visit. This can lower
your FPS/UPS and make the game slower.

* Earliest visible effect: Next scan
* Default: 100
* Min: 1
* Max: 1000000
* Internal name: `hunter-killer-enemies-per-cycle`

### Number of chunks to check per scan cycle

Every scan cycle ("Number of ticks between scans for enemy/pollution gap") a
fixed number of chunks (32x32 tile blocks in the map) is scanned if they are
close to pollution and unmapped part. The more chunks are scanned, the faster the list of
potential hiding places is updated and the earlier the spidertrons can
make sure it's safe there. This can lower your FPS/UPS and make the game
slower.

* Earliest visible effect: Next scan
* Default: 500
* Min: 1
* Max: 1000000
* Internal name: `hunter-killer-chunks-per-cycle`

### Size of gap between pollution and unmapped

If a chunk is checked to be interesting, a number of chunks around it are
checked if at least one contains pollution and at least one is unmapped (black
in the map view). This setting determines the number of chunks to check around
the current one and therefore the gap between pollution and the unknown.

The value is determined by the range of the spidertron's on-board radar. If the
gap is set too big, it will visit place that it can't map and therefore visit
it again next time. This setting is therefore only to accomodate mods that
increase the range of the Spidertron's radar.

Increasing this number beyond reasonable values (e.g. 5, equal to 160 tiles)
will result in a noticable slowdown of the game.

* Earliest visible effect: Immediately
* Default: 2
* Min: 1
* Max: 100
* Unit: chunks (32x32 tiles)
* Internal name: `hunter-killer-pollution-radius`

### Distance of spidertron path to water/nests

When a spidertron plans a path, it avoids getting too close to nests and water.
This prevents it from running through nests. You can increase the gap by
increasing the value. This can block access to otherwise reachable nests on
peninsulas or in narrow passages between lakes.

* Earliest visible effect: Next path planning
* Default: 8
* Min: 1
* Max: 100
* Unit: Tiles
* Internal name: `hunter-killer-pf-bbox`

### Stopping distance to target

When a spidertron plans a path, it tries to get as close to the target as
possible, but not closer than this distance. Setting this value too high can
result in pointless trips as nothing is explored or exploded.

* Earliest visible effect: Next path planning
* Default: 16
* Min: 1
* Max: 1000
* Unit: Tiles
* Internal name: `hunter-killer-pf-radius`

### Distance to retreat after attack

After a spidertron has reached it's target, it will retrace its steps to a safe
distance. If it was already closer than this, it will return to the starting
point.

* Earliest visible effect: Next attack
* Default: 100
* Min: 1
* Max: 1000000
* Unit: Tiles
* Internal name: `hunter-killer-retreat-distance`

### Percentage of health to go home

If a spidertron's health falls below this threshold during approach or after
retreating, it will return to the nearest home base to get repaired. Be aware
that the value is ignored during attack to not trigger a long and dangerous
path finding in the middle of a nest.

* Earliest visible effect: Immediately
* Default: 80
* Min: 1
* Max: 99
* Internal name: `hunter-killer-go-home-health`

### Difference between spidertron path lengths to steal target (before version 0.5)

This setting is not used in version 0.5.

Spidertrons gossip from time to time ("Number of ticks between stealing targets") about their targets. If two of them find
out that switching their targets is significantly less distance for both of
them, they reconsider their ways. *Significantly* means here: The total
distance (as the crow flies) between targets after switching is at least
*value* tiles shorter than the current total distance. *value* means the value of
this setting.

* Earliest visible effect: Next target steal cycle
* Default: 200
* Min: 1
* Max: 1000000
* Unit: Tiles
* Internal name: `hunter-killer-steal-distance`

### Number of cycles between target checks during planning

Every *value* state updates ("Number of ticks between state changes"),
spidertrons check if their target has been killed by another spidertron.
*value* means the value of this setting. If the target has been collateral
damage, they try to pick a new target.

* Earliest visible effect: Immediately
* Default: 5
* Min: 0
* Max: 1000000
* Internal name: `hunter-killer-target-check-cycles`

### Number of ticks for target search cycles

One tick corresponds to one full update of the game state. If you see 60 UPS,
60 ticks pass per second.

Every *value* (the value of this setting) ticks, spidertrons check their to-do
list of places to see and biters to kill. If they find some, one of them starts
planning.

* Earliest visible effect: New game / after loading
* Default: 6
* Min: 1
* Max: 1000000
* Internal name: `hunter-killer-freq-assign`

### Number of ticks between stealing targets (before version 0.5)

This setting is not used in version 0.5.

One tick corresponds to one full update of the game state. If you see 60 UPS,
60 ticks pass per second.

Every *value* (the value of this setting) ticks, spidertrons compare their maps
to see if they could be more efficient if they switch targets.

* Earliest visible effect: New game / after loading
* Default: 180
* Min: 1
* Max: 1000000
* Internal name: `hunter-killer-freq-reassign`

### Number of ticks between scans for enemy/pollution gap

One tick corresponds to one full update of the game state. If you see 60 UPS,
60 ticks pass per second.

Every *value* (the value of this setting) ticks, spidertrons scan a part of the
list of biter positions or chunks. See "Number of enemies to check per scan
cycle" and "Number of chunks to check per scan cycle".

The value of this setting can be balanced against the two others to keep the
UPS high during scanning.

* Earliest visible effect: New game / after loading
* Default: 12
* Min: 1
* Max: 1000000
* Internal name: `hunter-killer-freq-targets`

### Number of ticks between state changes

One tick corresponds to one full update of the game state. If you see 60 UPS,
60 ticks pass per second.

Every *value* (the value of this setting) ticks, spidertrons reconsider what
they shall be doing. Most of the time, it's the same as before.

This setting balances the reaction speed (e.g. should a spidertron return home)
vs. the game speed. Frequent, unnecessary checks slow down the game. Infrequent
checks could kill a spidertron, because it doesn't go home early enough when it
gets damaged.

* Earliest visible effect: New game / after loading
* Default: 30
* Min: 1
* Max: 1000000
* Internal name: `hunter-killer-freq-state`

### Distance to target when assembling before attack (new in version 0.5)

When a spidertron group plans an attack, it tries to keep the distance to the
target where the group assembles higher than the value of this setting. Higher
values can lead to a larger spread of the killers during the attack.

* Earliest visible effect: Next group assembly
* Default: 300
* Min: 1
* Max: 1000000
* Unit: Tiles
* Internal name: `hunter-killer-assemble-distance`

### Number of Killers to group for an attack (new in version 0.5)

Number of spidertrons to attack together. Lower numbers allow to attack more
targets at the same time (e.g. during rapid groth of the pollution cloud).
Higher numbers increase the power of a single attack.

* Earliest visible effect: Next group assembly
* Default: 2
* Min: 1
* Max: 1000000
* Unit: Spidertrons
* Internal name: `hunter-killer-attack-group-size`

### Search & Destroy

If on, search target anywhere on the map, regardless the pollution. This might
slow down the game over time as it reveals the whole (reachable) map.

* Earliest visible effect: Next Scan Cycle
* Default: Off
* Internal name: `hunter-killer-search-and-destroy-mode`

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

## Behavioural changes after updates

## 0.3

You might see a spike in exploration targets, esp. around lakes. This is due to
a parameter change for the path finder. Now, the path finder will select a
target, even if more of the center chunk is water. This results in some visits
to previously ignored chunks when the centre of the lake is unmapped. After
these lake chunks have been mapped, they edge of the lake will be ignored in
future scans as before.

Spidertrons will return earlier to base if they are damaged. Threshold was set
to 80% from 70% before.

Spidertrons will switch targets more frequently. The old cycle time was too
high and felt sluggish. This can lead to a few bogus switches if a larger
number of spidertrons is at the same place, e.g. a home base. However, the
solution will stabilize more quickly to reduce the total amount of travel.

## 0.5

Spidertrons will look for the closest target and don't switch targets
afterwards.

This may lead to increased wandering of the killers around the map, which can
be compensated by more spidertrons.
