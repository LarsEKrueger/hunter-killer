--[[
control.lua: Event handling script for the factorio mod *HunterKiller*.

Uses rstar from https://github.com/rick4stley/rstar/ as the r-tree
implementation for storing the target positions. MIT License

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

local StatisticsReporter = require 'StatisticsReporter'
local reporters = require 'reporters'
local targets = require 'targets'
local collision_mask_util = require 'collision-mask-util'
local util = require 'util'
local rstar = require 'rstar/rstar'
local aabb = require 'rstar/aabb'

-- Count and print number of killers
local function count_killers(vehicles, suffix)
  local killer_count = table_size( vehicles)
  storage.report_killers:set(killer_count)
end

-- Count and print number of homebases
local function count_bases(bases)
  local count = 0
  local b = bases
  while b do
    count = count + 1
    b=b.nxt
  end
  storage.report_bases:set(count)
end

-- Check if a vehicle is eligible to be managed by the mod.
local function is_eligible_vehicle(veh)
  if veh and veh.valid then
    -- If the name of the vehicle starts with 'Killer', it's eligible.
    if veh.entity_label then
      local killer_pos = string.find(veh.entity_label, 'Killer', 0, true)
      if killer_pos and killer_pos == 1 then
        return true
      end
    end
  end
  return false
end

-- Check if a tag is eligible to be managed by the mod.
local function is_eligible_homebase(tag)
  if tag and tag.valid then
    -- If the name of the tag starts with 'Homebase', it's eligible.
    local pos = string.find(tag.text, 'Homebase', 0, true)
    if pos and pos == 1 then
      return true
    end
  end
  return false
end

-- Detect all eligible vehicles and setup their state if they are new.
--
-- This function will be called when a vehicle's name or existence might have changed.
--
-- Vehicle ids will be used as keys. The vehicle state and a link to the
-- vehicle object will be used as the value in the table.
local function detect_vehicles()
  -- Get the vehicle list or start from scratch
  local old_vehicles = storage.vehicles or {}
  local new_vehicles = {}

  -- Go through all managed vehicles and remove those that are no longer eligible.
  for id,state in pairs(old_vehicles) do
    -- If veh doesn't exist anymore or is no longer named correctly, don't copy it to the new table.
    if is_eligible_vehicle(state.vehicle) then
      new_vehicles[id] = state
    end
  end

  -- Go through all vehicles in the game and add the eligible ones to the list
  -- of managed vehicles.
  local surf_vehicles = game.surfaces['nauvis'].find_entities_filtered{
        type='spider-vehicle',
        force='player'
      }

  for _,veh in ipairs(surf_vehicles) do
    if not new_vehicles[veh.unit_number] and is_eligible_vehicle(veh) then
      new_vehicles[veh.unit_number]={vehicle=veh, state=kState_idle, last_state=kState_idle}
    end
  end

  -- Write back the list
  storage.vehicles = new_vehicles

  count_killers( new_vehicles, ' managed')
end

-- Detect all homebase objects
local function detect_homebases()
  -- Get the list of homebase objects
  local bases = nil

  -- Go through all tags in the player's map and add the eligible one to the
  -- list of managed homebases
  local player = game.get_player(1)
  if player then
    local tags = player.force.find_chart_tags('nauvis')
    for _,tag in pairs(tags) do
      if is_eligible_homebase(tag) then
        local new_base = {tag=tag, nxt=bases}
        bases = new_base
      end
    end
  end

  -- Write back the list
  storage.homebases = bases

  count_bases(storage.homebases)
end

-- Compute the distance between two MapPositions
local function dist_between_pos(p1,p2)
  local dx = p1.x-p2.x
  local dy = p1.y-p2.y
  return math.sqrt( dx*dx + dy*dy)
end

-- Find targets ================================================

-- Return a bbox object from the given target
local function box_from_target(target)
  -- As boxes start at x,y and extend to x+w,y+h, shift x and y by half the
  -- width to center on the target
  local box = aabb.new( target.position.x-0.5, target.position.y-0.5)
  -- Add target as payload to the box
  box.target = target
  return box
end

-- Get the list of targets. Return true if targets were checked
local function find_valid_targets()
  local nauvis = game.surfaces['nauvis']
  if (not storage.enemy_list) and storage.target_tree:isEmpty() then
    local targets = nauvis.find_entities_filtered{
      force='enemy',
      is_military_target=true,
      type={'turret', 'spawner', 'unit-spawner'},
    }
    storage.enemy_list = targets
    if #targets > 0 then
      storage.report_targets:set(#targets)
    end
    storage.targets_count = 0
  end
  local some_checked = false
  if storage.enemy_list then
    local enemies_to_check = settings.global['hunter-killer-enemies-per-cycle'].value
    local chunk_rad = settings.global['hunter-killer-pollution-radius'].value
    local sad_mode = settings.global['hunter-killer-search-and-destroy-mode'].value
    local checked = 0

    local force = game.forces['player']
    while (checked < enemies_to_check) and (#storage.enemy_list > 0) do
      local idx = #storage.enemy_list
      local tgt = storage.enemy_list[idx]
      table.remove(storage.enemy_list,idx)
      some_checked = true
      if tgt.valid then
        local tgt_chunk_pos = {x=tgt.position.x/32.0,y=tgt.position.y/32.0}
        local is_polluted = sad_mode
        for dx = -chunk_rad,chunk_rad do
          if is_polluted then
            break
          end
          for dy = -chunk_rad,chunk_rad do
            if force.is_chunk_charted('nauvis', {tgt_chunk_pos.x+dx,tgt_chunk_pos.y+dy}) and
              (nauvis.get_pollution({tgt.position.x+32.0*dx,tgt.position.y+32.0*dy}) > 0.0) then
              is_polluted = true
              break
            end
          end
        end
        if is_polluted then
          local box = box_from_target( tgt)
          storage.target_tree:insert(box)
          storage.targets_count = (storage.targets_count or 0) + 1
        end
      end
      checked = checked + 1
    end
  end
  return some_checked
end

-- Return map_pos if chunk is interesting for exploration, nil otherwise
local function interesting_for_exploration( chunk, chunk_rad)
  local force = game.forces['player']
  local nauvis = game.surfaces['nauvis']
  local uncharted = 0
  local polluted = 0
  local sad_mode = settings.global['hunter-killer-search-and-destroy-mode'].value
  if sad_mode then
    polluted = 1
  end
  if chunk and force.is_chunk_charted('nauvis', {chunk.x,chunk.y}) then
    local map_pos = {x=chunk.x * 32.0 + 16.0, y=chunk.y * 32.0 + 16.0}
    for dx = -chunk_rad,chunk_rad do
      for dy = -chunk_rad,chunk_rad do
        if not force.is_chunk_charted('nauvis', {chunk.x+dx,chunk.y+dy}) then
          uncharted = uncharted + 1
        elseif nauvis.get_pollution({map_pos.x+32.0*dx,map_pos.y+32.0*dy}) > 0.0 then
          polluted = polluted + 1
        end
      end
    end
    if (uncharted > 0) and (polluted > 0) then
      return map_pos
    end
  end
  return nil
end

-- A chunk to explore has at least one polluted and one unexplored chunk in a 5x5 neighbourhood
local function find_chunks_to_explore()
  local force = game.forces['player']
  local nauvis = game.surfaces['nauvis']
  if not storage.chunk_iterator and storage.target_tree:isEmpty() then
    storage.chunk_iterator = nauvis.get_chunks()
    storage.place_count = 0
  end

  if storage.chunk_iterator then
    local chunks_to_check = settings.global['hunter-killer-chunks-per-cycle'].value
    local chunk_rad = settings.global['hunter-killer-pollution-radius'].value
    local checked = 0
    local added = false
    while (checked < chunks_to_check) do
      local chunk = storage.chunk_iterator()
      if not chunk then
        storage.report_places:set( storage.place_count)
        storage.chunk_iterator = nil
        storage.enemy_list = nil
        break
      end
      local map_pos = interesting_for_exploration(chunk, chunk_rad)
      if map_pos then
        -- Check if it's on water. Filters out most chunks in lakes really early.
        local tile = nauvis.get_tile(map_pos)
        if not tile or not tile.valid or (tile.name ~= 'water' and tile.name ~= 'deepwater') then
          -- Add a fake target and mark it as an exploration target
          storage.target_tree:insert( box_from_target(
          {
            position = map_pos,
            valid = true,
            health = 1.0,
            type = 'exploration',
            chunk = chunk,
          }))
          storage.place_count = storage.place_count + 1
          added = true
        end
      end
      checked = checked + 1
    end
  end
end

-- planner ==================================================

local kState_idle       = 0
local kState_planning   = 1
local kState_walking    = 2
local kState_approach   = 3
local kState_attack     = 4
local kState_retreat    = 5
local kState_goHome     = 6
local kState_reArm      = 7
local kState_leader     = 8
local kState_follower   = 9

-- Plan a path from target to current position.
local function plan_path( killer, target, ok_state, fail_state, pf_rad, info, req_info)
  -- Center of the circle we're walking while waiting for the planner to finish
  if not killer.taptap_ctr or dist_between_pos( killer.vehicle.position, killer.taptap_ctr) > 33.0 then
    killer.taptap_ctr = killer.vehicle.position
  end

  -- Set a reasonable default for the collision mask to avoid walking through water
  local pathing_collision_mask = {
    layers = { water_tile = true },
    consider_tile_transitions = true,
    colliding_with_tiles_only = true,
    not_colliding_with_itself = true
  }

  local pf_bbox = settings.global['hunter-killer-pf-bbox'].value
  -- local pf_rad = settings.global['hunter-killer-pf-radius'].value

  local request = {
    -- Keep a respectful distance to water and nests
    bounding_box =  {{-pf_bbox, -pf_bbox}, {pf_bbox, pf_bbox}},
    collision_mask = pathing_collision_mask,
    start = killer.vehicle.position,
    goal = target,
    force = killer.vehicle.force,
    -- Don't need to get too close
    radius = pf_rad,
    pathfinding_flags = {
      cache = true,
      low_priority = false,
    },
    path_resolution_modifier = -3,
    killer = killer,
  }
  if req_info then
    for k,v in pairs(req_info) do
      request[k] = v
    end
  end

  local nauvis = game.surfaces['nauvis']

  storage.pathfinder_requests = storage.pathfinder_requests or {}
  if killer.request_id then
    storage.pathfinder_requests[killer.request_id] = nil
  end
  local request_id = nauvis.request_path(request)
  storage.pathfinder_requests[request_id] = request
  killer.request_id = request_id
  killer.pathfinder_request = request
  killer.target_pos = target

  for k,v in pairs(info) do
    killer[k] = v
  end
  killer.ok_state=ok_state
  killer.fail_state = fail_state
  killer.state = kState_planning
end

-- Event callback if the planner is done
local function path_planner_finished(event)
  if storage.pathfinder_requests then
    local request = storage.pathfinder_requests[event.id]
    if request then
      if event.path then
        if request.killer.vehicle.valid then
          if request.store_path then
            request.killer.target_path = event.path
          else
            request.killer.vehicle.autopilot_destination = nil
            for _,p in ipairs(event.path) do
              request.killer.vehicle.add_autopilot_destination( p.position)
            end
          end
        end
        request.killer.state = request.killer.ok_state
        request.killer.dont_tap = nil
      elseif not event.try_again_later then
        request.killer.state = request.killer.fail_state
      end
      if request.killer.request_id then
        storage.pathfinder_requests[request.killer.request_id] = nil
      end
      request.killer.request_id = nil
      request.killer.pathfinder_request = nil
      storage.pathfinder_requests[event.id] = nil
    end
  end
end

-- State machine ===============================================

local function have_autopilot(vehicle)
  return vehicle.autopilot_destination or (table_size(vehicle.autopilot_destinations) ~= 0);
end

-- Try to send the vehicle home
local function vehicle_go_home(killer)
  local ok = false
  -- go home, find the closest homebase

  local home_dist = nil
  local home = nil
  local base = storage.homebases
  while base do
    if base.tag and base.tag.valid then
      local d = dist_between_pos( base.tag.position, killer.vehicle.position)
      if (not home_dist) or (d < home_dist) then
        home_dist = d
        home = base.tag
      end
    end
    base=base.nxt
  end

  if home then
    killer.home_position = home.position
    -- Send killers to marker, with just a bit of spacing to select them
    plan_path(killer, home.position, kState_goHome, kState_idle, 8.0, {})
    ok = true
  end
  return ok
end

-- Get the minimum health to return home as a ratio
local function get_min_health()
  local min_health = settings.global['hunter-killer-go-home-health'].value / 100.0
  return min_health
end

-- Check if the spidertron needs to go home
local function vehicle_wants_home(vehicle, min_health)
  -- is vehicle damaged?
  if vehicle.get_health_ratio() < min_health then
    return true
  end
  -- is ammo low there is a logistics request for it?
  local ammo_inv = vehicle.get_inventory(defines.inventory.spider_ammo)
  local trunk_inv = vehicle.get_inventory(defines.inventory.spider_trunk)
  local fuel_inv = vehicle.get_inventory(defines.inventory.fuel)
  -- Go through the logistics slots and check that enough items are in ammo + trunk + fuel.
  for logPointInd, logPoint in pairs( vehicle.get_logistic_point()) do
    for logSectInd, logSect in pairs( logPoint.sections) do
      for logFilterInd, logFilter in pairs( logSect.filters) do
        local log_req = logFilter.value
        if not log_req.name then
          break
        end
        local ammo_count = 0
        local trunk_count = 0
        local fuel_count = 0
        if ammo_inv then
          ammo_count = ammo_inv.get_item_count(log_req.name)
        end
        if trunk_inv then
          trunk_count = trunk_inv.get_item_count(log_req.name)
        end
        if fuel_inv then
          fuel_count = fuel_inv.get_item_count(log_req.name)
        end
        if ((ammo_count + trunk_count + fuel_count) == 0) then
          return true
        end
      end
    end
  end
  return false
end

-- Helper function to switch out equipment in the grid.
-- Taken from Constructron-Continued (MIT license).
---@param grid LuaEquipmentGrid
---@param old_eq LuaEquipment
---@param new_eq string
local function replace_roboports(grid, old_eq, new_eq)
    local grid_pos = old_eq.position
    local eq_energy = old_eq.energy
    grid.take{ position = old_eq.position }
    local new_set = grid.put{ name = new_eq, position = grid_pos }
    if new_set then
        new_set.energy = eq_energy
    end
end

-- Disable roboports by replacing them with versions that have 0 range
-- Adapted from Constructron-Continued (MIT license).
local function disable_roboports(vehicle)
  for _, eq in next, vehicle.grid.equipment do
    if eq.type == "roboport-equipment" then
      if not string.find(eq.name, "%-hk-disabled") then
        replace_roboports(vehicle.grid, eq, (eq.prototype.take_result.name .. "-hk-disabled"))
      end
    end
  end
end

-- Enable roboports by replacing them with versions that have normal range
-- Adapted from Constructron-Continued (MIT license).
local function enable_roboports(vehicle)
  for _, eq in next, vehicle.grid.equipment do
    if eq.type == "roboport-equipment" then
      replace_roboports(vehicle.grid, eq, eq.prototype.take_result.name)
    end
  end
end

-- State transition checker for killer spidertrons in idle state
local function trans_killer_idle( killer)
  -- White
  killer.vehicle.color = {1.0, 1.0, 1.0, 1.0}
  if vehicle_wants_home(killer.vehicle, get_min_health()) then
    vehicle_go_home(killer)
  end
  if have_autopilot(killer.vehicle) then
    killer.cached_closest = nil
  end
end

-- State transition checker for killer spidertrons in approach state
local function trans_killer_approach( killer)
  -- orange
  killer.vehicle.color = {1.0, 0.5, 0.0, 1.0}
  local attack = false
  local idle = false
  if killer.target and killer.target.valid then
    local retreat_dist = settings.global['hunter-killer-retreat-distance'].value
    if killer.target.type == 'exploration' then
      local chunk_rad = settings.global['hunter-killer-pollution-radius'].value
      if interesting_for_exploration(killer.target.chunk, chunk_rad) then
        if dist_between_pos(killer.target_pos, killer.vehicle.position) < retreat_dist then
          attack = true
        end
      else
        idle = true
      end
    else
      if killer.target.health and killer.target.health > 0.0 then
        if dist_between_pos(killer.target_pos, killer.vehicle.position) < retreat_dist then
          attack = true
        end
      end
    end
  else
    idle = true
  end
  if not have_autopilot(killer.vehicle) then
    idle=true
  end
  if vehicle_wants_home(killer.vehicle, get_min_health()) then
    vehicle_go_home(killer)
    attack = false
    idle = false
  end

  if attack then
    killer.safe_path = killer.vehicle.autopilot_destinations
    killer.state = kState_attack
    killer.taptap_ctr = nil
    disable_roboports(killer.vehicle)
  elseif idle then
    killer.vehicle.autopilot_destination = nil
    killer.state = kState_idle
    killer.taptap_ctr = nil
  end
end

-- State transition checker for killer spidertrons in attack state
local function trans_killer_attack( killer)
  -- red
  killer.vehicle.color = {1.0, 0.0, 0.0, 1.0}
  local retreat = false
  if killer.target and killer.target.valid then
    -- is target dead?
    if killer.target.health and killer.target.health <= 0.0 then
      retreat = true
    end
  else
    retreat = true
  end
  if retreat then
    local n = #killer.safe_path
    for i = 1, n do
      killer.vehicle.add_autopilot_destination( killer.safe_path[n+1-i])
    end
    killer.state = kState_retreat
  elseif not have_autopilot(killer.vehicle) then
    -- If we reached an exploration target, mark it dead to stop the other spiders from searching
    if killer.target and killer.target.type == 'exploration' then
      killer.target.valid = nil
      killer.target.health = nil
    end
    local n = #killer.safe_path
    for i = 1, n do
      killer.vehicle.add_autopilot_destination( killer.safe_path[n+1-i])
    end
    killer.state = kState_retreat
  end
end

-- State transition checker for killer spidertrons in retreat state
local function trans_killer_retreat( killer)
  -- cyan
  killer.vehicle.color = {0.0, 1.0, 1.0, 1.0}
  if not have_autopilot(killer.vehicle) then
    killer.state = kState_idle
    enable_roboports(killer.vehicle)
  end
end

-- State transition checker for killer spidertrons in go_home state
local function trans_killer_go_home( killer)
  -- blue
  killer.vehicle.color = {0.0, 0.0, 1.0, 1.0}

  -- If vehicle doesn't want to go home anymore, go idle
  if not vehicle_wants_home(killer.vehicle, 1.0) then
    killer.state = kState_idle
    killer.autopilot_destination = nil
  elseif not have_autopilot(killer.vehicle) then
     killer.state = kState_reArm
  end
end

-- State transition checker for killer spidertrons in re_arm state
local function trans_killer_re_arm( killer)
  -- green
  killer.vehicle.color = {0.0, 1.0, 0.0, 1.0}
  local pf_rad = settings.global['hunter-killer-pf-radius'].value
  if not killer.home_position or dist_between_pos(killer.home_position, killer.vehicle.position) > pf_rad then
    if vehicle_wants_home(killer.vehicle, get_min_health()) then
      vehicle_go_home(killer)
      return
    end
  end
  if killer.vehicle.get_health_ratio() >= 1.0 then
    local ammo_inv = killer.vehicle.get_inventory(defines.inventory.spider_ammo)
    local trunk_inv = killer.vehicle.get_inventory(defines.inventory.spider_trunk)
    local fuel_inv = killer.vehicle.get_inventory(defines.inventory.fuel)
    -- Go through the logistics slots and check the enough items are in ammo + trunk + fuel.
    local rearmed = true
    for logPointInd, logPoint in pairs( killer.vehicle.get_logistic_point()) do
      for logSectInd, logSect in pairs( logPoint.sections) do
        for logFilterInd, logFilter in pairs( logSect.filters) do
          local log_req = logFilter.value
          if not log_req.name then
            break
          end
          local ammo_count = 0
          local trunk_count = 0
          local fuel_count = 0
          if ammo_inv then
            ammo_count = ammo_inv.get_item_count(log_req.name)
          end
          if trunk_inv then
            trunk_count = trunk_inv.get_item_count(log_req.name)
          end
          if fuel_inv then
            fuel_count = fuel_inv.get_item_count(log_req.name)
          end
          if (ammo_count + trunk_count + fuel_count) < logFilter.min then
            rearmed = false
            break
          end
        end
      end
    end
    if rearmed then
        killer.state = kState_idle
    end
  end
end

-- State transition checker for killer spidertrons in planning state
local function trans_killer_planning( killer)
  -- Yellow
  killer.vehicle.color = {1.0, 1.0, 0.0, 1.0}

  -- Walk around in circles
  local taptap_radius = 15.0
  local taptap_steps = 16
  local nauvis = game.surfaces['nauvis']
  local another_round = false
  if not killer.dont_tap then
    if killer.taptap_ctr and (#killer.vehicle.autopilot_destinations < taptap_steps/2) then
      if #killer.vehicle.autopilot_destinations == 1 then
        killer.state = kState_walking
        if killer.request_id then
          storage.pathfinder_requests = storage.pathfinder_requests or {}
          storage.pathfinder_requests[killer.request_id] = nil
          killer.request_id = nil
          killer.pathfinder_request = nil
        end
        killer.ok_state = kState_idle
        return
      end
      -- Add another revolution
      for i = 0, (taptap_steps-1) do
        local angle = 2.0*math.pi*i/taptap_steps
        local x=killer.taptap_ctr.x + math.sin(angle)*taptap_radius
        local y=killer.taptap_ctr.y + math.cos(angle)*taptap_radius

        local tile = nauvis.get_tile(x,y)
        if tile and tile.valid and (tile.name ~= 'water') and (tile.name ~= 'deepwater') then
          killer.vehicle.add_autopilot_destination( { x=x, y=y})
        end
      end
      another_round = true
    end
  else
    return
  end

  -- Check the request needs to be tried again
  if another_round and killer.request_id and storage.pathfinder_requests and not storage.pathfinder_requests[killer.request_id] then

    local request = killer.pathfinder_request
    if request then
      local request_id = nauvis.request_path(request)
      storage.pathfinder_requests[request_id] = request
      killer.request_id = request_id
    else
      killer.vehicle.autopilot_destination = nil
      killer.state = kState_idle
    end
  end

  if not killer.request_id then
    killer.vehicle.autopilot_destination = nil
    killer.state = kState_idle
  end

  if killer.ok_state == kState_approach then
    killer.cyclesSinceTargetCheck = 1 + (killer.cyclesSinceTargetCheck or 0)
    if killer.cyclesSinceTargetCheck > settings.global['hunter-killer-target-check-cycles'].value then
      killer.cyclesSinceTargetCheck = 0
      if not killer.target or not killer.target.valid then
        killer.state = killer.fail_state
        if killer.request_id then
          storage.pathfinder_requests[killer.request_id] = nil
          killer.request_id = nil
        end
        return
      end
    end
  end
end

-- State transition checker for killer spidertrons in walking state
local function trans_killer_walking( killer)
  -- Grey
  killer.vehicle.color = {0.5, 0.5, 0.5, 1.0}
  if vehicle_wants_home(killer.vehicle, get_min_health()) then
    vehicle_go_home(killer)
    return
  end
  if not have_autopilot( killer.vehicle) then
    -- Reached the target, either set manually or automatically
    killer.state = kState_idle
    killer.vehicle.autopilot_destination = nil
    killer.group_leader = nil
    killer.target = nil
  else
    local pf_rad = settings.global['hunter-killer-pf-radius'].value
    if not killer.group_leader or
      not killer.group_leader.vehicle or
      not killer.target or
      (killer.group_leader.state ~= kState_leader)
      then
      -- If there is an assembly target and it moved away from the assembly
      -- position, go to idle to look for the next target.
      killer.state = kState_idle
      killer.vehicle.autopilot_destination = nil
      killer.group_leader = nil
      killer.target = nil
    end
  end
end

-- State transition checker for assembling killers in leader state.
local function trans_killer_leader( killer)
  -- Dark red
  killer.vehicle.color = {0.6, 0.1, 0.1, 1.0}
  local go_home = false
  if vehicle_wants_home(killer.vehicle, get_min_health()) then
    go_home = true
  end
  local pf_rad = settings.global['hunter-killer-pf-radius'].value

  -- Check if enemy building is dead or chunk has been explored
  if killer.target and killer.target.valid then
    if killer.target.type == 'exploration' then
      local chunk_rad = settings.global['hunter-killer-pollution-radius'].value
      if not interesting_for_exploration(killer.target.chunk, chunk_rad) then
        killer.state = kState_idle
      end
    end
  else
    killer.state = kState_idle
  end
  -- Check if killer has been moved manually
  if ( not have_autopilot(killer.vehicle) and
    killer.assembly_point and
    (dist_between_pos(killer.assembly_point,killer.vehicle.position) > pf_rad)
    ) then
    killer.state = kState_idle
  end

  if go_home or (killer.state == kState_idle) then
    killer.target_path = nil
    killer.target = nil
    killer.vehicle.autopilot_destination = nil
    killer.dont_tap = nil
    killer.assembly_point = nil
  end
  if go_home then
    vehicle_go_home(killer)
    return
  end
end

-- State transition checker for assembling killers in leader state.
local function trans_killer_follower( killer)
  -- Dark green
  killer.vehicle.color = {0.1, 0.6, 0.1, 1.0}
  local go_home = false
  if vehicle_wants_home(killer.vehicle, get_min_health()) then
    go_home = true
  end
  local pf_rad = settings.global['hunter-killer-pf-radius'].value
  if not killer.target or not killer.target.valid or
    not killer.group_leader or not killer.group_leader.vehicle.valid or
    not killer.group_leader.assembly_point or
    (killer.group_leader.state ~= kState_leader) or
    ( not have_autopilot(killer.vehicle) and
      (dist_between_pos(killer.group_leader.assembly_point,killer.vehicle.position) > pf_rad)
    ) then
    killer.state = kState_idle
  end

  if go_home or (killer.state == kState_idle) then
    killer.group_leader = nil
    killer.target = nil
    killer.vehicle.autopilot_destination = nil
    killer.dont_tap = nil
  end
  if go_home then
    vehicle_go_home(killer)
    return
  end
end

local state_dispatch = {
 [kState_idle] = trans_killer_idle,
 [kState_approach] = trans_killer_approach,
 [kState_attack] = trans_killer_attack,
 [kState_retreat] = trans_killer_retreat,
 [kState_goHome] = trans_killer_go_home,
 [kState_reArm] = trans_killer_re_arm,
 [kState_planning] = trans_killer_planning,
 [kState_walking] = trans_killer_walking,
 [kState_leader] = trans_killer_leader,
 [kState_follower] = trans_killer_follower,
}

-- Sorting criterion for killers
local function comp_dist(kd1,kd2)
  return kd1.d < kd2.d
end

-- If there are group_size idle killers, find the one with the closest distance
-- to any target and send all killers there
--
-- The most common case is waiting for the last spider to arrive. This happens
-- when you have a large base with many spiders and long ways to go.
local function send_killer_to_target()
  local force = game.forces['player']
  if not force.is_pathfinder_busy() then
    local killers = storage.vehicles or {}
    local min_health = get_min_health()
    local group_size = settings.global['hunter-killer-attack-group-size'].value
    local assemble_dist = settings.global['hunter-killer-assemble-distance'].value
    -- Count the idle killers and the leaders.
    local idle_killers = 0
    local leading_killers = 0
    local total_killers = 0
    local complete_group = false
    -- Index by unit_number of group leader
    local group_map = {}
    for id,killer in pairs(killers) do
      total_killers = total_killers + 1
      if killer.vehicle and
        killer.vehicle.valid and
        not vehicle_wants_home(killer.vehicle, min_health) then
        if (killer.state == kState_idle) and (not have_autopilot( killer.vehicle))  then
          idle_killers = idle_killers + 1
        elseif (killer.state == kState_leader) then
          if killer.target and killer.target.valid then
            -- If killer has a path to the target, but no assembly point, send them on their way.
            if killer.target_path and not killer.assembly_point then
              killer.vehicle.autopilot_destination = nil
              if #killer.target_path == 0 then
                killer.target = nil
                killer.target_path = nil
                killer.state = kState_idle
                idle_killers = idle_killers + 1
              else
                killer.assembly_point = killer.vehicle.position
                while #killer.target_path > 1 do
                  local d = dist_between_pos(killer.target_path[1].position, killer.target.position)
                  if d < assemble_dist then
                    break
                  end
                  killer.vehicle.add_autopilot_destination(killer.target_path[1].position)
                  killer.assembly_point = killer.target_path[1].position
                  table.remove(killer.target_path,1)
                end
              end
            end
            -- Create an entry in the group map if it doesn't exist.
            if not group_map[killer.vehicle.unit_number] then
              group_map[killer.vehicle.unit_number] = { followers = {} }
            end
            group_map[killer.vehicle.unit_number].leader = killer
          else
            killer.target = nil
            killer.target_path = nil
            killer.state = kState_idle
            idle_killers = idle_killers + 1
            killer.vehicle.autopilot_destination = nil
          end
          -- If state is still leader, count it
          if (killer.state == kState_leader) then
            leading_killers = leading_killers + 1
          end
        elseif killer.state == kState_follower then
          if killer.group_leader and killer.group_leader.vehicle.valid and killer.vehicle.valid then
            local leader_number = killer.group_leader.vehicle.unit_number
            -- Create an entry in the group map if it doesn't exist.
            if not group_map[leader_number] then
              group_map[leader_number] = { leader = nil, followers = { } }
            end
            group_map[leader_number].followers[#group_map[leader_number].followers + 1] = killer
            if (#group_map[leader_number].followers + 1) >= group_size then
              complete_group = true
            end
          end
        end
      end
    end
    local max_groups = math.floor(total_killers/group_size)

    -- If there are complete groups, send all of them. This doesn't cost much
    -- runtime as the paths are already computed.
    if complete_group then
      local group_sent = false
      for _,group in pairs(group_map) do
        -- Leader and group_size - 1 follower need to be present 
        if group.leader and ((#group.followers + 1) >= group_size) then
          -- Leader and all followers must have stopped
          if not have_autopilot(group.leader.vehicle) then
            local follower_stopped = true
            for _,follower in ipairs(group.followers) do
              if have_autopilot(follower.vehicle) then
                follower_stopped = false
                break
              end
            end
            if follower_stopped then
              group_sent = true
              -- Send them off
              group.followers[#group.followers+1] = group.leader

              local target = group.leader.target
              group.leader.target = nil
              for _,follower in ipairs(group.followers) do
                follower.target_pos = target.position
                follower.target = target
                follower.state = kState_approach
                follower.ok_state = nil
                follower.fail_state = nil
                follower.vehicle.autopilot_destination = nil
                follower.assembly_point = nil
                follower.group_leader = nil
                for _,p in ipairs(group.leader.target_path) do
                  follower.vehicle.add_autopilot_destination( p.position)
                end
              end
              group.leader.target_path = nil
            end
          end
        end
      end
      if group_sent then
        return
      end
    end

    -- We have only incomplete groups. Go through all idle killers and try to make one leader or follower.
    if (idle_killers > 0) then
      local pf_rad = settings.global['hunter-killer-pf-radius'].value
      local closest_d = nil
      local closest_t = nil
      local closest_is_target = false
      local closest_k = nil
      for _,killer in pairs(killers) do
        if killer.vehicle and
          killer.vehicle.valid and
          not vehicle_wants_home(killer.vehicle, min_health) and
          not have_autopilot( killer.vehicle) and
          (killer.state == kState_idle) then
          -- Candidate for assignment, find the closest of either leaders or target
          if leading_killers < max_groups then
            local tgt = killer.cached_closest
            if not tgt then
              tgt = storage.target_tree:nearest(box_from_target(killer.vehicle))
              killer.cached_closest = tgt
            end
            if tgt and not tgt.box.target.valid then
              storage.target_tree:delete(tgt.id)
              tgt = nil
            end
            if tgt then
              local d = dist_between_pos( tgt.box.target.position, killer.vehicle.position)
              if ((not closest_d) or (d < closest_d)) then
                closest_d = d
                closest_t = tgt
                closest_k = killer
                closest_is_target = true
              end
            else
              killer.cached_closest = nil
            end
          end
          for _,group in pairs(group_map) do
            -- Leader needs to be present and know where it wants to go and group needs to incomplete
            if group.leader and ((#group.followers + 1) < group_size) and group.leader.assembly_point then
              local d = dist_between_pos( group.leader.assembly_point, killer.vehicle.position)
              if ((not closest_d) or (d < closest_d)) then
                closest_d = d
                closest_t = group.leader
                closest_k = killer
                closest_is_target = false
              end
            end
          end
        end
      end
      -- We can assign this killer
      if closest_t then
        closest_k.assembly_point = nil
        closest_k.group_leader = nil
        closest_k.ok_state = nil
        closest_k.fail_state = nil
        closest_k.cached_closest = nil
        if closest_is_target then
          -- Delete target and surrounding targets, make closest_k a leader
          closest_k.target_path = nil
          closest_k.dont_tap = nil
          local store_path = true
          local next_state = kState_leader
          if group_size == 1 then
            store_path = false
            next_state = kState_approach
          end
          -- Keep selected distance to target
          local pf_rad = settings.global['hunter-killer-pf-radius'].value
          plan_path(
            closest_k,
            closest_t.box.target.position,
            next_state,
            kState_idle,
            pf_rad,
            {
              target = closest_t.box.target,
            },
            { store_path = store_path }
            )
          local in_range = {}
          storage.target_tree:range( {
            x=closest_t.box.target.position.x,
            y=closest_t.box.target.position.y,
            r=pf_rad}, in_range)
          for _,box in ipairs(in_range) do
            storage.target_tree:delete(box.id)
          end
          -- Original box needs to be deleted. There are cases where the
          -- box is not inside its own range.
          storage.target_tree:delete(closest_t.id)
        else
          -- Send towards the assembly point of the group leader. Keep them
          -- close together so they can start at the same time.
          closest_k.dont_tap = nil
          plan_path(
            closest_k,
            closest_t.assembly_point,
            kState_follower,
            kState_idle,
            4.0,
            {
              group_leader = closest_t,
              -- Make a copy of the current position to detect if the leader moved
              target = {
                position = closest_t.assembly_point,
                valid = true,
                health = 1.0,
                type = 'exploration',
              }
            },
            {})
        end
      end
    end
  end
end

-- Part of state machine processing, to be called frequently
local function spidertron_state_machine()
  local rescan_vehicles = false
  local killers = storage.vehicles or {}

  for id,killer in pairs(killers) do
    if killer.vehicle and killer.vehicle.valid then
      local current_state = killer.state
      -- Dispatch by killer to the respective transition checks
      local trans_killer = state_dispatch[killer.state]
      if trans_killer then
        trans_killer(killer)
      else
        -- Magenta: Invalid/unknown state
        killer.vehicle.color = { 1.0, 0.0, 1.0, 1.0}
        killer.vehicle.autopilot_destination = nil
        killer.state = kState_idle
      end
      killer.last_state = current_state
    else
      rescan_vehicles = true
    end
  end

  if rescan_vehicles then
    detect_vehicles()
  end
end

local function spidertron_assign_targets()
  send_killer_to_target()
end

local function spidertron_find_targets(event)
  if not find_valid_targets() then
    find_chunks_to_explore()
  end
  if settings.global['hunter-killer-debug-print-targets'].value and storage.target_tree then
    local cnt=0
    local traverse = { storage.target_tree.root }
    while #traverse > 0 do
      local b = table.remove(traverse, 1)
      if b.is_leaf then
        if b.box.target and b.box.target.valid then
          cnt=cnt+1
        end
        for i = 1, #b.children do
          local c = b.children[i]
          if c.box.target and c.box.target.valid then
            cnt=cnt+1
          end
        end
      else
        for i = 1, #b.children do
          table.insert( traverse, b.children[i])
        end
      end
    end
    -- Compute burndown rate
    if not storage.hunter_killer_last_cnt or not storage.hunter_killer_last_cnt_tick or (event.tick <= storage.hunter_killer_last_cnt_tick) or (cnt > storage.hunter_killer_last_cnt) then
      storage.hunter_killer_last_cnt = cnt
      storage.hunter_killer_last_cnt_tick = event.tick
      game.print( cnt .. ' places to visit')
    else
      local bd = storage.hunter_killer_last_cnt - cnt
      local dt = event.tick - storage.hunter_killer_last_cnt_tick
      -- Removed entries / minute
      local bdr = 3600.0 * bd / dt
      if not storage.hunter_killer_bdr_avg then
        storage.hunter_killer_bdr_avg = bdr
        game.print( cnt .. ' places to visit. ' .. bdr .. ' checks per minute')
      else
        storage.hunter_killer_bdr_avg = 0.99 * storage.hunter_killer_bdr_avg + 0.01 * bdr
        game.print( cnt .. ' places to visit. ' .. storage.hunter_killer_bdr_avg .. ' checks per minute on average')
      end
      storage.hunter_killer_last_cnt = cnt
      storage.hunter_killer_last_cnt_tick = event.tick
    end
  end
end

local function spidertron_rescan()
  detect_vehicles()
  detect_homebases()
end

local function sanity_check()
  -- No homebases
  if storage.homebases == nil or table_size(storage.homebases) == 0 then
    game.print( 'Hunter&Killer: No homebase on nauvis.\nSet at least one custom tag in the map view named "Homebase". No quotes, case matters.')
  end
  -- Total number of spiders is smaller than group size
  local num_vehicles = table_size(storage.vehicles)
  if (num_vehicles > 0) and (num_vehicles < settings.global['hunter-killer-attack-group-size'].value) then
    game.print( 'Hunter&Killer: Group size is larger than current number of Killers.\nReduce group size in Map Settings.')
  end
end

-- Register events: vehicle list may have changed
script.on_event(defines.events.on_entity_renamed, detect_vehicles)
script.on_event(defines.events.on_entity_cloned, detect_vehicles)
script.on_event(defines.events.on_entity_died, detect_vehicles, {{filter='vehicle'}})
script.on_event(defines.events.on_entity_settings_pasted, detect_vehicles)

-- Register events: homebase may have changed
script.on_event(defines.events.on_chart_tag_added, detect_homebases)
script.on_event(defines.events.on_chart_tag_modified, detect_homebases)
script.on_event(defines.events.on_chart_tag_removed, detect_homebases)

-- Register event: Start path search to the targets
script.on_nth_tick(settings.startup['hunter-killer-freq-assign'].value, spidertron_assign_targets)

-- Register event: Process the target list 5x per second
script.on_nth_tick(settings.startup['hunter-killer-freq-targets'].value, spidertron_find_targets)

-- Register event: Update state
script.on_nth_tick(settings.startup['hunter-killer-freq-state'].value, spidertron_state_machine)

-- Register event: Basic sanity check every minute
script.on_nth_tick(3600, sanity_check)

-- Register event: path planner is done
script.on_event(defines.events.on_script_path_request_finished, path_planner_finished)

-- Register the metatables
script.register_metatable( 'StatisticsReporterMt', StatisticsReporter.metatable)
script.register_metatable( 'rstarMt', rstar)
script.register_metatable( 'rsnodeMt', rstar.rsnodeMt)
script.register_metatable( 'aabbMt', aabb)

local function ensure_globals()
  reporters.ensure_globals()
  targets.ensure_globals()
end

-- Init globals
script.on_init( ensure_globals)
script.on_configuration_changed( ensure_globals)

script.on_configuration_changed( spidertron_rescan)
