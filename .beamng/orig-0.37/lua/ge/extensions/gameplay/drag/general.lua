-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local logTag = "drag_general"

-- Core state variables
local dragData
local gameplayContext = "freeroam"
local dragExtension

-- File and save management
local currentFileDir = "/gameplay/temp/"
local defaultSaveSlot = 'default'
local saveRoot = 'settings/cloud/'
local currentSavePath = saveRoot .. defaultSaveSlot .. "/"

-- System state
local needsMapReload = false
local needsCollisionRebuild = false
local currentLevel = ""
local initFlagCounter = 0

-- Career rewards
local careerRewards = 5

-- Import debug module
local debugModule = require('/lua/ge/extensions/gameplay/drag/debug')

-- Extension management
local function unloadAllExtensions()
  extensions.hook("onBeforeDragUnloadAllExtensions")
  extensions.unload('gameplay_drag_display')
  extensions.unload('gameplay_drag_times')
  extensions.unload('gameplay_drag_dragTypes_headsUpDrag')
  extensions.unload('gameplay_drag_dragTypes_bracketRace')
  extensions.unload('gameplay_drag_dragTypes_dragPracticeRace')
end

local function clear()
  dragData = nil
  debugModule.setSelectedVehicle(-1)
  debugModule.setAviableLanes({})
  needsMapReload = false
  needsCollisionRebuild = false
  dragExtension = nil
  unloadAllExtensions()
  gameplayContext = "freeroam"
  initFlagCounter = 0
  if ui_gameplayAppContainers then
    ui_gameplayAppContainers.hideApp('gameplayApps', 'drag')
    -- Clear any queued drag flash messages when clearing drag system
    ui_gameplayAppContainers.clearMessagesFromSource('drag')
  end
  guihooks.trigger('updateTreeLightStaging', false)
end

-- Save path management
local function setSavePath(path)
  currentSavePath = path and path or (saveRoot .. defaultSaveSlot .. "/")
end

local function setCurrentSaveSlot()
  local saveSlot, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end
  setSavePath(savePath .. "/career/")
end

-- Transform loading utilities
local function loadTransform(transform)
  for key, data in pairs(transform) do
    if key == "rot" then
      transform[key] = quat(data.x, data.y, data.z, data.w)
    else
      transform[key] = vec3(data.x, data.y, data.z)
    end
  end
  -- Compute local unit vectors
  transform.x, transform.y, transform.z = transform.rot * vec3(transform.scl.x,0,0), transform.rot * vec3(0,transform.scl.y,0), transform.rot * vec3(0,0,transform.scl.z)
end

-- Drag strip data loading
local function loadDragStripData(filepath)
  if not filepath then
    log("E", logTag, "No filepath given for loading drag strip")
    return
  end

  local data = jsonReadFile(filepath)
  if not data or not data.context or not data.strip or not data.phases or not next(data.strip.lanes) then
    log("E", logTag, "Failed to read file: " .. filepath)
    return
  end

  -- Load transforms for all lanes
  for _, lane in ipairs(data.strip.lanes) do
    for _, waypoint in pairs(lane.waypoints) do
      loadTransform(waypoint.transform)
    end
    loadTransform(lane.boundary.transform)

    local stageToEnd = lane.waypoints.endLine.transform.pos - lane.waypoints.stage.transform.pos
    lane.stageToEnd = stageToEnd
    lane.stageToEndNormalized = stageToEnd:normalized()
  end

  -- Load end camera transform if present
  if data.strip.endCamera then
    for key, data in pairs(data.strip.endCamera.transform) do
      if key == "rot" then
        data.strip.endCamera.transform[key] = quat(data.x, data.y, data.z, data.w)
      else
        data.strip.endCamera.transform[key] = vec3(data.x, data.y, data.z)
      end
    end
  end

  data.isCompleted = false
  data.isStarted = false
  data.racers = {}

  local dir, filename, ext = path.split(filepath, true)
  filename = filename:gsub('.'..ext, "")
  data._file = dir..data.stripInfo.id
  data.saveFile = data._file .. "/history.json"

  return data
end

-- Prefab and waypoint loading
local function loadPrefabs(data)
  if not data then return end

  -- Load waypoints
  for _, lane in ipairs(data.strip.lanes) do
    for _, waypoint in pairs(lane.waypoints) do
      if waypoint.waypoint ~= nil then
        local wp = scenetree.findObject(waypoint.name)
        if not wp then
          wp = createObject('BeamNGWaypoint')
          wp:setPosition(waypoint.transform.pos)
          local scale = waypoint.transform.scl or {x = 3, y = 3, z = 3}
          wp:setField('scale', 0, scale.x .. ' ' ..scale.y..' '..scale.z)
          wp:setField('rotation', 0, waypoint.transform.rot.x .. ' ' ..waypoint.transform.rot.y..' '..waypoint.transform.rot.z..' '..waypoint.transform.rot.w)
          wp:registerObject(waypoint.name)
          scenetree.MissionGroup:addObject(wp)
          needsMapReload = true
        else
          log("D", logTag, "Waypoint already exists in the scene: " .. waypoint.name)
        end
      end
    end
  end

  -- Load prefabs
  for prefabName, prefabData in pairs(data.prefabs) do
    if prefabData.path and prefabData.isUsed then
      local existingPrefab = scenetree.findObject(prefabName)
      if not existingPrefab then
        local scenetreeObject = spawnPrefab(Sim.getUniqueName(prefabName), prefabData.path, 0 .. " " .. 0 .. " " .. 0, "0 0 1 0", "1 1 1", false)
        scenetreeObject.canSave = false
        if scenetree.MissionGroup then
          scenetree.MissionGroup:add(scenetreeObject)
          prefabData.prefabId = scenetreeObject:getID()
          needsCollisionRebuild = true
        else
          log("E", logTag, "No missiongroup found!")
        end
      else
        log("D", logTag, 'Prefab already spawned: '..prefabName)
      end
    end
  end

  if needsCollisionRebuild then
    be:reloadCollision()
  end
  if needsMapReload then
    map.reset()
  end
end

-- Prefab cleanup
local function unloadPrefabs()
  if not dragData or gameplayContext == "freeroam" then return end

  if needsMapReload then
    for _, lane in ipairs(dragData.strip.lanes) do
      for _, point in pairs(lane) do
        point.waypoint.wp:delete()
      end
    end
    map.reset()
  end

  if needsCollisionRebuild then
    for _, prefabData in pairs(dragData.prefabs) do
      if prefabData.path and prefabData.isUsed then
        local obj = scenetree.findObjectById(prefabData.prefabId)
        if obj then
          if editor and editor.onRemoveSceneTreeObjects then
            editor.onRemoveSceneTreeObjects({prefabData.prefabId})
          end
          obj:delete()
        end
      end
    end
    be:reloadCollision()
  end
end

-- Racer setup
local function setupRacer(vehicleId, lane)
  if not dragData then return end

  if not vehicleId then
    log('E', logTag, 'No vehicle id')
    return
  end

  local vehicle = scenetree.findObjectById(vehicleId)
  if not vehicle or vehicle.className ~= "BeamNGVehicle" then
    log('E', logTag, 'Object with ID: ' .. vehicleId .. ' is not a vehicle')
    return
  end

  local oldData = jsonReadFile(currentSavePath .. "dragTimes.json") or {}
  local timesKey = M.generateHashFromFile(vehicleId)

  local dial = 10
  if oldData[timesKey] then
    dial = oldData[timesKey].time_1_4
  else
    if core_vehicles.getVehicleDetails(vehicleId).configs["Drag Times"] then
      dial = core_vehicles.getVehicleDetails(vehicleId).configs["Drag Times"].time_1_4 or 10
    end
  end

  local racer = {
    vehId = vehicleId,
    phases = {},
    currentPhase = 1,
    isPlayable = true,
    lane = lane,
    isDesqualified = false,
    desqualifiedReason = "None",
    isFinished = false,
    wheelsOffsets = {},
    currentCorners = {},
    canBeTeleported = dragData.canBeTeleported,
    canBeReseted = dragData.canBeReseted,
    treeStarted = false,
    timersStarted = false,
    damage = 0,
    timers = {
      dial = {type = "dialTimer", value = dial, isSet = true},
      timer = {type = "timer", value = 0},
      reactionTime = {type = "distanceTimer", value = 0, distance = 0.178, isSet = false, label = "Reaction Time"},
      time_60 = {type = "distanceTimer", value = 0, distance = 18.288, isSet = false, label = "Distance: 60ft / 18.28m"},
      time_330 = {type = "distanceTimer", value = 0, distance = 100.584, isSet = false, label = "Distance: 330ft / 100.58m"},
      time_1_8 = {type = "distanceTimer", value = 0, distance = 201.168, isSet = false, label = "Distance: 1/8th mile / 201.16m"},
      time_1000 = {type = "distanceTimer", value = 0, distance = 304.8, isSet = false, label = "Distance: 1000ft / 304.8m"},
      time_1_4 = {type = "distanceTimer", value = 0, distance = 402.336, isSet = false, label = "Distance: 1/4th mile / 402.34m"},
      velAt_1_8 = {type = "velocity", value = 0, distance = 201.168, isSet = false, label = "Distance: 1/8th mile / 201.16m"},
      velAt_1_4 = {type = "velocity", value = 0, distance = 402.336, isSet = false, label = "Distance: 1/4th mile / 402.34m"},
      time_0_60 = {type = "timeToVelocity", value = 0, velocity = 26.8224, isSet = false},
      brakingG = {type = "brakingG", value = 0, isSet = false, deltaTime = 1},
    },
  }

  -- Initialize vector fields
  racer.vehPos = vec3()
  racer.vehDirectionVector = vec3()
  racer.vehDirectionVectorUp = vec3()
  racer.vehRot = quat()
  racer.vehVelocity = vec3()
  racer.prevSpeed = 0
  racer.vehSpeed = 0
  racer.vehObj = nil

  -- Calculate wheel offsets
  local wheelCount = vehicle:getWheelCount()-1
  local wheelsByFrontness = {}
  local maxFrontness = -math.huge

  if wheelCount > 0 then
    local vehiclePos = vehicle:getPosition()
    local forward = vehicle:getDirectionVector()
    local up = vehicle:getDirectionVectorUp()
    local vehicleRot = quatFromDir(forward, up)
    local x, y, z = vehicleRot * vec3(1,0,0), vehicleRot * vec3(0,1,0), vehicleRot * vec3(0,0,1)
    local center = vehicle:getSpawnWorldOOBB():getCenter()

    for i = 0, wheelCount do
      local axisNodes = vehicle:getWheelAxisNodes(i)
      local nodePos = vec3(vehicle:getNodePosition(axisNodes[1]))
      local wheelNodePos = vehiclePos + nodePos

      local frontness = forward:dot(wheelNodePos - center)

      for key, _ in pairs(wheelsByFrontness) do
        if math.abs(tonumber(key) - frontness) < 0.2 then
          frontness = key
        end
      end

      local pos = vec3(nodePos:dot(x), nodePos:dot(y), nodePos:dot(z))
      wheelsByFrontness[frontness] = wheelsByFrontness[frontness] or {}
      table.insert(wheelsByFrontness[frontness], pos)

      maxFrontness = math.max(frontness, maxFrontness)
    end
  end

  if not next(wheelsByFrontness) then
    log('E', logTag, 'Couldnt find front wheels for ' .. vehicleId .. '! will use OOBB as wheel offsets')

    local vehiclePos = vehicle:getPosition()
    local forward = vehicle:getDirectionVector()
    local up = vehicle:getDirectionVectorUp()
    local vehicleRot = quatFromDir(forward, up)
    local x, y, z = vehicleRot * vec3(1,0,0), vehicleRot * vec3(0,1,0), vehicleRot * vec3(0,0,1)
    local frontLeft, frontRight = vehicle:getSpawnWorldOOBB():getPoint(0) - vehiclePos, vehicle:getSpawnWorldOOBB():getPoint(3) - vehiclePos

    local posL = vec3(frontLeft:dot(x), frontLeft:dot(y), frontLeft:dot(z))
    local posR = vec3(frontRight:dot(x), frontRight:dot(y), frontRight:dot(z))
    maxFrontness = "oobb"
    wheelsByFrontness[maxFrontness] = {posL, posR}
  end

  racer.allWheelsOffsets = wheelsByFrontness
  racer.wheelsCenter = {}
  racer.beamState = {}
  racer.frontWheelId = maxFrontness

  for k, v in pairs(racer.allWheelsOffsets) do
    racer.wheelsCenter[k] = {pos = vec3(), wheelCountInv = 1 / #racer.allWheelsOffsets[k]}
    racer.beamState[k] = {preStage = false, stage = false}
  end

  -- Initialize phases
  for _, phase in ipairs(dragData.phases) do
    table.insert(racer.phases, {
      name = phase.name,
      started = false,
      completed = false,
      dependency = phase.dependency,
      timerOffset = 0,
      startedOffset = phase.startedOffset,
    })
  end

  local details = core_vehicles.getVehicleDetails(vehicleId)
  if details then
    racer.niceName = (details.model.Brand or "") .. " " .. (details.configs.Name or "Unknown")
  end

  local status, ret = xpcall(function() return type(deserialize(vehicle.partConfig)) end, nop)
  racer.stock = not ret
  racer.licenseText = core_vehicles.getVehicleLicenseText(vehicle)

  if debugModule.getDebugMenu() then
    debugModule.selectElement(vehicleId)
  end

  dragData.racers[vehicleId] = racer
end

-- Mission setup interface
local function loadDragDataForMission(filepath)
  clear()
  local data = loadDragStripData(filepath)
  if not data then
    log("E", logTag, "Failed to load drag data from file: " .. filepath)
    return
  end

  loadPrefabs(data)
  gameplayContext = data.context
  if data.dragType == "headsUpRace" then
    extensions.load('gameplay_drag_dragTypes_headsUpDrag')
    dragExtension = gameplay_drag_dragTypes_headsUpDrag
  elseif data.dragType == "bracketRace" then
    extensions.load('gameplay_drag_dragTypes_bracketRace')
    dragExtension = gameplay_drag_dragTypes_bracketRace
  end
  dragData = data
end

local function setVehicles(vehicleIds)
  for _, data in ipairs(vehicleIds) do
    setupRacer(data.id, data.lane)
    if not dragData.racers[data.id] then
      log("E", logTag, "There is a problem with the vehicle setting, vehicle has not been set correctly.")
      return
    end
    dragData.racers[data.id].isPlayable = data.isPlayable
    if data.dial and data.dial > 0 then
      dragData.racers[data.id].timers.dial.value = data.dial
    end
  end
end

-- Freeroam setup interface
local function init()
  --return loadDragStripData(levelDir .. "/dragstrips/dragStripData.dragData.json")
end

-- Vehicle permission checking
local function getPropertyValue(obj, path)
  local current = obj
  for _, key in ipairs(path) do
    if current == nil then
      log("E", logTag, "Property path not found: " .. dump(path))
      return
    end
    current = current[key]
  end
  return current
end

local function checkVehiclePermission(model, rules)
  for _, rule in ipairs(rules) do
    local propertyValue = getPropertyValue(model, rule.path)

    if rule.allowedValues then
      local found = false
      for _, allowedValue in ipairs(rule.allowedValues) do
        if propertyValue == allowedValue then
          found = true
          break
        end
      end
      if not found then
        log("E", logTag, "Vehicle " .. model.model .. " does not match rule: " .. dump(rule.path))
        return false
      end
    elseif rule.value ~= nil then
      if propertyValue ~= rule.value then
        log("E", logTag, "Vehicle " .. model.model .. " does not match rule: " .. dump(rule.path))
        return false
      end
    end
  end
  return true
end


-- Example of a vehicle permission rules
-- local vehiclePermissionRules = {
--   {
--     ruleName = "vehicleType",
--     path = {"Type"},
--     allowedValues = {"Car", "Truck"}
--   },
--   {
--     ruleName = "notAuxiliary",
--     path = {"isAuxiliary"},
--     allowedValues = false
--   }
-- }
-- Generate opponents group based on the player vehicle.
----
-- -- If no dial is provided, it will use the player vehicle's dial.
-- -- If no vehiclePermissionRules are provided, it will allow all vehicles and configs.
-- -- If no offset is provided, it will use the default value: 0.5.
-- -- If no amount is provided, it will use the default value: 1.
local function generateOpponentsGroup(vehId, dial, vehiclePermissionRules, amount, offset)
  if not vehId then
    log("E", logTag, "Invalid input parameters")
    return
  end

  amount = amount or 1
  offset = offset or 0.5

  local configs = core_vehicles.getConfigList()
  local vehicleDetails = core_vehicles.getVehicleDetails(vehicleId)
  if not vehicleDetails then
    log("E", logTag, "Could not find vehicle details for ID: " .. tostring(vehicleId))
    return
  end

  if not vehicleDetails.configs["Drag Times"] then
    log("E", logTag, "Vehicle has no drag times data")
    return
  end

  local quarterMileScore = dial or vehicleDetails.configs["Drag Times"].time_1_4 or 10
  local minTime = quarterMileScore - offset
  local maxTime = quarterMileScore + 0.1

  local eligibleVehicles = {}
  local eligibleCount = 0

  for _, config in pairs(configs.configs) do
    if config["Drag Times"] and config["Drag Times"].time_1_4 and config["Drag Times"].time_1_4 >= minTime and config["Drag Times"].time_1_4 < maxTime then
      local model = core_vehicles.getModel(config.model_key).model
      if checkVehiclePermission(model, vehiclePermissionRules) and not string.match(config.key, 'simple_traffic') then
        eligibleCount = eligibleCount + 1
        eligibleVehicles[eligibleCount] = config
      end
    end
  end

  if eligibleCount == 0 then
    log("D", logTag, "No eligible vehicles found, using player vehicle as fallback")
    eligibleVehicles[1] = vehicleDetails
    eligibleCount = 1
  end

  math.randomseed(os.time())
  local opponentsGroup = {}
  for i = 1, amount do
    local selectedConfig = eligibleVehicles[math.random(eligibleCount)]
    local paints = tableKeys(tableValuesAsLookupDict(core_vehicles.getModel(selectedConfig.model_key).model.paints or {}))
    local paintCount = #paints

    table.insert(opponentsGroup, {
      model = selectedConfig.model_key,
      config = selectedConfig.key,
      paint = paintCount > 0 and paints[math.random(paintCount)] or nil,
    })
  end
  return opponentsGroup
end

local function setDragRaceData(data)
  if dragData then return end
  dragData = data
end

-- Race management
local function resetDragRace()
  dragExtension.resetDragRace()
end

local function clearRacers()
  dragData.racers = {}
end

local function unloadRace()
  clear()
end

local function setPlayableVehicle(vehicleId)
  if not vehicleId then return end
  dragData.racers[vehicleId].isPlayable = true
end

local function getTimers(vehicleId)
  if not dragData then return end
  return dragData.racers[vehicleId].timers or {}
end

local function getRacerData(vehicleId)
  if not dragData or not dragData.racers[vehicleId] then return end
  return dragData.racers[vehicleId] or {}
end

-- UI context management
local waitForUIContextResetCallback = false
local function trySetUIContainerContextToDrag()
  if ui_gameplayAppContainers then
    ui_gameplayAppContainers.showApp('gameplayApps', 'drag')
  end
end

local function startDragRaceActivity(lane)
  if not dragData or not dragData.racers then
    log("E", logTag, "Data not found to start the Drag Race")
    return
  end

  if lane ~= nil and gameplayContext == "freeroam" then
    dragData.racers = {}
    if lane == 1 then
      dragData.prefabs.christmasTree.treeType = ".500"
    else
      dragData.prefabs.christmasTree.treeType = ".400"
    end
    setupRacer(be:getPlayerVehicleID(0), lane)

    extensions.load('gameplay_drag_dragTypes_' .. dragData.dragType)
    dragExtension = gameplay_drag_dragTypes_dragPracticeRace
    gameplayContext = dragData.context or 'freeroam'
  end

  trySetUIContainerContextToDrag()
  guihooks.trigger('updateTreeLightStaging', true)
  dragExtension.startActivity()
end

-- No longer needed with individual app visibility system
local function onUIContainerContextReset()
  -- Legacy callback - functionality replaced by individual app visibility
end

local function getWinnersData()
  return gameplay_drag_utils.generateWinData()
end

local function getData()
  return dragData
end

local function getDragIsStarted()
  if not dragData then return false end
  return dragData.isStarted or false
end

-- Vehicle event hooks
local function onVehicleResetted(vehicleId)
  if be:getPlayerVehicleID(0) == vehicleId then
    M.clearTimeslip()
  end
  if gameplayContext == "freeroam" and dragData and dragData.isStarted then
    if dragData.racers[vehicleId] then
      clear()
    end
  end
end

local function onVehicleSwitched(oldId, newId)
  if gameplayContext == "freeroam" and dragData and dragData.isStarted then
    if dragData.racers[oldId] or dragData.racers[newId] then
      clear()
    end
  end
end

local function onVehicleDestroyed(vehicleId)
  if gameplayContext == "freeroam" and dragData and dragData.isStarted then
    if dragData.racers[vehicleId] then
      clear()
    end
  end
end

local function onExtensionLoaded()
  clear()
end

local function onAnyMissionChanged(status, id)
  clear()
  if status == "stopped" then
    dragData = init()
  end
end

-- Save/Load management
local savePathFreeroam = 'settings/cloud/drag/'
local savePathCareer = '/career/drag/'

local function getCurrentSavePath()
  local saveFolder = savePathFreeroam
  if career_career.isActive() then
    local saveSlot, savePath = career_saveSystem.getCurrentSaveSlot()
    saveFolder = savePath .. savePathCareer
  end
  return saveFolder
end

-- Dial times management
local dialData = nil

local function saveDialTimes()
  if not dialData then
    dialData = jsonReadFile(M.getCurrentSavePath() .. "dialTimes.json") or {
      dials = {},
    }
  end

  for _, racer in pairs(dragData.racers) do
    if racer.isPlayable then
      local hash = M.generateHashFromFile()
      local prevTime = (dialData.dials[hash] or {})._timestamp or os.time()
      local doUpdate = prevTime < os.time() - (24*60*60)

      local _dirt = {}
      local timerKeys = {"time_60", "time_330", "time_1_8", "time_1000", "time_1_4", "velAt_1_4", "velAt_1_8", "time_0_60", "brakingG" }
      for _, key in ipairs(timerKeys) do
        _dirt[key] = racer.timers[key].value
      end
      _dirt._timestamp = os.time()
      dialData.dials[hash] = _dirt
      dialData._dirty = true
    end
  end

  if not career_career.isActive() then
    M.saveDialFile(savePathFreeroam)
  end
end

local function saveDialFile(dir)
  if dialData and dialData._dirty then
    dialData._dirty = nil
    jsonWriteFile(dir .. "dragTimes.json", dialData, true)
    dialData = nil
  end
end

local function getDialTimes()
  if dialData then
    return dialData.dials
  else
    dialData = jsonReadFile(M.getCurrentSavePath() .. "dragTimes.json") or {
      dials = {},
    }
    return dialData.dials
  end
end

-- History management
local historyData = {}

local function saveHistory(timeslip)
  local file = historyData[dragData.saveFile]
  if not file then
    file = jsonReadFile(M.getCurrentSavePath() .. dragData.saveFile) or {
      history = {}
    }
    historyData[dragData.saveFile] = file
  end

  table.insert(file.history, timeslip)
  file._dirty = true

  if not career_career.isActive() then
    M.saveHistoryFile(savePathFreeroam)
  end
end

local function saveHistoryFile(dir)
  for file, data in pairs(historyData) do
    if data._dirty then
      data._dirty = false
      jsonWriteFile(dir..file, data, true)
    end
  end
  historyData = {}
end

local function dateToTimestamp(dateStr)
  return os.time({
    year = tonumber(dateStr:sub(11, 14)),
    month = tonumber(dateStr:sub(5, 6)),
    day = tonumber(dateStr:sub(8, 9)),
    hour = tonumber(dateStr:sub(16, 17)),
    min = tonumber(dateStr:sub(19, 20)),
    sec = tonumber(dateStr:sub(22, 23)),
    isdst = false
  })
end

local function getHistory(id)
  local filePath = M.getCurrentSavePath() .. "levels/" .. getCurrentLevelIdentifier() .. "/dragstrips/" .. id .. "/history.json"
  if not historyData[filePath] then
    local file = jsonReadFile(filePath) or {
      history = {},
    }
    historyData[filePath] = file
  end
  table.sort(historyData[filePath].history, function(a, b) return dateToTimestamp(a.stripInfo[3]) > dateToTimestamp(b.stripInfo[3]) end)
  return historyData[filePath]
end

local function setCareerRewards()
  if not career_career.isActive() or dragData.context == "activity" then return end
  local rewards = {bmra = math.ceil(careerRewards)}
  career_modules_playerAttributes.addAttributes(rewards,{label="Rewards for Drag Race", tags={"gameplay"}})
  return rewards
end

local function onSaveCurrentSaveSlot(currentSavePath)
  M.saveDialFile(currentSavePath .. savePathCareer)
  M.saveHistoryFile(currentSavePath .. savePathCareer)
end

local function onCareerActive()
  dialData = nil
  historyData = {}
end

-- Timeslip interface
local timerKeys = {"reactionTime", "time_60", "time_330", "time_1_8", "time_1000", "time_1_4", "dial" }
local velocityKeys = {"velAt_1_4", "velAt_1_8"}

local treeNames = {[".400"] = "Pro Tree", [".500"] = "Sportsman Tree"}

local function clearTimeslip()
  guihooks.trigger("onDragRaceTimeslipData", nil)
end

local function createTimeslipData()
  if not dragData or not next(dragData) then
    log("E", logTag, "No drag data found, cannot create timeslip data")
    return
  end

  local rawData = {}

  rawData.stripInfo = {
    stripName = dragData.stripInfo and dragData.stripInfo.stripName or "Drag Strip",
    levelName = core_levels.getLevelByName(getCurrentLevelIdentifier()).title,
    dateTime = os.date(dragData.stripInfo and dragData.stripInfo.dateFormat or "%a %m/%d/%Y %I:%M:%S %p"),
    tree = treeNames[dragData.prefabs.christmasTree.treeType],
  }
  rawData.env = {
    tempK = core_environment.getTemperatureK(),
    tempC = core_environment.getTemperatureK() - 273.15,
    tempF = (core_environment.getTemperatureK() - 273.15) * (9/5) + 32,
    customGrav = math.abs(core_environment.getGravity() - 9.81) > 0.01,
    gravity = string.format("%0.2f m/s²", math.abs(core_environment.getGravity())),
  }
  rawData.dragType = dragData.dragType

  rawData.racerInfos = {}
  for id, racer in pairs(dragData.racers) do
    local currentVehicle = core_vehicles.getVehicleDetails(id)
    local vehicleConfig = currentVehicle.configs

    local timers = {}
    for _, timeLabel in ipairs(timerKeys) do
      timers[timeLabel] = string.format("%0.3f", racer.timers[timeLabel].value)
    end
    local velocities = {}
    for _, velLabel in ipairs(velocityKeys) do
      velocities[velLabel..'_km/h'] = string.format("%0.3f", racer.timers[velLabel].value * 3.6)
      velocities[velLabel..'_mph'] = string.format("%0.3f", racer.timers[velLabel].value * 2.23694)
    end

    local info = {
      name = racer.niceName,
      stock = racer.stock and "Stock" or "Modified",
      licenseText = racer.licenseText,
      lane = dragData.strip.lanes[racer.lane].longName,
      laneNum = racer.lane,
      finalTime = racer.timers.time_1_4.value,
      rewards = M.setCareerRewrads() or {},
      dialDiff = (racer.timers.time_1_4.value + racer.timers.reactionTime.value) - racer.timers.dial.value,
      disqualification = racer.isDesqualified,
      brand = currentVehicle.model.Brand or "Unknown",
      country = currentVehicle.model.Country or "Unknown",
      drivetrain = vehicleConfig.Drivetrain or "Unknown",
      fuelType = vehicleConfig["Fuel Type"] or "Unknown",
      transmission = vehicleConfig.Transmission or "Unknown",
      configType = vehicleConfig["Config Type"] or "Unknown",
      inductionType = vehicleConfig["Induction Type"] or "Unknown",
      timers = timers,
      velocities = velocities
    }
    table.insert(rawData.racerInfos, info)
  end
  table.sort(rawData.racerInfos, function(a,b) return a.laneNum > b.laneNum end)
  return rawData
end

local function createTimeslipPanelData()
  local slip = M.createTimeslipData()
  local ret = {}
  for _, key in ipairs({"stripInfo","tree","env","racerInfos"}) do
    ret[key] = slip[key]
  end

  local grid = {
    labels = {},
    rows = {}
  }

  local tab = slip.timesTable
  for _, l in ipairs(tab[1]) do
    table.insert(grid.labels, l)
  end
  for i = 3, #tab do
    local row = {}
    table.insert(row, {
      text = (tab[i][1]):gsub("%.+$", "")
    })

    for j = 2, #tab[i] do
      local txt = tab[i][j]
      table.insert(row, {text = txt, mono=true})
    end
    table.insert(grid.rows, row)
  end

  ret.grid = grid
  return ret
end

local function sendTimeslipDataToUi()
  local slipData = M.createTimeslipData()

  if not slipData or not next(slipData) then
    guihooks.trigger("onDragRaceTimeslipData", nil)
    return
  end

  M.saveHistory(slipData)
  guihooks.trigger("onDragRaceTimeslipData", slipData)
end

local function generateHashFromFile(vehicleId)
  local currentVehicle = vehicleId and core_vehicles.getVehicleDetails(vehicleId) or core_vehicles.getCurrentVehicleDetails()

  if string.find(currentVehicle.current.pc_file, ".pc") then
    return hashStringSHA256(serialize(jsonReadFile(currentVehicle.current.pc_file)))
  end

  return hashStringSHA256(currentVehicle.current.pc_file)
end

local function screenshotTimeslip()
  local dir = "screenshots/timeslips/"..getScreenShotDateTimeString()
  screenshot.doScreenshot(nil, nil, dir,'jpg')
  ui_message("Timeslip saved: " .. dir .. ".jpg", nil, nil, "save")
end

-- Debug interface
local function drawDebugMenu()
  debugModule.drawDebugMenu(dragData, dragExtension)
end

local function setDebugMenu(enabled)
  debugModule.setDebugMenu(enabled)
end

local function getDebugMenu()
  return debugModule.getDebugMenu()
end

local function getExtension()
  return dragExtension
end

-- Public interface

-- Extension lifecycle
M.onExtensionLoaded = onExtensionLoaded

-- Data loading and setup
M.loadDragStripData = loadDragStripData
M.loadDragDataForMission = loadDragDataForMission
M.setDragRaceData = setDragRaceData

-- Racer management
M.setupRacer = setupRacer
M.setVehicles = setVehicles
M.clearRacers = clearRacers
M.setPlayableVehicle = setPlayableVehicle
M.getRacerData = getRacerData

-- Race control
M.resetDragRace = resetDragRace
M.unloadRace = unloadRace
M.startDragRaceActivity = startDragRaceActivity
M.getDragIsStarted = getDragIsStarted

-- Opponent generation
M.generateOpponentsGroup = generateOpponentsGroup

-- Timer and data access
M.getTimers = getTimers
M.getData = getData
M.getWinnersData = getWinnersData

-- Vehicle event handlers
M.onVehicleResetted = onVehicleResetted
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleDestroyed = onVehicleDestroyed

-- UI and context management
M.onUIContainerContextReset = onUIContainerContextReset
M.onAnyMissionChanged = onAnyMissionChanged

-- Save and file management
M.getCurrentSavePath = getCurrentSavePath
M.saveDialTimes = saveDialTimes
M.saveDialFile = saveDialFile
M.getDialTimes = getDialTimes
M.saveHistory = saveHistory
M.saveHistoryFile = saveHistoryFile
M.getHistory = getHistory
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onCareerActive = onCareerActive

-- Career and rewards
M.setCareerRewrads = setCareerRewards

-- Timeslip functionality
M.clearTimeslip = clearTimeslip
M.createTimeslipData = createTimeslipData
M.createTimeslipPanelData = createTimeslipPanelData
M.sendTimeslipDataToUi = sendTimeslipDataToUi
M.screenshotTimeslip = screenshotTimeslip

-- Utility functions
M.generateHashFromFile = generateHashFromFile

-- Debug interface
M.drawDebugMenu = drawDebugMenu
M.setDebugMenu = setDebugMenu
M.getDebugMenu = getDebugMenu
M.getExtension = getExtension

return M