-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local im  = ui_imgui

local C = {}

C.name = 'Vehicle Group by Performance Class'
C.description = 'Generates a vehicle group based on the given class.'
C.category = 'once_instant'
C.color = ui_flowgraph_editor.nodeColors.career
C.icon = ui_flowgraph_editor.nodeIcons.career
C.author = 'BeamNG'
C.dependencies = {'career_modules_vehicleClassGrouping'}

C.pinSchema = {
  {dir = 'in', type = {'string', 'number'}, name = 'class', description = 'Vehicle class ("S", "A", "B", "C", "D"); string or number (1 - 5).'},
  {dir = 'out', type = 'table', name = 'vehGroup', tableType = 'vehicleGroupData', description = 'Vehicle group data.'},
  {dir = 'out', type = 'number', name = 'aggressionCoef', description = 'Vehicle AI aggression multiplier.'}
}

C.tags = {'career', 'race', 'class', 'vehicle'}

function C:workOnce()
  local class = self.pinIn.class.value

  if type(class) == 'number' then
    local classArray = {"S", "A", "B", "C", "D"}
    class = classArray[clamp(math.floor(class), 1, 5)]
  end

  self.pinOut.vehGroup.value = career_modules_vehicleClassGrouping.generateGroup(class)
  self.pinOut.aggressionCoef.value = career_modules_vehicleClassGrouping.getAggressionMultiplier(class)
end

return _flowgraph_createNode(C)
