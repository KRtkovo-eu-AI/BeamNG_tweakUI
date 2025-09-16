-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- User constants.
local doiMultFactor = 2.5 -- The multiplier for the AABB margin.

local globalSmoothRadius = 4 -- The number of grid cells to smooth over.

local defaultFbmLacunarity = 2.0 -- Frequency multiplier per octave.
local defaultFbmGain = 0.5 -- Amplitude multiplier per octave.

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local M = {}

-- External modules.
local toolMgr = require('editor/toolManager')
local geom = require('editor/toolUtilities/geom')
local perlin = require('editor/toolUtilities/perlin') -- Currently unused, since simplex is preferred.
local simplex = require('editor/toolUtilities/simplex')

-- Module constants.
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil
local sqrt, huge = math.sqrt, math.huge

-- Module state.
local final, mod, mask, height = {}, {}, {}, {}
local sdf, closestX, closestY = {}, {}, {}
local globalTemp = {}
local gMin, gMax, tmpPoint2I = Point2I(0, 0), Point2I(0, 0), Point2I(0, 0)
local tmp1, tmp2 = vec3(), vec3()


-- Maps the given roughness and scale to the appropriate low-level noise parameters.
local function mapNoiseParameters(roughness, scale)
  roughness, scale = clamp(roughness, 0, 1), clamp(scale, 0, 1) -- Clamp the input roughness and scale to the range [0, 1].
  local noiseStrength = lerp(0.0, 1.0, roughness) -- Amplitude mapping.
  local noiseFreq = lerp(0.02, 0.2, scale) -- Frequency mapping: large bumps ~ 50m wavelength => freq ~= 0.02, small bumps ~ 5m wavelength => freq ~= 0.2.
  local fbmOctaves = floor(lerp(3, 6, scale) + 0.5) -- Octave mapping: avoid flickering patterns (three layers), richer detail (six layers).
  return noiseFreq, noiseStrength, fbmOctaves, defaultFbmLacunarity, defaultFbmGain
end

-- Undo callback for terraforming operations.
local function terraformUndo(data)
  local tb = extensions.editor_terrainEditor.getTerrainBlock()
  if not tb then
    return -- Early return if no terrain block.
  end

  -- Remove all spline meshes before terraforming to prevent collision mesh conflicts.
  toolMgr.removeAllSplineToolMeshes()

  local xMin, xMax, yMin, yMax = huge, -huge, huge, -huge
  for i = 1, #data do
    local d = data[i]
    local dx, dy = d.x, d.y
    tb:setHeight(dx, dy, max(0.0, d.old))
    xMin, xMax = min(xMin, dx), max(xMax, dx)
    yMin, yMax = min(yMin, dy), max(yMax, dy)
  end
  tmp1:set(xMin, yMin, 0)
  tmp2:set(xMax, yMax, 0)
  tb:updateGrid(tmp1, tmp2)
end

-- Redo callback for terraforming operations.
local function terraformRedo(data)
  local tb = extensions.editor_terrainEditor.getTerrainBlock()
  if not tb then
    return -- Early return if no terrain block.
  end

  -- Remove all spline meshes before terraforming to prevent collision mesh conflicts.
  toolMgr.removeAllSplineToolMeshes()

  local xMin, xMax, yMin, yMax = huge, -huge, huge, -huge
  for i = 1, #data do
    local d = data[i]
    local dx, dy = d.x, d.y
    tb:setHeight(dx, dy, max(0.0, d.new))
    xMin, xMax = min(xMin, dx), max(xMax, dx)
    yMin, yMax = min(yMin, dy), max(yMax, dy)
  end
  tmp1:set(xMin, yMin, 0)
  tmp2:set(xMax, yMax, 0)
  tb:updateGrid(tmp1, tmp2)
end

-- Terraforms the heightmap using the given terraforming data.
-- [Also commits the modification to support undo/redo].
local function modifyTerrainFromHeightArray(xSize, ySize, bXMin, bXMax, bYMin, bYMax, tb)
  local history, hCtr = {}, 1
  for x = 0, xSize - 1 do
    local rx = x + bXMin
    for y = 0, ySize - 1 do
      local idx = y * xSize + x
      if mod[idx] > 0.5 then
        local ry = y + bYMin
        local z = final[idx]
        local zOld = max(0, tb:getHeightGrid(rx, ry))
        tb:setHeightGrid(rx, ry, max(0, z))
        history[hCtr] = { old = zOld, new = z, x = rx, y = ry }
        hCtr = hCtr + 1
      end
    end
  end

  -- Update the terrain block.
  tmp1:set(bXMin, bYMin, 0)
  tmp2:set(bXMax, bYMax, 0)
  tb:updateGrid(tmp1, tmp2)
  editor_terrainEditor.setTerrainDirty()

  -- Commit the terraforming action to the undo/redo history.
  editor.history:commitAction("Terraform", history, terraformUndo, terraformRedo, true)
end

-- Blurs the heightmap using the given radius.
local function blur(xSize, ySize)
  -- X pass.
  table.clear(globalTemp)
  for x = 0, xSize - 1 do
    for y = 0, ySize - 1 do
      local idx = y * xSize + x
      local sum, count = 0.0, 0
      local yTimesXSize = y * xSize
      for dx = -globalSmoothRadius, globalSmoothRadius do
        local nx = x + dx
        local nIdx = yTimesXSize + nx
        if nx >= 0 and nx < xSize then
          sum = sum + final[nIdx]
          count = count + 1
        end
      end
      globalTemp[idx] = count > 0 and sum / count or final[idx]
    end
  end

  -- Y pass (with fade-in for outer non-modified points near mod zone).
  for x = 0, xSize - 1 do
    for y = 0, ySize - 1 do
      local idx = y * xSize + x
      local isMod = mod[idx] == 1
      local sum, count = 0.0, 0
      local influence = 0
      for dy = -globalSmoothRadius, globalSmoothRadius do
        local ny = y + dy
        if ny >= 0 and ny < ySize then
          local nIdx = ny * xSize + x
          sum = sum + globalTemp[nIdx]
          count = count + 1
          influence = influence + (mod[nIdx] or 0)
        end
      end
      if isMod then
        final[idx] = count > 0 and sum / count or globalTemp[idx]
      elseif influence > 0 then -- Blend softened final value toward blur only if neighbours were affected.
        local w = clamp(influence / (2 * globalSmoothRadius + 1), 0, 1)
        final[idx] = lerp(final[idx], sum / count, w)
      end
    end
  end
end

-- Fractal Brownian Motion.
local function fbm(x, y, octaves, lacunarity, gain)
  local total, frequency, amplitude, maxAmplitude = 0, 1, 1, 0
  for _ = 1, octaves do
    total = total + simplex.noise(x * frequency, y * frequency) * amplitude
    maxAmplitude = maxAmplitude + amplitude
    amplitude = amplitude * gain
    frequency = frequency * lacunarity
  end
  return total / maxAmplitude
end

-- Attempts to update the SDF for the given grid point, if better than the current value.
local function tryUpdate(x, y, nx, ny, xSize, ySize)
  if nx < 0 or ny < 0 or nx > xSize or ny > ySize then
    return
  end
  local nIdx = ny * xSize + nx
  local cx, cy = closestX[nIdx], closestY[nIdx]
  if cx and cy and cx >= 0 and cy >= 0 then
    local dx, dy = x - cx, y - cy
    local dist = dx * dx + dy * dy
    local idx = y * xSize + x
    if dist < sdf[idx] * sdf[idx] then
      sdf[idx] = sqrt(dist)
      closestX[idx], closestY[idx] = cx, cy
    end
  end
end

-- Terraform heightmap based on quad weights and an SDF falloff.
-- Terraforms the current heightmap using the given terraforming data.
-- The sources structure is an array containing each source element (eg a road).
-- Each source element is an array containing ordered polyline points with the following structure:
-- { pos = vec3(x, y, z), width = f, binormal = vec3(x, y, z) }.
-- 'DOI' (Domain of Influence) is the max distance at which the terraforming will affect, in meters.
-- 'margin' is the distance which the terraforming will affect the outer edge of the sources, in meters.
-- 'falloffExp' is the falloff exponent for the terraforming.
-- 'roughness' and 'scale' are the roughness and scale of the noise, respectively.
local function terraformToSources(DOI, margin, falloffExp, roughness, scale, sources)
  local tb = extensions.editor_terrainEditor.getTerrainBlock()
  local te = extensions.editor_terrainEditor.getTerrainEditor()
  if not sources or not tb or not te then
    return -- Early return if no sources, terrain block, or terrain editor.
  end

  -- Remove all spline meshes before terraforming to prevent collision mesh conflicts.
  toolMgr.removeAllSplineToolMeshes()

  -- Get the terrain block's world box.
  local extents = tb:getWorldBox():getExtents()
  local center = tb:getWorldBox():getCenter()
  local centerX, centerY = center.x, center.y
  local xHalf, yHalf = extents.x * 0.5, extents.y * 0.5
  local tXMin, tXMax = centerX - xHalf, centerX + xHalf
  local tYMin, tYMax = centerY - yHalf, centerY + yHalf
  local zMin = tb:getPosition().z

  -- Get the AABB of the union of sources.
  local box = geom.computeSourcesAABB(sources)
  DOI = max(5.0, DOI)
  local boxPad = DOI * doiMultFactor -- Expand the AABB by more than the DOI, to ensure fall off to zero.
  box.xMin = box.xMin - boxPad
  box.xMax = box.xMax + boxPad
  box.yMin = box.yMin - boxPad
  box.yMax = box.yMax + boxPad

  -- Get the grid bounds of the union of sources.
  tmp1:set(floor(max(tXMin, box.xMin)), floor(max(tYMin, box.yMin)), 0)
  tmp2:set(ceil(min(tXMax, box.xMax)), ceil(min(tYMax, box.yMax)), 0)
  te:worldToGridByPoint2I(tmp1, gMin, tb)
  te:worldToGridByPoint2I(tmp2, gMax, tb)
  local bXMin, bXMax, bYMin, bYMax = gMin.x, gMax.x, gMin.y, gMax.y
  local xSize, ySize = bXMax - bXMin + 1, bYMax - bYMin + 1

  -- Get the quadrilaterals of the sources and populate a kd-tree with them.
  local quads = geom.getAllQuadrilaterals(sources, margin)
  local tree = geom.populateTreeQuads(quads)

  -- Initialize the height, mask, SDF, and closest X/Y arrays.
  table.clear(mod); table.clear(mask);
  table.clear(height); table.clear(sdf);
  table.clear(closestX); table.clear(closestY)
  for x = 0, xSize - 1 do
    local gX = bXMin + x
    for y = 0, ySize - 1 do
      local idx = y * xSize + x
      local gY = bYMin + y
      tmpPoint2I.x, tmpPoint2I.y = gX, gY
      local pWS = te:gridToWorldByPoint2I(tmpPoint2I, tb)
      local pWSX, pWSY, z = pWS.x, pWS.y, nil
      for tIdx in tree:queryNotNested(pWSX, pWSY, pWSX, pWSY) do
        local hitZ = geom.intersectsUpQuadBarycentric(pWS, quads[tIdx]) -- Sample using bilinear interpolation over the quad.
        if hitZ then
          z = min(hitZ - zMin, z or huge)
        end
      end
      if z then -- This grid point is directly underneath the source, so it's a mask.
        height[idx] = z -- Use the sampled height of the source here.
        mask[idx] = 1
        sdf[idx] = 0 -- Set the SDF here, since we know its zero.
        mod[idx] = 1
        closestX[idx], closestY[idx] = x, y
      else -- This grid point is not directly underneath the source, so it's not a mask.
        height[idx] = tb:getHeightGrid(gX, gY) -- Use the original terrain height here. 
        mask[idx] = 0
        sdf[idx] = huge -- Set the SDF to infinity for now.
        mod[idx] = 0
        closestX[idx], closestY[idx] = -1, -1
      end
    end
  end

  -- Propagate the SDF.
  for _ = 1, 2 do -- Number of passes.
    for x = 0, xSize - 1 do -- Forward pass.
      for y = 0, ySize - 1 do
        tryUpdate(x, y, x - 1, y, xSize, ySize) -- Try to update the SDF for the recti neighbours.
        tryUpdate(x, y, x + 1, y, xSize, ySize)
        tryUpdate(x, y, x, y - 1, xSize, ySize)
        tryUpdate(x, y, x, y + 1, xSize, ySize)
      end
    end
    for x = xSize - 1, 0, -1 do -- Backward pass.
      for y = ySize - 1, 0, -1 do
        tryUpdate(x, y, x - 1, y, xSize, ySize) -- Try to update the SDF for the recti neighbours.
        tryUpdate(x, y, x + 1, y, xSize, ySize)
        tryUpdate(x, y, x, y - 1, xSize, ySize)
        tryUpdate(x, y, x, y + 1, xSize, ySize)
      end
    end
  end

  -- Diffuse the heightmap based on the SDF.
  local DOIInv = 1.0 / DOI
  table.clear(final)
  for x = 0, xSize - 1 do
    local bXMinPlusX = bXMin + x
    for y = 0, ySize - 1 do
      local original = tb:getHeightGrid(bXMinPlusX, bYMin + y) -- Original height of the grid point.
      local idx = y * xSize + x
      local dist = sdf[idx]
      if mask[idx] == 1 then
        final[idx] = height[idx] -- If the grid point is a mask, use the height of the source here.
        mod[idx] = 1 -- Set the mod array to 1 to indicate that the grid point is within the DOI.
      elseif dist <= DOI then
        local cx, cy = closestX[idx], closestY[idx]
        local ribbonZ = (cx and cy and cx >= 0 and cy >= 0) and height[cy * xSize + cx] or original
        local w = clamp((1.0 - dist * DOIInv) ^ falloffExp, 0, 1) -- Weight of blend, based non-linearly on distance to ribbon.
        final[idx] = lerp(original, ribbonZ, w) -- If grid point within DOI, blend between original height and ribbon height.
        mod[idx] = 1 -- Set the mod array to 1 to indicate that the grid point is within the DOI.
      else
        final[idx] = original -- If the grid point is outside the DOI, use the original height here.
      end
    end
  end

  -- Apply noise, if requested.
  if roughness > 0 then
    local noiseFreq, noiseStrength, fbmOctaves, fbmLacunarity, fbmGain = mapNoiseParameters(roughness, scale)
    for x = 0, xSize - 1 do
      local rx = bXMin + x
      for y = 0, ySize - 1 do
        local idx = y * xSize + x
        if mod[idx] == 1 then
          tmpPoint2I.x, tmpPoint2I.y = rx, bYMin + y
          local pWS = te:gridToWorldByPoint2I(tmpPoint2I, tb)
          local n = fbm(pWS.x * noiseFreq, pWS.y * noiseFreq, fbmOctaves, fbmLacunarity, fbmGain)
          local dist = sdf[idx]
          local w = clamp((1.0 - dist * DOIInv) ^ falloffExp, 0, 1)
          final[idx] = final[idx] + n * noiseStrength * w
        end
      end
    end
  end

  -- Smoothing pass for the transitions (and overall polish).
  blur(xSize, ySize)

  -- Set the final changes in the terrain and manage undo/redo history.
  modifyTerrainFromHeightArray(xSize, ySize, bXMin, bXMax, bYMin, bYMax, tb)
end


-- Public interface.
M.terraformToSources =                                  terraformToSources

return M