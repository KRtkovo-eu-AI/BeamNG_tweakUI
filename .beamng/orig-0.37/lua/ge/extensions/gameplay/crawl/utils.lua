-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local logTag = "crawl_utils"

local gameplay_crawl_boundary = require('ge/extensions/gameplay/crawl/boundary')
local gameplay_crawl_display = require('ge/extensions/gameplay/crawl/display')
local recovery = require('vehicle/recovery')

local infractionPoints = {
  tooMuchZAcceleration = 5,
  drivingBackwards = 2,
  damageThreshold1 = 10,
  damageThreshold2 = 15,
  vehicleFlippedUpright = 25,
  vehicleReset = 50,
  boundaryViolation = 15,
  skippedCheckpoint = 10,
}

local infractionCooldowns = {
  tooMuchZAcceleration = 5,
  drivingBackwards = 5,
  boundaryViolation = 3,
}

local damageThresholds = {
  threshold1 = 1000,
  threshold2 = 4000,
}

local drivingBackwardsSettings = {
  velocityDotThreshold = -0.1,
  distanceThreshold = 2,
}

local zAccelerationSettings = {
  threshold = 3,
}

local markers = nil
local markerModes = {}
local crawlStates = {}
local markersVisibleForPath = nil
local spawnedPrefabIds = {}
local isPreviewMode = false
local pathStatsCache = {}
local dottedPath = {}
local dottedPathTimer = 0

local completionDelay = 3

local function unloadPrefabs()
  for _, id in ipairs(spawnedPrefabIds) do
    local obj = scenetree.findObjectById(id)
    if obj then
      obj:delete()
    end
  end
  spawnedPrefabIds = {}

  gameplay_crawl_boundary.cleanupBoundaryMarkers()
end

local function loadPrefabs(prefabFileList)
  if not prefabFileList then return end

  for _, filePath in ipairs(prefabFileList or {}) do
    local _, fn = path.splitWithoutExt(filePath)
    local scenetreeObject = spawnPrefab(Sim.getUniqueName(fn), filePath, 0 .. " " .. 0 .. " " .. 0, "0 0 1 0", "1 1 1", false)
    scenetreeObject.canSave = false
    if scenetree.MissionGroup then
      scenetree.MissionGroup:add(scenetreeObject)
    end
    table.insert(spawnedPrefabIds, scenetreeObject:getID())
  end

  if gameplay_crawl_general.activeTrail and gameplay_crawl_general.activeTrail.boundary then
    gameplay_crawl_boundary.spawnBoundaryMarkers(gameplay_crawl_general.activeTrail.boundary, 2.0)
  end
end

local function clearMarkers()
  if markers then
    markers.onClientEndMission()
    markers = nil
    markersVisibleForPath = nil
  end
  markerModes = {}
  isPreviewMode = false
end

local function clearCrawler(crawlerId)
  if not crawlerId then
    return
  end
  crawlStates[crawlerId] = nil
end

local function clear()
  clearMarkers()
  unloadPrefabs()

  for crawlerId, _ in pairs(crawlStates) do
    clearCrawler(crawlerId)
  end
  crawlStates = {}
  gameplay_crawl_general.activeTrail = nil

  gameplay_crawl_display.clearPointsMessage()
end

local function onPreviewUpdate(dtSim)
  dottedPathTimer = dottedPathTimer + dtSim
  local sinOff = 0.8
  local radiusBase = 0.1
  local radiusMax = 0.33
  for _, pos in ipairs(dottedPath) do
    if dottedPathTimer*100 > pos.distanceFromStart then
      local t = (dottedPathTimer*5 - pos.distanceFromStart/4)
      local radius = math.sin(t)
      if radius > sinOff and t > 0 then
        radius = ((radius-sinOff)/(1-sinOff)) * (radiusMax-radiusBase) + radiusBase
      else
        radius = radiusBase
      end
      debugDrawer:drawSphere(pos.pos+vec3(0,0,0), radius, ColorF(1,1,1,1))
    end
  end
end

local function setupCrawlMarkers(path)
  if markersVisibleForPath == path._filePath then
    return
  elseif markersVisibleForPath ~= nil then
    markers.onClientEndMission()
  end
  markersVisibleForPath = path._filePath

  if not markers then
    markers = require('scenario/race_marker')
    markers.init()
  end

  if not path then
    log('W', logTag, 'No path available for trail')
    return
  end

  local wps = {}
  local markerModes = {}
  for i, pn in ipairs(path.nodes or {}) do
    if pn.pos then
      table.insert(wps, {
        name = tostring(i),
        pos = pn.pos,
        radius = pn.radius or 6.0,
        normal = nil,
        delay = 0
      })
      markerModes[tostring(i)] = 'hidden'
    end
  end
  if path.nodes and #path.nodes > 0 then
    markerModes[tostring(#path.nodes)] = 'final'
  end

  markers.setupMarkers(wps,'crawlMarker')
  markers.setModes(markerModes)

  dottedPath = {}
  dottedPathTimer = -1
  local stepDist = 1.5

  if path and path.nodes and #path.nodes > 0 then
    local pathnodes = path.nodes
    local pathPositions = { be:getPlayerVehicle(0):getPosition()}
    for i, pn in ipairs(pathnodes) do
      if pn.pos then
        table.insert(pathPositions, pn.pos)
      end
    end

    local currentDist = 0
    local dotPos = vec3()

    for i = 1, #pathPositions - 1 do
      local currentPos = pathPositions[i]
      local nextPos = pathPositions[i + 1]
      if currentPos and nextPos then
        dotPos:set(currentPos)
        local direction = (nextPos - currentPos):normalized()
        local segmentLength = (nextPos - currentPos):length()
        local segmentEndDist = currentDist + segmentLength
        while currentDist < segmentEndDist-stepDist do
          dotPos = dotPos + direction*stepDist

          local terrainHeight = 0
          if core_terrain then
            terrainHeight = core_terrain.getTerrainHeight(dotPos) or dotPos.z
          end
          dotPos.z = terrainHeight + 1

          currentDist = currentDist + stepDist
          table.insert(dottedPath, {
            pos = vec3(dotPos),
            distanceFromStart = currentDist
          })
        end
      end
    end
  end

  isPreviewMode = true

  log('I', logTag, 'Setup crawl markers with ' .. #wps .. ' waypoints')
  log('I', logTag, 'Generated ' .. #dottedPath .. ' dotted path positions')
end

local function activateCrawlMarkers()
  if markers and gameplay_crawl_general.activeTrail and gameplay_crawl_general.activeTrail.path then
    local path = gameplay_crawl_general.activeTrail.path
    if path.nodes and #path.nodes > 0 then
      markerModes[tostring(1)] = 'current'
      markers.setModes(markerModes)
    end
  end

  isPreviewMode = false
end

local function updateCrawlMarkerModes(trail, crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.active then
    return
  end

  local currentIndex = state.currentPathnodeIndex
  local pathnodes = gameplay_crawl_general.activeTrail.path.nodes

  for i, _ in ipairs(pathnodes) do
    markerModes[tostring(i)] = 'inactive'
  end
  markerModes[tostring(#pathnodes)] = 'final'

  if currentIndex <= #pathnodes then
    markerModes[tostring(currentIndex)] = 'current'
  end

  for pathnodeId, _ in pairs(state.completedPathnodes) do
    markerModes[tostring(pathnodeId)] = 'finished'
  end

  if currentIndex == #pathnodes then
    markerModes[tostring(currentIndex)] = 'final'
    if state.isCompleting then
      markerModes[tostring(currentIndex)] = 'finished'
    end
  end

  markers.setModes(markerModes)
end

local function showCompletionResults(crawlerId)
  local state = crawlStates[crawlerId]
  if not state then
    return
  end
  local vehicleData = map.objects[crawlerId]
  local damage = math.max(0, state.crawlerData.infractionData.accumulatedDamage + math.max(0, vehicleData.damage - state.crawlerData.infractionData.startingDamage))
  local completionTime = state.currentTime
  local points = state.crawlerData.points or 0

  log('I', logTag, string.format('Crawl completed - Time: %.2fs, Points: %d, Damage: %.2f', completionTime, points, damage))

  extensions.hook("onCrawlResultsShown", {
    crawlerId = crawlerId,
    time = completionTime,
    points = points,
    damage = damage
  })
  gameplay_crawl_display.showCrawlCompletedMessage(completionTime, points, damage)
end

local function checkPathnodeReached(pathnodes, crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.active or not state.crawlerData then
    return
  end

  local currentCorners = state.crawlerData.dynamicData.currentCorners
  if not currentCorners or #currentCorners == 0 then
    return
  end

  local currentIndex = state.currentPathnodeIndex or 1
  if currentIndex > #pathnodes then
    return
  end

  local reachedPathnodeIndex = nil
  local skippedCheckpoints = 0

  for i = currentIndex, #pathnodes do
    local pathnode = pathnodes[i]
    if pathnode and pathnode.pos then
      local radius = pathnode.radius or 6.0
      local anyCornerReached = false

      for j, corner in ipairs(currentCorners) do
        local distance = (corner - pathnode.pos):length()
        if distance <= radius then
          anyCornerReached = true
          break
        end
      end

      if anyCornerReached then
        if not state.completedPathnodes then
          state.completedPathnodes = {}
        end

        if not state.completedPathnodes[i] then
          state.completedPathnodes[i] = true
          state.pathnodeTimings = state.pathnodeTimings or {}
          state.pathnodeTimings[i] = state.currentTime

          reachedPathnodeIndex = i

          if i > currentIndex then
            skippedCheckpoints = i - currentIndex
            gameplay_crawl_display.showSkippedCheckpointsMessage(skippedCheckpoints)
            state.crawlerData.points = state.crawlerData.points + (skippedCheckpoints * infractionPoints.skippedCheckpoint)

            for skippedIdx = currentIndex, i - 1 do
              local skippedPathnode = pathnodes[skippedIdx]
              if skippedPathnode then
                state.completedPathnodes[skippedIdx] = true
                state.pathnodeTimings[skippedIdx] = state.currentTime
                log('I', logTag, string.format('Crawler %s auto-completed skipped pathnode %d', crawlerId, skippedIdx))
              end
            end
          end
          gameplay_crawl_display.showGateReachedMessage()

          log('I', logTag, string.format('Crawler %s reached node %d', crawlerId, i))
          break
        end
      end
    end
  end

  if reachedPathnodeIndex then
    if reachedPathnodeIndex == #pathnodes then
      state.isCompleting = true
      state.completionStartTime = state.currentTime
      updateCrawlMarkerModes(state.trail, crawlerId)
      log('I', logTag, string.format('Crawler %s completed trail', crawlerId))
      showCompletionResults(crawlerId)
    else
      state.currentPathnodeIndex = reachedPathnodeIndex + 1
    end
  end
end

local function stopCrawl()
  gameplay_crawl_display.clearPointsMessage()
  clear()
end

local function startCrawl(crawlerId, trail, crawlerData)
  if not crawlerId or not trail then
    log('E', logTag, 'Invalid parameters for startCrawl')
    return false
  end

  local state = {
    active = true,
    trail = trail,
    crawlerData = crawlerData,
    currentPathnodeIndex = 1,
    completedPathnodes = {},
    pathnodeTimings = {},
    eventLog = {},
    currentTime = 0,
    isCompleting = false,
    completionStartTime = 0,
    events = {},
    crawlStarted = false
  }

  crawlStates[crawlerId] = state

  local path = gameplay_crawl_general.activeTrail and gameplay_crawl_general.activeTrail.path

  if path and path.nodes and #path.nodes > 0 then
    activateCrawlMarkers()
    log('I', logTag, string.format('Started crawl for %s with %d nodes', crawlerId, #path.nodes))
    gameplay_crawl_display.showStartedCrawlMessage()
    gameplay_crawl_display.showPointsMessage(crawlerData.points or 0)
    return true
  else
    log('E', logTag, 'No valid path for trail')
    return false
  end
end

local function digestCrawlEvents(crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.events then
    return
  end

  local events = state.events

  if events.pathnodeReached then
    table.insert(state.eventLog, {
      type = 'pathnodeReached',
      pathnodeId = events.pathnodeReachedId,
      pathnodeIndex = events.pathnodeReachedIndex,
      time = state.currentTime
    })

    extensions.hook("onCrawlPathnodeReached", {
      crawlerId = crawlerId,
      pathnodeId = events.pathnodeReachedId,
      pathnodeIndex = events.pathnodeReachedIndex,
      time = state.currentTime,
      pathnodeTimings = state.pathnodeTimings
    })

    log("I",logTag,string.format("Pathnode reached: ID=%s, Index=%d", events.pathnodeReachedId, events.pathnodeReachedIndex))
    events.pathnodeReached = false
    events.pathnodeReachedId = nil
    events.pathnodeReachedIndex = nil
  end

  if events.crawlStarted then
    table.insert(state.eventLog, {
      type = 'crawlStarted',
      time = state.currentTime
    })

    log('I', logTag, 'Crawl started')
    events.crawlStarted = false
  end

  if events.disqualified then
    table.insert(state.eventLog, {
      type = 'disqualified',
      time = state.disqualificationTime
    })

    extensions.hook("showDisqualifiedMessage", {
      crawlerId = crawlerId,
      time = state.disqualificationTime
    })

    log("I",logTag,string.format("Crawler %s disqualified", crawlerId))
    clear()

    events.disqualified = false
    events.disqualificationTime = nil
  end
end

local function setupCrawlerData(veh)
  if not veh then
    log('E', logTag, 'No vehicle available, cannot setup crawler data')
    return
  end
  local vehicleData = map.objects[veh:getID()]
  local cD = {
    id = veh:getID(),
    isPlayable = true,
    isDesc = false,
    descReason = "None",
    isFinished = false,
    damage = 0,
    lastPoints = 0,
    points = 0,
    time = 0,
    dynamicData = {
      vehPos = vec3(),
      vehDirectionVector = vec3(),
      vehDirectionVectorUp = vec3(),
      vehRot = quat(),
      vehVelocity = vec3(),
      vehObj = veh,
      bbCenter = vec3(),
      wheelOffsets = {},
      currentCorners = {},
    },
    infractionData = {
      startingDamage = vehicleData.damage,
      accumulatedDamage = 0,
      lastKnownDamage = vehicleData.damage,
      damageThreshold1000 = false,
      damageThreshold4000 = false,
      tooMuchZAccCooldown = 0,
      drivingBackwardsCooldown = 0,
      drivingBackwardsDistance = 0,
      boundaryViolationCooldown = 0,
    }
  }
  cD.dynamicData.oobb = cD.dynamicData.vehObj:getSpawnWorldOOBB()

  local wCount = veh:getWheelCount()-1
  if wCount > 0 then
    local vehiclePos = veh:getPosition()
    local vRot = quatFromDir(veh:getDirectionVector(), veh:getDirectionVectorUp())
    local x,y,z = vRot * vec3(1,0,0),vRot * vec3(0,1,0),vRot * vec3(0,0,1)
    for i=0, wCount do
      local axisNodes = veh:getWheelAxisNodes(i)
      local nodePos = vec3(veh:getNodePosition(axisNodes[1]))
      local pos = vec3(nodePos:dot(x), nodePos:dot(y), nodePos:dot(z))
      table.insert(cD.dynamicData.wheelOffsets, pos)
      table.insert(cD.dynamicData.currentCorners, vRot*pos + vehiclePos)
    end
  end

  core_vehicleBridge.registerValueChangeNotification(veh, "accZSmooth")
  return cD
end

local function updateCrawlerData(crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.crawlerData then
    return
  end

  local veh = state.crawlerData.dynamicData.vehObj
  if not veh then
    return
  end

  state.crawlerData.dynamicData.vehPos:set(veh:getPositionXYZ())
  state.crawlerData.dynamicData.vehDirectionVector:set(veh:getDirectionVector())
  state.crawlerData.dynamicData.vehDirectionVectorUp:set(veh:getDirectionVectorUp())
  state.crawlerData.dynamicData.vehRot:set(veh:getRotation())
  state.crawlerData.dynamicData.vehVelocity:set(veh:getVelocity())
  state.crawlerData.dynamicData.bbCenter:set(be:getObjectOOBBCenterXYZ(crawlerId))

  local vehPos = state.crawlerData.dynamicData.vehPos
  local vehDir = state.crawlerData.dynamicData.vehDirectionVector
  local vehDirUp = state.crawlerData.dynamicData.vehDirectionVectorUp
  local vehRot = quatFromDir(vehDir, vehDirUp)

  for i, corner in ipairs(state.crawlerData.dynamicData.wheelOffsets) do
    state.crawlerData.dynamicData.currentCorners[i]:setRotate(vehRot, corner)
    state.crawlerData.dynamicData.currentCorners[i]:setAdd(vehPos)
  end
end

local tmp1, tmp2 = vec3(), vec3()
local function checkInfractions(crawlerId, dtSim)
  local state = crawlStates[crawlerId]
  if not state or not state.crawlerData then
    return
  end

  local veh = state.crawlerData.dynamicData.vehObj
  local infractionData = state.crawlerData.infractionData
  local vehicleData = map.objects[crawlerId]
  infractionData.tooMuchZAccCooldown = infractionData.tooMuchZAccCooldown - dtSim
  infractionData.drivingBackwardsCooldown = infractionData.drivingBackwardsCooldown - dtSim
  infractionData.boundaryViolationCooldown = infractionData.boundaryViolationCooldown - dtSim

  local accZSmooth = core_vehicleBridge.getCachedVehicleData(crawlerId, "accZSmooth") or 0
  if accZSmooth >= zAccelerationSettings.threshold then
    if infractionData.tooMuchZAccCooldown <= 0 then
      gameplay_crawl_display.showTooMuchZAccMessage()
      state.crawlerData.points = state.crawlerData.points + infractionPoints.tooMuchZAcceleration
    end
    infractionData.tooMuchZAccCooldown = infractionCooldowns.tooMuchZAcceleration
  end

  tmp1:set(veh:getDirectionVectorXYZ())
  tmp2:set(veh:getVelocityXYZ())
  tmp1.z = 0
  tmp2.z = 0
  local dot = tmp1:dot(tmp2)
  if dot < drivingBackwardsSettings.velocityDotThreshold then
    if infractionData.drivingBackwardsCooldown <= 0 then
      infractionData.drivingBackwardsDistance = infractionData.drivingBackwardsDistance + dtSim * math.abs(dot)
      if infractionData.drivingBackwardsDistance > drivingBackwardsSettings.distanceThreshold then
        gameplay_crawl_display.showDrivingBackwardsMessage()
        infractionData.drivingBackwardsCooldown = infractionCooldowns.drivingBackwards
        state.crawlerData.points = state.crawlerData.points + infractionPoints.drivingBackwards
      end
    end
  else
    infractionData.drivingBackwardsDistance = infractionData.drivingBackwardsDistance - dtSim * math.abs(dot)
    if infractionData.drivingBackwardsDistance < 0 then
      infractionData.drivingBackwardsDistance = 0
    end
  end

  local currentDamage = vehicleData.damage
  local lastKnownDamage = infractionData.lastKnownDamage

  if currentDamage < lastKnownDamage - 100 then
    infractionData.accumulatedDamage = infractionData.accumulatedDamage + lastKnownDamage - infractionData.startingDamage
    infractionData.lastKnownDamage = currentDamage
  else
    local damageIncrease = math.max(0, currentDamage - lastKnownDamage)
    infractionData.accumulatedDamage = infractionData.accumulatedDamage + damageIncrease
    infractionData.lastKnownDamage = currentDamage
  end

  local totalDamage = math.max(0, infractionData.accumulatedDamage + math.max(0, currentDamage - infractionData.startingDamage))

  if not infractionData.damageThreshold1000 then
    if totalDamage >= damageThresholds.threshold1 then
      infractionData.damageThreshold1000 = true
      gameplay_crawl_display.showDamageThreshold1000Message()
      state.crawlerData.points = state.crawlerData.points + infractionPoints.damageThreshold1
    end
  end

  if not infractionData.damageThreshold4000 then
    if totalDamage >= damageThresholds.threshold2 then
      infractionData.damageThreshold4000 = true
      gameplay_crawl_display.showDamageThreshold4000Message()
      state.crawlerData.points = state.crawlerData.points + infractionPoints.damageThreshold2
    end
  end
end

local function onVehicleFlippedUpright(crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.crawlerData then
    return
  end
  state.crawlerData.points = state.crawlerData.points + infractionPoints.vehicleFlippedUpright
  gameplay_crawl_display.showVehicleFlippedUprightMessage()
end

local function onVehicleReset(crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.crawlerData then
    return
  end

  local vehicleData = map.objects[crawlerId]
  local infractionData = state.crawlerData.infractionData

  infractionData.accumulatedDamage = infractionData.accumulatedDamage + math.max(0, vehicleData.damage - infractionData.startingDamage)
  infractionData.lastKnownDamage = 0
  infractionData.startingDamage = 0

  state.crawlerData.points = state.crawlerData.points + infractionPoints.vehicleReset
  gameplay_crawl_display.showVehicleResetMessage()
end

local function onBoundaryViolation(crawlerId)
  local state = crawlStates[crawlerId]
  if not state or not state.crawlerData then
    return
  end

  local infractionData = state.crawlerData.infractionData
  if infractionData.boundaryViolationCooldown > 0 then
    return
  end

  state.crawlerData.points = state.crawlerData.points + infractionPoints.boundaryViolation
  infractionData.boundaryViolationCooldown = infractionCooldowns.boundaryViolation
  gameplay_crawl_display.showBoundaryViolationMessage()
end

local function updateCrawl(dtSim)
  gameplay_crawl_boundary.updateBoundaryAnimations(dtSim)

  for crawlerId, state in pairs(crawlStates) do
    if not state or not state.active then
      return
    end
    state.currentTime = state.currentTime + dtSim

    updateCrawlerData(crawlerId)

    local path = gameplay_crawl_general.activeTrail and gameplay_crawl_general.activeTrail.path
    local boundary = gameplay_crawl_general.activeTrail and gameplay_crawl_general.activeTrail.boundary

    if path and path.nodes then
      checkPathnodeReached(path.nodes, crawlerId)
    end

    if boundary then
      gameplay_crawl_boundary.checkBoundary(boundary, state.crawlerData, crawlStates)
    end

    checkInfractions(crawlerId, dtSim)
    digestCrawlEvents(crawlerId)

    if state.crawlerData.points ~= state.crawlerData.lastPoints then
      gameplay_crawl_display.showPointsMessage(state.crawlerData.points)
      state.crawlerData.lastPoints = state.crawlerData.points
    end

    if state.isCompleting and state.completionStartTime > 0 then
      local elapsed = state.currentTime - state.completionStartTime
      if elapsed >= completionDelay then
        stopCrawl()
      end
    end
  end
end

local function drawMarkers(dtReal, dtSim, dtRaw)
  if markersVisibleForPath == nil then
    return
  end

  for crawlerId, state in pairs(crawlStates) do
    if state.active then
      updateCrawlMarkerModes(state.trail, crawlerId)
    end
  end

  if markers then
    markers.render(dtReal, dtSim)
  end
end

local function onDrawOnMinimap(td)
  if markers then
    markers.drawOnMinimap(td)
  end
end

local function onPreRender(dtReal, dtSim, dtRaw)
  if not crawlStates then
    return
  end
  drawMarkers(dtReal, dtSim, dtRaw)
  if isPreviewMode then
    onPreviewUpdate(dtSim)
  end
end

local function calculatePathStats(pathId, pathReversed)
  if not pathId then
    return nil
  end

  if pathStatsCache[pathId] then
    return pathStatsCache[pathId]
  end

  local path = gameplay_crawl_saveSystem.getPathById(pathId)
  if not path or not path.nodes or #path.nodes < 2 then
    return nil
  end

  local totalDistance = 0
  local totalElevationChange = 0
  local stepDistance = 5.0

  local pathnodes = path.nodes
  local pathPositions = {}

  for i, pn in ipairs(pathnodes) do
    if pathReversed then
      i = #pathnodes - i + 1
    end
    if pn.pos then
      table.insert(pathPositions, pn.pos)
    end
  end

  if #pathPositions < 2 then
    return nil
  end

  for i = 1, #pathPositions - 1 do
    local currentPos = pathPositions[i]
    local nextPos = pathPositions[i + 1]

    if currentPos and nextPos then
      local segmentLength = currentPos:distance(nextPos)
      local elevationChange = nextPos.z - currentPos.z

      local numSteps = math.max(1, math.floor(segmentLength / stepDistance))
      local stepSize = segmentLength / numSteps

      for step = 1, numSteps do
        totalDistance = totalDistance + stepSize
        totalElevationChange = totalElevationChange + (elevationChange / numSteps)
      end
    end
  end

  local stats = {
    totalDistance = totalDistance,
    totalElevationChange = totalElevationChange,
    elevationGain = math.max(0, totalElevationChange),
    elevationLoss = math.abs(math.min(0, totalElevationChange))
  }

  pathStatsCache[pathId] = stats

  log('I', logTag, string.format('Calculated path stats for %s: Distance=%.1fm, Elevation=%.1fm', pathId, totalDistance, totalElevationChange))

  return stats
end

M.startCrawl = startCrawl
M.stopCrawl = stopCrawl
M.updateCrawl = updateCrawl
M.drawMarkers = drawMarkers
M.clearMarkers = clearMarkers
M.clear = clear
M.clearCrawler = clearCrawler
M.loadPrefabs = loadPrefabs
M.unloadPrefabs = unloadPrefabs
M.setupCrawlerData = setupCrawlerData
M.onPreRender = onPreRender
M.onDrawOnMinimap = onDrawOnMinimap
M.onVehicleFlippedUpright = onVehicleFlippedUpright
M.onVehicleReset = onVehicleReset
M.onBoundaryViolation = onBoundaryViolation
M.calculatePathStats = calculatePathStats
M.setupCrawlMarkers = setupCrawlMarkers
M.activateCrawlMarkers = activateCrawlMarkers

M.getCrawlState = function(crawlerId)
  return crawlStates[crawlerId]
end

M.getCrawlerPosition = function(crawlerId)
  return crawlStates[crawlerId].crawlerData.dynamicData.vehPos
end

M.setCrawlState = function(crawlerId, state)
  if crawlerId and state then
    crawlStates[crawlerId] = state
    return true
  end
  return false
end

M.getAllCrawlStates = function()
  return crawlStates
end

M.isPreviewMode = function()
  return isPreviewMode
end

M.getDottedPath = function()
  return dottedPath
end

M.infractionPoints = infractionPoints
M.infractionCooldowns = infractionCooldowns
M.damageThresholds = damageThresholds
M.drivingBackwardsSettings = drivingBackwardsSettings
M.zAccelerationSettings = zAccelerationSettings

local originalDropPlayerAtCameraNoReset = commands.dropPlayerAtCameraNoReset
if originalDropPlayerAtCameraNoReset then
  commands.dropPlayerAtCameraNoReset = function()
    log('D', logTag, 'F7 teleport hook called')
    for crawlerId, state in pairs(crawlStates) do
      if state and state.active then
        log('D', logTag, 'Adding penalty for F7 teleport to crawler: ' .. tostring(crawlerId))
        onVehicleReset(crawlerId)
      end
    end
    return originalDropPlayerAtCameraNoReset()
  end
end

local originalStartRecovering = recovery.startRecovering
if originalStartRecovering then
  recovery.startRecovering = function(useAltMode)
    for crawlerId, state in pairs(crawlStates) do
      if state and state.active then
        onVehicleReset(crawlerId)
      end
    end
    return originalStartRecovering(useAltMode)
  end
end

local function trackVehReset()
  for crawlerId, state in pairs(crawlStates) do
    if state and state.active then
      onVehicleReset(crawlerId)
    end
  end
end

M.trackVehReset = trackVehReset

return M