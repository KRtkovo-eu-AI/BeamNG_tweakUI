-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local gameplay_crawl_saveSystem = require('/lua/ge/extensions/gameplay/crawl/saveSystem')

local M = {}
local im = ui_imgui
local ffi = require('ffi')

local toolWindowName = "Crawl Data Editor"
local pathEditModeName = "Edit Pathnodes"
local boundaryEditModeName = "Edit Boundaries"
local trailEditModeName = "Edit Trail"

local boundaries = require('/lua/ge/extensions/editor/crawlEditor/boundaries')(M)
local paths = require('/lua/ge/extensions/editor/crawlEditor/paths')(M)
local trails = require('/lua/ge/extensions/editor/crawlEditor/trails')()
local startingPositions = require('/lua/ge/extensions/editor/crawlEditor/startingPositions')()
local input = require('/lua/ge/extensions/editor/crawlEditor/input')

local currentFileDir = "settings/cloud/crawls/"
local currentFileName
local crawlData
local mouseInfo
local currentTab = "paths"

local allTrails = {}
local allPaths = {}
local allBoundaries = {}
local allStartingPositions = {}

local selectedTrailIndex = -1
local selectedPathIndex = -1
local selectedBoundaryIndex = -1
local selectedStartingPositionIndex = -1

local unsavedColor = im.ImVec4(1, 0.3, 0.1, 1.0)

local function updateReferences(oldFilePath, newFilePath, objectType)
  if not oldFilePath or not newFilePath or oldFilePath == newFilePath then
    return
  end

  for _, trail in ipairs(allTrails) do
    local updated = false

    if objectType == "path" and trail.pathId == oldFilePath then
      trail.pathId = newFilePath
      updated = true
    elseif objectType == "boundary" and trail.boundaryId == oldFilePath then
      trail.boundaryId = newFilePath
      updated = true
    elseif objectType == "startingPosition" and trail.startingPositionId == oldFilePath then
      trail.startingPositionId = newFilePath
      updated = true
    end

    if updated then
      gameplay_crawl_saveSystem.saveTrail(trail, trail._filePath)
    end
  end
end

local function renameObjectFile(oldFilePath, newFilePath, objectType)
  if not oldFilePath or not newFilePath or oldFilePath == newFilePath then
    return false
  end

  if FS:fileExists(newFilePath) then
    dump('[CRAWL_EDITOR] Cannot rename: target file already exists: ' .. newFilePath)
    return false
  end

  local success = FS:renameFile(oldFilePath, newFilePath)
  if not success then
    dump('[CRAWL_EDITOR] Failed to rename file from ' .. oldFilePath .. ' to ' .. newFilePath)
    return false
  end

  updateReferences(oldFilePath, newFilePath, objectType)

  local object = nil
  if objectType == "trail" then
    for _, trail in ipairs(allTrails) do
      if trail._filePath == oldFilePath then
        trail._filePath = newFilePath
        local _, fileName, _ = path.splitWithoutExt(newFilePath, true)
        trail._fileName = fileName
        object = trail
        break
      end
    end
  elseif objectType == "path" then
    for _, pathh in ipairs(allPaths) do
      if pathh._filePath == oldFilePath then
        pathh._filePath = newFilePath
        local _, fileName, _ = path.splitWithoutExt(newFilePath, true)
        pathh._fileName = fileName
        object = pathh
        break
      end
    end
  elseif objectType == "boundary" then
    for _, boundary in ipairs(allBoundaries) do
      if boundary._filePath == oldFilePath then
        boundary._filePath = newFilePath
        local _, fileName, _ = path.splitWithoutExt(newFilePath, true)
        boundary._fileName = fileName
        object = boundary
        break
      end
    end
  elseif objectType == "startingPosition" then
    for _, startingPosition in ipairs(allStartingPositions) do
      if startingPosition._filePath == oldFilePath then
        startingPosition._filePath = newFilePath
        local _, fileName, _ = path.splitWithoutExt(newFilePath, true)
        startingPosition._fileName = fileName
        object = startingPosition
        break
      end
    end
  end

  if object then
    if objectType == "trail" then
      gameplay_crawl_saveSystem.saveTrail(object, newFilePath)
    elseif objectType == "path" then
      gameplay_crawl_saveSystem.savePath(object, newFilePath)
    elseif objectType == "boundary" then
      gameplay_crawl_saveSystem.saveBoundary(object, newFilePath)
    elseif objectType == "startingPosition" then
      gameplay_crawl_saveSystem.saveStartingPosition(object, newFilePath)
    end
  end

  dump('[CRAWL_EDITOR] Successfully renamed ' .. objectType .. ' from ' .. oldFilePath .. ' to ' .. newFilePath)
  return true
end



local function getNewCrawlData()
  return {
    name = "New Crawl",
    description = "A new crawl location",
    icon = "rockCrawling01",
    trails = {},
    metadata = {
      version = "1.0",
      created = os.date(),
      description = "Crawl system data for this level"
    }
  }
end

local function loadAllObjects()
  local trailFiles = gameplay_crawl_saveSystem.getAllTrailFiles()
  local pathFiles = gameplay_crawl_saveSystem.getAllPathFiles()
  local boundaryFiles = gameplay_crawl_saveSystem.getAllBoundaryFiles()
  local startingPositionFiles = gameplay_crawl_saveSystem.getAllStartingPositionFiles()

  dump(string.format('[CRAWL_EDITOR] Found files - Trails: %d, Paths: %d, Boundaries: %d, Starting Positions: %d',
    #trailFiles, #pathFiles, #boundaryFiles, #startingPositionFiles))

  allTrails = {}
  allPaths = {}
  allBoundaries = {}
  allStartingPositions = {}

  for _, filePath in ipairs(trailFiles) do
    local trail = gameplay_crawl_saveSystem.getTrailById(filePath)
    if trail then
      table.insert(allTrails, trail)
    end
  end

  for _, filePath in ipairs(pathFiles) do
    local path = gameplay_crawl_saveSystem.getPathById(filePath)
    if path then
      table.insert(allPaths, path)
    end
  end

  for _, filePath in ipairs(boundaryFiles) do
    local boundary = gameplay_crawl_saveSystem.getBoundaryById(filePath)
    if boundary then
      table.insert(allBoundaries, boundary)
    end
  end

  for _, filePath in ipairs(startingPositionFiles) do
    local startingPosition = gameplay_crawl_saveSystem.getStartingPositionById(filePath)
    if startingPosition then
      table.insert(allStartingPositions, startingPosition)
    end
  end

  dump(string.format('[CRAWL_EDITOR] Loaded %d trails, %d paths, %d boundaries, %d starting positions', #allTrails, #allPaths, #allBoundaries, #allStartingPositions))
end

local function getSelectedTrail()
  if selectedTrailIndex > 0 and selectedTrailIndex <= #allTrails then
    return allTrails[selectedTrailIndex]
  end
  return nil
end

local function getSelectedPath()
  if selectedPathIndex > 0 and selectedPathIndex <= #allPaths then
    return allPaths[selectedPathIndex]
  end
  return nil
end

local function getSelectedBoundary()
  if selectedBoundaryIndex > 0 and selectedBoundaryIndex <= #allBoundaries then
    return allBoundaries[selectedBoundaryIndex]
  end
  return nil
end

local function getSelectedStartingPosition()
  if selectedStartingPositionIndex > 0 and selectedStartingPositionIndex <= #allStartingPositions then
    return allStartingPositions[selectedStartingPositionIndex]
  end
  return nil
end

local function markAsDirty(objectType, index)
  if objectType == "trail" and index > 0 and index <= #allTrails then
    allTrails[index]._dirty = true
    dump(string.format('[CRAWL_EDITOR] Marked trail %d (%s) as dirty', index, allTrails[index]._fileName or 'unnamed'))
  elseif objectType == "path" and index > 0 and index <= #allPaths then
    allPaths[index]._dirty = true
    dump(string.format('[CRAWL_EDITOR] Marked path %d (%s) as dirty', index, allPaths[index]._fileName or 'unnamed'))
  elseif objectType == "boundary" and index > 0 and index <= #allBoundaries then
    allBoundaries[index]._dirty = true
    dump(string.format('[CRAWL_EDITOR] Marked boundary %d (%s) as dirty', index, allBoundaries[index]._fileName or 'unnamed'))
  elseif objectType == "startingPosition" and index > 0 and index <= #allStartingPositions then
    allStartingPositions[index]._dirty = true
    dump(string.format('[CRAWL_EDITOR] Marked starting position %d (%s) as dirty', index, allStartingPositions[index]._fileName or 'unnamed'))
  else
    dump(string.format('[CRAWL_EDITOR] Failed to mark %s %d as dirty - invalid type or index', objectType or 'unknown', index or 'nil'))
  end
end

local function createAndSaveObject(type, filePath)
  local success = false
  local newObject = nil

  if not type or not filePath then
    log('E', 'crawl_editor', 'Invalid type or filePath provided to createAndSaveObject')
    return false
  end

  if type == "trail" then
    newObject = trails:getNewTrail()
    if newObject then
      success = gameplay_crawl_saveSystem.saveTrail(newObject, filePath)
    end
  elseif type == "path" then
    newObject = paths:getNewPath()
    if newObject then
      success = gameplay_crawl_saveSystem.savePath(newObject, filePath)
    end
  elseif type == "boundary" then
    newObject = boundaries:getNewBoundary()
    if newObject then
      success = gameplay_crawl_saveSystem.saveBoundary(newObject, filePath)
    end
  elseif type == "startingPosition" then
    newObject = startingPositions:getNewStartingPosition()
    if newObject then
      success = gameplay_crawl_saveSystem.saveStartingPosition(newObject, filePath)
    end
  else
    log('E', 'crawl_editor', string.format('Unknown object type: %s', type))
    return false
  end

  if success and newObject then
    loadAllObjects()

    if type == "trail" then
      for i, trail in ipairs(allTrails) do
        if trail._filePath == filePath then
          selectedTrailIndex = i
          currentTab = "trails"
          editor.selectEditMode(editor.editModes.trailEditMode)
          trails:setTrail(trail)
          break
        end
      end
    elseif type == "path" then
      for i, path in ipairs(allPaths) do
        if path._filePath == filePath then
          selectedPathIndex = i
          currentTab = "paths"
          editor.selectEditMode(editor.editModes.pathEditMode)
          paths:setPath(path)
          break
        end
      end
    elseif type == "boundary" then
      for i, boundary in ipairs(allBoundaries) do
        if boundary._filePath == filePath then
          selectedBoundaryIndex = i
          currentTab = "boundaries"
          editor.selectEditMode(editor.editModes.boundaryEditMode)
          boundaries:setBoundary(boundary)
          break
        end
      end
    elseif type == "startingPosition" then
      for i, startingPosition in ipairs(allStartingPositions) do
        if startingPosition._filePath == filePath then
          selectedStartingPositionIndex = i
          currentTab = "startingPositions"
          editor.selectEditMode(editor.editModes.startingPositionEditMode)
          startingPositions:setStartingPosition(startingPosition)
          break
        end
      end
    end

    log('I', 'crawl_editor', string.format('Successfully created and saved new %s to: %s', type, filePath))
  else
    log('E', 'crawl_editor', string.format('Failed to create and save new %s to: %s', type, filePath))
  end

  return success
end

local function showFileSelectionDialog(type)
  local fileSuffix = {}
  if type == "trail" then
    fileSuffix = {{"Trail Files", ".trail.json"}}
  elseif type == "path" then
    fileSuffix = {{"Path Files", ".path.json"}}
  elseif type == "boundary" then
    fileSuffix = {{"Boundary Files", ".boundary.json"}}
  elseif type == "startingPosition" then
    fileSuffix = {{"Starting Position Files", ".startingPosition.json"}}
  end

  local currentLevel = getCurrentLevelIdentifier()
  if not currentLevel then
    log('E', 'crawl_editor', 'No level currently loaded, cannot save file')
    return
  end

  local currentFileDir = "levels/" .. currentLevel .. "/crawls/"
  extensions.editor_fileDialog.saveFile(
    function(data)
      createAndSaveObject(type, data.filepath)
    end,
    fileSuffix,
    false,
    currentFileDir
  )
end

local function show()
  editor.clearObjectSelection()
  editor.showWindow(toolWindowName)
  currentFileDir = "levels/" .. getCurrentLevelIdentifier() .. "/crawls/"
end

local function onPathEditModeActivate()
  editor.clearObjectSelection()
  local selectedPath = getSelectedPath()
  if selectedPath then
    paths:setPath(selectedPath)
  end
end

local function onPathEditModeDeactivate()
  paths:setPath(nil)
  paths:selectPathnode(nil)
  editor.clearObjectSelection()
end

local function onPathEditModeUpdate()
  local selectedPath = getSelectedPath()
  if not selectedPath then
    return
  end
  input.updateMouseInfo()
  mouseInfo = input.getMouseInfo()
  paths:draw(mouseInfo)
end

local function drawPathnodesAlways()
  local selectedPath = getSelectedPath()
  if not selectedPath then
    return
  end

  paths:setPath(selectedPath)
  paths:drawPathnodeSelectionIndicators(mouseInfo)
end

local function onBoundaryEditModeActivate()
  editor.clearObjectSelection()
  local selectedBoundary = getSelectedBoundary()
  if selectedBoundary then
    boundaries:setBoundary(selectedBoundary)
  end
end

local function onBoundaryEditModeDeactivate()
  boundaries:setBoundary(nil)
  editor.clearObjectSelection()
end

local function onBoundaryEditModeUpdate()
  local selectedBoundary = getSelectedBoundary()
  if not selectedBoundary then
    return
  end
  input.updateMouseInfo()
  mouseInfo = input.getMouseInfo()
  boundaries:draw(mouseInfo)
end

local function onStartingPositionEditModeActivate()
  editor.clearObjectSelection()
  local selectedStartingPosition = getSelectedStartingPosition()
  if selectedStartingPosition then
    startingPositions:setStartingPosition(selectedStartingPosition)
  end
end

local function onStartingPositionEditModeDeactivate()
  startingPositions:setStartingPosition(nil)
  editor.clearObjectSelection()
end

local function onStartingPositionEditModeUpdate()
  local selectedStartingPosition = getSelectedStartingPosition()
  if not selectedStartingPosition then
    return
  end
  input.updateMouseInfo()
  mouseInfo = input.getMouseInfo()
  startingPositions:draw(mouseInfo)
end

local function onTrailEditModeUpdate()
  local selectedTrail = getSelectedTrail()
  if not selectedTrail then
    return
  end
  input.updateMouseInfo()
  mouseInfo = input.getMouseInfo()
  trails:draw(mouseInfo)
end

local function onTrailEditModeActivate()
  local selectedTrail = getSelectedTrail()
  if selectedTrail then
    trails:setTrail(selectedTrail)
  end
end

local function onTrailEditModeDeactivate()
  trails:clearSelection()
end

local function drawBoundariesAlways()
  local selectedBoundary = getSelectedBoundary()
  if not selectedBoundary then
    return
  end

  boundaries:setBoundary(selectedBoundary)
end

local function drawStartingPositionsAlways()
  local selectedStartingPosition = getSelectedStartingPosition()
  if not selectedStartingPosition then
    return
  end

  startingPositions:setStartingPosition(selectedStartingPosition)
  startingPositions:drawStartingPositionIndicators(mouseInfo)
end

local function updateCurrentTab()
  if selectedTrailIndex > 0 then
    currentTab = "trails"
  elseif selectedPathIndex > 0 then
    currentTab = "paths"
  elseif selectedBoundaryIndex > 0 then
    currentTab = "boundaries"
  elseif selectedStartingPositionIndex > 0 then
    currentTab = "startingPositions"
  else
    currentTab = "none"
  end
end

local function onEditorInitialized()
  editor.registerWindow(toolWindowName, im.ImVec2(1800,900))
  editor.addWindowMenuItem("Crawl Data Editor", function() show() end, {groupMenuName="Gameplay"})

  loadAllObjects()
  updateCurrentTab()

  if crawlData == nil then
    crawlData = getNewCrawlData()
  end

  trails:setCurrentTab("paths")

  editor.editModes.pathEditMode = {
    displayName = pathEditModeName,
    onUpdate = onPathEditModeUpdate,
    onActivate = onPathEditModeActivate,
    onDeactivate = onPathEditModeDeactivate,
    auxShortcuts = {},
    icon = editor.icons.tb_path,
    iconTooltip = "Pathnode Editor",
    hideObjectIcons = true
  }

  editor.editModes.pathEditMode.auxShortcuts[bit.bor(editor.AuxControl_LMB, editor.AuxControl_Shift)] = "Create new pathnode"

  editor.editModes.boundaryEditMode = {
    displayName = boundaryEditModeName,
    onUpdate = onBoundaryEditModeUpdate,
    onActivate = onBoundaryEditModeActivate,
    onDeactivate = onBoundaryEditModeDeactivate,
    auxShortcuts = {},
    icon = editor.icons.tb_zone,
    iconTooltip = "Boundary Editor",
    hideObjectIcons = true
  }

  editor.editModes.boundaryEditMode.auxShortcuts[bit.bor(editor.AuxControl_LMB, editor.AuxControl_Shift)] = "Add boundary vertex"
  editor.editModes.boundaryEditMode.auxShortcuts[bit.bor(editor.AuxControl_LMB, editor.AuxControl_Alt)] = "Insert vertex between existing"
  editor.editModes.boundaryEditMode.auxShortcuts[bit.bor(editor.AuxControl_LMB, editor.AuxControl_Ctrl)] = "Select multiple vertices"

  editor.editModes.startingPositionEditMode = {
    displayName = "Edit Starting Position",
    onUpdate = onStartingPositionEditModeUpdate,
    onActivate = onStartingPositionEditModeActivate,
    onDeactivate = onStartingPositionEditModeDeactivate,
    auxShortcuts = {},
    icon = editor.icons.tb_path,
    iconTooltip = "Starting Position Editor",
    hideObjectIcons = true
  }

  editor.editModes.startingPositionEditMode.auxShortcuts[bit.bor(editor.AuxControl_LMB)] = "Select starting position"

  editor.editModes.trailEditMode = {
    displayName = trailEditModeName,
    onUpdate = onTrailEditModeUpdate,
    onActivate = onTrailEditModeActivate,
    onDeactivate = onTrailEditModeDeactivate,
    auxShortcuts = {},
    icon = editor.icons.tb_path,
    iconTooltip = "Trail Editor",
    hideObjectIcons = true
  }

  editor.editModes.trailEditMode.auxShortcuts[bit.bor(editor.AuxControl_LMB)] = "Select trail position"
end

local function onSerialize()
  local ret = {
    currentFileDir = currentFileDir,
    currentFileName = currentFileName,
    crawlData = crawlData,
    currentTab = currentTab,
    selectedTrailIndex = selectedTrailIndex,
    selectedPathIndex = selectedPathIndex,
    selectedBoundaryIndex = selectedBoundaryIndex,
    selectedStartingPositionIndex = selectedStartingPositionIndex
  }
  return ret
end

local function onDeserialized(data)
  if data then
    currentFileDir = data.currentFileDir or currentFileDir
    currentFileName = data.currentFileName
    crawlData = data.crawlData or crawlData
    currentTab = data.currentTab or currentTab
    selectedTrailIndex = data.selectedTrailIndex or -1
    selectedPathIndex = data.selectedPathIndex or -1
    selectedBoundaryIndex = data.selectedBoundaryIndex or -1
    selectedStartingPositionIndex = data.selectedStartingPositionIndex or -1
  end
end

local function onEditorGui()
  if not crawlData then return end

  mouseInfo = input:getMouseInfo()

  drawPathnodesAlways()
  drawBoundariesAlways()
  drawStartingPositionsAlways()

  if editor.beginWindow(toolWindowName, toolWindowName, im.flags(im.WindowFlags_MenuBar)) then
    if im.BeginMenuBar() then
      if im.BeginMenu("File") then
        if im.MenuItem1("Save All") then
          local savedCount = 0

          for _, trail in ipairs(allTrails) do
            if gameplay_crawl_saveSystem.saveTrail(trail, trail._filePath) then
              savedCount = savedCount + 1
              trail._dirty = false
              log('I', 'crawl_editor', string.format('Marked trail (%s) as clean after Save All', trail._fileName or 'unnamed'))
            end
          end

          for _, path in ipairs(allPaths) do
            if gameplay_crawl_saveSystem.savePath(path, path._filePath) then
              savedCount = savedCount + 1
              path._dirty = false
              log('I', 'crawl_editor', string.format('Marked path (%s) as clean after Save All', path._fileName or 'unnamed'))
            end
          end

          for _, boundary in ipairs(allBoundaries) do
            if gameplay_crawl_saveSystem.saveBoundary(boundary, boundary._filePath) then
              savedCount = savedCount + 1
              boundary._dirty = false
              log('I', 'crawl_editor', string.format('Marked boundary (%s) as clean after Save All', boundary._fileName or 'unnamed'))
            end
          end

          for _, startingPosition in ipairs(allStartingPositions) do
            if gameplay_crawl_saveSystem.saveStartingPosition(startingPosition, startingPosition._filePath) then
              savedCount = savedCount + 1
              startingPosition._dirty = false
              log('I', 'crawl_editor', string.format('Marked starting position (%s) as clean after Save All', startingPosition._fileName or 'unnamed'))
            end
          end

          log('I', 'crawl_editor', 'Saved ' .. savedCount .. ' objects')
        end

        if im.MenuItem1("Reload All") then
          loadAllObjects()
          log('I', 'crawl_editor', 'Reloaded all objects')
        end

        im.Separator()

        if im.MenuItem1("Clear Cache") then
          gameplay_crawl_saveSystem.clearCache()
          log('I', 'crawl_editor', 'Cleared save system cache')
        end

        im.EndMenu()
      end

      if im.BeginMenu("View") then
        if im.MenuItem1("Refresh Lists") then
          loadAllObjects()
          log('I', 'crawl_editor', 'Refreshed object lists')
        end
        im.EndMenu()
      end

      im.EndMenuBar()
    end

    im.Text("Current tab: " .. currentTab)
    im.Separator()
    if im.BeginChild1("LeftPanel", im.ImVec2(im.GetWindowWidth() * 0.4, 0), true) then

      im.Separator()
      im.TextColored(im.ImVec4(0.8, 0.6, 0.2, 1.0), "Trails")
      im.SameLine()
      if im.Button("Add Trail") then
        showFileSelectionDialog("trail")
      end
      for idx, trail in ipairs(allTrails) do
        im.PushID1("trail_" .. idx)

        local displayName = trail._fileName
        if trail._dirty then
          displayName = "*** " .. displayName .. " ***"
          im.PushStyleColor2(im.Col_Text, unsavedColor)
          dump(string.format('[CRAWL_EDITOR] Displaying trail %d (%s) as dirty', idx, trail._fileName or 'unnamed'))
        end

        if im.Selectable1(displayName..'##'..trail._filePath, selectedTrailIndex == idx) then
          selectedTrailIndex = idx
          currentTab = "trails"
          editor.selectEditMode(editor.editModes.trailEditMode)
        end

        if trail._dirty then im.PopStyleColor() end
        im.PopID()
      end

      im.Separator()
      im.TextColored(im.ImVec4(0.8, 0.6, 0.2, 1.0), "Paths")
      im.SameLine()
      if im.Button("Add Path") then
        showFileSelectionDialog("path")
      end
      for idx, path in ipairs(allPaths) do
        im.PushID1("path_" .. idx)

        local displayName = path._fileName
        if path._dirty then
          displayName = "*** " .. displayName .. " ***"
          im.PushStyleColor2(im.Col_Text, unsavedColor)
        end

        if im.Selectable1(displayName..'##'..path._filePath, selectedPathIndex == idx) then
          selectedPathIndex = idx
          currentTab = "paths"
          editor.selectEditMode(editor.editModes.pathEditMode)
        end

        if path._dirty then im.PopStyleColor() end
        im.PopID()
      end

      im.Separator()
      im.TextColored(im.ImVec4(0.8, 0.6, 0.2, 1.0), "Boundaries")
      im.SameLine()
      if im.Button("Add Boundary") then
        showFileSelectionDialog("boundary")
      end
      for idx, boundary in ipairs(allBoundaries) do
        im.PushID1("boundary_" .. idx)

        local displayName = boundary._fileName
        if boundary._dirty then
          displayName = "*** " .. displayName .. " ***"
          im.PushStyleColor2(im.Col_Text, unsavedColor)
        end

        if im.Selectable1(displayName..'##'..boundary._filePath, selectedBoundaryIndex == idx) then
          selectedBoundaryIndex = idx
          currentTab = "boundaries"
          editor.selectEditMode(editor.editModes.boundaryEditMode)
        end

        if boundary._dirty then im.PopStyleColor() end
        im.PopID()
      end

      im.Separator()
      im.TextColored(im.ImVec4(0.8, 0.6, 0.2, 1.0), "Starting Positions")
      im.SameLine()
      if im.Button("Add Starting Position") then
        showFileSelectionDialog("startingPosition")
      end
      for idx, startingPosition in ipairs(allStartingPositions) do
        im.PushID1("starting_position_" .. idx)

        local displayName = startingPosition._fileName
        if startingPosition._dirty then
          displayName = "*** " .. displayName .. " ***"
          im.PushStyleColor2(im.Col_Text, im.ImVec4(1.0, 0.0, 0.0, 1.0))
        end

        if im.Selectable1(displayName..'##'..startingPosition._filePath, selectedStartingPositionIndex == idx) then
          selectedStartingPositionIndex = idx
          currentTab = "startingPositions"
          editor.selectEditMode(editor.editModes.startingPositionEditMode)
        end

        if startingPosition._dirty then im.PopStyleColor() end
        im.PopID()
      end

      im.EndChild()
    end

    im.SameLine()

    if im.BeginChild1("RightPanel", im.ImVec2(0, 0), true) then
      im.Text("Details")
      im.SameLine()
      if im.Button("Save") then
        if currentTab == "trails" and selectedTrailIndex > 0 then
          local selectedTrail = allTrails[selectedTrailIndex]
          if selectedTrail then
            if gameplay_crawl_saveSystem.saveTrail(selectedTrail, selectedTrail._filePath) then
              selectedTrail._dirty = false
              dump('[CRAWL_EDITOR] Marked trail ' .. selectedTrailIndex .. ' (' .. (selectedTrail._fileName or 'unnamed') .. ') as clean after save')
            end
          end
        end
        if currentTab == "paths" and selectedPathIndex > 0 then
          local selectedPath = allPaths[selectedPathIndex]
          if selectedPath then
            if gameplay_crawl_saveSystem.savePath(selectedPath, selectedPath._filePath) then
              selectedPath._dirty = false
              dump('[CRAWL_EDITOR] Marked path ' .. selectedPathIndex .. ' (' .. (selectedPath._fileName or 'unnamed') .. ') as clean after save')
            end
          end
        end
        if currentTab == "boundaries" and selectedBoundaryIndex > 0 then
          local selectedBoundary = allBoundaries[selectedBoundaryIndex]
          if selectedBoundary then
            if gameplay_crawl_saveSystem.saveBoundary(selectedBoundary, selectedBoundary._filePath) then
              selectedBoundary._dirty = false
              dump('[CRAWL_EDITOR] Marked boundary ' .. selectedBoundaryIndex .. ' (' .. (selectedBoundary._fileName or 'unnamed') .. ') as clean after save')
            end
          end
        end
        if currentTab == "startingPositions" and selectedStartingPositionIndex > 0 then
          local selectedStartingPosition = allStartingPositions[selectedStartingPositionIndex]
          if selectedStartingPosition then
            if gameplay_crawl_saveSystem.saveStartingPosition(selectedStartingPosition, selectedStartingPosition._filePath) then
              selectedStartingPosition._dirty = false
              dump('[CRAWL_EDITOR] Marked starting position ' .. selectedStartingPositionIndex .. ' (' .. (selectedStartingPosition._fileName or 'unnamed') .. ') as clean after save')
            end
          end
        end
      end

      if currentTab == "trails" and selectedTrailIndex > 0 then
        im.SameLine()
        im.PushStyleColor2(im.Col_Button, im.ImVec4(0.8, 0.2, 0.2, 1.0))
        im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.9, 0.3, 0.3, 1.0))
        im.PushStyleColor2(im.Col_ButtonActive, im.ImVec4(0.7, 0.1, 0.1, 1.0))
        if im.Button("Delete Trail") then
          local selectedTrail = allTrails[selectedTrailIndex]
          if selectedTrail then
            table.remove(allTrails, selectedTrailIndex)

            if selectedTrailIndex <= #allTrails then
            else
              selectedTrailIndex = #allTrails > 0 and 1 or 0
            end

            if #allTrails == 0 then
              selectedTrailIndex = 0
            end
          end
        end
        im.PopStyleColor()
        im.PopStyleColor()
        im.PopStyleColor()
      elseif currentTab == "paths" and selectedPathIndex > 0 then
        im.SameLine()
        im.PushStyleColor2(im.Col_Button, im.ImVec4(0.8, 0.2, 0.2, 1.0))
        im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.9, 0.3, 0.3, 1.0))
        im.PushStyleColor2(im.Col_ButtonActive, im.ImVec4(0.7, 0.1, 0.1, 1.0))
        if im.Button("Delete Path") then
          local selectedPath = allPaths[selectedPathIndex]
          if selectedPath then
            for _, trail in ipairs(allTrails) do
              if trail.pathId == selectedPath._filePath then
                trail.pathId = nil
                trail.pathReversed = false
                trail._dirty = true
              end
            end

            table.remove(allPaths, selectedPathIndex)

            if selectedPathIndex <= #allPaths then
            else
              if #allTrails > 0 then
                selectedPathIndex = 0
                selectedTrailIndex = 1
                currentTab = "trails"
              else
                selectedPathIndex = 0
              end
            end

            if #allPaths == 0 then
              selectedPathIndex = 0
              if #allTrails > 0 then
                selectedTrailIndex = 1
                currentTab = "trails"
              end
            end
          end
        end
        im.PopStyleColor()
        im.PopStyleColor()
        im.PopStyleColor()
      elseif currentTab == "boundaries" and selectedBoundaryIndex > 0 then
        im.SameLine()
        im.PushStyleColor2(im.Col_Button, im.ImVec4(0.8, 0.2, 0.2, 1.0))
        im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.9, 0.3, 0.3, 1.0))
        im.PushStyleColor2(im.Col_ButtonActive, im.ImVec4(0.7, 0.1, 0.1, 1.0))
        if im.Button("Delete Boundary") then
          local selectedBoundary = allBoundaries[selectedBoundaryIndex]
          if selectedBoundary then
            for _, trail in ipairs(allTrails) do
              if trail.boundaryId == selectedBoundary._filePath then
                trail.boundaryId = nil
                trail._dirty = true
              end
            end

            table.remove(allBoundaries, selectedBoundaryIndex)

            if selectedBoundaryIndex <= #allBoundaries then
            else
              if #allTrails > 0 then
                selectedBoundaryIndex = 0
                selectedTrailIndex = 1
                currentTab = "trails"
              else
                selectedBoundaryIndex = 0
              end
            end

            if #allBoundaries == 0 then
              selectedBoundaryIndex = 0
              if #allTrails > 0 then
                selectedTrailIndex = 1
                currentTab = "trails"
              end
            end
          end
        end
        im.PopStyleColor()
        im.PopStyleColor()
        im.PopStyleColor()
      elseif currentTab == "startingPositions" and selectedStartingPositionIndex > 0 then
        im.SameLine()
        im.PushStyleColor2(im.Col_Button, im.ImVec4(0.8, 0.2, 0.2, 1.0))
        im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.9, 0.3, 0.3, 1.0))
        im.PushStyleColor2(im.Col_ButtonActive, im.ImVec4(0.7, 0.1, 0.1, 1.0))
        if im.Button("Delete Starting Position") then
          local selectedStartingPosition = allStartingPositions[selectedStartingPositionIndex]
          if selectedStartingPosition then
            for _, trail in ipairs(allTrails) do
              if trail.startingPositionId == selectedStartingPosition._filePath then
                trail.startingPositionId = nil
                trail._dirty = true
              end
            end

            table.remove(allStartingPositions, selectedStartingPositionIndex)

            if selectedStartingPositionIndex <= #allStartingPositions then
            else
              if #allTrails > 0 then
                selectedStartingPositionIndex = 0
                selectedTrailIndex = 1
                currentTab = "trails"
              else
                selectedStartingPositionIndex = 0
              end
            end

            if #allStartingPositions == 0 then
              selectedStartingPositionIndex = 0
              if #allTrails > 0 then
                selectedTrailIndex = 1
                currentTab = "trails"
              end
            end
          end
        end
        im.PopStyleColor()
        im.PopStyleColor()
        im.PopStyleColor()
      end

      im.Separator()

      if currentTab == "trails" and selectedTrailIndex > 0 then
        local selectedTrail = allTrails[selectedTrailIndex]
        if selectedTrail then
          trails:drawTrailDetail(selectedTrail)
        end
      elseif currentTab == "paths" and selectedPathIndex > 0 then
        local selectedPath = allPaths[selectedPathIndex]
        if selectedPath then
          paths:drawPathDetail(selectedPath)
        end
      elseif currentTab == "boundaries" and selectedBoundaryIndex > 0 then
        local selectedBoundary = allBoundaries[selectedBoundaryIndex]
        if selectedBoundary then
          boundaries:drawBoundaryDetail(selectedBoundary)
        end
      elseif currentTab == "startingPositions" and selectedStartingPositionIndex > 0 then
        local selectedStartingPosition = allStartingPositions[selectedStartingPositionIndex]
        if selectedStartingPosition then
          startingPositions:drawStartingPositionDetail(selectedStartingPosition)
        end
      else
        im.Text("Select a trail, path, boundary, or starting position to view details.")
      end

      im.EndChild()
    end

    editor.endWindow()
  end
end

local function testLogging()
  dump('[CRAWL_EDITOR] Test logging function called successfully!')
  dump('[CRAWL_EDITOR] Current time: ' .. os.date())
  return true
end

M.getAllTrails = function() return allTrails end
M.getAllPaths = function() return allPaths end
M.getAllBoundaries = function() return allBoundaries end
M.getAllStartingPositions = function() return allStartingPositions end
M.getSelectedTrailIndex = function() return selectedTrailIndex end
M.getSelectedPathIndex = function() return selectedPathIndex end
M.getSelectedBoundaryIndex = function() return selectedBoundaryIndex end
M.getSelectedStartingPositionIndex = function() return selectedStartingPositionIndex end
M.setSelectedTrailIndex = function(index) selectedTrailIndex = index end
M.setSelectedPathIndex = function(index) selectedPathIndex = index end
M.setSelectedBoundaryIndex = function(index) selectedBoundaryIndex = index end
M.setSelectedStartingPositionIndex = function(index) selectedStartingPositionIndex = index end
M.getSelectedTrail = getSelectedTrail
M.getSelectedPath = getSelectedPath
M.getSelectedBoundary = getSelectedBoundary
M.getSelectedStartingPosition = getSelectedStartingPosition
M.renameObjectFile = renameObjectFile
M.markAsDirty = markAsDirty
M.testLogging = testLogging
M.onEditorInitialized = onEditorInitialized
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.onEditorGui = onEditorGui
M.loadAllObjects = loadAllObjects

return M