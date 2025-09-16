-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local logTag = "crawl_boundary"

local spawnedBoundaryMarkersId = nil -- Track the boundary markers group
local boundaryObjects = {} -- Table to track boundary objects and their info
local visibilityRadius = 100 -- Hide markers beyond this distance (in meters)

-- Animation settings
local animationDuration = 0.5 -- Animation duration in seconds
local fadeInDuration = 0.3 -- Fade in duration
local fadeOutDuration = 0.2 -- Fade out duration
local scaleUpDuration = 0.4 -- Scale up duration
local maxScale = 1.0 -- Final scale
local minScale = 0.1 -- Starting scale for scale up animation

-- Quadtree for efficient spatial queries (using existing BeamNG implementation)
local boundaryQuadtree = nil
local quadtreeBounds = nil




-- Build quadtree from boundary objects
local function buildBoundaryQuadtree()
  if not boundaryObjects or not next(boundaryObjects) then
    return
  end

  -- Calculate 2D bounds (ignore Z for quadtree)
  local minX, minY = math.huge, math.huge
  local maxX, maxY = -math.huge, -math.huge

  for _, objectInfo in pairs(boundaryObjects) do
    local pos = objectInfo.finalPosition
    minX = math.min(minX, pos.x)
    minY = math.min(minY, pos.y)
    maxX = math.max(maxX, pos.x)
    maxY = math.max(maxY, pos.y)
  end

  quadtreeBounds = {minX = minX, minY = minY, maxX = maxX, maxY = maxY}

  -- Create new quadtree
  local quadtree = require('quadtree')
  boundaryQuadtree = quadtree.newQuadtree()

  -- Preload all objects into quadtree
  for objectId, objectInfo in pairs(boundaryObjects) do
    local pos = objectInfo.finalPosition
    -- Use a small bounding box around each point (1m x 1m)
    boundaryQuadtree:preLoad(objectId, pos.x - 0.5, pos.y - 0.5, pos.x + 0.5, pos.y + 0.5)
  end

  -- Build the quadtree
  boundaryQuadtree:build(6) -- Max depth of 6 should be sufficient

  log('I', logTag, string.format('Built quadtree with %d objects, bounds: %.1f x %.1f',
    #boundaryObjects, maxX - minX, maxY - minY))
end


-- Function to update boundary object visibility (kept for compatibility with utils.lua)
local function updateBoundaryAnimations(dtSim)
  if not boundaryObjects then
    return
  end

  -- Get current player position once per frame (not camera)
  local playerPos = nil
  if gameplay_crawl_utils and gameplay_crawl_utils.getPlayerPosition then
    playerPos = gameplay_crawl_utils.getPlayerPosition()
  else
    -- Fallback to camera position if no player position available
    playerPos = getCameraPosition()
  end

  if not playerPos then
    return
  end

  -- Use quadtree for efficient querying if available
  if boundaryQuadtree then
    local visibleObjects = {}

    -- Query quadtree for objects within visibility radius
    -- Create a bounding box around the player position
    local queryX, queryY = playerPos.x, playerPos.y
    local queryRadius = visibilityRadius

    -- Query quadtree for objects in the area
    for objectId in boundaryQuadtree:queryNotNested(
      queryX - queryRadius, queryY - queryRadius,
      queryX + queryRadius, queryY + queryRadius
    ) do
      -- Check if object is actually within the circular radius
      local objectInfo = boundaryObjects[objectId]
      if objectInfo and playerPos:distance(objectInfo.finalPosition) <= queryRadius then
        table.insert(visibleObjects, objectId)
      end
    end

    -- Create lookup table for visible objects
    local visibleLookup = {}
    for _, objectId in ipairs(visibleObjects) do
      visibleLookup[objectId] = true
    end

    -- Update objects with animations
    for objectId, objectInfo in pairs(boundaryObjects) do
      local obj = scenetree.findObjectById(objectId)
      if obj then
        local isCurrentlyVisible = visibleLookup[objectId] or false
        local wasVisible = objectInfo.lastVisible

        -- Handle visibility changes
        if isCurrentlyVisible and not wasVisible then
          -- Object just became visible - start appearing animation
          objectInfo.animationState = "appearing"
          objectInfo.animationTimer = 0
          obj.hidden = false
        elseif not isCurrentlyVisible and wasVisible then
          -- Object just became hidden - start disappearing animation
          objectInfo.animationState = "disappearing"
          objectInfo.animationTimer = 0
        end

        -- Update animation state
        if objectInfo.animationState == "appearing" then
          objectInfo.animationTimer = objectInfo.animationTimer + dtSim

          if objectInfo.animationTimer >= animationDuration then
            -- Animation complete
            objectInfo.animationState = "visible"
            objectInfo.animationTimer = 0
            obj:setScale(vec3(maxScale, maxScale, maxScale))
            obj:setField('instanceColor', 0, '1 1 1 1')
          else
            -- Update scale and alpha during appearing animation
            local scaleT = math.min(objectInfo.animationTimer / scaleUpDuration, 1.0)
            local alphaT = math.min(objectInfo.animationTimer / fadeInDuration, 1.0)

            local currentScale = lerp(minScale, maxScale, smootherstep(scaleT))
            local currentAlpha = lerp(0.0, 1.0, smootherstep(alphaT))

            obj:setScale(vec3(currentScale, currentScale, currentScale))
            obj:setField('instanceColor', 0, string.format('1 1 1 %.2f', currentAlpha))
          end

        elseif objectInfo.animationState == "disappearing" then
          objectInfo.animationTimer = objectInfo.animationTimer + dtSim

          if objectInfo.animationTimer >= fadeOutDuration then
            -- Animation complete - hide object
            objectInfo.animationState = "hidden"
            objectInfo.animationTimer = 0
            obj.hidden = true
          else
            -- Update alpha during disappearing animation
            local alphaT = 1.0 - (objectInfo.animationTimer / fadeOutDuration)
            local currentAlpha = lerp(0.0, 1.0, smootherstep(alphaT))

            obj:setField('instanceColor', 0, string.format('1 1 1 %.2f', currentAlpha))
          end

        elseif objectInfo.animationState == "visible" then
          -- Object is fully visible and stable
          obj:setScale(vec3(maxScale, maxScale, maxScale))
          obj:setField('instanceColor', 0, '1 1 1 1')
        end

        -- Update last visible state
        objectInfo.lastVisible = isCurrentlyVisible

      else
        -- Object no longer exists, remove from tracking
        boundaryObjects[objectId] = nil
      end
    end
  end
end



-- Function to reset boundary objects tracking
local function resetBoundaryObjects()
  -- Reset all objects to hidden state before clearing
  for objectId, objectInfo in pairs(boundaryObjects) do
    local obj = scenetree.findObjectById(objectId)
    if obj then
      obj.hidden = true
      obj:setScale(vec3(minScale, minScale, minScale))
      obj:setField('instanceColor', 0, '1 1 1 0')
    end
  end

  boundaryObjects = {}
  log('I', logTag, 'Reset boundary objects tracking')
end

-- Utility function to spawn flag markers along crawl boundary
local function spawnBoundaryMarkers(boundary, spacing)
  if not boundary or not boundary.vertices or #boundary.vertices < 3 then
    log('W', logTag, 'Invalid boundary for spawning markers')
    return
  end

  spacing = spacing or 2.0 -- Default spacing of 2 meters

  -- Clean up existing boundary markers
  if spawnedBoundaryMarkersId then
    local group = scenetree.findObjectById(spawnedBoundaryMarkersId)
    if group then
      group:delete()
    end
    spawnedBoundaryMarkersId = nil
  end

  -- Reset boundary objects tracking
  resetBoundaryObjects()

  -- Create a new group for boundary markers
  local markerGroup = createObject("SimGroup")
  markerGroup:registerObject(Sim.getUniqueName("BoundaryMarkers"))
  scenetree.MissionGroup:addObject(markerGroup)
  spawnedBoundaryMarkersId = markerGroup:getId()

  local flagMeshPath = "/art/shapes/race/flagMarker.dae"
  local points = {}

  -- Generate points along the boundary perimeter
  for i, vertex in ipairs(boundary.vertices) do
    local nextIdx = vertex.next or (i == #boundary.vertices and 1 or i + 1)
    local nextVertex = boundary.vertices[nextIdx]

    local startPos = vertex.pos
    local endPos = nextVertex.pos
    local segmentLength = startPos:distance(endPos)

    -- Calculate number of markers for this segment
    local numMarkers = math.floor(segmentLength / spacing)
    if numMarkers < 1 then numMarkers = 1 end

        -- Generate points along this segment
    for j = 0, numMarkers - 1 do
      local t = j / numMarkers
      local pos = lerp(startPos, endPos, t)

      -- Align to terrain
      if core_terrain then
        pos.z = core_terrain.getTerrainHeight(pos) or pos.z
      else
        pos.z = be:getSurfaceHeightBelow(pos + vec3(0, 0, 1)) + 0.1
      end

      -- Calculate direction vector along the boundary
      local dirVec = (endPos - startPos):normalized()
      local dirVecUp = vec3(0, 0, 1)

      -- Get terrain normal for proper alignment
      if core_terrain then
        dirVecUp = core_terrain.getTerrainSmoothNormal(pos)
      else
        dirVecUp = map.surfaceNormal(pos, 1)
      end

      -- Create rotation from direction and up vector
      local rot = quatFromDir(dirVec, dirVecUp)

      table.insert(points, {pos = pos, rot = rot})
    end
  end

    -- Spawn flag markers at calculated positions
  for i, point in ipairs(points) do
    local name = Sim.getUniqueName("BoundaryFlag_" .. i)
    local marker = createObject('TSStatic')
    marker:setField('shapeName', 0, flagMeshPath)
    marker.scale = vec3(1, 1, 1)
    marker.useInstanceRenderData = true
    marker:setField('instanceColor', 0, '1 1 1 1')
    marker:setInternalName('boundaryMarker')
    marker.canSave = false
    marker:registerObject(name)

              -- Store object info for tracking
      local objectId = marker:getId()
      boundaryObjects[objectId] = {
        finalPosition = vec3(point.pos),
        animationState = "hidden", -- hidden, appearing, visible, disappearing
        animationTimer = 0,
        lastVisible = false
      }

         -- Set marker at final position with initial animation state
     marker:setPosRot(point.pos.x, point.pos.y, point.pos.z, point.rot.x, point.rot.y, point.rot.z, point.rot.w)
     marker:setScale(vec3(minScale, minScale, minScale)) -- Start small
     marker:setField('instanceColor', 0, '1 1 1 0') -- Start transparent
     marker:updateInstanceRenderData()

    markerGroup:addObject(marker)
    -- Note: The marker IDs are not added to spawnedPrefabIds here since they're managed separately
    -- in the boundary module. The cleanup is handled by the markerGroup deletion.
  end

     -- Build quadtree for efficient spatial queries
   buildBoundaryQuadtree()

  log('I', logTag, string.format('Spawned %d boundary markers along crawl boundary', #points))
  return spawnedBoundaryMarkersId
end

-- Function to manually spawn boundary markers for a given boundary
local function spawnBoundaryMarkersForBoundary(boundary, spacing)
  if not boundary then
    log('E', logTag, 'No boundary provided for spawning markers')
    return nil
  end
  return spawnBoundaryMarkers(boundary, spacing or 2.0)
end

-- Function to remove only boundary markers
local function removeBoundaryMarkers()
  if spawnedBoundaryMarkersId then
    local group = scenetree.findObjectById(spawnedBoundaryMarkersId)
    if group then
      group:delete()
    end
    spawnedBoundaryMarkersId = nil
    log('I', logTag, 'Removed boundary markers')
  end

  -- Reset tracking
  resetBoundaryObjects()
end

-- Function to clean up boundary markers (called from unloadPrefabs)
local function cleanupBoundaryMarkers()
  if spawnedBoundaryMarkersId then
    local group = scenetree.findObjectById(spawnedBoundaryMarkersId)
    if group then
      group:delete()
    end
    spawnedBoundaryMarkersId = nil
  end

  -- Reset tracking
  resetBoundaryObjects()
end

local function checkBoundary(site, crawler, crawlStates)
  if not site then
    log('E', logTag, 'No site data available')
    return false
  end

  local state = crawlStates and crawlStates[crawler.id]
  if not state or not state.active then
    return false
  end

  -- Check if any corner of the vehicle is outside the boundary
  local currentCorners = crawler.dynamicData.currentCorners
  if not currentCorners or #currentCorners == 0 then
    -- Fallback to center position if no corners available
    local vehPos = crawler.dynamicData.bbCenter
    if site:containsPoint2D(vehPos) then
      return true
    else
      -- Single point outside - disqualify
      state.events.disqualified = true
      state.events.disqualificationTime = state.currentTime
      log('W', logTag, string.format('Player disqualified for crawler %s - center outside boundaries', crawler.id))
      return false
    end
  end

  -- Count how many corners are outside the boundary
  local outsideCorners = 0
  local totalCorners = #currentCorners

  for i, corner in ipairs(currentCorners) do
    if not site:containsPoint2D(corner) then
      outsideCorners = outsideCorners + 1
    end
  end

  -- If all corners are outside, disqualify
  if outsideCorners >= totalCorners then
    if not state.events.disqualified then
      state.events.disqualified = true
      state.events.disqualificationTime = state.currentTime
      log('W', logTag, string.format('Player disqualified for crawler %s - all %d corners outside boundaries', crawler.id, totalCorners))
    end
    return false
  end

  if outsideCorners > 0 then
    if gameplay_crawl_utils.onBoundaryViolation then
      gameplay_crawl_utils.onBoundaryViolation(crawler.id)
      log('W', logTag, string.format('Boundary violation penalty for crawler %s - %d/%d corners outside', crawler.id, outsideCorners, totalCorners))
    end
  end

  return true
end

-- Function to set visibility radius for boundary markers
local function setVisibilityRadius(radius)
  visibilityRadius = radius or 200
  log('I', logTag, string.format('Set boundary markers visibility radius to %d meters', visibilityRadius))
end

-- Function to set animation timing
local function setAnimationTiming(duration, fadeIn, fadeOut, scaleUp)
  animationDuration = duration or 0.5
  fadeInDuration = fadeIn or 0.3
  fadeOutDuration = fadeOut or 0.2
  scaleUpDuration = scaleUp or 0.4

  log('I', logTag, string.format('Set animation timing: duration=%.1fs, fadeIn=%.1fs, fadeOut=%.1fs, scaleUp=%.1fs',
    animationDuration, fadeInDuration, fadeOutDuration, scaleUpDuration))
end

-- Function to rebuild quadtree (useful if boundary objects change)
local function rebuildQuadtree()
  buildBoundaryQuadtree()
end

-- Function to get quadtree statistics for debugging
local function getQuadtreeStats()
  if not boundaryQuadtree then
    return {built = false, objectCount = 0}
  end

  return {
    built = true,
    objectCount = #boundaryObjects,
    bounds = quadtreeBounds
  }
end

-- Function to trigger appearing animation for all currently visible objects
local function triggerAppearingAnimation()
  if not boundaryObjects then
    return
  end

  for objectId, objectInfo in pairs(boundaryObjects) do
    local obj = scenetree.findObjectById(objectId)
    if obj and not obj.hidden then
      -- Reset to initial animation state
      objectInfo.animationState = "appearing"
      objectInfo.animationTimer = 0
      objectInfo.lastVisible = true

      -- Set initial visual state
      obj:setScale(vec3(minScale, minScale, minScale))
      obj:setField('instanceColor', 0, '1 1 1 0')
      obj.hidden = false
    end
  end

  log('I', logTag, 'Triggered appearing animation for visible boundary markers')
end

-- Export functions
M.spawnBoundaryMarkers = spawnBoundaryMarkers
M.spawnBoundaryMarkersForBoundary = spawnBoundaryMarkersForBoundary
M.removeBoundaryMarkers = removeBoundaryMarkers
M.cleanupBoundaryMarkers = cleanupBoundaryMarkers
M.checkBoundary = checkBoundary
M.updateBoundaryAnimations = updateBoundaryAnimations
M.resetBoundaryObjects = resetBoundaryObjects
M.setVisibilityRadius = setVisibilityRadius
M.setAnimationTiming = setAnimationTiming
M.rebuildQuadtree = rebuildQuadtree
M.getQuadtreeStats = getQuadtreeStats
M.triggerAppearingAnimation = triggerAppearingAnimation

return M
