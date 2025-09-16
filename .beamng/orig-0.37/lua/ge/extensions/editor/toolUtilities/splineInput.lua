-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- This is a utility class for handling mouse and keyboard events across various spline-editing tools.

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- User constants.
local isMouseMoveTolSq = 0.0001 -- The tolerance for determining if the mouse is moving, in squared meters per frame.
local heightSensitivity = 1 -- The sensitivity of the height adjustment, in meters per pixel.

local joinDist = 15.0 -- The max distance considered, for loop/join formation, in meters.

local minSplineWidth, maxSplineWidth = 3.0, 200.0 -- The minimum and maximum widths for a spline, in meters.
local minSplineHeight, maxSplineHeight = 0.0, 70.0 -- The minimum and maximum heights for a spline, in meters.
local defaultSplineVel, defaultSplineVelLimit = 13.5, 70.0 -- The default velocity and velocity limit for a spline node, in meters per second.

local timeUntilTextAppears = 1.0 -- The time it takes for the text to appear when adding a new node, in seconds.

local intsctTol = 10000.0 -- The tolerance for hit detection, in meters.
local baseHitScale = 0.2  -- A base factor used to scale the hit detection tolerance.

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local M = {}

-- Module dependencies.
local meshSplineMgr = require('editor/meshSpline/splineMgr')
local masterSplineMgr = require('editor/masterSpline/splineMgr')
local assemblySplineMgr = require('editor/assemblySpline/splineMgr')
local decalSplineMgr = require('editor/decalSpline/splineMgr')
local drivePathSplineMgr = require('editor/drivePathEditor/splineMgr')
local roadSplineGroupMgr = require('editor/roadSpline/groupMgr')
local geom = require('editor/toolUtilities/geom')
local render = require('editor/toolUtilities/render')
local gizmo = require('editor/toolUtilities/gizmo')
local util = require('editor/toolUtilities/util')

-- Module constants.
local im = ui_imgui
local min, max, ceil, sqrt = math.min, math.max, math.ceil, math.sqrt
local globalUp = vec3(0, 0, 1)
local joinDistSq = joinDist * joinDist
local altKeyIdx, ctrlKeyIdx, shiftKeyIdx = im.GetKeyIndex(im.Key_ModAlt), im.GetKeyIndex(im.Key_ModCtrl), im.GetKeyIndex(im.Key_ModShift)
local delKeyIdx, cKeyIdx, vKeyIdx = im.GetKeyIndex(im.Key_Delete), im.GetKeyIndex(im.Key_C), im.GetKeyIndex(im.Key_V)
local meshPrefix = meshSplineMgr.getToolPrefixStr()
local masterPrefix = masterSplineMgr.getToolPrefixStr()
local assemblyPrefix = assemblySplineMgr.getToolPrefixStr()
local decalPrefix = decalSplineMgr.getToolPrefixStr()
local drivePathPrefix = drivePathSplineMgr.getToolPrefixStr()
local roadPrefix = roadSplineGroupMgr.getToolPrefixStr()
local toolUIModules = { -- Tool UI module names for runtime requiring when setting selection.
  [meshPrefix] = 'editor_meshSpline',
  [masterPrefix] = 'editor_masterSpline', 
  [assemblyPrefix] = 'editor_assemblySpline',
  [decalPrefix] = 'editor_decalSpline',
  [drivePathPrefix] = 'editor_drivePathEditor',
  [roadPrefix] = 'editor_roadSpline',
}
local toolGetSplines = { -- Jump table for getting splines from each compatible tool.
  [meshPrefix] = meshSplineMgr.getMeshSplines,
  [masterPrefix] = masterSplineMgr.getMasterSplines,
  [assemblyPrefix] = assemblySplineMgr.getAssemblySplines,
  [decalPrefix] = decalSplineMgr.getDecalSplines,
  [drivePathPrefix] = drivePathSplineMgr.getDrivePathSplines,
  [roadPrefix] = roadSplineGroupMgr.getGroups,
}
local toolModeKeys = { -- Jump table for getting the mode key from each compatible tool.
  [meshPrefix] = meshSplineMgr.getEditModeKey,
  [masterPrefix] = masterSplineMgr.getEditModeKey,
  [assemblyPrefix] = assemblySplineMgr.getEditModeKey,
  [decalPrefix] = decalSplineMgr.getEditModeKey,
  [drivePathPrefix] = drivePathSplineMgr.getEditModeKey,
  [roadPrefix] = roadSplineGroupMgr.getEditModeKey,
}
local toolDeepCopyFuncs = { -- Jump table for getting the deep copy function from each compatible tool.
  [meshPrefix] = meshSplineMgr.deepCopyMeshSpline,
  [masterPrefix] = masterSplineMgr.deepCopyMasterSpline,
  [assemblyPrefix] = assemblySplineMgr.deepCopyAssemblySpline,
  [decalPrefix] = decalSplineMgr.deepCopyDecalSpline,
  [drivePathPrefix] = drivePathSplineMgr.deepCopyDrivePathSpline,
  [roadPrefix] = roadSplineGroupMgr.deepCopyGroup,
}
local typeScales = { -- The scale factors for the different hit types.
  node = 0.9,
  rib = 1.1,
  bar = 1.1,
}

-- Module state.
local mouseLastRawY = 0.0
local lastAltDown, hasDeletePressedRecently = false, false
local dragSplineIdx, dragNodeIdx, dragStatePre, isDragRib, isDragBar, dragRibIsFirstHandle = nil, nil, nil, nil, nil, nil
local isLoopAvailable, isJoinAvailable = false, false
local joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2 = nil, nil, nil, nil
local ctrlCProfile = nil
local hasPastePressedRecently = false
local markupTimer, markupTime, restTimer, restTime = hptimer(), 0.0, hptimer(), 0.0
local candType, candDist, candSplineIdx, candNodeIdx, candRibIdx = {}, {}, {}, {}, {}
local candIdxLower, candPHit, candPriority, hitCandidates, tmpTable = {}, {}, {}, {}, {}
local allSplines, splineToolNames = {}, {}
local mouseVel2D, mouseLast, binVec = vec3(), vec3(), vec3()
local lastDragMousePos = vec3()


-- Handles end drag events (loop formation, joins, cleanup).
local function handleEndDragEvents(splines, selSpline, copyFn, copyStateFn, joinFn, undoFn, redoFn, undoStateFn, redoStateFn, afterEndDragFn, isShiftDown)
  if dragStatePre then
    -- If there is a loop available and SHIFT is held, form the loop.
    if isLoopAvailable and isShiftDown then
      local fullStatePre = copyFn(selSpline)
      local lastIdx = #selSpline.nodes
      table.remove(selSpline.nodes, lastIdx)
      table.remove(selSpline.widths, lastIdx)
      table.remove(selSpline.nmls, lastIdx)
      selSpline.isLoop = true
      selSpline.isDirty = true
      isLoopAvailable = false
      editor.history:commitAction("Drag Loop", { old = fullStatePre, new = copyFn(selSpline) }, undoFn, redoFn, true)
      dragStatePre, isDragRib, isDragBar, dragSplineIdx, dragNodeIdx, dragRibIsFirstHandle = nil, nil, nil, nil, nil, nil -- Reset drag state.
      return false
    end

    -- If there is a join available and SHIFT is held, form the join.
    if isJoinAvailable and isShiftDown and joinFn and copyStateFn then
      local fullStatePre = copyStateFn()
      joinFn(joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2)
      isJoinAvailable = false
      joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2 = nil, nil, nil, nil
      editor.history:commitAction("Drag Join", { old = fullStatePre, new = copyStateFn() }, undoStateFn, redoStateFn, true)
      dragStatePre, isDragRib, isDragBar, dragSplineIdx, dragNodeIdx, dragRibIsFirstHandle = nil, nil, nil, nil, nil, nil -- Reset drag state.
      return true -- Indicate join was handled.
    end

    -- End the drag.
    editor.history:commitAction("Drag", { old = dragStatePre, new = copyFn(splines[dragSplineIdx]) }, undoFn, redoFn, true)
    if afterEndDragFn then
      afterEndDragFn(selSpline)
    end
  end

  -- Reset the drag state.
  dragStatePre, isDragRib, isDragBar, dragSplineIdx, dragNodeIdx, dragRibIsFirstHandle = nil, nil, nil, nil, nil, nil

  return false
end

-- Handles bar dragging operations.
local function handleBarDragging(selSpline, mouseRawY, isBarsLimits, isLockShape, isShiftDown)
  local vals = isBarsLimits and selSpline.velLimits or selSpline.vels -- Determine which data the bars represent.
  local delta = (mouseLastRawY - mouseRawY) * heightSensitivity -- Calculate the magnitude of the drag.
  if isShiftDown then
    delta = delta * 0.1 -- Apply precision scaling when SHIFT is held.
  end
  if isLockShape then -- Rigid translation.
    for i = 1, #vals do
      vals[i] = max(minSplineHeight, min(maxSplineHeight, vals[i] + delta))
    end
  else -- A single bar is being dragged.
    vals[dragNodeIdx] = max(minSplineHeight, min(maxSplineHeight, vals[dragNodeIdx] + delta))
  end
  local barPts = selSpline.barPoints
  if barPts and barPts[dragNodeIdx] then
    render.drawSphereHighlight(barPts[dragNodeIdx])
  end
  selSpline.isDirty = true
end

-- Handles rib dragging operations.
local function handleRibDragging(selSpline, isLockShape, isShiftDown)
  -- Calculate the magnitude of the drag.
  local widths = selSpline.widths
  local ribPoints, dragNodeIdxTimesTwo, delta = selSpline.ribPoints, dragNodeIdx * 2, 0.0
  local isHalfSpline = selSpline.tileSet ~= nil or selSpline.spacing ~= nil
  if isHalfSpline then -- Half-spline.
    local ribPoint = ribPoints[dragNodeIdxTimesTwo]
    render.drawSphereHighlight(ribPoint)
    render.markupWidthDisplay(ribPoint, widths[dragNodeIdx])
    local divIdx = selSpline.discMap[dragNodeIdx]
    delta = mouseVel2D:dot(selSpline.binormals[divIdx])
  else -- Full spline.
    local p1, p2 = ribPoints[dragNodeIdxTimesTwo], ribPoints[dragNodeIdxTimesTwo - 1]
    render.drawSphereHighlight(p1)
    render.drawSphereHighlight(p2)
    render.markupWidthDisplay(p1, widths[dragNodeIdx])
    binVec:setSub2(p2, p1)
    binVec:normalize()
    local handleSign = dragRibIsFirstHandle and -1 or 1
    delta = handleSign * mouseVel2D:dot(binVec)
  end

  -- Apply precision scaling when SHIFT is held.
  if isShiftDown then
    delta = delta * 0.1
  end

  -- Move the widths appropriately.
  if isLockShape then -- Move all widths by the same amount.
    for i = 1, #widths do
      widths[i] = max(minSplineWidth, min(maxSplineWidth, widths[i] + delta))
    end
  else -- Move a single width.
    widths[dragNodeIdx] = max(minSplineWidth, min(maxSplineWidth, widths[dragNodeIdx] + delta))
  end

  selSpline.isDirty = true
end

-- Handles node dragging and formation detection (loops/joins).
local function handleNodeDragging(splines, out, mousePos, isLockShape)
  -- Translate the nodes appropriately.
  local nodes = splines[dragSplineIdx].nodes
  if isLockShape then -- Rigid translation.
    for i = 1, #nodes do
      nodes[i]:setAdd(mouseVel2D)
    end
  else -- A single node is being dragged.
    -- Calculate offset from initial positions to prevent jumping
    local offset = mousePos - mouseLast
    nodes[dragNodeIdx]:setAdd(offset)
  end

  -- Check for loop candidate (start to end/end to start of the same spline).
  local numNodes = #nodes
  isLoopAvailable = false
  if (dragNodeIdx == 1 or dragNodeIdx == numNodes) and numNodes > 3 and not splines[out.spline].isLoop then
    local nodeStart, nodeEnd = nodes[1], nodes[numNodes]
    if nodeStart:squaredDistance(nodeEnd) < joinDistSq then
      render.renderCandidateLoop(nodeStart, nodeEnd) -- Show a line joining the start and end nodes, to indicate a loop is possible.
      isLoopAvailable = true -- Mark that we have a loop candidate.
    end
  end

  -- Check for join candidate (between two separate splines of the same tool).
  isJoinAvailable = false
  if (dragNodeIdx == 1 or dragNodeIdx == numNodes) and not isLoopAvailable and numNodes > 1 then
    local draggedNode, isDraggingStart = nodes[dragNodeIdx], dragNodeIdx == 1
    for i = 1, #splines do -- Check the selected spline against all other splines in the tool.
      local otherSpline = splines[i]
      if i ~= out.spline and otherSpline.isEnabled and not otherSpline.isLink and not otherSpline.isLoop then
        local otherNodes = otherSpline.nodes
        if #otherNodes > 1 then
          local otherStart, otherEnd = otherNodes[1], otherNodes[#otherNodes]
          local distToStart, distToEnd = draggedNode:squaredDistance(otherStart), draggedNode:squaredDistance(otherEnd)
          local canJoinToStart, canJoinToEnd = distToStart < joinDistSq, distToEnd < joinDistSq
          if isDraggingStart and canJoinToStart then -- Start to start of other spline.
            render.renderCandidateJoin(draggedNode, otherStart)
            joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2, isJoinAvailable = out.spline, 1, i, 1, true
            break
          elseif not isDraggingStart and canJoinToStart then -- End to start of other spline.
            render.renderCandidateJoin(draggedNode, otherStart)
            joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2, isJoinAvailable = out.spline, numNodes, i, 1, true
            break
          elseif isDraggingStart and canJoinToEnd then -- Start to end of other spline.
            render.renderCandidateJoin(draggedNode, otherEnd)
            joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2, isJoinAvailable = out.spline, 1, i, #otherNodes, true
            break
          elseif not isDraggingStart and canJoinToEnd then -- End to end of other spline.
            render.renderCandidateJoin(draggedNode, otherEnd)
            joinSplineIdx1, joinNodeIdx1, joinSplineIdx2, joinNodeIdx2, isJoinAvailable = out.spline, numNodes, i, #otherNodes, true
            break
          end
        end
      end
    end -- End of loop through splines.
  end

  -- Only set dirty flag if mouse has moved enough to warrant an update.
  local mouseMoveDistanceSq = mousePos:squaredDistance(lastDragMousePos)
  if mouseMoveDistanceSq > isMouseMoveTolSq then
    splines[dragSplineIdx].isDirty = true
    lastDragMousePos:set(mousePos) -- Update last position for next frame.
  end
end

-- Updates timers and mouse state
local function updateTimersAndMouseState(mouseRawY, mousePos)
  -- Update the markup timer.
  local deltaTime = markupTimer:stopAndReset() * 0.001
  markupTime = markupTime > deltaTime and markupTime - deltaTime or -1.0

  -- Update the rest timer.
  local restDelta = restTimer:stopAndReset() * 0.001
  restTime = restTime > restDelta and restTime - restDelta or -1.0

  -- Update the mouse state.
  mouseLastRawY, mouseLast = mouseRawY, mousePos
end

-- Calculates distance-adaptive tolerance for hit detection
-- [rayPos - Camera ray position]
-- [targetPos - Position of the target (node/rib/bar)]
-- [targetType - 'node', 'rib', or 'bar' for different scaling]
local function getAdaptiveTolerance(rayPos, targetPos, targetType)
  local distance = rayPos:distance(targetPos)
  local visualScale = sqrt(distance) -- Scale the tolerance as distance increases.
  local typeScale = typeScales[targetType] -- Get the type-specific scaling.
  return baseHitScale * visualScale * typeScale
end

-- Sort function for hit candidates by priority and distance.
local function sortCandidatesByPriorityAndDistance(a, b)
  if candPriority[a] ~= candPriority[b] then
    return candPriority[a] < candPriority[b] -- Lower priority number = higher actual priority.
  end
  return candDist[a] < candDist[b] -- Closer distance wins.
end

-- Aggregates splines from all tools into module-scope arrays for cross-tool hit detection.
-- [Returns the total number of splines collected.]
local function getAllSplines()
  table.clear(allSplines)
  table.clear(splineToolNames)
  local ctr = 1

  -- Mesh splines.
  local meshSplines = meshSplineMgr.getMeshSplines()
  for i = 1, #meshSplines do
    allSplines[ctr], splineToolNames[ctr] = meshSplines[i], meshPrefix
    ctr = ctr + 1
  end

  -- Master splines.
  local masterSplines = masterSplineMgr.getMasterSplines()
  for i = 1, #masterSplines do
    allSplines[ctr], splineToolNames[ctr] = masterSplines[i], masterPrefix
    ctr = ctr + 1
  end

  -- Assembly splines.
  local assemblySplines = assemblySplineMgr.getAssemblySplines()
  for i = 1, #assemblySplines do
    allSplines[ctr], splineToolNames[ctr] = assemblySplines[i], assemblyPrefix
    ctr = ctr + 1
  end

  -- Decal splines.
  local decalSplines = decalSplineMgr.getDecalSplines()
  for i = 1, #decalSplines do
    allSplines[ctr], splineToolNames[ctr] = decalSplines[i], decalPrefix
    ctr = ctr + 1
  end

  -- Drive path splines.
  local drivePathSplines = drivePathSplineMgr.getDrivePathSplines()
  for i = 1, #drivePathSplines do
    allSplines[ctr], splineToolNames[ctr] = drivePathSplines[i], drivePathPrefix
    ctr = ctr + 1
  end

  -- Road splines (uses groups instead of splines).
  local roadGroups = roadSplineGroupMgr.getGroups()
  for i = 1, #roadGroups do
    allSplines[ctr], splineToolNames[ctr] = roadGroups[i], roadPrefix
    ctr = ctr + 1
  end

  return ctr
end

-- Optimized hit detection that prioritizes by distance to resolve selection conflicts.
-- Returns the best hit target based on closest distance to camera ray.
-- Always checks splines from all tools for cross-tool selection.
-- [SelSpline - The currently selected spline.]
-- [MousePos - The 3D mouse position.]
-- [UseRibs - Whether to check rib handles.]
-- [UseBars - Whether to check bar handles.]
local function getBestHitTarget(selSpline, mousePos, useRibs, useBars)
  -- Get the latest camera-to-mouse ray.
  local ray = getCameraMouseRay()
  local rayPos, rayDir = ray.pos, ray.dir

  -- Get all splines from all compatible tools.
  getAllSplines()

  -- Check nodes first (highest priority).
  table.clear(candType); table.clear(candDist); table.clear(candSplineIdx)
  table.clear(candNodeIdx); table.clear(candRibIdx); table.clear(candIdxLower)
  table.clear(candPHit); table.clear(candPriority)
  local numSplines, ctr = #allSplines, 1
  for i = 1, numSplines do
    local spline = allSplines[i]
    if spline.isEnabled and not spline.isLink then
      local nodes = spline.nodes
      for j = 1, #nodes do
        local adaptiveTol = getAdaptiveTolerance(rayPos, nodes[j], 'node')
        local intA, intB = intersectsRay_Sphere(rayPos, rayDir, nodes[j], adaptiveTol)
        if intA and intB then
          local dist = min(intA, intB)
          if dist < intsctTol then
            candType[ctr], candDist[ctr], candSplineIdx[ctr], candNodeIdx[ctr], candPriority[ctr] = 'node', dist, i, j, 1
            ctr = ctr + 1
          end
        end
      end
    end
  end

  -- Check ribs (width handles) - only for the selected spline.
  if useRibs and selSpline and selSpline.isEnabled and not selSpline.isLink then
    local ribPoints = selSpline.ribPoints
    if ribPoints then
      local numRibPoints = #ribPoints
      if numRibPoints > 0 then
        -- Find the selected spline index in allSplines array.
        local selSplineIdx = nil
        for i = 1, numSplines do
          if allSplines[i] == selSpline then
            selSplineIdx = i
            break
          end
        end
        if selSplineIdx then
          local isHalfSpline = selSpline.tileSet ~= nil or selSpline.spacing ~= nil -- Check if the spline is a half-spline.
          if isHalfSpline then -- For half-splines, only check even-indexed ribs.
            for j = 2, numRibPoints, 2 do
              local adaptiveTol = getAdaptiveTolerance(rayPos, ribPoints[j], 'rib')
              local intA, intB = intersectsRay_Sphere(rayPos, rayDir, ribPoints[j], adaptiveTol)
              if intA and intB then
                local dist = min(intA, intB)
                if dist < intsctTol then
                  candType[ctr], candDist[ctr], candSplineIdx[ctr], candRibIdx[ctr], candPriority[ctr] = 'rib', dist, selSplineIdx, j, 2
                  ctr = ctr + 1
                end
              end
            end
          else -- For full splines, check all rib points.
            for j = 1, numRibPoints do
              local adaptiveTol = getAdaptiveTolerance(rayPos, ribPoints[j], 'rib')
              local intA, intB = intersectsRay_Sphere(rayPos, rayDir, ribPoints[j], adaptiveTol)
              if intA and intB then
                local dist = min(intA, intB)
                if dist < intsctTol then
                  candType[ctr], candDist[ctr], candSplineIdx[ctr], candRibIdx[ctr], candPriority[ctr] = 'rib', dist, selSplineIdx, j, 2
                  ctr = ctr + 1
                end
              end
            end
          end
        end
      end
    end
  end

  -- Check bars (height handles) - only for the selected spline.
  if useBars and selSpline and selSpline.isEnabled and not selSpline.isLink then
    local barPoints = selSpline.barPoints
    if barPoints then
      local numBarPoints = #barPoints
      if numBarPoints > 0 then
        -- Find the selected spline index in allSplines array.
        local selSplineIdx = nil
        for i = 1, numSplines do
          if allSplines[i] == selSpline then
            selSplineIdx = i
            break
          end
        end
        if selSplineIdx then
          for j = 1, numBarPoints do
            local adaptiveTol = getAdaptiveTolerance(rayPos, barPoints[j], 'bar')
            local intA, intB = intersectsRay_Sphere(rayPos, rayDir, barPoints[j], adaptiveTol)
            if intA and intB then
              local dist = min(intA, intB)
              if dist < intsctTol then
                candType[ctr], candDist[ctr], candSplineIdx[ctr], candNodeIdx[ctr], candPriority[ctr] = 'bar', dist, selSplineIdx, j, 3
                ctr = ctr + 1
              end
            end
          end
        end
      end
    end
  end

  -- Check spline for node insertion (only for selected spline).
  if selSpline and selSpline.isEnabled and not selSpline.isLink then
    local isOverSpline, idxLower, pHit = geom.isMouseOverSpline(selSpline, mousePos)
    if isOverSpline and pHit then
      candType[ctr], candDist[ctr], candIdxLower[ctr], candPHit[ctr], candPriority[ctr] = 'spline', pHit:distance(rayPos), idxLower, pHit, 4
      ctr = ctr + 1
    end
  end

  -- Early return if no candidates were found.
  if ctr == 1 then
    return nil
  end

  -- Build indices array for sorting.
  local numCandidates = ctr - 1
  table.clear(hitCandidates)  -- Clear any stale indices from previous frames.
  for i = 1, numCandidates do
    hitCandidates[i] = i
  end

  -- Sort indices by priority first, then by distance.
  table.sort(hitCandidates, sortCandidatesByPriorityAndDistance)

  -- Return best candidate.
  local bestIdx = hitCandidates[1]
  tmpTable.type = candType[bestIdx]
  tmpTable.dist = candDist[bestIdx]
  tmpTable.splineIdx = candSplineIdx[bestIdx]
  tmpTable.nodeIdx = candNodeIdx[bestIdx]
  tmpTable.ribIdx = candRibIdx[bestIdx]
  tmpTable.idxLower = candIdxLower[bestIdx]
  tmpTable.pHit = candPHit[bestIdx]
  tmpTable.priority = candPriority[bestIdx]

  -- Include tool information for cross-tool detection.
  if bestIdx then
    tmpTable.toolName = splineToolNames[candSplineIdx[bestIdx]]
  else
    tmpTable.toolName = nil
  end

  return tmpTable
end


-- Handles the user input events for spline-editing tools.
-- Splines are user-editable polylines along the centerline of a variable width. They can be used to create roads, paths, etc.
-- [Splines - The collection of splines to handle events for.]
-- [Out - A table which contains the following common fields (will be updated as the user interacts with the splines):]
  -- [SelSplineIdx - The index of the selected spline.]
  -- [SelNodeIdx - The index of the selected node.]
  -- [SelLayerIdx - The index of the selected layer. NOTE: This is only used for the 'decal placement' case.]
  -- [IsGizmoActive - A flag which indicates whether the gizmo is active.]
-- [IsRotEnabled - A flag which indicates whether the rotation gizmo is enabled.]
-- [IsConformToTerrain - A flag which indicates whether the spline should be conform to the surface below, or not. Used for vertical gizmo control.]
-- [UseRibs - A flag which indicates whether to use ribs (handles for width adjustment).]
-- [UseBars - A flag which indicates whether to use bars (handles for height adjustment).]
-- [IsBarsLimits - A flag which indicates whether the bars are limits (true) or velocities (false).]
-- [UseCopyPaste - A flag which indicates whether to use the copy/paste profile feature.]
-- [UseGizmo - A flag which indicates whether to use gizmo.]
-- [IsLockShape - A flag which indicates whether the shape of the spline is locked, or not.]
-- [DefaultSplineWidth - The default width for a spline when adding a new node, in meters.]
-- [DeepCopyFunct - A function which deep copies a spline.]
-- [DeepCopyStateFunct - A function which deep copies the state of a spline.]
-- [CopyProfileFunct - A function which copies a profile.]
-- [PasteProfileFunct - A function which pastes a profile.]
-- [RibStartDragCallback - A function which is called when the user starts dragging a rib.]
-- [AfterEndDragCallback - A function which is called when the user ends dragging.]
-- [JoinFunct - A function which is called when the user forms a join.]
-- [UndoFunct - The undo callback function for a single spline edit.]
-- [RedoFunct - The redo callback function for a single spline edit.]
-- [UndoStateFunct - The undo callback function for the full spline state edit.]
-- [RedoStateFunct - The redo callback function for the full spline state edit.]
local function handleSplineEvents(
  splines, out,
  isRotEnabled, isConformToTerrain, useRibs, useBars, isBarsLimits, useCopyPaste, useGizmo, isLockShape,
  defaultSplineWidth,
  deepCopyFunct, deepCopyStateFunct, copyProfileFunct, pasteProfileFunct, afterEndDragCallback, joinFunct,
  undoFunct, redoFunct, undoStateFunct, redoStateFunct)

  -- Update the mouse position and velocity.
  local mousePos = util.mouseOnMapPos()
  local mouseRawY = im.GetMousePos().y
  mouseVel2D:set(mousePos.x - mouseLast.x, mousePos.y - mouseLast.y, 0.0)
  local isShiftDown, isAltDown, isCtrlDown = im.IsKeyDown(shiftKeyIdx), im.IsKeyDown(altKeyIdx), im.IsKeyDown(ctrlKeyIdx)
  local isCDown, isVDown, isDelDown = im.IsKeyDown(cKeyIdx), im.IsKeyDown(vKeyIdx), im.IsKeyDown(delKeyIdx)

  -- Manage the rest timer.
  if mouseVel2D:squaredLength() > isMouseMoveTolSq then
    restTime = timeUntilTextAppears
  end

  -- Get the selected spline (may be nil if no splines or invalid selection).
  local selSpline = splines[out.spline]

  -- Scene-only events (when mouse is hovering over the terrain).
  if util.isMouseHoveringOverTerrain() then
    -- Draw the mouse cursor (inactive if no selection or selected spline disabled) and show appropriate delayed markup.
    local isActive = selSpline ~= nil and selSpline.isEnabled == true
    render.drawSphereCursor(mousePos, isActive)
    if restTime < 0.0 then
      if selSpline and not selSpline.isEnabled then
        render.markupSelectedSplineDisabled(mousePos)
      elseif not selSpline then
        render.markupSelectOrAdd(mousePos)
      end
    end

    -- Handle 'end drag' events.
    if not im.IsMouseDown(0) then
      local joinHandled = handleEndDragEvents(splines, selSpline, deepCopyFunct, deepCopyStateFunct, joinFunct, undoFunct, redoFunct, undoStateFunct, redoStateFunct, afterEndDragCallback, isShiftDown)
      if joinHandled then return end
    end

    -- Handle active dragging events.
    if dragSplineIdx then
      if isDragBar then -- User is dragging a bar.
        handleBarDragging(selSpline, mouseRawY, isBarsLimits, isLockShape, isShiftDown)
      elseif isDragRib then -- User is dragging a rib.
        handleRibDragging(selSpline, isLockShape, isShiftDown)
      else -- User is dragging a node.
        handleNodeDragging(splines, out, mousePos, isLockShape)
      end
      mouseLast, mouseLastRawY = mousePos, mouseRawY
      return -- Early return if currently dragging.
    end

    -- Handle 'add node' and 'start dragging' events.
    local bestHit = getBestHitTarget(selSpline, mousePos, useRibs, useBars)
    if bestHit then
      local bestHitType = bestHit.type
      if bestHitType == 'node' then -- 'Hover-Over-Node' events.
        local hoverSplineIdx, hoverNodeIdx = bestHit.splineIdx, bestHit.nodeIdx

        -- Check if this is a cross-tool hit (from another spline tool).
        if bestHit.toolName and bestHit.toolName ~= editor.editMode.displayName then
          local targetSpline = allSplines[hoverSplineIdx]
          if targetSpline and targetSpline.isEnabled then
            render.drawSphereHighlightHover(targetSpline.nodes[hoverNodeIdx])
            render.markupSelectSpline(targetSpline.nodes[hoverNodeIdx]) -- Show selection prompt.
            if im.IsMouseClicked(0) then -- Only switch tools on click, not hover.
              local getSplinesFn = toolGetSplines[bestHit.toolName] -- Switch to the appropriate tool using jump table lookup.
              local getModeKeyFn = toolModeKeys[bestHit.toolName]
              if getSplinesFn and getModeKeyFn then
                local modeKey = getModeKeyFn() -- Call the function to get the actual mode key
                local targetSplines = getSplinesFn()
                if targetSplines and modeKey then
                  local actualSplineIdx = nil -- Find the actual index within the target tool's splines.
                  for i = 1, #targetSplines do
                    if targetSplines[i] == targetSpline then
                      actualSplineIdx = i
                      break
                    end
                  end
                  if actualSplineIdx then
                    editor.selectEditMode(editor.editModes[modeKey])
                    local uiModuleName = toolUIModules[bestHit.toolName]
                    local toolUIModule = extensions[uiModuleName] -- Get the UI module of the tool which is being switched to.
                    toolUIModule.setSelectedSplineIdx(actualSplineIdx) -- Set the selected spline index in the tool.
                    toolUIModule.setSelectedNodeIdx(hoverNodeIdx) -- Set the selected node index in the tool.
                    if not targetSpline.isLink then -- Initialise drag state only if the spline is not linked.
                      local targetDeepCopyFn = toolDeepCopyFuncs[bestHit.toolName]
                      if targetDeepCopyFn then
                        dragStatePre = targetDeepCopyFn(targetSplines[actualSplineIdx])
                        isDragRib, dragSplineIdx, dragNodeIdx = false, actualSplineIdx, hoverNodeIdx
                        mouseLast = mousePos
                      end
                    end
                  end
                end
              end
            end
          end
          return -- Don't process further in this frame.
        end

        -- Regular same-tool hit detection.
        -- Convert allSplines index to current tool's splines index.
        local targetSpline = allSplines[hoverSplineIdx]
        local actualSplineIdx = nil
        for i = 1, #splines do
          if splines[i] == targetSpline then
            actualSplineIdx = i
            break
          end
        end

        if actualSplineIdx and splines[actualSplineIdx].isEnabled then
          local actualHoverSplineIdx = actualSplineIdx
          render.drawSphereHighlightHover(splines[actualHoverSplineIdx].nodes[hoverNodeIdx])
          if actualHoverSplineIdx ~= out.spline then
            render.markupSelectSpline(splines[actualHoverSplineIdx].nodes[hoverNodeIdx])
          elseif not dragSplineIdx and not im.IsMouseDown(0) and markupTime < 0.0 then
            render.markupDrag(splines[actualHoverSplineIdx].nodes[hoverNodeIdx])
          end
          if im.IsMouseClicked(0) then
              out.spline, out.node = actualHoverSplineIdx, hoverNodeIdx
              if not splines[actualHoverSplineIdx].isLink then -- Only allow dragging if the spline is not linked.
                dragStatePre = deepCopyFunct(splines[actualHoverSplineIdx])
                isDragRib, dragSplineIdx, dragNodeIdx = false, actualHoverSplineIdx, hoverNodeIdx
              end
          end
        end
      elseif bestHitType == 'rib' then -- 'Hover-Over-Rib' events.
        -- Rib hit detection (ribs are only shown for selected spline in current tool).
        local ribSplineIdx, ribIdx = bestHit.splineIdx, bestHit.ribIdx
        local spline = allSplines[ribSplineIdx] -- Use allSplines index, not current tool's splines
        if spline and spline.isEnabled then
          local ribPts = spline.ribPoints
          render.drawSphereHighlightHover(ribPts[ribIdx])
          local isHalfSpline = spline.tileSet ~= nil or spline.spacing ~= nil -- Check if the spline is a half-spline.
          if not isHalfSpline then
            local idx2 = ribIdx % 2 == 0 and ribIdx - 1 or ribIdx + 1
            render.drawSphereHighlightHover(ribPts[idx2]) -- Only highlight the odd rib if we have a full spline.
          end
          if not dragSplineIdx then
            render.markupAdjustWidth(ribPts[ribIdx])
          end
          if im.IsMouseClicked(0) then
            local nodeIdx = ceil(ribIdx * 0.5)
            -- Only allow rib dragging if the spline is not linked.
            if not spline.isLink then
              dragStatePre = deepCopyFunct(spline)
              isDragRib, dragSplineIdx, dragNodeIdx = true, out.spline, nodeIdx
              dragRibIsFirstHandle = ribIdx % 2 == 0
              mouseLastRawY = mouseRawY
              out.node = nodeIdx
            end
            mouseLast = mousePos
            return
          end
        end
      elseif bestHitType == 'bar' then -- 'Hover-Over-Bar' events.
        -- Bar hit detection (bars are only shown for selected spline in current tool).
        local barSplineIdx, barNodeIdx = bestHit.splineIdx, bestHit.nodeIdx
        local spline = allSplines[barSplineIdx] -- Use allSplines index, not current tool's splines
        if spline and spline.isEnabled then
          local barPts = spline.barPoints
          render.drawSphereHighlightHover(barPts[barNodeIdx])
          if not dragSplineIdx then
            render.markupAdjustBar(barPts[barNodeIdx])
          end
          if im.IsMouseClicked(0) then
            if not spline.isLink then -- Only allow bar dragging if the spline is not linked.
              dragStatePre = deepCopyFunct(spline)
              isDragBar, dragSplineIdx, dragNodeIdx = true, out.spline, barNodeIdx
              mouseLastRawY = mouseRawY
              out.node = barNodeIdx
            end
            mouseLast = mousePos
            return
          end
        end
      elseif bestHitType == 'spline' then -- 'Hover-Over-Spline' events.
        if selSpline and selSpline.isEnabled and not selSpline.isLink then
          local idxLower, pHit = bestHit.idxLower, bestHit.pHit
          render.drawSphereHighlightHover(pHit)
          render.drawSphereNode(pHit)
          if not dragSplineIdx and not im.IsMouseDown(0) and markupTime < 0.0 then
            render.markupInsertNode(pHit)
          end
          if im.IsMouseClicked(0) then
            local splinePre = deepCopyFunct(selSpline)
            local tableIdx = idxLower + 1
            table.insert(selSpline.nodes, tableIdx, vec3(pHit))
            local widths, nmls = selSpline.widths, selSpline.nmls
            local isLoop = selSpline.isLoop
            local n = #widths
            local iPrev = tableIdx - 1
            local iNext = tableIdx
            if isLoop then
              iPrev, iNext = ((iPrev - 1) % n) + 1, ((iNext - 1) % n) + 1
            end
            local lerpWidth = (widths[iPrev] + widths[iNext]) * 0.5
            table.insert(widths, tableIdx, lerpWidth)
            local lerpNormal = lerp(nmls[iPrev], nmls[iNext], 0.5)
            table.insert(nmls, tableIdx, lerpNormal)
            if useBars then
              local vels, velLimits = selSpline.vels, selSpline.velLimits
              local lerpVel = (vels[iPrev] + vels[iNext]) * 0.5
              local lerpVelLimit = (velLimits[iPrev] + velLimits[iNext]) * 0.5
              table.insert(vels, tableIdx, lerpVel)
              table.insert(velLimits, tableIdx, lerpVelLimit)
            end
            out.node = tableIdx
            markupTime = timeUntilTextAppears
            selSpline.isDirty = true
            editor.history:commitAction("Insert Node", { old = splinePre, new = deepCopyFunct(selSpline) }, undoFunct, redoFunct)
          end
        end
      end
    else -- 'Hover-Over-Free-Space' events.
      if selSpline and selSpline.isEnabled then
        if restTime < 0.0 then
          if selSpline.isLink then
            render.markupLinkedSplineCannotAdd(mousePos)
          elseif selSpline.isLoop then
            render.markupLoopedSplineCannotAdd(mousePos)
          else
            render.markupAddNode(mousePos)
          end
        end
        if im.IsMouseClicked(0) and not selSpline.isLoop and not selSpline.isLink then
          local statePre = deepCopyFunct(selSpline)
          local selNodes, selWidths, selNmls, selVels, selVelLimits = selSpline.nodes, selSpline.widths, selSpline.nmls, selSpline.vels, selSpline.velLimits
          if #selNodes > 1 then
            if mousePos:squaredDistance(selNodes[1]) < mousePos:squaredDistance(selNodes[#selNodes]) then
              table.insert(selNodes, 1, vec3(mousePos))
              table.insert(selWidths, 1, selWidths[1])
              table.insert(selNmls, 1, vec3(selNmls[1] or globalUp))
              if useBars then
                table.insert(selVels, 1, selVels[1])
                table.insert(selVelLimits, 1, selVelLimits[1])
              end
              out.node = 1
            else
              table.insert(selNodes, vec3(mousePos))
              table.insert(selWidths, selWidths[#selWidths])
              table.insert(selNmls, vec3(selNmls[#selNmls]))
              if useBars then
                table.insert(selVels, selVels[#selVels])
                table.insert(selVelLimits, selVelLimits[#selVelLimits])
              end
              out.node = #selNodes
            end
          else
            selNodes[#selNodes + 1] = vec3(mousePos)
            table.insert(selWidths, #selWidths > 0 and selWidths[#selWidths] or defaultSplineWidth)
            table.insert(selNmls, vec3(selNmls[#selNmls] or globalUp))
            if useBars then
              table.insert(selVels, selVels[#selVels] or defaultSplineVel)
              table.insert(selVelLimits, selVelLimits[#selVelLimits] or defaultSplineVelLimit)
            end
            out.node = #selNodes
          end
          markupTime = timeUntilTextAppears
          selSpline.isDirty = true
          editor.history:commitAction("Add Node", { old = statePre, new = deepCopyFunct(selSpline) }, undoFunct, redoFunct, true)
        end
      end
    end
  end

  -- Handle node deletion using the delete key.
  if selSpline and not selSpline.isLink and selSpline.isEnabled then
    if isDelDown then
      if not hasDeletePressedRecently and out.node > 0 and out.node <= #selSpline.nodes then
        local splinePre = deepCopyFunct(selSpline)
        table.remove(selSpline.nodes, out.node)
        table.remove(selSpline.widths, out.node)
        table.remove(selSpline.nmls, out.node)
        out.node = max(1, min(#selSpline.nodes, out.node))
        selSpline.isDirty = true
        editor.history:commitAction("Delete Node", { old = splinePre, new = deepCopyFunct(selSpline) }, undoFunct, redoFunct, true)
        hasDeletePressedRecently = true
      end
    else
      hasDeletePressedRecently = false -- Only allows one time use of the delete key.
    end
  end

  -- If requested, manage the ALT key for toggling the gizmo on/off.
  if useGizmo then
    if isAltDown and isAltDown ~= lastAltDown then
      out.isGizmoActive = not out.isGizmoActive
    end
    if out.isGizmoActive then -- Handle the gizmo for translation, if it is active.
      gizmo.handleGizmo(isRotEnabled, out.spline, out.node, splines, isConformToTerrain, isLockShape, deepCopyFunct, undoFunct, redoFunct)
    end
    lastAltDown = isAltDown
  end

  -- Check if the user is attempting to copy/paste a profile.
  if useCopyPaste then
    if isCtrlDown and isCDown and out.spline then
      ctrlCProfile = copyProfileFunct(splines[out.spline])
    end
    if isCtrlDown and isVDown and ctrlCProfile and out.spline and not hasPastePressedRecently then
      local splinePre = deepCopyFunct(splines[out.spline])
      pasteProfileFunct(splines[out.spline], ctrlCProfile)
      editor.history:commitAction("Paste Profile", { old = splinePre, new = deepCopyFunct(splines[out.spline]) }, undoFunct, redoFunct, true)
      hasPastePressedRecently = true
    end
    if not isVDown then
      hasPastePressedRecently = false -- Only allows one time use of the paste key.
    end
  end

  -- Update timers and mouse state.
  updateTimersAndMouseState(mouseRawY, mousePos)
end

-- Handles the user input events for spline-editing tools.
-- Splines are user-editable polylines along the centerline of a variable width. They can be used to create roads, paths, etc.
-- [SelSpline - The selected spline.]
-- [Nodes - The collection of navigation graph nodes to handle events for.]
-- [DeepCopyFunct - A function which deep copies a spline.]
-- [UndoFunct - The undo callback function for a single spline edit.]
-- [RedoFunct - The redo callback function for a single spline edit.]
-- [isBarsLimit - Whether to use velLimits (true) or vels (false) for bar heights.]
local function handleNavGraphEvents(selSpline, nodes, deepCopyFunct, undoFunct, redoFunct, isBarsLimit)
  -- Update the mouse position and velocity, and cache the current mouse state.
  local mouseRawY = im.GetMousePos().y -- The current raw mouse y-position (2D).
  local mousePos = util.mouseOnMapPos() -- The current mouse position on the map (3D).
  mouseVel2D:set(mousePos.x - mouseLast.x, mousePos.y - mouseLast.y, 0.0) -- The 2D mouse velocity (XY).
  if mouseVel2D:squaredLength() > isMouseMoveTolSq then
    restTime = timeUntilTextAppears -- Reset the rest time when the mouse is moving.
  end

  -- Scene-only events (when mouse is hovering over the terrain).
  if util.isMouseHoveringOverTerrain() then
    -- Draw the mouse cursor (inactive when no selection).
    render.drawSphereCursor(mousePos, selSpline ~= nil)

    -- Handle 'end bar drag' events.
    if not im.IsMouseDown(0) then
      if dragStatePre then
        editor.history:commitAction("Drag Bar", { old = dragStatePre, new = deepCopyFunct(selSpline) }, undoFunct, redoFunct, true)
        dragStatePre = nil
      end
      isDragBar, dragNodeIdx = nil, nil
    end

    -- Handle any active bar dragging events.
    if isDragBar then
      local vals = isBarsLimit and selSpline.velLimits or selSpline.vels -- The velocities of the spline nodes.
      if not vals then
        vals = selSpline.vels
      end
      if not vals or #vals == 0 then
        vals = {}
        for i = 1, #selSpline.barPoints do
          vals[i] = defaultSplineVel
        end
        if isBarsLimit then
          selSpline.velLimits = vals
        else
          selSpline.vels = vals
        end
      end
      local delta = (mouseLastRawY - mouseRawY) * heightSensitivity -- The vertical mouse velocity.
      vals[dragNodeIdx] = max(minSplineHeight, min(maxSplineHeight, vals[dragNodeIdx] + delta)) -- Move bar of the selected node by rel. amount.
      selSpline.isDirty = true
    end

    -- Handle 'add node' and 'start dragging' events.
    local isMouseOverHandle = false
    local isOverNode, hoverNodeKey = geom.isMouseOverGraphNode(nodes)
    isMouseOverHandle = isMouseOverHandle or isOverNode
    if isOverNode then -- 'Hover-Over-Node' events.
      render.drawSphereHighlight(nodes[hoverNodeKey]) -- Draw a highlight when the mouse is over a graph node.
      if not im.IsMouseDown(0) and markupTime < 0.0 then
        render.markupGraphNodeHover(nodes[hoverNodeKey]) -- Draw a special markup when the mouse is over a graph node.
      end
      if im.IsMouseClicked(0) then
        local statePre = deepCopyFunct(selSpline)
        local doesContain, idx = util.doesPathContainNode(selSpline.graphNodes, hoverNodeKey)
        if doesContain then
          table.remove(selSpline.graphNodes, idx) -- Path contains the node already, so remove it.
          table.remove(selSpline.vels, idx) -- Remove the velocity for the node.
          if selSpline.velLimits then
            table.remove(selSpline.velLimits, idx) -- Remove the velocity limit for the node.
          end
        else
          table.insert(selSpline.graphNodes, hoverNodeKey) -- Path does not contain the node, so add it (to end).
          table.insert(selSpline.vels, defaultSplineVel) -- Add a default velocity for the new node.
          if selSpline.velLimits then
            table.insert(selSpline.velLimits, defaultSplineVel) -- Add a default velocity limit for the new node.
          end
        end
        -- Immediately update barPoints to match the new graphNodes array.
        local graphData = { nodes = nodes }
        geom.updateBarPointsGraph(selSpline, graphData, isBarsLimit)
        selSpline.isDirty = true
        editor.history:commitAction("Change Path", { old = statePre, new = deepCopyFunct(selSpline) }, undoFunct, redoFunct)
        markupTime = timeUntilTextAppears
      end
    else -- Not over a node.
      tmpTable[1] = selSpline
      local isOverBar, _, barNodeIdx = geom.isMouseOverBar(tmpTable)
      isMouseOverHandle = isMouseOverHandle or isOverBar
        if isOverBar then -- 'Hover-Over-Bar' events.
        local barPts = selSpline.barPoints
          render.drawSphereHighlightHover(barPts[barNodeIdx]) -- Pulsing highlight (same as ribs)
        if not dragSplineIdx then
          render.markupAdjustBar(barPts[barNodeIdx]) -- Markup when the mouse is over a bar.
        end
        if im.IsMouseClicked(0) then
          dragStatePre = deepCopyFunct(selSpline)
          isDragBar, dragNodeIdx = true, barNodeIdx
          mouseLastRawY = mouseRawY
          mouseLast = mousePos
          return
        end
      else -- 'Hover-Over-Free-Space' events.
        if restTime < 0.0 and not isMouseOverHandle then
          render.markupGraphFreeSpace(mousePos) -- Markup when the mouse is over free space.
        end
      end
    end
  end

  -- Manage the markup event timers.
  -- [Timers run from some positive value when set, then decrement beyond zero. Events are triggered when the timers drop below zero.]
  local deltaTime = markupTimer:stopAndReset() * 0.001
  markupTime = markupTime > deltaTime and markupTime - deltaTime or -1.0
  local restDelta = restTimer:stopAndReset() * 0.001
  restTime = restTime > restDelta and restTime - restDelta or -1.0

  -- Update the mouse position data.
  mouseLast, mouseLastRawY = mousePos, mouseRawY
end


-- Public interface.
M.handleSplineEvents =                                  handleSplineEvents
M.handleNavGraphEvents =                                handleNavGraphEvents

return M