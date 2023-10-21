--[[
  data-final-fixes.lua: Script for the factorio mod *HunterKiller*. Create roboports with range zero.
]]


-- create copies of roboports with 0 construction radius.
-- Adapted from Contructron-Continued (MIT license)
local roboports = data.raw["roboport-equipment"]
local reduced_roboports = {}

for name, eq in pairs(roboports) do
   local max_radius = math.min(eq.construction_radius, 1)
   -- skip if equipment has no construction radius
   if not (max_radius == 0) then
     -- create copies with reduced construction radius
     local eq_copy = table.deepcopy(eq)
     eq_copy.construction_radius = 0
     eq_copy.localised_name = {"equipment-name." .. name}
     eq_copy.name = name .. "-hk-disabled";
     if not eq.take_result then
       eq_copy.take_result = name
     end
     table.insert(reduced_roboports, eq_copy)
   end
end

data:extend(reduced_roboports)
