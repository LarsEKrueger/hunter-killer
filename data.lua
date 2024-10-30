--[[

data.lua: Data handling script for the factorio mod *HunterKiller*.
]]

local collision_mask_util = require 'collision-mask-util'

-- Get an unused collision layer
for i, l in pairs( data.raw['collision-layer']) do
  log( serpent.line( l))
end
local nest_layer = table.deepcopy( data.raw['collision-layer']['object'])

-- Add that layer to nests and worms
if nest_layer then
  nest_layer.name = 'hk_nest_layer'
  data:extend{ nest_layer }
  for i, type in pairs( {'unit-spawner','turret','tile'}) do
    for name, entity in pairs( data.raw[type]) do
      if (type ~= 'tile') or entity.draw_in_water_layer then
        local entity_mask = collision_mask_util.get_mask(entity)
        entity_mask.layers[nest_layer.name] = true
        entity.collision_mask = entity_mask
        log( '>>' .. type .. '<<, >>' .. name .. '<<: ' .. serpent.line( entity_mask))
      end
    end
  end
else
  error( "Can't get a collision mask")
end
