--[[

data.lua: Data handling script for the factorio mod *HunterKiller*.
]]

local collision_mask_util = require 'collision-mask-util'

-- Get an unused collision layer
local nest_layer = collision_mask_util.get_first_unused_layer()

-- Add that layer to nests and worms
if nest_layer then
  for i, type in pairs ({'unit-spawner','turret','tile'}) do
    for name, entity in pairs (data.raw[type]) do
      if (type ~= 'tile') or entity.draw_in_water_layer then
        local entity_mask = collision_mask_util.get_mask(entity)
        collision_mask_util.add_layer(entity_mask, nest_layer)
        entity.collision_mask = entity_mask
        log( '>>' .. type .. '<<, >>' .. name .. '<<: ' .. serpent.line( entity_mask))
      end
    end
  end
  log( 'layer = >>' .. nest_layer .. '<<')
else
  error( "Can't get a collision mask")
end
