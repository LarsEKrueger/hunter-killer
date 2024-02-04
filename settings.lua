--[[
  settings.lua: Define user-controllable parameters for the factorio mod *HunterKiller*.

Copyright 2023 Lars Krueger

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

data:extend({
  {
    name = "hunter-killer-enemies-per-cycle",
    localised_name = "Number of enemies to check per scan cycle",
    localised_description = "Lower = faster game, higher = faster reaction",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-chunks-per-cycle",
    localised_name = "Number of chunks to check per scan cycle",
    localised_description = "Lower = faster game, higher = faster reaction",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 500,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-pollution-radius",
    localised_name = "Size of gap between pollution and unmapped",
    localised_description = "Lower = more biter attacks, higher = slower game. unit: chunks",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 1,
    maximum_value = 100,
  },
  {
    name = "hunter-killer-pf-bbox",
    localised_name = "Distance of spidertron path to water/nests",
    localised_description = "Lower = reach more places, higher = less damage. unit: tiles",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 8,
    minimum_value = 1,
    maximum_value = 100,
  },
  {
    name = "hunter-killer-pf-radius",
    localised_name = "Stopping distance to target",
    localised_description = "Lower = more collateral damage, higher = less damage. unit: tiles",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 16,
    minimum_value = 1,
    maximum_value = 1000,
  },
  {
    name = "hunter-killer-assemble-distance",
    localised_name = "Distance to target when assembling before attack",
    localised_description = "Lower = faster attacks, higher = less damage. unit: tiles",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 300,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-retreat-distance",
    localised_name = "Distance to retreat after attack",
    localised_description = "Lower = faster attacks, higher = less damage. unit: tiles",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-go-home-health",
    localised_name = "Percentage of health to go home",
    localised_description = "Lower = longer attacks, higher = less damage",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 80,
    minimum_value = 1,
    maximum_value = 99,
  },
  {
    name = "hunter-killer-target-check-cycles",
    localised_name = "Number of cycles between target checks during planning",
    localised_description = "Lower = faster reaction, higher = slower game",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 0,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-freq-assign",
    localised_name = "Number of ticks for target search cycles",
    localised_description = "Lower = faster reaction and slower game. unit: 1/UPS",
    type = "int-setting",
    setting_type = "startup",
    default_value = 6,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-freq-targets",
    localised_name = "Number of ticks between scans for enemy/pollution gap",
    localised_description = "Lower = Faster reaction and slower game. unit: 1/UPS",
    type = "int-setting",
    setting_type = "startup",
    default_value = 12,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-freq-state",
    localised_name = "Number of ticks between state changes",
    localised_description = "Lower = Faster reaction and slower game. unit: 1/UPS",
    type = "int-setting",
    setting_type = "startup",
    default_value = 30,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-attack-group-size",
    localised_name = "Number of Killers to group for an attack",
    localised_description = "Lower = more targets dealt with, higher = less damage to Spidertrons",
    type = "int-setting",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 1,
    maximum_value = 1000000,
  },
  {
    name = "hunter-killer-debug-print-targets",
    localised_name = "Debug: Count and print the number of places checked per minute",
    localised_description = "Can degrade performance",
    type = "bool-setting",
    setting_type = "runtime-global",
    default_value = false,
  }
})
