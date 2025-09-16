-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local logTag = "crawl_general"
M.dependencies = { 'gameplay_crawl_saveSystem', 'gameplay_crawl_utils', 'gameplay_crawl_boundary', 'gameplay_crawl_display' }

-- Active trail table - replaces crawlActive and contains all active trail data
M.activeTrail = nil
local crawlersData = {}

local function clear()
  if M.activeTrail then
    gameplay_crawl_utils.unloadPrefabs()
  end

  M.activeTrail = nil
  gameplay_crawl_utils.clear()
  crawlersData = {}
end

local function loadCrawlDataFromMission()
  -- TODO: Implement
end

local function startCrawl(trail, veh)
  if not trail or not veh then
    log('E', logTag, 'Cannot start crawl: no valid trail data')
    return
  end

  -- Clear any existing active crawl
  if M.activeTrail then
    log('I', logTag, 'Clearing existing crawl before starting new one')
    gameplay_crawl_utils.stopCrawl()
    crawlersData = {}
  end

  -- Load trail, boundary, path, and starting position data into activeTrail
  M.activeTrail = {
    trail = trail,
    boundary = gameplay_crawl_saveSystem.getBoundaryById(trail.boundaryId),
    path = deepcopy(gameplay_crawl_saveSystem.getPathById(trail.pathId)),
    startingPosition = gameplay_crawl_saveSystem.getStartingPositionById(trail.startingPositionId),
    prefabs = trail.prefabs or {}
  }

  if trail.pathReversed then
    M.activeTrail.path.nodes = arrayReverse(M.activeTrail.path.nodes)
  end

  local crawlerData = gameplay_crawl_utils.setupCrawlerData(veh)
  table.insert(crawlersData, crawlerData)

  gameplay_crawl_utils.loadPrefabs(M.activeTrail.prefabs)

  if gameplay_crawl_utils.startCrawl(veh:getID(), trail, crawlerData) then
    log('I', logTag, 'Crawl started successfully')
    extensions.hook('onCrawlStarted')
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if M.activeTrail then
    gameplay_crawl_utils.updateCrawl(dtSim)
  end
end

local function getBigMapTpPosRot(poi, veh)
  local trail = gameplay_crawl_saveSystem.getTrailById(poi.data.trailId)
  if trail and trail.startingPositionId then
    local startingPos = gameplay_crawl_saveSystem.getStartingPositionById(trail.startingPositionId)
    if startingPos then
      local pos = startingPos.transform.position
      local rot = startingPos.transform.rotation or quat(0, 0, 0, 1)

      -- Calculate rotation to face the first path node
      if trail.pathId then
        local path = gameplay_crawl_saveSystem.getPathById(trail.pathId)
        if path and path.nodes and #path.nodes > 0 then
          local firstNode = path.nodes[1]
          if firstNode and firstNode.pos then
            local direction = (firstNode.pos - pos):normalized()
            if direction:length() > 0.001 then -- Avoid division by zero
              rot = quatFromDir(direction, vec3(0, 0, 1))
            end
          end
        end
      end

      return pos, rot
    end
  end
  return nil, nil
end

local function onGetRawPoiListForLevel(levelIdentifier, elements)
  local trails = gameplay_crawl_saveSystem.getAllTrails()
  if trails and not M.activeTrail and (career_career.isActive() or settings.getValue("enableCrawlInFreeroam")) then
    for _, trail in ipairs(trails) do
      local startingPosition = nil
      if trail.startingPositionId then
        startingPosition = gameplay_crawl_saveSystem.getStartingPositionById(trail.startingPositionId)
      end

      if startingPosition then
        local pos = startingPosition.transform.position
        local radius = startingPosition.transform.radius or 10

        local rotation = startingPosition.transform.rotation
        if trail.pathId then
          local path = gameplay_crawl_saveSystem.getPathById(trail.pathId)
          if path and path.nodes and #path.nodes > 0 then
            local firstNode = path.nodes[1]
            if firstNode and firstNode.pos then
              local direction = (firstNode.pos - pos):normalized()
              if direction:length() > 0.001 then -- Avoid division by zero
                rotation = quatFromDir(direction, vec3(0, 0, 1))
              end
            end
          end
        end

        local poi = {
          id = string.format("crawl##%s", trail._fileName or "trail"),
          data = { type = "crawl", trailId = trail._filePath },
          markerInfo = {
            crawlMarker = {
              pos = pos,
              rot = rotation,
              radius = radius,
              iconPos = startingPosition.iconPosition,
              onInside = function(interactData)
              end,
            }
          }
        }
        poi.markerInfo.bigmapMarker = {
          pos = pos,
          icon = "mission_rockcrawling01_triangle",
          name = trail.name or "Crawl Trail",
          description = "A rockcrawling trail to test your off-road skills.",
          thumbnail = trail.thumbnail,
          previews = {trail.thumbnail},
          quickTravelPosRotFunction = getBigMapTpPosRot
        }

        -- Add score information like drift spots
        local trailStats = gameplay_crawl_saveSystem.getPlayerTrailStats(trail._filePath)
        if trailStats and trailStats.bestPenaltyPoints < math.huge then
          poi.markerInfo.bigmapMarker.description = poi.markerInfo.bigmapMarker.description .. "\n" .. string.format("Best Penalty Points: %d", trailStats.bestPenaltyPoints)
        end
        if trailStats then
          poi.markerInfo.bigmapMarker.aggregatePrimary = {label = 'bigMap.progressLabels.bestPoints', value = trailStats.bestPenaltyPoints < math.huge and trailStats.bestPenaltyPoints or "-"}
        end
        table.insert(elements, poi)
      end
    end
  end
end


local function onActivityAcceptGatherData(elemData, activityData)
  for _, elem in ipairs(elemData) do
    if elem.type == "crawl" then
      local trail = gameplay_crawl_saveSystem.getTrailById(elem.trailId)

      -- Calculate path statistics
      local pathStats = nil
      if trail.pathId then
        pathStats = gameplay_crawl_utils.calculatePathStats(trail.pathId, trail.pathReversed)
      end

      local props = {}

      -- Add path statistics to props if available
      if pathStats then
        table.insert(props, {
          icon = "ui_icons_distance",
          keyLabel = "Distance",
          valueLabel = string.format("%.1f m", pathStats.totalDistance)
        })

        if pathStats.elevationGain > 0 then
          table.insert(props, {
            icon = "ui_icons_elevation_up",
            keyLabel = "Elevation Gain",
            valueLabel = string.format("%.1f m", pathStats.elevationGain)
          })
        end

        if pathStats.elevationLoss > 0 then
          table.insert(props, {
            icon = "ui_icons_elevation_down",
            keyLabel = "Elevation Loss",
            valueLabel = string.format("%.1f m", pathStats.elevationLoss)
          })
        end
      end

            -- Add player score information like drift spots
      local trailStats = gameplay_crawl_saveSystem.getPlayerTrailStats(elem.trailId)
      if trailStats then
                if trailStats.bestPenaltyPoints < math.huge then
          table.insert(props, {
            icon = "ui_icons_points",
            keyLabel = "Best Penalty Points",
            valueLabel = string.format("%d", trailStats.bestPenaltyPoints)
          })
        end

        if trailStats.bestTime < math.huge then
          table.insert(props, {
            icon = "ui_icons_time",
            keyLabel = "Best Time",
            valueLabel = string.format("%.2fs", trailStats.bestTime)
          })
        end

        if trailStats.attempts > 0 then
          table.insert(props, {
            icon = "ui_icons_attempts",
            keyLabel = "Attempts",
            valueLabel = tostring(trailStats.attempts)
          })
        end
      end

      local data = {
        data = elem,
        icon = "mission_rockcrawling01_triangle",
        heading = trail.name,
        preheadings = {"Freeroam Crawl"},
        props = props,
        buttonLabel = "Play",
        buttonFun = function()
          local veh = be:getPlayerVehicle(0)
          if veh then
            startCrawl(trail, veh)
          end
          ui_missionInfo.closeDialogue()
        end,
      }
      table.insert(activityData, data)
    end
  end
end

local function onActivityIndexVisible(data)
  -- If no data, clear markers (player left POI area)
  if not data then
    if not M.activeTrail then
      gameplay_crawl_utils.clearMarkers()
    end
    return
  end

  -- If we have an active trail, don't show preview markers
  if M.activeTrail then
    return
  end

  -- Show preview markers for crawl POIs
  if data.type == "crawl" then
    local trail = gameplay_crawl_saveSystem.getTrailById(data.trailId)
    local path = deepcopy(gameplay_crawl_saveSystem.getPathById(trail.pathId))
    if trail.pathReversed then
      path.nodes = arrayReverse(path.nodes)
    end
    gameplay_crawl_utils.setupCrawlMarkers(path)
  end
end

local function onDrawOnMinimap(td)
  if M.activeTrail then
    local boundary = M.activeTrail.boundary
    if boundary then
      boundary:drawMinimap(td)
    end
  end
end

local function onExtensionLoaded()
  clear()
  -- Ensure save directories exist
  gameplay_crawl_saveSystem.ensurePlayerSaveDirectories()
end

local function onSerialize()
  clear()
end

local function onVehicleSwitched(oldId, newId)
  if M.activeTrail then
    clear()
  end
end

local function onVehicleDestroyed(vehId)
  if M.activeTrail then
    clear()
  end
end

local function onAnyMissionChanged(status, id)
  if status == "stopped" then
    clear()
  end
end

local function onCrawlResultsShown(eventData)
  local time = eventData.time
  local points = eventData.points
  local damage = eventData.damage

  log('I', logTag, string.format('Showing crawl results - Time: %.2fs, Points: %d, Damage: %.2f', time, points, damage))

      -- Save the player's score and time
  if M.activeTrail and M.activeTrail.trail then
    local trailId = M.activeTrail.trail._filePath or M.activeTrail.trail.id
    if trailId then
      local result = gameplay_crawl_saveSystem.addNewPlayerScore(trailId, time, points, damage)

      -- Log new records (no tasklist notifications for crawl)
      if result and result.isNewBestTime then
        log('I', logTag, string.format('New best time for trail %s: %.2fs', trailId, result.bestTime))
      end

      if result and result.isNewBestPenaltyPoints then
        log('I', logTag, string.format('New best penalty points for trail %s: %d', trailId, result.bestPenaltyPoints))
      end
    end
  end
end

M.clear = clear
M.onGetRawPoiListForLevel = onGetRawPoiListForLevel
M.onActivityAcceptGatherData = onActivityAcceptGatherData
M.onActivityIndexVisible = onActivityIndexVisible
M.onDrawOnMinimap = onDrawOnMinimap
M.onExtensionLoaded = onExtensionLoaded
M.onSerialize = onSerialize
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleDestroyed = onVehicleDestroyed
M.onAnyMissionChanged = onAnyMissionChanged
M.onCrawlResultsShown = onCrawlResultsShown
M.onUpdate = onUpdate
M.startCrawl = startCrawl

return M