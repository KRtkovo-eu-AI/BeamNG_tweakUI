-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local im = ui_imgui
local logTag = "drag_debug"

-- Debug state variables
local debugMenu = true
local selectedVehicle = -1
local aviableLanes = {}

-- Color constants for debug UI
local red = im.ImVec4(1,0.5,0.5,0.75)
local yellow = im.ImVec4(1,1,0.5,0.75)
local green = im.ImVec4(0.5,1,0.5,0.75)

-- Debug functions
local function getSelection(classNames)
  local id
  if editor.selection and editor.selection.object and editor.selection.object[1] then
    local currId = editor.selection.object[1]
    if not classNames or arrayFindValueIndex(classNames, scenetree.findObjectById(currId).className) then
      id = currId
    end
  end
  return id
end

local function selectElement(index)
  selectedVehicle = index
end

local function getLastElement(dragData)
  for vehId,_ in pairs(dragData.racers) do
    selectedVehicle = vehId
  end
end

-- Main debug menu drawing function
local function drawDebugMenu(dragData, ext)
  if not debugMenu then return end

  if im.Begin("Drag Race General Debug") then
    im.SameLine()
    if im.Button("Clear Save Data ##clearData") then
      dragData = nil
    end

    if dragData then
      im.Columns(2,'mainDrag')
      im.Text("Drag Data")
      im.Text("Context: ")
      im.SameLine()
      im.Text(dragData.context)

      im.Text("dragtype extension: ")
      im.SameLine()
      im.TextColored(ext and green or red, ext and ext.__extensionName__ or "No Extension")

      im.Text("Is Started:")
      im.SameLine()
      im.TextColored(dragData.isStarted and green or red, dragData.isStarted and "Started" or "Stopped")

      im.NewLine()
      im.Text("Phases: ")
      for index, value in ipairs(dragData.phases or {}) do
        im.SameLine()
        if im.Button("Play " .. value.name) then
          ext.startDebugPhase(index, dragData)
        end
      end
      im.NewLine()

      if im.Button("Start Drag Race") then
        gameplay_drag_general.startDragRaceActivity()
      end

      if im.Button("Reset Drag Race") then
        ext.resetDragRace()
      end

      im.NextColumn()
      im.Text("Strip Data")
      im.NewLine()
      if dragData.strip.endCamera then
        im.Text("End Camera: ")
        im.SameLine()
        im.Text("Position: {" .. dragData.strip.endCamera.transform.pos.x .. ", " .. dragData.strip.endCamera.transform.pos.y .. ", " .. dragData.strip.endCamera.transform.pos.z .. "}")
        im.SameLine()
        im.Text("Rotation: {" .. dragData.strip.endCamera.transform.rot.x .. ", " .. dragData.strip.endCamera.transform.rot.y .. ", " .. dragData.strip.endCamera.transform.rot.z .. ", " .. dragData.strip.endCamera.transform.rot.w .. "}")
        im.SameLine()
        im.Text("Scale: {" .. dragData.strip.endCamera.transform.scl.x .. ", " .. dragData.strip.endCamera.transform.scl.y .. ", " .. dragData.strip.endCamera.transform.scl.z .. "}")
      end

      for nameType, p in pairs(dragData.prefabs) do
        im.Text("Prefab: " .. nameType)
        im.SameLine()
        im.Text(" | Is Used: " .. tostring(p.isUsed))
        if p.isUsed then
          im.SameLine()
          im.Text(" |  " .. (p.path or "No path founded"))
        end
      end
      im.NextColumn()

      im.Columns(2, 'vehicles')

      im.BeginChild1("vehicle select", im.GetContentRegionAvail(), 1)
      im.Text("Vehicle Settings")
      for k,v in ipairs(aviableLanes) do
        if v then
          if im.Selectable1("Empty Lane - " ..k.. "##" .. k) then
            local vehId = getSelection()

            gameplay_drag_general.setupRacer(vehId, k)
            if not dragData.racers[vehId] then
              aviableLanes[k] = true
            else
              aviableLanes[k] = false
            end
          end
          if im.IsItemHovered() then
            im.tooltip("Add selected vehicle from scenetree to Lane: " ..k)
          end
        end
      end
      for vehId, _ in pairs(dragData.racers or {}) do
        if im.Selectable1(string.format("Racer ID: %d Lane: %d", vehId, dragData.racers[vehId].lane), vehId == selectedVehicle) then
          selectElement(vehId)
        end
      end
      im.EndChild()
      im.NextColumn()

      im.BeginChild1("vehicle detail", im.GetContentRegionAvail(), 1)
      if selectedVehicle and dragData.racers[selectedVehicle] then
        if im.Button("Remove Vehicle" .. "##"..selectedVehicle) then
          aviableLanes[dragData.racers[selectedVehicle].lane] = true
          dragData.racers[selectedVehicle] = nil
          selectedVehicle = -1
          getLastElement(dragData)
        end

        im.NewLine()
        im.Text("Lane ".. dragData.racers[selectedVehicle].lane .. " Data :")
        if selectedVehicle ~= -1 then
          im.Text("(Click to dump, hover to preview)")
          for key, laneData in pairs(dragData.strip.lanes[dragData.racers[selectedVehicle].lane]) do
            if im.Button("Lanedata: " .. key) then
              dump(laneData.transform)
            end
            if im.IsItemHovered() and editor_dragRaceEditor then
              local rot = quat(laneData.transform.rot)
              local x, y, z = laneData.transform.x, laneData.transform.y, laneData.transform.z
              local scl = (x+y+z)/2
              editor_dragRaceEditor.drawAxisBox(((-scl*2)+vec3(laneData.transform.pos)),x*2,y*2,z*2,color(255,255,255,0.2*255))
              local pos = vec3(laneData.transform.pos)
              debugDrawer:drawLine(pos, pos + x, ColorF(1,0,0,0.8))
              debugDrawer:drawLine(pos, pos + y, ColorF(0,1,0,0.8))
              debugDrawer:drawLine(pos, pos + z, ColorF(0,0,1,0.8))
            end
          end
        end
        im.Text("Vehicle Data: ")
        local vehicleData = dragData.racers[selectedVehicle]
        if not vehicleData then
          im.Text("No vehicle data yet")
        else
          if im.Button("Dump Vehicle data") then
            dump(dragData.racers[selectedVehicle])
          end
          local isP = im.BoolPtr(vehicleData.isPlayable)
          im.Checkbox("Is Playable", isP)
          vehicleData.isPlayable = isP[0]
          im.SameLine()
          im.Text(vehicleData.isPlayable and "Is Playable" or "Not playable")
          im.Text("Lane: " .. vehicleData.lane)
          im.Text(vehicleData.isDesqualified and "Desqualified" or "Not desqualified")
          im.Text("Desqualification Reason: " ..vehicleData.desqualifiedReason)
          im.Separator()
          im.Text("Phases")

          for _, phase in ipairs(vehicleData.phases) do
            im.Text(phase.name .. " - ")
            im.SameLine()
            im.TextColored(phase.started and green or red, "Started")
            im.SameLine()
            im.TextColored(phase.completed and green or red, "Completed")
            im.Text(dumps(phase))
            im.Separator()
          end
        end
      end
      im.EndChild()
      im.NextColumn()
    end
    im.Columns(0)
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if debugMenu then
    local dragData = gameplay_drag_general.getData()
    local ext = gameplay_drag_general.getExtension()
    drawDebugMenu(dragData, ext)
  end
end

-- Public interface
M.debugMenu = debugMenu
M.selectedVehicle = selectedVehicle
M.aviableLanes = aviableLanes

M.setDebugMenu = function(enabled)
  debugMenu = enabled
end

M.getDebugMenu = function()
  return debugMenu
end

M.setSelectedVehicle = function(vehId)
  selectedVehicle = vehId
end

M.getSelectedVehicle = function()
  return selectedVehicle
end

M.setAviableLanes = function(lanes)
  aviableLanes = lanes
end

M.getAviableLanes = function()
  return aviableLanes
end

M.drawDebugMenu = drawDebugMenu
M.getSelection = getSelection
M.selectElement = selectElement
M.getLastElement = getLastElement
M.onUpdate = onUpdate

return M