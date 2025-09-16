-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local im = ui_imgui
local ffi = require('ffi')

-- ============================================================================
-- CONSTANTS AND CONFIGURATION
-- ============================================================================

local CONSTANTS = {
  WINDOW_NAME = "Drag Race Editor",
  WINDOW_SIZE = im.ImVec2(1800, 900),

  DEFAULT_FILE_DIR = "/gameplay/temp/",
  FILE_EXTENSION = ".dragData.json",

  DRAG_TYPES = {
    "headsUpRace", "bracketRace", "loopRace", "tuffTrucksRace",
    "dragPracticeRace", "streetRodRace", "streetDogfightRace"
  },

  RACE_PHASES = {"stage", "countdown", "race", "stop"},

  TREE_TYPES = {".400", ".500"},

  CONTEXT_TYPES = {"freeroam", "activity"},

  DEFAULT_TRANSFORM = {
    pos = vec3(1, 0, 0),
    rot = quat(1, 0, 0, 0),
    scl = vec3(3, 3, 3)
  },

  DEFAULT_WAYPOINT = {
    speed = 5,
    mode = "limit"
  },

  COLORS = {
    WHITE = ColorF(1, 1, 1, 1),
    BLACK = ColorI(0, 0, 0, 192),
    RED = ColorF(1, 0, 0, 0.8),
    GREEN = ColorF(0, 1, 0, 0.8),
    BLUE = ColorF(0, 0, 1, 0.8),
    YELLOW = ColorF(1, 1, 0, 0.8),
    SUCCESS = im.ImVec4(0.0, 1.0, 0.0, 1.0),
    WARNING = im.ImVec4(1.0, 1.0, 0.0, 1.0),
    ERROR = im.ImVec4(1.0, 0.0, 0.0, 1.0)
  },

  UI = {
    INPUT_WIDTH = 120,
    BUTTON_HEIGHT = 20,
    SPACING = 5
  }
}

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local State = {
  dragRaceData = nil,
  currentFileDir = CONSTANTS.DEFAULT_FILE_DIR,
  currentFileName = nil,

  selectedLaneIndex = -1,
  mouseInfo = nil,
  hasUnsavedChanges = false,

  transforms = {},
  endCameraTransform = nil,

  usingPrefabs = im.BoolPtr(false),
  hasEndCamera = im.BoolPtr(false),

  search = require('/lua/ge/extensions/editor/util/searchUtil')(),

  undoStack = {},
  redoStack = {},
  maxUndoSteps = 20,

  lastError = nil,
  errorTimeout = 0
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function logError(message)
  State.lastError = message
  State.errorTimeout = 3
  log('E', 'DragRaceEditor', message)
end

local function showError()
  if State.lastError and State.errorTimeout > 0 then
    im.TextColored(CONSTANTS.COLORS.ERROR, "Error: " .. State.lastError)
    State.errorTimeout = State.errorTimeout - im.GetIO().DeltaTime
    if State.errorTimeout <= 0 then
      State.lastError = nil
    end
  end
end

local function markUnsavedChanges()
  State.hasUnsavedChanges = true
end

local function clearUnsavedChanges()
  State.hasUnsavedChanges = false
end

local function saveToUndoStack()
  if #State.undoStack >= State.maxUndoSteps then
    table.remove(State.undoStack, 1)
  end
  table.insert(State.undoStack, deepcopy(State.dragRaceData))
  State.redoStack = {}
end

local function undo()
  if #State.undoStack > 0 then
    table.insert(State.redoStack, State.dragRaceData)
    State.dragRaceData = table.remove(State.undoStack)
    markUnsavedChanges()
  end
end

local function redo()
  if #State.redoStack > 0 then
    table.insert(State.undoStack, State.dragRaceData)
    State.dragRaceData = table.remove(State.redoStack)
    markUnsavedChanges()
  end
end

local function validateDragRaceData(data)
  if not data then return false, "No data provided" end
  if not data.strip or not data.strip.lanes then
    return false, "Invalid strip data"
  end
  if not data.dragType or data.dragType == "" then
    return false, "Drag type not selected"
  end
  return true
end

local function createNewLane(laneIndex)
  return {
    shortName = "Lane " .. laneIndex,
    longName = "Lane " .. laneIndex,
    laneOrder = laneIndex,
    color = "blue",
    waypoints = {
      spawn = {
        name = "drag_" .. laneIndex .. "_spawn",
        transform = deepcopy(CONSTANTS.DEFAULT_TRANSFORM),
        waypoint = deepcopy(CONSTANTS.DEFAULT_WAYPOINT)
      },
      stage = {
        name = "drag_" .. laneIndex .. "_stage",
        transform = deepcopy(CONSTANTS.DEFAULT_TRANSFORM),
        waypoint = deepcopy(CONSTANTS.DEFAULT_WAYPOINT)
      },
      endLine = {
        name = "drag_" .. laneIndex .. "_endLine",
        transform = deepcopy(CONSTANTS.DEFAULT_TRANSFORM),
        waypoint = deepcopy(CONSTANTS.DEFAULT_WAYPOINT)
      }
    },
    boundary = {
      transform = deepcopy(CONSTANTS.DEFAULT_TRANSFORM)
    }
  }
end

local function createNewDragRaceData()
  return {
    strip = {
      lanes = {}
    },
    dragType = "",
    context = "",
    stripInfo = {
      stripName = ""
    },
    canBeTeleported = false,
    canBeReseted = false,
    phases = {},
    prefabs = {
      christmasTree = {
        isUsed = false,
        treeType = ".400"
      },
      displaySign = {
        isUsed = false,
      },
      paths = {
        isUsed = false,
      },
      decorations = {
        isUsed = false,
      },
    },
  }
end

local function reorderLanes(t, old, new)
  local value = t[old]
  if new < old then
     table.move(t, new, old - 1, new + 1)
  else
     table.move(t, old + 1, new, old)
  end
  t[new] = value
end

-- ============================================================================
-- TRANSFORM MANAGEMENT
-- ============================================================================

local function setupTransform(label, transform, allowTranslate, allowRotate, allowScale)
  local transformUtil = require('/lua/ge/extensions/editor/util/transformUtil')(label, label)
  transformUtil.allowTranslate = allowTranslate or true
  transformUtil.allowRotate = allowRotate or true
  transformUtil.allowScale = allowScale or true
  transformUtil:set(transform.pos, transform.rot, transform.scl)
  return transformUtil
end

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

local function addLane()
  saveToUndoStack()
  local newLane = createNewLane(#State.dragRaceData.strip.lanes + 1)
  table.insert(State.dragRaceData.strip.lanes, newLane)
  M.selectLane(#State.dragRaceData.strip.lanes)
  markUnsavedChanges()
end

local function removeSelectedLane()
  if State.selectedLaneIndex > 0 and State.selectedLaneIndex <= #State.dragRaceData.strip.lanes then
    saveToUndoStack()
    table.remove(State.dragRaceData.strip.lanes, State.selectedLaneIndex)
    State.selectedLaneIndex = State.selectedLaneIndex - 1
    if State.selectedLaneIndex == 0 and #State.dragRaceData.strip.lanes > 0 then
      State.selectedLaneIndex = 1
    end
    if #State.dragRaceData.strip.lanes <= 0 then
      State.selectedLaneIndex = -1
    end
    markUnsavedChanges()
  end
end

local function duplicateSelectedLane()
  if State.selectedLaneIndex > 0 and State.selectedLaneIndex <= #State.dragRaceData.strip.lanes then
    saveToUndoStack()
    local originalLane = State.dragRaceData.strip.lanes[State.selectedLaneIndex]
    local newLane = deepcopy(originalLane)
    newLane.shortName = originalLane.shortName .. " (Copy)"
    newLane.longName = originalLane.longName .. " (Copy)"
    newLane.laneOrder = #State.dragRaceData.strip.lanes + 1
    table.insert(State.dragRaceData.strip.lanes, newLane)
    M.selectLane(#State.dragRaceData.strip.lanes)
    markUnsavedChanges()
  end
end

local function selectLane(index)
  State.selectedLaneIndex = index
  local lane = State.dragRaceData.strip.lanes[State.selectedLaneIndex]

  if not lane then return end

  State.transforms.spawn = setupTransform("Player Spawn " .. index, lane.waypoints.spawn.transform)
  State.transforms.stage = setupTransform("Stage " .. index, lane.waypoints.stage.transform)
  State.transforms.endLine = setupTransform("End Line " .. index, lane.waypoints.endLine.transform)
  State.transforms.boundary = setupTransform("Boundary " .. index, lane.boundary.transform)

  -- Set up transforms for each waypoint type
  for waypointType, waypoint in pairs(lane.waypoints) do
    State.transforms[waypointType] = setupTransform(waypointType:sub(1, 1):upper() .. waypointType:sub(2) .. " " .. index, waypoint.transform)
  end
end
M.selectLane = selectLane

local function saveDragRaceData(savePath)
  local valid, error = validateDragRaceData(State.dragRaceData)
  if not valid then
    logError("Cannot save: " .. error)
    return false
  end

  local cleanData = deepcopy(State.dragRaceData)
  jsonWriteFile(savePath, cleanData, true)
  local dir, filename, ext = path.split(savePath)
  State.currentFileDir = dir
  State.currentFileName = filename
  clearUnsavedChanges()
  return true
end

local function loadDragRaceData(filename)
  if not filename then
    return false
  end

  local json = jsonReadFile(filename)
  if not json then
    logError('Unable to find drag data file: ' .. tostring(filename))
    return false
  end

  local dir, filename, ext = path.split(filename)
  State.currentFileDir = dir
  State.currentFileName = filename
  State.dragRaceData = json

  for _, lane in ipairs(State.dragRaceData.strip.lanes) do
    lane.boundary.transform.pos = vec3(lane.boundary.transform.pos) or vec3()
    lane.boundary.transform.rot = quat(lane.boundary.transform.rot) or quat()
    lane.boundary.transform.scl = vec3(lane.boundary.transform.scl) or vec3()

    for _, waypoint in pairs(lane.waypoints) do
      waypoint.transform.pos = vec3(waypoint.transform.pos) or vec3()
      waypoint.transform.rot = quat(waypoint.transform.rot) or quat()
      waypoint.transform.scl = vec3(waypoint.transform.scl) or vec3()
    end
  end

  if State.dragRaceData.strip.endCamera then
    State.hasEndCamera = im.BoolPtr(true)
  end

  for _, value in pairs(State.dragRaceData.prefabs) do
    if value.isUsed then
      State.usingPrefabs = im.BoolPtr(true)
      break
    end
  end

  M.selectLane(1)
  clearUnsavedChanges()
  return true
end

local function updateMouseInfo()
  if not State.mouseInfo then State.mouseInfo = {} end
  if core_forest.getForestObject() then core_forest.getForestObject():disableCollision() end
  State.mouseInfo.camPos = core_camera.getPosition()
  State.mouseInfo.ray = getCameraMouseRay()
  State.mouseInfo.rayDir = vec3(State.mouseInfo.ray.dir)
  State.mouseInfo.rayCast = cameraMouseRayCast()
  State.mouseInfo.valid = State.mouseInfo.rayCast and true or false

  if core_forest.getForestObject() then core_forest.getForestObject():enableCollision() end
  if not State.mouseInfo.valid then
    State.mouseInfo.down = false
    State.mouseInfo.hold = false
    State.mouseInfo.up   = false
    State.mouseInfo.closestNodeHovered = nil
  else
    State.mouseInfo.down =  im.IsMouseClicked(0) and not im.GetIO().WantCaptureMouse
    State.mouseInfo.hold = im.IsMouseDown(0) and not im.GetIO().WantCaptureMouse
    State.mouseInfo.up =  im.IsMouseReleased(0) and not im.GetIO().WantCaptureMouse
    if State.mouseInfo.down then
      State.mouseInfo.hold = false
      State.mouseInfo._downPos = vec3(State.mouseInfo.rayCast.pos)
      State.mouseInfo._downNormal = vec3(State.mouseInfo.rayCast.normal)
    end
    if State.mouseInfo.hold then
      State.mouseInfo._holdPos = vec3(State.mouseInfo.rayCast.pos)
      State.mouseInfo._holdNormal = vec3(State.mouseInfo.rayCast.normal)
    end
    if State.mouseInfo.up then
      State.mouseInfo._upPos = vec3(State.mouseInfo.rayCast.pos)
      State.mouseInfo._upNormal = vec3(State.mouseInfo.rayCast.normal)
    end
  end
end

-- ============================================================================
-- UI COMPONENTS
-- ============================================================================

local function drawFileMenu()
  if im.BeginMenu("File") then
    if im.MenuItem1("New") then
      saveToUndoStack()
      State.dragRaceData = createNewDragRaceData()
      State.currentFileName = nil
      clearUnsavedChanges()
    end

    if im.MenuItem1("Load...") then
      editor_fileDialog.openFile(function(data)
        loadDragRaceData(data.filepath)
      end, {{"Drag Data Files", CONSTANTS.FILE_EXTENSION}}, false, State.currentFileDir)
    end

    local canSave = State.currentFileDir and State.currentFileName and State.dragRaceData
    if not canSave then im.BeginDisabled() end
    if im.MenuItem1("Save") then
      saveDragRaceData(State.currentFileDir .. State.currentFileName)
    end
    if not canSave then im.EndDisabled() end

    if im.MenuItem1("Save as...") then
      extensions.editor_fileDialog.saveFile(function(data)
        saveDragRaceData(data.filepath)
      end, {{"Drag Data Files", CONSTANTS.FILE_EXTENSION}}, false, State.currentFileDir)
    end

    im.Separator()

    if im.MenuItem1("Undo") then
      undo()
    end

    if im.MenuItem1("Redo") then
      redo()
    end

    im.EndMenu()
  end
end

local function drawEditMenu()
  if im.BeginMenu("Edit") then
    if im.MenuItem1("Add Lane") then
      addLane()
    end

    if im.MenuItem1("Remove Selected Lane") then
      removeSelectedLane()
    end

    im.Separator()

    if im.MenuItem1("Clear All") then
      saveToUndoStack()
      State.dragRaceData = createNewDragRaceData()
      State.selectedLaneIndex = -1
      markUnsavedChanges()
    end

    im.EndMenu()
  end
end

local function drawViewMenu()
  if im.BeginMenu("View") then
    if im.MenuItem1("Show Transforms") then
    end

    if im.MenuItem1("Show Waypoints") then
    end

    im.EndMenu()
  end
end

local function drawHelpMenu()
  if im.BeginMenu("Help") then
    if im.MenuItem1("Documentation") then
    end

    if im.MenuItem1("About") then
    end

    im.EndMenu()
  end
end

local function drawMenuBar()
  if im.BeginMenuBar() then
    drawFileMenu()
    drawEditMenu()
    drawViewMenu()
    drawHelpMenu()
    im.EndMenuBar()
  end
end

local function drawBasicInfo()
  im.BeginChild1("basicInfo", im.ImVec2(0, 100), true)
  im.Text("Basic Information")
  im.Separator()

  im.Text("Drag Name: ")
  im.SameLine()
  local dragName = im.ArrayChar(256, State.dragRaceData.stripInfo.stripName or "")
  if im.InputText("##dragName", dragName, 256) then
    State.dragRaceData.stripInfo.stripName = ffi.string(dragName)
    markUnsavedChanges()
  end

  im.Text("Drag Type: ")
  im.SameLine()
  im.PushItemWidth(CONSTANTS.UI.INPUT_WIDTH)
  local dType = State.search:beginSearchableSimpleCombo(im, "dragTypes",
    State.dragRaceData.dragType ~= "" and State.dragRaceData.dragType or "Select Drag Type",
    CONSTANTS.DRAG_TYPES)
  if dType then
    State.dragRaceData.dragType = dType
    markUnsavedChanges()
  end
  im.PopItemWidth()

  im.Text("Context: ")
  im.SameLine()
  im.PushItemWidth(CONSTANTS.UI.INPUT_WIDTH)
  local context = State.search:beginSearchableSimpleCombo(im, "dragContext",
    State.dragRaceData.context ~= "" and State.dragRaceData.context or "Select Context",
    CONSTANTS.CONTEXT_TYPES)
  if context then
    State.dragRaceData.context = context
    markUnsavedChanges()
  end
  im.PopItemWidth()

  im.EndChild()
end

local function drawPhasesSection()
  im.BeginChild1("phases", im.ImVec2(0, 150), true)
  im.Text("Race Phases")
  im.Separator()

  im.PushItemWidth(CONSTANTS.UI.INPUT_WIDTH)
  local phase = State.search:beginSearchableSimpleCombo(im, "phase", "Select Phase", CONSTANTS.RACE_PHASES)
  if phase then
    table.insert(State.dragRaceData.phases, {
      name = phase,
      dependency = true,
      startedOffset = 0,
    })
    markUnsavedChanges()
  end
  im.PopItemWidth()

  for i, p in ipairs(State.dragRaceData.phases) do
    im.Text(i .. ". " .. p.name)
    im.SameLine()
    if im.Button("Remove##phase" .. i) then
      table.remove(State.dragRaceData.phases, i)
      markUnsavedChanges()
    end

    if i > 1 then
      im.SameLine()
      if im.Button("↑##up" .. i) then
        reorderLanes(State.dragRaceData.phases, i, i - 1)
        markUnsavedChanges()
      end
    end

    if i < #State.dragRaceData.phases then
      im.SameLine()
      if im.Button("↓##down" .. i) then
        reorderLanes(State.dragRaceData.phases, i, i + 1)
        markUnsavedChanges()
      end
    end

    im.SameLine()
    local dependency = im.BoolPtr(p.dependency)
    if im.Checkbox("Dependencies##" .. i, dependency) then
      p.dependency = dependency[0]
      markUnsavedChanges()
    end
  end

  im.EndChild()
end

local function drawPrefabsSection()
  im.BeginChild1("prefabs", im.ImVec2(0, 200), true)
  im.Text("Prefabs")
  im.Separator()

  local function drawPrefabHelper(label, prefabType)
    im.Text(label)
    im.SameLine()
    local boolptr = im.BoolPtr(State.dragRaceData.prefabs[prefabType].isUsed or false)
    if im.Checkbox("##isUsed_" .. label, boolptr) then
      State.dragRaceData.prefabs[prefabType].isUsed = boolptr[0]
      markUnsavedChanges()
    end

    if im.IsItemHovered() then
      im.tooltip("Enable to use prefab for this component")
    end

    im.SameLine()
    if im.Button("Load...##" .. label) then
      editor_fileDialog.openFile(function(data)
        State.dragRaceData.prefabs[prefabType].path = data.filepath
        markUnsavedChanges()
      end, {{"Prefab Files", ".prefab.json"}}, false)
    end

    if State.dragRaceData.prefabs[prefabType].path then
      im.SameLine()
      im.TextColored(CONSTANTS.COLORS.SUCCESS, "Loaded!")
      im.SameLine()
      if im.Button("Clear##" .. label) then
        State.dragRaceData.prefabs[prefabType].path = nil
        markUnsavedChanges()
      end
    elseif State.dragRaceData.prefabs[prefabType].isUsed then
      im.SameLine()
      im.TextColored(CONSTANTS.COLORS.WARNING, "No prefab loaded")
    end
  end

  drawPrefabHelper("Christmas Tree: ", "christmasTree")

  if State.dragRaceData.prefabs.christmasTree.isUsed then
    im.PushItemWidth(80)
    im.Text("Tree Type: ")
    im.SameLine()
    local tType = State.search:beginSearchableSimpleCombo(im, "treeType",
      State.dragRaceData.prefabs.christmasTree.treeType, CONSTANTS.TREE_TYPES)
    if tType then
      State.dragRaceData.prefabs.christmasTree.treeType = tType
      markUnsavedChanges()
    end
    im.PopItemWidth()
  end

  drawPrefabHelper("Display Sign: ", "displaySign")
  drawPrefabHelper("AI Path: ", "paths")
  drawPrefabHelper("Decoration: ", "decorations")

  im.EndChild()
end

local function drawLanesSection()
  im.BeginChild1("lanes", im.ImVec2(0, 300), true)
  im.Text("Drag Lanes")
  im.Separator()

  if im.Button("Add Lane") then
    addLane()
  end

  if State.selectedLaneIndex > 0 then
    im.SameLine()
    if im.Button("Remove Lane") then
      removeSelectedLane()
    end

    im.SameLine()
    if im.Button("Duplicate Lane") then
      duplicateSelectedLane()
    end
  end

  im.NewLine()

  for i, lane in ipairs(State.dragRaceData.strip.lanes) do
    local isSelected = i == State.selectedLaneIndex
    local label = string.format("Lane %d: %s", i, lane.shortName or "Unnamed")

    if im.Selectable1(label, isSelected) then
      M.selectLane(i)
    end

    if im.IsItemHovered() then
      im.tooltip(string.format("Long Name: %s\nColor: %s", lane.longName or "N/A", lane.color or "N/A"))
    end
  end

  im.EndChild()
end

local function drawLaneDetails()
  if State.selectedLaneIndex <= 0 or not State.dragRaceData.strip.lanes[State.selectedLaneIndex] then
    im.Text("Select a lane to edit its details")
    return
  end

  local lane = State.dragRaceData.strip.lanes[State.selectedLaneIndex]

  im.BeginChild1("laneDetails", im.ImVec2(0, 0), true)
  im.Text("Lane " .. State.selectedLaneIndex .. " Details")
  im.Separator()

  im.Text("Short Name: ")
  local shortName = im.ArrayChar(256, lane.shortName or "")
  if im.InputText("##shortName", shortName, 256) then
    lane.shortName = ffi.string(shortName)
    markUnsavedChanges()
  end

  im.Text("Long Name: ")
  local longName = im.ArrayChar(256, lane.longName or "")
  if im.InputText("##longName", longName, 256) then
    lane.longName = ffi.string(longName)
    markUnsavedChanges()
  end

  im.Text("Color: ")
  im.SameLine()
  local color = im.ArrayChar(256, lane.color or "")
  if im.InputText("##color", color, 256) then
    lane.color = ffi.string(color)
    markUnsavedChanges()
  end

  im.NewLine()

  im.Text("Waypoints")
  im.Separator()

      for waypointType, waypoint in pairs(lane.waypoints) do
    if im.CollapsingHeader1(waypointType:sub(1, 1):upper() .. waypointType:sub(2), 0) then
      im.Text("Name: ")
      local wpName = im.ArrayChar(256, waypoint.name or "")
      if im.InputText("##" .. waypointType .. "Name", wpName, 256) then
        waypoint.name = ffi.string(wpName)
        markUnsavedChanges()
      end

      if waypoint.waypoint then
        local speed = im.FloatPtr(waypoint.waypoint.speed or 0)
        if im.InputFloat("Speed##" .. waypointType, speed) then
          waypoint.waypoint.speed = speed[0]
          markUnsavedChanges()
        end

        im.PushItemWidth(100)
        local mode = State.search:beginSearchableSimpleCombo(im, "Mode##" .. waypointType,
          waypoint.waypoint.mode or "limit", {"set", "off", "limit"})
        if mode then
          waypoint.waypoint.mode = mode
          markUnsavedChanges()
        end
        im.PopItemWidth()
      end

      im.NewLine()
      im.Text("Transform:")
      if State.transforms[waypointType] and State.transforms[waypointType]:update(State.mouseInfo) then
        waypoint.transform.pos = State.transforms[waypointType].allowTranslate and State.transforms[waypointType].pos or waypoint.transform.pos
        waypoint.transform.rot = State.transforms[waypointType].allowRotate and State.transforms[waypointType].rot or waypoint.transform.rot
        waypoint.transform.scl = State.transforms[waypointType].allowScale and State.transforms[waypointType].scl or waypoint.transform.scl
        markUnsavedChanges()
      end
    end
  end

  if im.CollapsingHeader1("Boundary", 0) then
    im.Text("Boundary settings for lane " .. State.selectedLaneIndex)
    im.NewLine()
    im.Text("Transform:")
    if State.transforms.boundary and State.transforms.boundary:update(State.mouseInfo) then
      lane.boundary.transform.pos = State.transforms.boundary.allowTranslate and State.transforms.boundary.pos or lane.boundary.transform.pos
      lane.boundary.transform.rot = State.transforms.boundary.allowRotate and State.transforms.boundary.rot or lane.boundary.transform.rot
      lane.boundary.transform.scl = State.transforms.boundary.allowScale and State.transforms.boundary.scl or lane.boundary.transform.scl
      markUnsavedChanges()
    end
  end

  im.EndChild()
end

local function drawTransformsPreview()
  if State.selectedLaneIndex > 0 and State.dragRaceData.strip.lanes[State.selectedLaneIndex] then
    local lane = State.dragRaceData.strip.lanes[State.selectedLaneIndex]
    local i = State.selectedLaneIndex

    if lane.waypoints.spawn then
      debugDrawer:drawTextAdvanced(lane.waypoints.spawn.transform.pos,
        String(string.format("Spawn %d", i)), CONSTANTS.COLORS.WHITE, true, false, CONSTANTS.COLORS.BLACK)
      debugDrawer:drawSphere(lane.waypoints.spawn.transform.pos, lane.waypoints.spawn.transform.scl.x, ColorF(1,1,1,0.2))
    end

    if lane.waypoints.endLine then
      debugDrawer:drawTextAdvanced(lane.waypoints.endLine.transform.pos,
        String(string.format("EndLine %d", i)), CONSTANTS.COLORS.WHITE, true, false, CONSTANTS.COLORS.BLACK)
      debugDrawer:drawSphere(lane.waypoints.endLine.transform.pos, lane.waypoints.endLine.transform.scl.x, ColorF(1,1,1,0.2))
    end

    if lane.waypoints.stage then
      debugDrawer:drawTextAdvanced(lane.waypoints.stage.transform.pos,
        String(string.format("Stage %d", i)), CONSTANTS.COLORS.WHITE, true, false, CONSTANTS.COLORS.BLACK)
      debugDrawer:drawSphere(lane.waypoints.stage.transform.pos, lane.waypoints.stage.transform.scl.x, ColorF(1,1,1,0.2))
    end

    if lane.boundary then
      debugDrawer:drawTextAdvanced(lane.boundary.transform.pos,
        String(string.format("Boundary %d", i)), CONSTANTS.COLORS.WHITE, true, false, CONSTANTS.COLORS.BLACK)
      local x, y, z = lane.boundary.transform.rot * vec3(lane.boundary.transform.scl.x,0,0), lane.boundary.transform.rot * vec3(0,lane.boundary.transform.scl.y,0), lane.boundary.transform.rot * vec3(0,0,lane.boundary.transform.scl.z)
      local scl = (x+y+z)/2
      M.drawAxisBox(((-scl*2) + lane.boundary.transform.pos),x*2,y*2,z*2,color(0,0,255,0.2*255))
    end
  end

  if State.dragRaceData.strip.endCamera and State.dragRaceData.strip.endCamera.transform then
    debugDrawer:drawTextAdvanced(State.dragRaceData.strip.endCamera.transform.pos,
      String("End Camera"), CONSTANTS.COLORS.WHITE, true, false, CONSTANTS.COLORS.BLACK)
  end
end

-- ============================================================================
-- INITIALIZATION AND MAIN LOOP
-- ============================================================================

local function onEditorInitialized()
  editor.registerWindow(CONSTANTS.WINDOW_NAME, CONSTANTS.WINDOW_SIZE)
  editor.addWindowMenuItem("Drag Race Editor", function() M.show() end, {groupMenuName="Gameplay"})

  if State.dragRaceData == nil then
    State.dragRaceData = createNewDragRaceData()
  end
end

local function onSerialize()
  return {
    selectedLaneIndex = State.selectedLaneIndex,
    currentFileDir = State.currentFileDir,
    currentFileName = State.currentFileName,
    dragRaceData = State.dragRaceData,
    hasUnsavedChanges = State.hasUnsavedChanges
  }
end

local function onDeserialized(data)
  State.currentFileDir = data.currentFileDir or State.currentFileDir
  State.currentFileName = data.currentFileName or State.currentFileName
  State.dragRaceData = data.dragRaceData or State.dragRaceData
  State.hasUnsavedChanges = data.hasUnsavedChanges or false
end

local function show()
  editor.clearObjectSelection()
  editor.showWindow(CONSTANTS.WINDOW_NAME)
end

local function onEditorGui()
  if editor.beginWindow(CONSTANTS.WINDOW_NAME, CONSTANTS.WINDOW_NAME, im.WindowFlags_MenuBar) then
    drawMenuBar()

    showError()

    im.Columns(3, 'mainLayout')

    drawBasicInfo()
    drawPhasesSection()
    drawPrefabsSection()

    im.NextColumn()

    drawLanesSection()

    im.NextColumn()

    drawLaneDetails()

    im.Columns(0)

    updateMouseInfo()

    drawTransformsPreview()

    editor.endWindow()
  end
end

-- ============================================================================
-- HELPER FUNCTIONS FOR EXTERNAL USE
-- ============================================================================

-- helper function
  M.drawAxisBox = function(corner, x, y, z, clr)
    -- draw all faces in a loop
    for _, face in ipairs({{x,y,z},{x,z,y},{y,z,x}}) do
      local a,b,c = face[1],face[2],face[3]
      -- spokes
      debugDrawer:drawLine((corner    ), (corner+c    ), ColorF(0,0,0,0.75))
      debugDrawer:drawLine((corner+a  ), (corner+c+a  ), ColorF(0,0,0,0.75))
      debugDrawer:drawLine((corner+b  ), (corner+c+b  ), ColorF(0,0,0,0.75))
      debugDrawer:drawLine((corner+a+b), (corner+c+a+b), ColorF(0,0,0,0.75))
      -- first side
      debugDrawer:drawTriSolid(
        vec3(corner    ),
        vec3(corner+a  ),
        vec3(corner+a+b),
        clr)
      debugDrawer:drawTriSolid(
        vec3(corner+b  ),
        vec3(corner    ),
        vec3(corner+a+b),
        clr)
      -- back of first side
      debugDrawer:drawTriSolid(
        vec3(corner+a  ),
        vec3(corner    ),
        vec3(corner+a+b),
        clr)
      debugDrawer:drawTriSolid(
        vec3(corner    ),
        vec3(corner+b  ),
        vec3(corner+a+b),
        clr)
      -- other side
      debugDrawer:drawTriSolid(
        vec3(c+corner    ),
        vec3(c+corner+a  ),
        vec3(c+corner+a+b),
        clr)
      debugDrawer:drawTriSolid(
        vec3(c+corner+b  ),
        vec3(c+corner    ),
        vec3(c+corner+a+b),
        clr)
      -- back of other side
      debugDrawer:drawTriSolid(
        vec3(c+corner+a  ),
        vec3(c+corner    ),
        vec3(c+corner+a+b),
        clr)
      debugDrawer:drawTriSolid(
        vec3(c+corner    ),
        vec3(c+corner+b  ),
        vec3(c+corner+a+b),
        clr)
    end
  end

-- ============================================================================
-- EXPORT FUNCTIONS
-- ============================================================================

M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.show = show
M.onEditorInitialized = onEditorInitialized
M.onEditorGui = onEditorGui

return M