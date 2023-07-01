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

-- Get the list of target that are not blocked. Return true if target were checked
local function find_valid_targets()
  local nauvis = game.surfaces['nauvis']
  if (not global.enemy_list) and (not global.targets or (#global.targets == 0)) then
    local targets = nauvis.find_entities_filtered{
      force='enemy',
      is_military_target=true,
      type={'turret', 'spawner'},
    }
    global.enemy_list = targets
    if #targets > 0 then
      game.print( #targets .. ' enemies of the realm found')
    end
  end
  local some_checked = false
  local valid_targets = global.targets or {}
  if global.enemy_list then
    local enemies_to_check = 100
    local checked = 0

    local force = game.forces['player']
    while (checked < enemies_to_check) and (#global.enemy_list > 0) do
      local idx = #global.enemy_list
      local tgt = global.enemy_list[idx]
      table.remove(global.enemy_list,idx)
      some_checked = true
      if tgt.valid then
        if not is_target_blocked(tgt.position) then
          local tgt_chunk_pos = {x=tgt.position.x/32.0,y=tgt.position.y/32.0}
          local is_polluted = false
          for dx = -2,2 do
            if is_polluted then
              break
            end
            for dy = -2,2 do
              if force.is_chunk_charted('nauvis', {tgt_chunk_pos.x+dx,tgt_chunk_pos.y+dy}) and
                (nauvis.get_pollution({tgt.position.x+32.0*dx,tgt.position.y+32.0*dy}) > 0.0) then
                is_polluted = true
                break
              end
            end
          end
          if is_polluted then
            valid_targets[#valid_targets+1] = tgt
          end
        end
      end
      checked = checked + 1
    end
  end
  global.targets = valid_targets
  return some_checked
end

-- Return map_pos if chunk is interesting for exploration, nil otherwise
local function interesting_for_exploration( chunk)
  local force = game.forces['player']
  local nauvis = game.surfaces['nauvis']
  local uncharted = 0
  local polluted = 0
  if chunk and force.is_chunk_charted('nauvis', {chunk.x,chunk.y}) then
    local map_pos = {x=chunk.x * 32.0 + 16.0, y=chunk.y * 32.0 + 16.0}
    if not is_target_blocked(map_pos) then
      for dx = -2,2 do
        for dy = -2,2 do
          if not force.is_chunk_charted('nauvis', {chunk.x+dx,chunk.y+dy}) then
            uncharted = uncharted + 1
          elseif nauvis.get_pollution({map_pos.x+32.0*dx,map_pos.y+32.0*dy}) > 0.0 then
            polluted = polluted + 1
          end
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
  if not global.chunk_iterator and (not global.targets or (#global.targets == 0)) then
    global.chunk_iterator = nauvis.get_chunks()
  end

  local valid_targets = global.targets or {}
  if global.chunk_iterator then
    local chunks_to_check = 500
    local checked = 0
    while (checked < chunks_to_check) do
      local chunk = global.chunk_iterator()
      if not chunk then
        game.print( #valid_targets .. ' places to visit')
        global.chunk_iterator = nil
        global.enemy_list = nil
        break
      end
      local map_pos = interesting_for_exploration(chunk)
      if map_pos then
        -- Add a fake target and mark it as an exploration target
        valid_targets[#valid_targets+1] = {
          position = map_pos,
          valid = true,
          health = 1.0,
          type = 'exploration',
          chunk = chunk,
        }
      end
      checked = checked + 1
    end
  end
  global.targets = valid_targets
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

-- Plan a path from target to current position.
local function plan_path( killer, target, ok_state, fail_state, info)
  -- Center of the circle we're walking while waiting for the planner to finish
  if not killer.taptap_ctr or dist_between_pos( killer.vehicle.position, killer.taptap_ctr) > 32.0 then
    killer.taptap_ctr = killer.vehicle.position
  end

  local pathing_collision_mask = {"water-tile", "consider-tile-transitions", "colliding-with-tiles-only", "not-colliding-with-itself"}
  local request = {
    bounding_box =  {{-2, -2}, {2, 2}},
    collision_mask = pathing_collision_mask,
    start = killer.vehicle.position,
    goal = target,
    force = killer.vehicle.force,
    radius = 1,
    pathfinding_flags = {
      cache = true,
      low_priority = false,
    },
    path_resolution_modifier = -4,
    killer = killer,
  }

  local nauvis = game.surfaces['nauvis']

  global.pathfinder_requests = global.pathfinder_requests or {}
  if killer.request_id then
    global.pathfinder_requests[killer.request_id] = nil
  end
  local request_id = nauvis.request_path(request)
  global.pathfinder_requests[request_id] = request
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
  if global.pathfinder_requests then
    local request = global.pathfinder_requests[event.id]
    if request then
      if event.path then
        if request.killer.vehicle.valid then
          request.killer.vehicle.autopilot_destination = nil
          for _,p in ipairs(event.path) do
            request.killer.vehicle.add_autopilot_destination( p.position)
          end
        end
        request.killer.state = request.killer.ok_state
      else
        if not event.try_again_later then
          block_target(request.goal)
          request.killer.state = request.killer.fail_state
        end
      end
      if request.killer.request_id then
        global.pathfinder_requests[request.killer.request_id] = nil
      end
      request.killer.request_id = nil
      request.killer.pathfinder_request = nil
      global.pathfinder_requests[event.id] = nil
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
  if vehicle_wants_home(killer.vehicle) then
    game.print('idle vehicle ' .. killer.vehicle.unit_number .. ' wants to go home')
    vehicle_go_home(killer)
  end
end

-- State transition checker for killer spidertrons in approach state
local function trans_killer_approach( killer)
  -- orange
  killer.vehicle.color = {1.0, 0.5, 0.0, 1.0}
  local attack = false
  local idle = false
  if killer.target and killer.target.valid then
    if killer.target.type == 'exploration' then
      if interesting_for_exploration(killer.target.chunk) then
        if dist_between_pos(killer.target_pos, killer.vehicle.position) < 100.0 then
          attack = true
        end
      else
        idle = true
      end
    else
      if killer.target.health and killer.target.health > 0.0 then
        if dist_between_pos(killer.target_pos, killer.vehicle.position) < 100.0 then
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
  if not have_autopilot(killer.vehicle) then
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
  -- Yellow
  killer.vehicle.color = {1.0, 1.0, 0.0, 1.0}

  -- Walk around in circles
  local taptap_radius = 15.0
  local taptap_steps = 16
  local nauvis = game.surfaces['nauvis']
  local another_round = false
  if killer.taptap_ctr and (#killer.vehicle.autopilot_destinations < taptap_steps/2) then
    if #killer.vehicle.autopilot_destinations == 1 then
      killer.state = kState_walking
      if killer.request_id then
        global.pathfinder_requests = global.pathfinder_requests or {}
        global.pathfinder_requests[killer.request_id] = nil
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

  -- Check the request needs to be tried again
  if another_round and killer.request_id and global.pathfinder_requests and not global.pathfinder_requests[killer.request_id] then
    local request = killer.pathfinder_request
    if request then
      local request_id = nauvis.request_path(request)
      global.pathfinder_requests[request_id] = request
      killer.request_id = request_id
    else
      killer.state = kState_idle
    end
  end

  if not killer.request_id then
    killer.state = kState_idle
  end

  if killer.request_id then
    rendering.draw_line{color=killer.vehicle.color,width=1.0,from=killer.taptap_ctr,to=killer.target_pos,surface=nauvis,time_to_live=29}
    rendering.draw_text{text=killer.request_id,target=killer.taptap_ctr,color=killer.vehicle.color,surface=nauvis,time_to_live=29}
    rendering.draw_text{text=killer.request_id,target=killer.target_pos,color=killer.vehicle.color,surface=nauvis,time_to_live=29}
  end

  if killer.ok_state == kState_approach then
    killer.cyclesSinceTargetCheck = 1 + (killer.cyclesSinceTargetCheck or 0)
    if killer.cyclesSinceTargetCheck > 5 then
      killer.cyclesSinceTargetCheck = 0
      if not killer.target or not killer.target.valid then
        killer.state = killer.fail_state
        if killer.request_id then
          global.pathfinder_requests[killer.request_id] = nil
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

-- Take the first target and find the closest idle spider
local function send_closest_spider()
  local force = game.forces['player']
  if (not force.is_pathfinder_busy()) and global.targets then
    if #global.targets > 0 then
      local idx = 1
      if global.targets[idx].valid then
        local tgt_pos = global.targets[idx].position
        if not is_target_blocked(tgt_pos) then
          local killers = global.vehicles or {}
          local closest_d = nil
          local closest_killer = nil
          for id,killer in pairs(killers) do
            if killer.vehicle and killer.vehicle.valid then
              if (killer.state == kState_idle) and not vehicle_wants_home(killer.vehicle) then
                local d = dist_between_pos( tgt_pos, killer.vehicle.position)
                if ((not closest_d) or (d < closest_d)) and (not is_target_blocked(tgt_pos)) then
                  closest_d = d
                  closest_killer = killer
                end
              end
            end
          end
          if not closest_killer then
            return
          end
          plan_path( closest_killer, tgt_pos, kState_approach, kState_idle, { target = global.targets[idx] })
        end
      end
      table.remove(global.targets,idx)
    else
      -- No more targets, clear the block list
      global.target_blockers = {}
    end
  end
end

-- Check each idle spider if it can take the target of an approaching spider
local function steal_target()
  local force = game.forces['player']
  local stole = false
  if not force.is_pathfinder_busy() then
    local killers = global.vehicles or {}
    -- Loop over all potential thiefs
    for id_i,killer_i in pairs(killers) do
      if killer_i.vehicle and killer_i.vehicle.valid and
        not vehicle_wants_home(killer_i.vehicle) then
        if (killer_i.state == kState_idle) then
          -- Loop over all potential victims, find out if killer_i is closer and steal target
          local closest_d = nil
          local closest_killer = nil
          for id_j,killer_j in pairs(killers) do
            if (id_j ~= id_i) and killer_j.vehicle and killer_j.vehicle.valid and
              ((killer_j.state == kState_approach) or (killer_j.state == kState_planning)) and
              not vehicle_wants_home(killer_j.vehicle) then
              local d_ij = dist_between_pos(killer_i.vehicle.position,killer_j.target_pos)
              local d_jj = dist_between_pos(killer_j.vehicle.position,killer_j.target_pos)
              if (d_ij < d_jj) and  ((not closest_d) or (d_ij < closest_d)) then
                closest_d = d_ij
                closest_killer = killer_j
              end
            end
          end
          if closest_killer then
            global.pathfinder_requests = global.pathfinder_requests or {}
            if closest_killer.request_id then
              global.pathfinder_requests[closest_killer.request_id] = nil
              closest_killer.request_id = nil
            end
            closest_killer.state = kState_idle
            closest_killer.vehicle.autopilot_destination = nil
            plan_path( killer_i, closest_killer.target_pos, kState_approach, kState_idle, { target = closest_killer.target })
            stole = true
          end
        elseif ((killer_i.state == kState_planning) and (killer_i.ok_state == kState_approach)) or
          (killer_i.state == kState_approach) then
          -- Loop over all potential victims, find out if switching targets gives an smaller total sum of distance
          local closest_d = nil
          local closest_killer = nil
          for id_j,killer_j in pairs(killers) do
            if (id_j ~= id_i) and killer_j.vehicle and killer_j.vehicle.valid and
              ((killer_j.state == kState_approach) or (killer_j.state == kState_planning)) and
              not vehicle_wants_home(killer_j.vehicle) then
              local d_ij = dist_between_pos(killer_i.vehicle.position,killer_j.target_pos)
              local d_jj = dist_between_pos(killer_j.vehicle.position,killer_j.target_pos)
              local d_ji = dist_between_pos(killer_j.vehicle.position,killer_i.target_pos)
              local d_ii = dist_between_pos(killer_i.vehicle.position,killer_i.target_pos)
              local d_switch = d_ji + d_ij
              local d_keep = d_ii + d_jj
              if ((not closest_d) or (d_switch < closest_d)) and
                (d_switch < d_keep) and -- Switching reduces overall distance
                (math.abs(d_switch - d_keep) > 200) then
                closest_d = d_i
                closest_killer = killer_j
              end
            end
          end
          if closest_killer then
            global.pathfinder_requests = global.pathfinder_requests or {}
            if killer_i.request_id then
              global.pathfinder_requests[killer_i.request_id] = nil
              killer_i.request_id = nil
            end
            killer_i.state = kState_idle
            killer_i.vehicle.autopilot_destination = nil
            if closest_killer.request_id then
              global.pathfinder_requests[closest_killer.request_id] = nil
              closest_killer.request_id = nil
            end
            closest_killer.state = kState_idle
            closest_killer.vehicle.autopilot_destination = nil
            local target_i = killer_i.target
            local tgt_pos_i = killer_i.target_pos
            plan_path( killer_i, closest_killer.target_pos, kState_approach, kState_idle, { target = closest_killer.target })
            plan_path( closest_killer, tgt_pos_i, kState_approach, kState_idle, { target = target_i })
            stole = true
          end
        end
      end
    end -- for killer_i
  end
  return stole
end

-- Find the first idle killer and send it to the closest target
local function send_killer_to_target()
  local force = game.forces['player']
  if not force.is_pathfinder_busy() then
    global.targets = global.targets or {}
    local killers = global.vehicles or {}
    for id,killer in pairs(killers) do
      if killer.vehicle and killer.vehicle.valid then
        if (killer.state == kState_idle) and not vehicle_wants_home(killer.vehicle) then
          local closest_d = nil
          local closest_tgt = nil
          local closest_i = nil
          for i,tgt in ipairs(global.targets) do
            if not tgt.valid then
              table.remove(global.targets,i)
            else
              local d = dist_between_pos( tgt.position, killer.vehicle.position)
              if ((not closest_d) or (d < closest_d)) and (not is_target_blocked(tgt.position)) then
                closest_d = d
                closest_tgt = tgt
                closest_i = i
              end
            end
          end
          if closest_i then
            plan_path( killer, closest_tgt.position, kState_approach, kState_idle, { target = closest_tgt })
            table.remove(global.targets,closest_i)
            return
          end
        end
      end
    end
  end
end

-- Part of state machine processing, to be called frequently
local function spidertron_state_machine()
  local rescan_vehicles = false
  local killers = global.vehicles or {}

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

  if rescan_vehicles then
    detect_vehicles()
  end
end

local function spidertron_reassign_targets()
  steal_target()
end

local function spidertron_assign_targets()
  local killers = global.vehicles or {}
  if table_size(killers) < 5 then
    send_killer_to_target()
  else
    send_closest_spider()
    send_closest_spider()
  end
end

local function spidertron_find_targets()
  if not find_valid_targets() then
    find_chunks_to_explore()
  end
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

-- Start path search to the targets 10x per seconds
script.on_nth_tick(6, spidertron_assign_targets)

-- Sort targets by distance every 5 seconds
script.on_nth_tick(300, spidertron_reassign_targets)

-- Process the target list 5x per second
script.on_nth_tick(12, spidertron_find_targets)

-- Update state 2x per second
script.on_nth_tick(30, spidertron_state_machine)

-- Register the path planner
script.on_event(defines.events.on_script_path_request_finished, path_planner_finished)

-- Register the metatables for PriorityQueue
script.register_metatable( 'PriorityQueue', getmetatable(PriorityQueue))
script.register_metatable( 'PriorityQueueMt', getmetatable(PriorityQueue.new()))
