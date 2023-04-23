--[[
  control.lua: Event handling script for the factorio mod *HunterKiller*.

  Uses the priority queue class from https://github.com/iskolbin/lpriorityqueue
]]

local PriorityQueue = require 'PriorityQueue'

-- Count and print number of killers
local function count_killers(vehicles, suffix)
  local killer_count = table_size( vehicles)
  game.print(killer_count .. ' killer spidertrons' .. suffix)
end

-- Count and print number of homebases
local function count_bases(bases, suffix)
  local count = 0
  local b = bases
  while b do
    count = count + 1
    b=b.nxt
  end
  game.print(count .. ' home bases' .. suffix)
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
  local old_vehicles = global.vehicles or {}
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
  global.vehicles = new_vehicles

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
  global.homebases = bases

  count_bases(global.homebases, ' managed')
end

-- Compute the distance between two MapPositions
local function dist_between_pos(p1,p2)
  local dx = p1.x-p2.x
  local dy = p1.y-p2.y
  return math.sqrt( dx*dx + dy*dy)
end

-- Block List ===================================================
local function block_code_from_pos( pos)
  local block_res = 16.0
  local x = math.floor(pos.x / block_res + 0.5)
  local y = math.floor(pos.y / block_res + 0.5)
  return x .. ':' .. y
end

-- Check if a given position is in the block list
local function is_target_blocked(pos)
  local block_list = global.target_blockers or {}
  local bc = block_code_from_pos(pos)
  if block_list[bc] then
    return true
  end
  return false
end

-- Add a point to the block list
local function block_target(pos)
  local block_list = global.target_blockers or {}
  local bc = block_code_from_pos(pos)
  block_list[bc] = pos
  global.target_blockers = block_list
end

-- Find targets ================================================

-- Get the list of target that are not blocked
local function find_valid_targets()
  local nauvis = game.surfaces['nauvis']
  local targets = nauvis.find_entities_filtered{
        force='enemy',
        is_military_target=true,
        type={'turret', 'spawner'},
      }
  local force = game.forces['player']
  local nauvis = game.surfaces['nauvis']
  local valid_targets = global.targets or {}
  local cache_polluted = {}
  for _,tgt in ipairs(targets) do
    if tgt and tgt.valid then
      if not is_target_blocked(tgt.position) then
        local tgt_chunk_pos = {x=tgt.position.x/32.0,y=tgt.position.y/32.0}
        local tgt_chunk_code = math.floor(tgt_chunk_pos.x) .. ':' .. math.floor(tgt_chunk_pos.y)
        local is_polluted = false
        if cache_polluted[tgt_chunk_code] then
          is_polluted = true
        else
          for dx = -2,2 do
            for dy = -2,2 do
              if force.is_chunk_charted('nauvis', {tgt_chunk_pos.x+dx,tgt_chunk_pos.y+dy}) and
                (nauvis.get_pollution({tgt.position.x+32.0*dx,tgt.position.y+32.0*dy}) > 0.0) then
                is_polluted = true
                cache_polluted[tgt_chunk_code] = true
                break
              end
            end
          end
        end
        if is_polluted then
          valid_targets[#valid_targets+1] = tgt
        end
      end
    end
  end
  global.targets = valid_targets
end

-- Find the closest enemy target to a given position
--
-- Check if there is pollution at the position
local function closest_target(pos)
  local tgt_dist = nil
  local target = nil
  local iTarget = nil
  for iTgt,tgt in ipairs(global.targets) do
    if tgt.valid then
      local d = dist_between_pos( tgt.position, pos)
      if (not tgt_dist) or (d < tgt_dist) and (not is_target_blocked(tgt.position)) then
        tgt_dist = d
        target = tgt
        iTarget = iTgt
      end
    end
  end
  if iTarget then
    table.remove( global.targets, iTarget)
  end
  return target
end

-- Grid coordinates ==================================
local kGrid_stepSize   = 10.0
local kGrid_diagStepSize = math.sqrt(2.0) * kGrid_stepSize

local function grid_pos_to_map( grid_pos)
  return {x=grid_pos.x * kGrid_stepSize,y=grid_pos.y * kGrid_stepSize}
end

local function compute_grid_pos(pos)
  -- Round position to nearest grid position. This should still fall onto a
  -- land tile, even on small islands.
  local x = math.floor(pos.x / kGrid_stepSize + 0.5)
  local y = math.floor(pos.y / kGrid_stepSize + 0.5)

  return {x=x,y=y}
end

local function compute_grid_code( grid_pos)
  return grid_pos.x .. ':' .. grid_pos.y
end

-- Path finding ===========================================

local function get_grid_node( grid_pos, code)
  local grid_node = global.grid[code]
  if not grid_node then
    -- Create grid node. For each direction, remember if the direction is
    -- walkable Also remember if we already tried to connect in that direction.
    local map_pos = grid_pos_to_map( grid_pos)

    local walkable = false
    local nauvis = game.surfaces['nauvis']
    local force = game.forces['player']
    -- local color = { 1.0, 1.0, 1.0, 1.0 }  -- Not charted = white
    if force.is_chunk_charted( nauvis, { math.floor(map_pos.x/32.0), math.floor(map_pos.y/32.0)}) then
      local tile = nauvis.get_tile(map_pos.x,map_pos.y)
      -- if not tile then
      --   color = { 1.0, 0.0, 1.0, 1.0} -- nil = magenta
      -- elseif not tile.valid then
      --   color = { 1.0, 0.0, 0.0, 1.0} -- invalid = red
      -- elseif tile.name == 'water' then
      --   color = { 0.3, 0.3, 1.0, 1.0} -- water = lightblue
      -- elseif tile.name == 'deepwater' then
      --   color = { 0.0, 0.0, 1.0, 1.0} -- deepwater = darkblue
      -- else
      --   color = { 0.0, 1.0, 0.0, 1.0} -- ok = green
      -- end
      walkable = tile and tile.valid and (tile.name ~= 'water') and (tile.name ~= 'deepwater')
    end
    grid_node = {
        grid_pos = grid_pos,
        walkable = walkable,
    }
    -- rendering.draw_circle{ color = color, radius = 0.5, filled = true, target = map_pos, surface='nauvis', time_to_live = 1000}
    global.grid[code] = grid_node
  end
  return grid_node
end

local function grid_is_walkable( grid_pos, grid_code)
  local grid_node = get_grid_node( grid_pos, grid_code)
  return grid_node.walkable
end

local function clear_chunk_from_cache(event)
  if event.force == 'player' then
     local chunk_pos = event.position
     local map_pos = {x=chunk_pos.x * 32.0, y=chunk_pos.y * 32.0}
     for dx = -2,2 do
       for dy = -2,2 do
         local grid_pos = compute_grid_pos( {x=map_pos.x + dx * kGrid_stepSize, y=map_pos.y + dy * kGrid_stepSize})
         local grid_code = compute_grid_code( grid_pos)
         global.grid[grid_code] = nil
       end
     end
  end
end


-- A* planner ==================================================

local kState_idle       = 0
local kState_planning   = 1
local kState_walking    = 2
local kState_approach   = 3
local kState_attack     = 4
local kState_retreat    = 5
local kState_goHome     = 6
local kState_reArm      = 7

-- Update neighbour
local function plan_add_neighbour( killer, grid_pos, grid_code, parent_gc, parent_mn, add_distance, near_water)
  if grid_is_walkable( grid_pos, grid_code) then
    local tentative_gScore = parent_mn.gScore + add_distance
    local map_pos = grid_pos_to_map( grid_pos)
    local goal_dist = dist_between_pos( killer.goal, map_pos)
    local weight = 3.0
    local prio = (weight * goal_dist + tentative_gScore)
    if near_water then
      prio = 0.0
    end
    if not killer.map[grid_code] then
      killer.map[grid_code] = {
        grid_pos = grid_pos,
        gScore = tentative_gScore,
        hScore = goal_dist,
        parent = parent_gc,
      }
      if not killer.openSet:contains( grid_code) then
        killer.openSet:enqueue( grid_code, prio)
      end
    elseif tentative_gScore < killer.map[grid_code].gScore then
      local neighbour = killer.map[grid_code]
      neighbour.gScore = tentative_gScore
      neighbour.hScore = goal_dist
      neighbour.parent = parent_gc
      if not killer.openSet:contains( grid_code) then
        killer.openSet:enqueue( grid_code, prio)
      end
    end
  end
end

local kFound_noPath   = 0
local kFound_found    = 1
local kFound_stopped  = 2
local kFound_planning = 3

-- One step of the A*
local function path_search( killer)

  killer.plan_calls = killer.plan_calls + 1

  if killer.openSet:empty() then
    block_target(killer.target_pos)
    return {found = kFound_noPath}
  end
  local current_gc, _ = killer.openSet:dequeue()
  -- The grid entry must exist
  local current_mn = killer.map[current_gc]
  local current_gp = current_mn.grid_pos

  -- If close to goal, stop searching
  if (current_mn.hScore < kGrid_stepSize) then
    return {grid_code=current_gc, found = kFound_found}
  end
  -- if (killer.plan_calls > 1000) then
  --   return {grid_code=current_gc, found = kFound_stopped}
  -- end

  -- The current position is walkable. Check the 8 neighbours and insert those that are walkable too.
  local n_gp = { x=current_gp.x, y=current_gp.y - 1.0 }
  local s_gp = { x=current_gp.x, y=current_gp.y + 1.0 }
  local e_gp = { x=current_gp.x + 1.0, y=current_gp.y }
  local w_gp = { x=current_gp.x - 1.0, y=current_gp.y }

  local n_gc = compute_grid_code( n_gp)
  local s_gc = compute_grid_code( s_gp)
  local e_gc = compute_grid_code( e_gp)
  local w_gc = compute_grid_code( w_gp)

  local ne_gp = { x=current_gp.x + 1.0, y=current_gp.y - 1.0 }
  local nw_gp = { x=current_gp.x - 1.0, y=current_gp.y - 1.0 }
  local se_gp = { x=current_gp.x + 1.0, y=current_gp.y + 1.0 }
  local sw_gp = { x=current_gp.x - 1.0, y=current_gp.y + 1.0 }

  local ne_gc = compute_grid_code( ne_gp)
  local nw_gc = compute_grid_code( nw_gp)
  local se_gc = compute_grid_code( se_gp)
  local sw_gc = compute_grid_code( sw_gp)

  local near_water =
  (not grid_is_walkable( n_gp, n_gc)) or
  (not grid_is_walkable( e_gp, e_gc)) or
  (not grid_is_walkable( s_gp, s_gc)) or
  (not grid_is_walkable( w_gp, w_gc)) or
  (not grid_is_walkable( ne_gp, ne_gc)) or
  (not grid_is_walkable( nw_gp, nw_gc)) or
  (not grid_is_walkable( se_gp, se_gc)) or
  (not grid_is_walkable( sw_gp, sw_gc))

  plan_add_neighbour( killer, n_gp, n_gc, current_gc, current_mn, kGrid_stepSize, near_water)
  plan_add_neighbour( killer, e_gp, e_gc, current_gc, current_mn, kGrid_stepSize, near_water)
  plan_add_neighbour( killer, s_gp, s_gc, current_gc, current_mn, kGrid_stepSize, near_water)
  plan_add_neighbour( killer, w_gp, w_gc, current_gc, current_mn, kGrid_stepSize, near_water)

  plan_add_neighbour( killer, ne_gp, ne_gc, current_gc, current_mn, kGrid_diagStepSize, near_water)
  plan_add_neighbour( killer, nw_gp, nw_gc, current_gc, current_mn, kGrid_diagStepSize, near_water)
  plan_add_neighbour( killer, se_gp, se_gc, current_gc, current_mn, kGrid_diagStepSize, near_water)
  plan_add_neighbour( killer, sw_gp, sw_gc, current_gc, current_mn, kGrid_diagStepSize, near_water)

  return {found = kFound_planning}
end

-- Plan a path from target to current position.
local function plan_path( killer, target, ok_state, fail_state, info)
  -- Center of the circle we're walking while waiting for the planner to finish
  if not killer.taptap_ctr or dist_between_pos( killer.vehicle.position, killer.taptap_ctr) > 32.0 then
    killer.taptap_ctr = killer.vehicle.position
  end
  killer.openSet = PriorityQueue.new('min')
  -- Info about the map points that have been visited or need to be visited
  killer.map = {}
  killer.plan_calls = 0
  -- Goal of the path search, i.e. starting position of future path
  killer.goal = killer.vehicle.position
  -- Target to reach, i.e. end position of future path.
  killer.target_pos = target

  -- Create the grid if it doesn't exits
  if not global.grid then
    global.grid = {}
  end

  -- Insert the starting node into the grid
  local tgt_gp = compute_grid_pos(target)
  local tgt_gc = compute_grid_code( tgt_gp)
  local goal_dist = dist_between_pos( killer.goal, killer.target_pos)
  killer.initial_goal_dist = goal_dist
  killer.openSet:enqueue( tgt_gc, goal_dist)
  killer.map[tgt_gc] = {
    grid_pos = tgt_gp,
    gScore = 0.0,
    hScore = goal_dist,
    -- No parent
  }

  -- Create entry in global grid. If the target is on water, stop planning.
  local walkable = grid_is_walkable(tgt_gp,tgt_gc)
  if walkable then
    killer.state = kState_planning
    killer.ok_state = ok_state
    killer.fail_state = fail_state

    for k,v in pairs(info) do
      killer[k] = v
    end
  else
    block_target(killer.target_pos)
    killer.state = fail_state
  end
  return walkable
end

-- State machine ===============================================

local function check_stuck_state(killer)
  local stuck = false
  if killer.last_state ~= killer.state then
    killer.stuck_count = 0
  else
    killer.stuck_count = killer.stuck_count + 1
    if killer.stuck_count > 100 then
      stuck = true
    end
  end
  return stuck
end

local function have_autopilot(vehicle)
  return vehicle.autopilot_destination or (table_size(vehicle.autopilot_destinations) ~= 0);
end

-- Try to send the vehicle home
local function vehicle_go_home(killer)
  local ok = false
  -- go home, find the closest homebase

  local home_dist = nil
  local home = nil
  local base = global.homebases
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
    plan_path(killer, home.position, kState_goHome, kState_idle, {})
    ok = true
  end
  return ok
end

-- Check if the spidertron needs to go home
local function vehicle_wants_home(vehicle)
  local retreat = false
  -- is vehicle damaged?
  if vehicle.get_health_ratio() < 0.5 then
    retreat = true
  end
  -- is ammo low?
  local ammo_inv = vehicle.get_inventory(defines.inventory.spider_ammo)
  if ammo_inv then
    if ammo_inv.is_empty() then
      retreat = true
    end
  end
  return retreat
end


-- State transition checker for killer spidertrons in idle state
local function trans_killer_idle( killer, valid_targets)
  -- White
  killer.vehicle.color = {1.0, 1.0, 1.0, 1.0}

  local approach = true
  if vehicle_wants_home(killer.vehicle) then
    game.print('idle vehicle ' .. killer.vehicle.unit_number .. ' wants to go home')
    if vehicle_go_home(killer) then
      approach = false
    end
  end

  if global.idle_vehicles_processed < 1 then
    if approach and global.targets then
      local tgt = closest_target( killer.vehicle.position)
      global.idle_vehicles_processed = global.idle_vehicles_processed + 1
      if tgt then
        if plan_path( killer, tgt.position, kState_approach, kState_idle, { target = tgt }) then
        end
      end
    end
  end
end

-- State transition checker for killer spidertrons in approach state
local function trans_killer_approach( killer)
  -- orange
  killer.vehicle.color = {1.0, 0.5, 0.0, 1.0}
  local attack = false
  local idle = false
  if killer.target then
    if killer.target.valid and killer.target.health and killer.target.health > 0.0 then
      if dist_between_pos(killer.target_pos, killer.vehicle.position) < 100.0 then
        attack = true
      end
    else
      idle = true
    end
  end
  if not have_autopilot(killer.vehicle) then
    idle=true
  end
  if vehicle_wants_home(killer.vehicle) then
    game.print('approaching vehicle ' .. killer.vehicle.unit_number .. ' wants to go home')
    vehicle_go_home(killer)
    attack = false
    idle = false
  end

  if attack then
    killer.safe_path = killer.vehicle.autopilot_destinations
    killer.state = kState_attack
    killer.taptap_ctr = nil
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
    killer.taptap_ctr = nil
    killer.vehicle.autopilot_destination = nil
    killer.state = kState_idle
  end
end

-- State transition checker for killer spidertrons in retreat state
local function trans_killer_retreat( killer)
  -- cyan
  killer.vehicle.color = {0.0, 1.0, 1.0, 1.0}
  if check_stuck_state(killer) then
    killer.vehicle.autopilot_destination = nil
    -- Idle to search for the next target
    killer.state = kState_idle
  elseif not killer.vehicle.autopilot_destination then
    killer.state = kState_idle
  end
end

-- State transition checker for killer spidertrons in go_home state
local function trans_killer_go_home( killer)
  -- blue
  killer.vehicle.color = {0.0, 0.0, 1.0, 1.0}
  if not have_autopilot(killer.vehicle) then
     killer.state = kState_reArm
  end
end

-- State transition checker for killer spidertrons in re_arm state
local function trans_killer_re_arm( killer)
  -- green
  killer.vehicle.color = {0.0, 1.0, 0.0, 1.0}
  if not killer.home_position or dist_between_pos(killer.home_position, killer.vehicle.position) > 10.0 then
    if vehicle_wants_home(killer.vehicle) then
      vehicle_go_home(killer)
      return
    end
  end
  if killer.vehicle.get_health_ratio() >= 1.0 then
    local ammo_inv = killer.vehicle.get_inventory(defines.inventory.spider_ammo)
    if ammo_inv then
      if ammo_inv.is_full() then
        killer.state = kState_idle
      end
    end
  end
end

-- State transition checker for killer spidertrons in planning state
local function trans_killer_planning( killer)
  global.planning_steps_sum = global.planning_steps_sum + global.planning_steps
  local planning_steps = math.floor( global.planning_steps_sum) - global.planning_steps_done
  global.planning_steps_done = global.planning_steps_done + planning_steps

  -- Yellow
  killer.vehicle.color = {1.0, 1.0, 0.0, 1.0}

  global.new_planning_vehicles = global.new_planning_vehicles + 1

  -- Walk around in circles
  local taptap_radius = 15.0
  local taptap_steps = 16
  if killer.taptap_ctr and (#killer.vehicle.autopilot_destinations < taptap_steps) then
    if #killer.vehicle.autopilot_destinations == 1 then
      killer.state = kState_walking
      killer.ok_state = kState_idle
      return
    end
    -- Add another revolution
    local nauvis = game.surfaces['nauvis']
    for i = 0, (taptap_steps-1) do
      local angle = 2.0*math.pi*i/taptap_steps
      local x=killer.taptap_ctr.x + math.sin(angle)*taptap_radius
      local y=killer.taptap_ctr.y + math.cos(angle)*taptap_radius

      local tile = nauvis.get_tile(x,y)
      if tile and tile.valid and (tile.name ~= 'water') and (tile.name ~= 'deepwater') then
        killer.vehicle.add_autopilot_destination( { x=x, y=y})
      end
    end
  end

  local final = nil
  if planning_steps > 0 then

    if killer.ok_state == kState_approach then
      killer.cyclesSinceTargetCheck = 1 + (killer.cyclesSinceTargetCheck or 0)
      if killer.cyclesSinceTargetCheck > 20 then
        killer.cyclesSinceTargetCheck = 0
        if not killer.target or not killer.target.valid then
          killer.state = killer.fail_state
          return
        end
      end
    end

    if killer.openSet and not killer.openSet._higherpriority then
      killer.openSet._higherpriority = function (a,b)
        return a < b
      end
    end
    for i = 1, planning_steps do
      local res = path_search( killer)
      if res.found ~= kFound_planning then
        final = res
        break
      end
    end
    if killer.decorations then
      for _,d in ipairs(killer.decorations) do
        rendering.destroy( d)
      end
    end

    local ds = {}
    if false then
      -- Draw a line to the target position
      local color = { 0.0, 1.0, 0.5, 1.0}
      ds[#ds+1] = rendering.draw_line{
        color = color,
        from = killer.goal,
        to = killer.target_pos,
        width=2.0,
        surface='nauvis',
        time_to_live = 100}

      -- Draw the front
      local color = { 1.0, 0.5, 0.5, 1.0}
      local n = math.min( #killer.openSet, 100)
      for i = 1, n do
        local grid_code = killer.openSet[i]
        local grid_pos = killer.map[grid_code].grid_pos
        local map_pos = grid_pos_to_map( grid_pos)
        ds[#ds+1] = rendering.draw_circle{ color = color, radius = 0.8, target = map_pos, surface='nauvis', time_to_live = 100}
        -- ds[#ds+1] = rendering.draw_text{ color = color, text = i .. ': ' .. killer.openSet._priorities[i], target = map_pos, surface='nauvis', time_to_live = 100}
        local parent_gc = killer.map[grid_code].parent
        if parent_gc then
          local parent_gp = killer.map[parent_gc].grid_pos
          local parent_mp = grid_pos_to_map( parent_gp)
          ds[#ds+1] = rendering.draw_line{ color = color, from = parent_mp, to = map_pos, width=1.0, surface='nauvis', time_to_live = 100}
        end
      end

      -- Draw the best path
      if not killer.openSet:empty() then
        local grid_code, _ = killer.openSet:peek()
        local last_pos = killer.goal
        local color = { 1.0, 0.3, 0.3, 1.0}
        while grid_code do
          local grid_pos = killer.map[grid_code].grid_pos
          local map_pos = grid_pos_to_map( grid_pos)
          ds[#ds+1] = rendering.draw_line{ color = color, from = last_pos, to = map_pos, width=3.0, surface='nauvis', time_to_live = 100}
          last_pos = map_pos
          grid_code = killer.map[grid_code].parent
        end
      end

      -- local color = { 0.8, 0.3, 0.3, 1.0}
      -- local block_list = global.target_blockers or {}
      -- for _,ctr in pairs(block_list) do
      --   if type(ctr) == 'table' then
      --     ds[#ds+1] = rendering.draw_circle{ color = color, radius = 16.0, width = 10.0, target = ctr, surface='nauvis', time_to_live = 100}
      --   end
      -- end
    end
    killer.decorations = ds

    if final then
      if final.found == kFound_found then
        -- We found a path, set the autopilot
        killer.vehicle.autopilot_destination=nil
        local grid_code = final.grid_code
        while grid_code do
          local grid_pos = killer.map[grid_code].grid_pos
          local map_pos = grid_pos_to_map( grid_pos)
          killer.vehicle.add_autopilot_destination( map_pos)
          grid_code = killer.map[grid_code].parent
        end
        killer.state = killer.ok_state
      elseif final.found == kFound_stopped then
        -- Restart planning to the best guess towards the target
        local grid_code = final.grid_code
        local grid_pos = killer.map[grid_code].grid_pos
        local map_pos = grid_pos_to_map( grid_pos)
        killer.target = nil
        plan_path( killer, map_pos, killer.ok_state, killer.fail_state, {})
      elseif final.found == kFound_noPath then
        killer.state = killer.fail_state
      end
    end
  end
end

-- State transition checker for killer spidertrons in walking state
local function trans_killer_walking( killer)
  -- Grey
  killer.vehicle.color = {0.5, 0.5, 0.5, 1.0}
  if not have_autopilot( killer.vehicle) then
    killer.state = killer.ok_state
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
 [kState_walking] = trans_killer_walking
}

-- A chunk to explore has at least one polluted and one unexplored chunk in a 5x5 neighbourhood
local function find_chunks_to_explore()
  local force = game.forces['player']
  local nauvis = game.surfaces['nauvis']
  if not global.chunk_iterator and (not global.targets or (#global.targets == 0)) then
    global.chunk_iterator = nauvis.get_chunks()
  end

  if global.chunk_iterator then
    game.print( 'find_chunks_to_explore: do chunks')
    local chunks_to_check = 100
    local checked = 0
    local valid_targets = global.targets or {}
    while (checked < chunks_to_check) do
      local chunk = global.chunk_iterator()
      if not chunk then
        game.print( 'find_chunks_to_explore: done')
        global.chunk_iterator = nil
        break
      end
      local map_pos = {x=chunk.x * 32.0 + 16.0, y=chunk.y * 32.0 + 16.0}

      local uncharted = 0
      local polluted = 0
      for dx = -2,2 do
        for dy = -2,2 do
          if not force.is_chunk_charted('nauvis', {chunk.x+dx,chunk.y+dy}) then
            uncharted = uncharted + 1
          elseif nauvis.get_pollution({map_pos.x+32.0*dx,map_pos.y+32.0*dy}) > 0.0 then
            polluted = polluted + 1
          end
        end
      end

      -- Add it to the list of targets
      if (uncharted > 0) and (polluted > 0) then
        local map_pos = {x=chunk.x * 32.0 + 16.0, y=chunk.y * 32.0 + 16.0}
        -- Add a fake target and mark it as an exploration target
        valid_targets[#valid_targets+1] = { position = map_pos, valid = true, health = 1.0, type = 'exploration' }
      end

      checked = checked + 1
    end
    game.print( #valid_targets .. ' total targets')
    global.targets = valid_targets
  end
end

-- Part of state machine processing, to be called frequently
local function spidertron_state_machine()

  local rescan_vehicles = false
  local killers = global.vehicles or {}

  -- If there are idle vehicles and the target list is old, find a new target list
  local cycles_since_new_targets = global.cycles_since_new_targets or 0
  cycles_since_new_targets = cycles_since_new_targets + 1
  if (cycles_since_new_targets > 300) and (#global.targets == 0) then
    -- Find all idle vehicles that require the target list
    for id,killer in pairs(killers) do
      if killer.vehicle and killer.vehicle.valid then
        if killer.state == kState_idle then
          find_valid_targets()
          global.cycles_since_new_targets = 0
          return
        end
      end
    end
  end
  global.cycles_since_new_targets = cycles_since_new_targets

  if not global.planning_vehicles then
    global.planning_vehicles = #killers
  end

  -- Ensure roughly the same number of planning steps per cycle.
  local planning_steps = 50
  if global.planning_vehicles > 0 then
    -- Ensure at least one step per cycle
    planning_steps = planning_steps / global.planning_vehicles
  end
  global.planning_steps = planning_steps

  global.planning_steps_done = 0.0
  global.planning_steps_sum = 0.0
  global.idle_vehicles_processed = 0
  global.new_planning_vehicles = 0
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
        killer.state = kState_idle
      end
      killer.last_state = current_state
    else
      rescan_vehicles = true
    end
  end
  global.planning_vehicles = global.new_planning_vehicles

  if rescan_vehicles then
    detect_vehicles()
  elseif global.planning_steps_done < global.planning_steps then
    find_chunks_to_explore()
  end

  -- Clear the block list if this hasn't been done in a while
  local calls_since_empty_blocklist = global.calls_since_empty_blocklist or 0
  if calls_since_empty_blocklist > 10000 then
    global.target_blockers = {}
    global.grid = {}
    calls_since_empty_blocklist = 0
  end
  calls_since_empty_blocklist = calls_since_empty_blocklist + 1
  global.calls_since_empty_blocklist = calls_since_empty_blocklist
end

-- Register the vehicle detector
script.on_event(defines.events.on_entity_renamed, detect_vehicles)
script.on_event(defines.events.on_entity_cloned, detect_vehicles)
script.on_event(defines.events.on_entity_died, detect_vehicles, {{filter='vehicle'}})
script.on_event(defines.events.on_entity_settings_pasted, detect_vehicles)

-- Register the homebase detector
script.on_event(defines.events.on_chart_tag_added, detect_homebases)
script.on_event(defines.events.on_chart_tag_modified, detect_homebases)
script.on_event(defines.events.on_chart_tag_removed, detect_homebases)

-- Register the state machine handler
script.on_nth_tick(6, spidertron_state_machine)

-- Register the metatables for PriorityQueue
script.register_metatable( 'PriorityQueue', getmetatable(PriorityQueue))
script.register_metatable( 'PriorityQueueMt', getmetatable(PriorityQueue.new()))

-- Register event to clear the cache if a chunk is charted
script.on_event( defines.events.on_chunk_charted, clear_chunk_from_cache)
