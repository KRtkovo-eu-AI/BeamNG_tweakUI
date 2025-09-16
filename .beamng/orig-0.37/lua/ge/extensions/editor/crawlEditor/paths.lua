-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local C = {}
local im = ui_imgui
local ffi = require('ffi')
local utilPath = path

local lastPath = nil
local editEnded = im.BoolPtr(false)

local function setFieldUndo(data)
  local pathnode = data.pathnode
  if pathnode then
    pathnode[data.field] = data.old
  end
end

local function setFieldRedo(data)
  local pathnode = data.pathnode
  if pathnode then
    pathnode[data.field] = data.new
  end
end

local function setTransformUndo(data)
  local pathnode = data.pathnode
  if pathnode then
    pathnode.pos = data.old.pos
  end
end

local function setTransformRedo(data)
  local pathnode = data.pathnode
  if pathnode then
    pathnode.pos = data.new.pos
  end
end

local function markPathAsDirty(path)
  if editor_crawlEditor and editor_crawlEditor.markAsDirty then
    local allPaths = editor_crawlEditor.getAllPaths()
    for i, p in ipairs(allPaths) do
      if p == path then
        editor_crawlEditor.markAsDirty("path", i)
        break
      end
    end
  end
end

function C:init(crawlEditorParam)
  self.crawlEditor = crawlEditorParam
  self.path = nil
  self.selectedPathnodeIndex = -1
  self.currentPathnode = nil
  self._prevGizmoPos = vec3(0, 0, 0)
  self._prevPathnodePos = {}
  self.beginDragRotation = quat(1, 0, 0, 0)
  self.snapToTerrain = true
end

function C:setFields(path)
  if not path then return end
  self.name = im.ArrayChar(256, path.name or "")
  self.fileName = im.ArrayChar(256, path._fileName or "")
  self.description = im.ArrayChar(1024, path.description or "")
end

function C:setPath(pathParam)
  self.path = pathParam
end

function C:selectPathnode(index)
  self.selectedPathnodeIndex = index
  if index and index > 0 and self.path and self.path.nodes and self.path.nodes[index] then
    self.currentPathnode = self.path.nodes[index]
  else
    self.currentPathnode = nil
  end
end

function C:getSelectedPathnodeIndex()
  return self.selectedPathnodeIndex
end

function C:setSelectedPathnodeIndex(index)
  self:selectPathnode(index)
end

function C:drawPathsList(allPaths, selection)

  if im.Button("Add Path") then
    local newPath = self:getNewPath()
    table.insert(allPaths, newPath)
    selection.index = #allPaths
  end

  for i, path in ipairs(allPaths) do
    local isSelected = (i == selection.index)
    local displayName = path.name or "Unnamed Path"
    local pathnodeCount = path.nodes and #path.nodes or 0
    displayName = displayName .. " (" .. pathnodeCount .. " nodes)"

    if im.Selectable1(displayName, isSelected) then
      if selection.index == i then
        selection.index = -1
      end
      selection.index = i
      selection.clicked = true
    end

    -- Right-click context menu
    if im.BeginPopupContextItem("path_context_" .. i) then
      if im.MenuItem1("Delete") then
        table.remove(allPaths, i)
        if selection.index >= i then
          selection.index = selection.index - 1
        end
      end
      im.EndPopup()
    end
  end

  if #allPaths == 0 then
    im.Text("No paths available")
  end
end

function C:drawPathDetail(path)
  if not path then return end

  if lastPath ~= path then
    self:setFields(path)
    lastPath = path
  end

  im.Text("Path Details")
  im.Separator()

  -- Name
  im.Text("Name")
  editEnded[0] = false
  editor.uiInputText("##PathName", self.name, nil, nil, nil, nil, editEnded)
  if editEnded[0] then
    path.name = ffi.string(self.name)
    markPathAsDirty(path)
  end

  -- File Name (rename functionality)
  im.Separator()
  im.Text("File Name")
  im.SameLine()
  if im.Button("Rename") then
    local newFileName = ffi.string(self.fileName)
    if newFileName ~= path._fileName and newFileName ~= "" then
      local oldFilePath = path._filePath
      local dir, _, ext = utilPath.splitWithoutExt(oldFilePath, true)
      local newFilePath = dir .. newFileName .. "." .. ext

      -- Use the rename function from the main editor
      if editor_crawlEditor and editor_crawlEditor.renameObjectFile then
        editor_crawlEditor.renameObjectFile(oldFilePath, newFilePath, "path")
      end
    end
  end

  editor.uiInputText("##FileName", self.fileName, nil, nil, nil, nil, nil)

  -- Description
  im.Text("Description")
  editEnded[0] = false
  editor.uiInputText("##PathDescription", self.description, nil, nil, nil, nil, editEnded)
  if editEnded[0] then
    path.description = ffi.string(self.description)
    markPathAsDirty(path)
  end

  im.Separator()

  -- Nodes
  im.Text("Nodes:")
  if not path.nodes then
    path.nodes = {}
  end

  if im.Button("Add Node") then
    self:getNewPathnode()
    markPathAsDirty(path)
  end

  im.Separator()
  local removeIdx = nil
  for i, pathnode in ipairs(path.nodes) do
    im.PushID1(i.."_pathnode")
    local isSelected = (i == self.selectedPathnodeIndex)
    local displayName = pathnode.name or ("Node " .. i)

    if im.Selectable1(displayName, isSelected) then
      self:selectPathnode(i)
    end

    if im.SmallButton("Delete##" .. i) then
      removeIdx = i
    end
    im.PopID()
  end
  if removeIdx then
    table.remove(path.nodes, removeIdx)
    markPathAsDirty(path)
  end

  -- Selected node details
  if self.currentPathnode then
    im.Separator()
    im.Text("Selected Node:")

    local pathnodeName = im.ArrayChar(256, self.currentPathnode.name or "")
    im.Text("Name")
    local nameEditEnded = im.BoolPtr(false)
    editor.uiInputText("##NodeName", pathnodeName, nil, nil, nil, nil, nameEditEnded)
    if nameEditEnded[0] then
      self.currentPathnode.name = ffi.string(pathnodeName)
      markPathAsDirty(path)
    end

    -- Position
    local pos = im.ArrayFloat(3)
    pos[0] = self.currentPathnode.pos.x
    pos[1] = self.currentPathnode.pos.y
    pos[2] = self.currentPathnode.pos.z

    local posEditEnded = im.BoolPtr(false)
    editor.uiInputFloat3("Position", pos, nil, nil, posEditEnded)
    if posEditEnded[0] then
      self.currentPathnode.pos = vec3(pos[0], pos[1], pos[2])
      markPathAsDirty(path)
    end

    -- Radius
    do
      local radiusPtr = im.FloatPtr(self.currentPathnode.radius or 6.0)
      local radiusEditEnded = im.BoolPtr(false)
      editor.uiInputFloat("Radius", radiusPtr, nil, nil, nil, nil, radiusEditEnded)
      if radiusEditEnded[0] then
        self.currentPathnode.radius = radiusPtr[0]
        markPathAsDirty(path)
      end
    end

    -- Flags (as JSON string for simplicity)
    self.currentPathnode.flags = self.currentPathnode.flags or {}
    local flagsStr = (json and json.encode and json.encode(self.currentPathnode.flags)) or "{}"
    local flagsBuf = im.ArrayChar(512, flagsStr)
    local flagsEditEnded = im.BoolPtr(false)
    editor.uiInputText("Flags (json)", flagsBuf, nil, nil, nil, nil, flagsEditEnded)
    if flagsEditEnded[0] then
      local ok, decoded = pcall(function(s)
        return (json and json.decode and json.decode(s)) or {}
      end, ffi.string(flagsBuf))
      if ok and type(decoded) == 'table' then
        self.currentPathnode.flags = decoded
        markPathAsDirty(path)
      end
    end
  end
end

function C:getNewPath()
  local path = {
    name = "New Path",
    description = "A new path",
    nodes = {}
  }
  return path
end

function C:getNewPathnode()
  local path = self.path
  if not path then
    path = self:getNewPath()
    self.path = path
  end
  local node = {
    name = "Node " .. tostring(#path.nodes + 1),
    pos = vec3(0, 0, 0),
    radius = 4.0,
    flags = {}
  }
  table.insert(path.nodes, node)
  return node
end

function C:findPathnode(mouseInfo, objects)
  local minNodeDist = 4294967295
  local closest = nil
  local clrF = ColorF(1, 1, 1, 0.75)
  local clrSelected = ColorF(0.91, 0.49, 0.24, 0.75)

  for idx, obj in pairs(objects) do
    local distNodeToCam = (obj.pos - mouseInfo.camPos):length()
    local nodeRayDistance = (obj.pos - mouseInfo.camPos):cross(mouseInfo.rayDir):length() / mouseInfo.rayDir:length()
    local sphereRadius = (mouseInfo.camPos - obj.pos):length() / 40

    local selected = false
    if self.selectedPathnodeIndex == idx then
      selected = true
    end

    if selected then
      debugDrawer:drawSphere(obj.pos, sphereRadius, clrSelected)
    else
      debugDrawer:drawSphere(obj.pos, sphereRadius, clrF)
    end

    if nodeRayDistance <= sphereRadius then
      if distNodeToCam < minNodeDist then
        minNodeDist = distNodeToCam
        closest = obj
      end
    end
  end
  return closest
end

function C:tryInsert(mouseInfo)
  if not self.path or not self.path.nodes or #self.path.nodes < 2 then
    return
  end

  local objs = {}
  for i, pn in ipairs(self.path.nodes) do
    local nextIdx = i == #self.path.nodes and 1 or i + 1
    table.insert(objs, {
      pos = (pn.pos + self.path.nodes[nextIdx].pos) / 2,
      radius = 3,
      orig = i
    })
  end

  local hit = self:findPathnode(mouseInfo, objs)
  if hit and mouseInfo.down then
    local newPathnode = self:getNewPathnode()
    newPathnode.pos = hit.pos

    -- Insert the new node after the original node
    local insertIndex = hit.orig + 1
    table.insert(self.path.nodes, insertIndex, newPathnode)

    -- Select the newly inserted node
    self:selectPathnode(insertIndex)

    markPathAsDirty(self.path)
  end
end

function C:input(mouseInfo)
  if not self.path then return end

  if editor.keyModifiers.shift then
    if not editor.isAxisGizmoHovered() and mouseInfo.down then
      local newPathnode = self:getNewPathnode()
      newPathnode.pos = mouseInfo._downPos
      self:selectPathnode(#self.path.nodes)
      markPathAsDirty(self.path)
    end
  elseif editor.keyModifiers.alt then
    self:tryInsert(mouseInfo)
  else
    local objects = {}
    for i, pathnode in ipairs(self.path.nodes) do
      table.insert(objects, {
        pos = pathnode.pos,
        index = i,
        radius = (mouseInfo.camPos - pathnode.pos):length() / 40
      })
    end

    local hit = self:findPathnode(mouseInfo, objects)
    if not editor.isAxisGizmoHovered() and mouseInfo.down then
      if editor.keyModifiers.ctrl then
        if hit then
          self:selectPathnode(hit.index)
        end
      else
        if hit then
          self:selectPathnode(hit.index)
        else
          self:selectPathnode(-1)
        end
      end
    end
  end
end

function C:updateTransform()
  if not self.path or not self.currentPathnode then return end

  local transform = QuatF(0, 0, 0, 0):getMatrix()
  transform:setPosition(self.currentPathnode.pos)
  editor.setAxisGizmoTransform(transform)
end

function C:beginDrag()
  if not self.currentPathnode then return end

  self._prevGizmoPos = vec3(editor.getAxisGizmoTransform():getColumn(3))
  self._prevPathnodePos = deepcopy(self.currentPathnode.pos)
end

function C:dragging()
  if not self.path or not self.currentPathnode then return end

  local posOffset = (vec3(editor.getAxisGizmoTransform():getColumn(3)) - self._prevGizmoPos) / 2

  if editor.getAxisGizmoMode() == editor.AxisGizmoMode_Translate then
    self.currentPathnode.pos = self.currentPathnode.pos + posOffset

    if self.snapToTerrain then
      local newPos, succ = self:dropToTerrain(self.currentPathnode.pos)
      self.currentPathnode.pos = newPos
      if not succ then
        self.currentPathnode.pos.z = self._prevPathnodePos.z
      end
    end
  end

  self._prevGizmoPos = vec3(editor.getAxisGizmoTransform():getColumn(3))
end

function C:dropToTerrain(pos)
  local p = vec3(pos)
  if core_terrain then
    p.z = (core_terrain.getTerrainHeight(p) or p.z)
    return p, true
  end
  return p, false
end

function C:endDragging()
  if not self.currentPathnode then return end

  if self.snapToTerrain then
    local newPos = self:dropToTerrain(self.currentPathnode.pos)
    self.currentPathnode.pos = newPos
  end

  local oldPos = self._prevPathnodePos
  local newPos = self.currentPathnode.pos

  editor.history:commitAction("Manipulate Pathnode",
    {pathnode = self.currentPathnode, old = {pos = oldPos}, new = {pos = newPos}},
    setTransformUndo, setTransformRedo)

  markPathAsDirty(self.path)
end

function C:draw(mouseInfo)
  if not self.path then return end
  if self.currentPathnode then
    editor.updateAxisGizmo(function()
      self:beginDrag()
    end, function()
      self:endDragging()
    end, function()
      self:dragging()
    end)
    editor.drawAxisGizmo()
  end

  self:input(mouseInfo)
  self:updateTransform()
end

function C:drawPathnodeSelectionIndicators(mouseInfo)
  if not self.path or not self.path.nodes then
    return
  end

  -- Safety check for mouseInfo
  if not mouseInfo or not mouseInfo.camPos then
    return
  end

  for i, pathnode in ipairs(self.path.nodes) do
    local isSelected = (i == self.selectedPathnodeIndex)
    local color = isSelected and ColorF(0.91, 0.49, 0.24, 0.75) or ColorF(1, 1, 1, 0.75)

    debugDrawer:drawSphere(pathnode.pos, pathnode.radius, color)

    if pathnode.name then
      debugDrawer:drawTextAdvanced(pathnode.pos, String(pathnode.name .. " (" .. i .. ")"), ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 192))
    end
  end

  -- Draw direction triangles between pathnodes
  for i = 1, #self.path.nodes - 1 do
    local fromNode = self.path.nodes[i]
    local toNode = self.path.nodes[i + 1]

    if fromNode and toNode then
      debugDrawer:drawSquarePrism(
        fromNode.pos,
        toNode.pos,
        Point2F(2, 4),
        Point2F(0, 0),
        ColorF(0, 1, 0, 0.4))
    end
  end
end

return function(...)
  local o = {}
  setmetatable(o, C)
  C.__index = C
  o:init(...)
  return o
end