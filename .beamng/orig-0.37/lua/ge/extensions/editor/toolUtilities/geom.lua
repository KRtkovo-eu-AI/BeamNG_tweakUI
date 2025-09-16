-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- This is a utility class containing geometric functions, for use with spline-editing tools.

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- User constants.
local autoBankTuning = 500 -- The tuning factor for the auto banking of a spline.
local maxBankDeg = 15 -- The maximum bank angle in degrees for sharpest corners.

local maxRayDist = 10000 -- The maximum distance for the camera -> mouse ray, in meters.

local defaultMinNumDivisions = 10 -- The minimum number of subdivisions used when interpolating the secondary geometry properties of a spline.
local maxDivisionSpacing = 20.0 -- The maximum allowed spacing between consecutive division points, in meters (determines the minimum number of subdivisions)

local endMargin = 10 -- The margin to add to the first and last points of a polygon, in meters.

local minScale = 0.01 -- The minimum scale for the adaptive sampling of a spline.
local kappaSensitivity = 150 -- The sensitivity of the adaptive sampling of a spline to curvature.

local mouseToNodetol = 2 -- The distance tolerance used when testing if the mouse is close to a node, in meters.                                                                        -- The sq. distance tolerance used when testing if the mouse is close to a spline.
local intermediateTolSq = 1 -- The sq. distance tolerance used when testing if the mouse is close to a spline.

local barScale = 0.5 -- The scale factor for the bar points (height = barScale * velocity).

local epsilon = 1e-6 -- A small value used to avoid division by zero.
local closeTolSq = 4.1 -- The sq. distance tolerance used when testing if two nodes are close to each other, in meters squared.

local splitPartingDistance = 2 -- The distance to push apart the two splines at the split point, in meters.

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local M = {}

-- Module dependencies.
local kdTreeB2d = require('kdtreebox2d')
local util = require('editor/toolUtilities/util')

-- Module constants.
local abs, min, max, floor, rad = math.abs, math.min, math.max, math.floor, math.rad
local sin, cos, tan, acos, pi, sqrt = math.sin, math.cos, math.tan, math.acos, math.pi, math.sqrt
local random, huge = math.random, math.huge
local splineGranInv = 1.0 / defaultMinNumDivisions
local globalUp = vec3(0, 0, 1)
local preRotQuats = {
  [0] = quat(0, 0, 0, 1), -- 0° (identity).
  [1] = quat(0, 0, 0.70710678, 0.70710678), -- 90°.
  [2] = quat(0, 0, 1, 0), -- 180°.
  [3] = quat(0, 0, 0.70710678, -0.70710678), -- 270°.
}

-- Module state.
local intersections, leftPts, rightPts = {}, {}, {}
local tmpQuat = quat()
local tmpPoint2I = Point2I(0, 0)
local pThis, pLast, mousePos2D, tmpTangent = vec3(), vec3(), vec3(), vec3()
local tmp0, tmp1, tmp2, tmp3 = vec3(), vec3(), vec3(), vec3()
local ab, bc, abNorm, bcNorm, tmpTan, tmpCross = vec3(), vec3(), vec3(), vec3(), vec3(), vec3()


-- Returns the pre-rotation quaternions.
local function getPreRotQuats() return preRotQuats end

-- Returns the scale factor for the bar points.
local function getBarScale() return barScale end

-- Returns the squared distance between two line segments.
local function squaredSegSegDist(a0, a1, b0, b1, outP1, outP2)
  local a0X, a0Y, a0Z = a0.x, a0.y, a0.z
  local a1X, a1Y, a1Z = a1.x, a1.y, a1.z
  local b0X, b0Y, b0Z = b0.x, b0.y, b0.z
  local b1X, b1Y, b1Z = b1.x, b1.y, b1.z
  local ux, uy, uz = a1X - a0X, a1Y - a0Y, a1Z - a0Z
  local vx, vy, vz = b1X - b0X, b1Y - b0Y, b1Z - b0Z
  local wx, wy, wz = a0X - b0X, a0Y - b0Y, a0Z - b0Z

  -- Compute the dot products.
  local a = ux * ux + uy * uy + uz * uz
  local b = ux * vx + uy * vy + uz * vz
  local c = vx * vx + vy * vy + vz * vz
  local d = ux * wx + uy * wy + uz * wz
  local e = vx * wx + vy * wy + vz * wz

  -- Compute s, t - the parameters of the closest points on the segments.
  local denom = a * c - b * b + epsilon
  local denomInv = 1.0 / denom
  local s = (b * e - c * d) * denomInv
  local t = (a * e - b * d) * denomInv
  s = max(0, min(1, s))
  t = max(0, min(1, t))

  -- Compute the distance vector.
  local dx = wx + s * ux - t * vx
  local dy = wy + s * uy - t * vy
  local dz = wz + s * uz - t * vz

  -- Compute the closest points on the segments.
  outP1:set(a0X + s * ux, a0Y + s * uy, a0Z + s * uz)
  outP2:set(b0X + t * vx, b0Y + t * vy, b0Z + t * vz)

  -- Return the squared distance.
  return dx * dx + dy * dy + dz * dz
end

-- Checks if the mouse is over a node of any spline in the given collection of splines.
-- [Splines - The collection of splines to check, which must have a member array 'nodes', containing the ordered points of the splines.]
local function isMouseOverNode(splines)
  -- Get the camera-to-mouse ray.
  local ray = getCameraMouseRay()
  local rayPos, rayDir = ray.pos, ray.dir

  -- Check each spline in turn.
  for i = 1, #splines do
    local nodes = splines[i].nodes
    for j = 1, #nodes do
      local a, b = intersectsRay_Sphere(rayPos, rayDir, nodes[j], mouseToNodetol) -- Get any intersection points between the ray and node sphere.
      if min(a, b) < maxRayDist then -- If they do exist, the mouse is over this node, so we have found target.
        return true, i, j -- Return the spline/node indices along with the true result.
      end
    end
  end

  -- The mouse is not over any node, so return nil.
  return false, nil, nil
end

-- Checks if the mouse is over the given polyline.
local function isMouseOverPolyline(points, mousePos)
  -- Project the mouse position onto the {z = 0} plane.
  mousePos2D:set(mousePos.x, mousePos.y, 0.0)

  -- Check each node, in each spline, in turn.
  for j = 1, #points - 1 do
    local p0, p1 = points[j], points[j + 1]
    tmp1:set(p0.x, p0.y, 0.0)
    tmp2:set(p1.x, p1.y, 0.0)
    if mousePos2D:squaredDistanceToLineSegment(tmp1, tmp2) < intermediateTolSq then
      return true, j
    end
  end

  -- The mouse is not over the polyline, so return nil.
  return false, nil
end

-- Checks if the mouse is over a rib.
-- [Splines - The collection of splines to check, which must have a member 1D array 'ribPoints', containing the ordered points of the ribs.]
local function isMouseOverRib(splines)
  -- Get the camera-to-mouse ray.
  local ray = getCameraMouseRay()
  local rayPos, rayDir = ray.pos, ray.dir

  -- Check each spline in turn.
  for i = 1, #splines do
    local spline = splines[i]
    if spline.isEnabled then
      local ribPoints = spline.ribPoints
      if ribPoints and #ribPoints > 0 then
        -- Detect if this is a sidewalk spline by checking for sidewalk-specific properties.
        local isHalfSpline = spline.tileSet ~= nil or spline.spacing ~= nil -- TODO: This is a hack to detect if this is a sidewalk spline.

        if isHalfSpline then
          -- For half-splines, only check odd-indexed ribs (right edge)
          for j = 2, #ribPoints, 2 do
            local a, b = intersectsRay_Sphere(rayPos, rayDir, ribPoints[j], mouseToNodetol) -- The intersection points between ray and node sphere.
            if min(a, b) < maxRayDist then -- If one exists, the mouse is over this rib point.
              return true, i, j -- Returns: isOverRib, spline index in give table, rib index in given table.
            end
          end
        else
          -- For full splines, check all rib points
          for j = 1, #ribPoints do
            local a, b = intersectsRay_Sphere(rayPos, rayDir, ribPoints[j], mouseToNodetol) -- The intersection points between ray and node sphere.
            if min(a, b) < maxRayDist then -- If one exists, the mouse is over this rib point.
              return true, i, j -- Returns: isOverRib, spline index in give table, rib index in given table.
            end
          end
        end
      end
    end
  end

  -- The mouse is not over any rib, so return nil.
  return false, nil, nil
end

-- Checks if the mouse is over a bar.
-- [Splines - The collection of splines to check, which must have a member 1D array 'barPoints', containing the ordered points of the bars.]
local function isMouseOverBar(splines)
  -- Get the camera-to-mouse ray.
  local ray = getCameraMouseRay()
  local rayPos, rayDir = ray.pos, ray.dir

  -- Check each spline in turn.
  for i = 1, #splines do
    local spline = splines[i]
    if spline and spline.isEnabled then
      local barPoints = spline.barPoints
      if barPoints and #barPoints > 0 then
        for j = 1, #barPoints do
          local a, b = intersectsRay_Sphere(rayPos, rayDir, barPoints[j], mouseToNodetol) -- The intersection points between ray and node sphere.
          if min(a, b) < maxRayDist then -- If one exists, the mouse is over this bar point.
            return true, i, j -- Returns: isOverBar, spline index in give table, bar index in given table.
          end
        end
      end
    end
  end

  -- The mouse is not over any bar, so return nil.
  return false, nil, nil
end

-- Checks if the mouse is over a node in the navigation graph.
local function isMouseOverGraphNode(nodes)
  -- Get the camera-to-mouse ray.
  local ray = getCameraMouseRay()
  local rayPos, rayDir = ray.pos, ray.dir

  -- Check each graph node in turn.
  for key, node in pairs(nodes) do
    local a, b = intersectsRay_Sphere(rayPos, rayDir, node, mouseToNodetol) -- Get any intersection points between the ray and node sphere.
    if min(a, b) < maxRayDist then -- If they do exist, the mouse is over this node, so we have found target.
      return true, key -- Return the node key along with the true result.
    end
  end

  -- The mouse is not over any graph node, so return nil.
  return false, nil
end

-- Returns the axis-aligned bounding box of the given array of points.
local function getAABB(points)
  local xMin, xMax, yMin, yMax = huge, -huge, huge, -huge
  for i = 1, #points do
    local p = points[i]
    local pX, pY = p.x, p.y
    xMin, xMax, yMin, yMax = min(xMin, pX), max(xMax, pX), min(yMin, pY), max(yMax, pY)
  end
  return { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
end

-- Computes a polygonal outline from the given spline. Includes a given margin.
-- [Polygons are fast to deal with using scanline spans.]
-- [Returns: polygon]
local function computeSplinePolygon(spline, margin, polygon)
  -- Create the left and right edge polylines.
  table.clear(leftPts); table.clear(rightPts)
  local divPoints, tangents, binormals, divWidths = spline.divPoints, spline.tangents, spline.binormals, spline.divWidths
  local numDiv = #divPoints
  for i = 1, numDiv do
    local p, bin = divPoints[i], binormals[i]
    local halfWidth = divWidths[i] * 0.5 + margin
    local pX, pY, latX, latY = p.x, p.y, bin.x * halfWidth, bin.y * halfWidth
    leftPts[i], rightPts[i] = vec3(pX - latX, pY - latY, 0), vec3(pX + latX, pY + latY, 0)
  end

  -- Move the first and last points outwards by the margin.
  tmpTan:setScaled2(tangents[1], endMargin)
  leftPts[1]:setSub(tmpTan)
  rightPts[1]:setSub(tmpTan)
  tmpTan:setScaled2(tangents[numDiv], endMargin)
  leftPts[numDiv]:setAdd(tmpTan)
  rightPts[numDiv]:setAdd(tmpTan)

  -- Create the polygon from the left and right edge polylines.
  table.clear(polygon)
  local ctr = 1
  for i = 1, numDiv do
    polygon[ctr] = leftPts[i]
    ctr = ctr + 1
  end
  for i = numDiv, 1, -1 do
    polygon[ctr] = rightPts[i]
    ctr = ctr + 1
  end
end

-- Checks if the given point (p) is inside the given triangle (a, b, c).
local function isPointInTriangle(p, a, b, c)
  local v0, v1, v2 = c - a, b - a, p - a
  local dot00, dot01, dot02, dot11, dot12 = v0:dot(v0), v0:dot(v1), v0:dot(v2), v1:dot(v1), v1:dot(v2)
  local denom = dot00 * dot11 - dot01 * dot01
  if denom == 0 then
    return false
  end
  local invDenom = 1.0 / denom
  local u = (dot11 * dot02 - dot01 * dot12) * invDenom
  local v = (dot00 * dot12 - dot01 * dot02) * invDenom
  return (u >= 0.0 and v >= 0.0 and (u + v) <= 1.0)
end

-- Returns the normal of the terrain at the given world-space point.
local function getTerrainNormal(p)
  local tb = extensions.editor_terrainEditor.getTerrainBlock()
  local te = extensions.editor_terrainEditor.getTerrainEditor()
  te:worldToGridByPoint2I(p, tmpPoint2I, tb) -- World point to grid.
  local gx, gy = tmpPoint2I.x, tmpPoint2I.y
  local dzdx = (tb:getHeightGrid(gx + 1, gy) - tb:getHeightGrid(gx - 1, gy)) * 0.5 -- Sample neighbourhood.
  local dzdy = (tb:getHeightGrid(gx, gy + 1) - tb:getHeightGrid(gx, gy - 1)) * 0.5
  local normal = vec3(-dzdx, -dzdy, 1)
  normal:normalize()
  return normal
end

-- Returns the normal of the terrain at the given world-space point, in-place.
local function getTerrainNormalInPlace(p, out)
  local tb = extensions.editor_terrainEditor.getTerrainBlock()
  local te = extensions.editor_terrainEditor.getTerrainEditor()
  te:worldToGridByPoint2I(p, tmpPoint2I, tb) -- World point to grid.
  local gx, gy = tmpPoint2I.x, tmpPoint2I.y
  local dzdx = (tb:getHeightGrid(gx + 1, gy) - tb:getHeightGrid(gx - 1, gy)) * 0.5 -- Sample neighbourhood.
  local dzdy = (tb:getHeightGrid(gx, gy + 1) - tb:getHeightGrid(gx, gy - 1)) * 0.5
  out:set(-dzdx, -dzdy, 1)
  out:normalize()
end

-- Rotates vector v around the z-axis, by angle theta (in radians). In place.
local function rotateVecAroundZ(vec, v, angle)
  local vX, vY = v.x, v.y
  local cosA, sinA = cos(angle), sin(angle)
  vec:set(vX * cosA - vY * sinA, vX * sinA + vY * cosA, v.z)
end

-- Rotates vector v around unit axis k, by angle theta (in radians).
-- [Uses the standard Rodrigues formula].
local function rotateVecAroundAxis(v, k, theta)
  local c, s = cos(theta), sin(theta)
  tmp0:setCross(k, v)
  tmp0:setScaled(s)
  local kDotV = k:dot(v)
  tmp1:setScaled2(k, kDotV * (1.0 - c))
  tmp0:setAdd(tmp1)
  tmp2:set(v.x * c, v.y * c, v.z * c)
  tmp0:setAdd(tmp2)
  return tmp0:copy()
end

-- Rotates vector v around unit axis k, by angle theta (radians) into 'out' without allocations.
-- out = v * cos(theta) + (k x v) * sin(theta) + k * (k . v) * (1 - cos(theta))
local function rotateVecAroundAxisInlined(v, k, theta, out)
  local c, s = cos(theta), sin(theta)
  local oneMinusC = 1.0 - c
  tmp0:setCross(k, v) -- tmp0 = k x v.
  tmp0:setScaled(s)
  local kDotV = k:dot(v) -- tmp1 = k * (k . v) * (1 - c).
  tmp1:setScaled2(k, kDotV * oneMinusC)
  out:setScaled2(v, c) -- out = v * c + tmp0 + tmp1.
  out:setAdd(tmp0)
  out:setAdd(tmp1)
  return out
end

-- Robust curvature radius approximation using 3 points.
local function computeTurningRadius(p1, p2, p3)
  ab:setSub2(p2, p1)
  bc:setSub2(p3, p2)
  local abLen, bcLen = ab:length(), bc:length()
  abNorm:set(ab)
  abNorm:normalize()
  bcNorm:set(bc)
  bcNorm:normalize()
  local dot = clamp(abNorm:dot(bcNorm), -1.0, 1.0)
  local angle = acos(dot)
  local avgLen = 0.5 * (abLen + bcLen)
  return avgLen / tan(angle * 0.5 + epsilon)
end

-- Checks if the given line segment (a, b) intersects with the given line segment (c, d).
local function isLineSegIntersect(a, b, c, d)
  local xnorm, xnorm2 = closestLinePoints(a, b, c, d)
  return xnorm >= 0.0 and xnorm <= 1.0 and xnorm2 >= 0.0 and xnorm2 <= 1.0
end

-- Finds the intersection point between two line segments. Inlined.
local function intersection2LineSegs(p1, p2, q1, q2, out)
  local xnorm, xnorm2 = closestLinePoints(p1, p2, q1, q2)
  if xnorm >= 0.0 and xnorm <= 1.0 and xnorm2 >= 0.0 and xnorm2 <= 1.0 then
    local p1X, p1Y = p1.x, p1.y
    out:set(p1X + xnorm * (p2.x - p1X), p1Y + xnorm * (p2.y - p1Y), 0)
    return out
  end
  return nil
end

-- Computes the (small) angle between two unit vectors, in radians.
local function angleBetweenVecsNorm(a, b) return acos(a:dot(b)) end

-- Computes the (small) angle between two vectors of arbitrary length, in radians.
local function angleBetweenVecs(a, b)
  tmp0:set(a)
  tmp0:normalize()
  tmp1:set(b)
  tmp1:normalize()
  return acos(tmp0:dot(tmp1))
end

-- Computes the (small) angle between two vectors (on the XY plane).
local function angleBetweenVecs2D(a, b)
  tmp0:set(a.x, a.y, 0)
  tmp0:normalize()
  tmp1:set(b.x, b.y, 0)
  tmp1:normalize()
  return acos(tmp0:dot(tmp1))
end

-- Compute the signed angle between two vectors around a given axis.
-- [Assumes vectors are in plane of rotation.]
local function signedAngleBetweenVecs(a, b, axis)
  local dotAB = clamp(a:dot(b), -1, 1)
  local angle = acos(dotAB)
  tmp0:setCross(a, b)
  local sign = tmp0:dot(axis) >= 0 and 1 or -1
  return angle * sign
end

-- Compute the signed angle between two vectors around a given axis.
-- [Vectors are projected onto the plane of rotation before computation.]
local function signedAngleAroundAxis(fromVec, toVec, axis)
  local fromProj = fromVec:projectToOriginPlane(axis)
  local toProj = toVec:projectToOriginPlane(axis)
  local dot = max(-1, min(1, fromProj:dot(toProj)))
  local angle = acos(dot) -- The unsigned angle.
  local sign = (fromProj:cross(toProj)):dot(axis) >= 0 and 1 or -1 -- Determine the sign of the angle.
  return angle * sign * (180 / pi) -- Signed angle in degrees.
end

-- Intersects the given point with the given quadrilateral, and returns the height at the intersection point.
local function intersectsUpQuadBarycentric(p, q)
  local u, v = p:invBilinear2D(q[1], q[2], q[3], q[4])
  if u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0 then
    return lerp(lerp(q[1].z, q[2].z, u), lerp(q[3].z, q[4].z, u), v)
  end
  return false
end

-- Determines if the given point is inside the given quadrilateral.
local function pointInQuadBarycentric(p, q)
  local u, v = p:invBilinear2D(q[1], q[2], q[3], q[4])
  return (u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0)
end

-- Computes the bounding box of the given sources.
local function computeSourcesAABB(sources)
  local xMin, xMax, yMin, yMax = huge, -huge, huge, -huge
  for i = 1, #sources do
    local source = sources[i]
    for j = 1, #source do
      local p = source[j].pos
      local x, y = p.x, p.y
      xMin, xMax, yMin, yMax = min(xMin, x), max(xMax, x), min(yMin, y), max(yMax, y)
    end
  end
  return { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
end

-- Gets quadrilaterals, with lateral bloating (no longitudinal stretching).
local function getAllQuadrilaterals(sources, margin)
  local quads, ctr = {}, 1
  for i = 1, #sources do
    local source = sources[i]
    for j = 2, #source do
      local s1, s2 = source[j - 1], source[j]
      local p1, p2 = s1.pos, s2.pos
      if j == 2 then
        p1 = p1 + (p1 - p2):normalized() * margin -- Bloat the first point longitudinally.
      elseif j == #source then
        p2 = p2 + (p2 - p1):normalized() * margin -- Bloat the last point longitudinally.
      end
      local bin1, bin2 = s1.binormal, s2.binormal
      local hw1, hw2 = s1.width * 0.5 + margin, s2.width * 0.5 + margin -- Half widths, bloated laterally.
      local lateral1, lateral2 = bin1 * hw1, bin2 * hw2
      quads[ctr] = { p1 - lateral1, p1 + lateral1, p2 - lateral2, p2 + lateral2 } -- Set quad, widened sideways only (not lengthened).
      ctr = ctr + 1
    end
  end
  return quads
end

-- Creates and populates a kd-tree containing the given quadrilaterals.
local function populateTreeQuads(quads)
  local tree = kdTreeB2d.new(#quads)
  for i = 1, #quads do
    local q = quads[i]
    local q1, q2, q3, q4 = q[1], q[2], q[3], q[4]
    local q1X, q1Y, q2X, q2Y, q3X, q3Y, q4X, q4Y = q1.x, q1.y, q2.x, q2.y, q3.x, q3.y, q4.x, q4.y
    tree:preLoad(i, min(q1X, q2X, q3X, q4X), min(q1Y, q2Y, q3Y, q4Y), max(q1X, q2X, q3X, q4X), max(q1Y, q2Y, q3Y, q4Y))
  end
  tree:build()
  return tree
end

-- Splits a spline at the given node index, returning two sets of geometry.
-- [Returns: nodes1, widths1, nmls1, nodes2, widths2, nmls2 (split arrays).]
local function splitSplineGeometry(nodes, widths, nmls, splitNodeIdx)
  local numNodes = #nodes
  if splitNodeIdx < 1 or splitNodeIdx > numNodes then
    return nil, nil, nil, nil, nil, nil -- Invalid split index.
  end

  -- Copy the first half of the geometry.
  local nodes1, widths1, nmls1 = {}, {}, {}
  for i = 1, splitNodeIdx do
    nodes1[i], widths1[i], nmls1[i] = vec3(nodes[i]), widths[i], vec3(nmls[i])
  end

  -- Copy the second half of the geometry.
  local nodes2, widths2, nmls2 = {}, {}, {}
  for i = splitNodeIdx, numNodes do
    local j = i - splitNodeIdx + 1
    nodes2[j], widths2[j], nmls2[j] = vec3(nodes[i]), widths[i], vec3(nmls[i])
  end

  -- Push apart the shared split point for visual clarity.
  if #nodes1 > 1 and #nodes2 > 1 then
    local tangent = nodes[min(numNodes, splitNodeIdx + 1)] - nodes[max(1, splitNodeIdx - 1)]
    tangent:normalize()
    local offset = tangent * splitPartingDistance

    -- Move the end of first spline away from split point.
    nodes1[#nodes1] = nodes1[#nodes1] - offset
    -- Move the start of second spline away from split point.
    nodes2[1] = nodes2[1] + offset
  end

  return nodes1, widths1, nmls1, nodes2, widths2, nmls2
end

-- Splits a loop spline at the given node index, returning reordered geometry.
-- [Returns: nodesNew, widthsNew, nmlsNew (reordered loop arrays).]
local function splitLoopSplineGeometry(nodes, widths, nmls, splitNodeIdx)
  local numNodes = #nodes
  if splitNodeIdx < 1 or splitNodeIdx > numNodes then
    return nil, nil, nil -- Invalid split index.
  end

  local nodesNew, widthsNew, nmlsNew, ctr = {}, {}, {}, 1
  for i = splitNodeIdx, numNodes do -- Copy from split point to end.
    nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(nodes[i]), widths[i], vec3(nmls[i])
    ctr = ctr + 1
  end
  for i = 1, splitNodeIdx - 1 do -- Copy from start to split point.
    nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(nodes[i]), widths[i], vec3(nmls[i])
    ctr = ctr + 1
  end

  -- Push apart the two splines at the split point.
  if #nodesNew > 1 then
    local tangent = nodesNew[2] - nodesNew[#nodesNew]
    tangent:normalize()
    local offset = tangent * splitPartingDistance
    nodesNew[1] = nodesNew[1] + offset
    nodesNew[#nodesNew] = nodesNew[#nodesNew] - offset
  end

  return nodesNew, widthsNew, nmlsNew
end

-- Joins two spline geometries at the specified node indices.
-- [Returns: nodesNew, widthsNew, nmlsNew (joined arrays).]
local function joinSplineGeometry(n1, w1, nm1, nodeIdx1, n2, w2, nm2, nodeIdx2)
  local nodesNew, widthsNew, nmlsNew, ctr = {}, {}, {}, 1

  if nodeIdx1 == 1 and nodeIdx2 == 1 then -- Start-Start: reverse spline2, append spline1.
    for i = #n2, 1, -1 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n2[i]), w2[i], vec3(nm2[i])
      ctr = ctr + 1
    end
    for i = 2, #n1 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n1[i]), w1[i], vec3(nm1[i])
      ctr = ctr + 1
    end
  elseif nodeIdx1 == 1 and nodeIdx2 == #n2 then -- Start-End: append spline2, then spline1.
    for i = 1, #n2 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n2[i]), w2[i], vec3(nm2[i])
      ctr = ctr + 1
    end
    for i = 2, #n1 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n1[i]), w1[i], vec3(nm1[i])
      ctr = ctr + 1
    end
  elseif nodeIdx1 == #n1 and nodeIdx2 == 1 then -- End-Start: append spline2 to spline1.
    for i = 1, #n1 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n1[i]), w1[i], vec3(nm1[i])
      ctr = ctr + 1
    end
    for i = 2, #n2 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n2[i]), w2[i], vec3(nm2[i])
      ctr = ctr + 1
    end
  elseif nodeIdx1 == #n1 and nodeIdx2 == #n2 then -- End-End: reverse spline2, append to spline1.
    for i = 1, #n1 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n1[i]), w1[i], vec3(nm1[i])
      ctr = ctr + 1
    end
    for i = #n2 - 1, 1, -1 do
      nodesNew[ctr], widthsNew[ctr], nmlsNew[ctr] = vec3(n2[i]), w2[i], vec3(nm2[i])
      ctr = ctr + 1
    end
  else
    return nil, nil, nil -- Invalid node indices.
  end

  return nodesNew, widthsNew, nmlsNew
end

-- Flips the direction of the given spline.
local function flipSplineDirection(spline)
  local nodes, widths, nmls = spline.nodes, spline.widths, spline.nmls
  local newNodes, newWidths, newNmls = {}, {}, {}
  for i = #nodes, 1, -1 do
    table.insert(newNodes, nodes[i])
    table.insert(newWidths, widths[i])
    table.insert(newNmls, nmls[i])
  end
  spline.nodes, spline.widths, spline.nmls = newNodes, newWidths, newNmls
  spline.isDirty = true
end

-- Compute the closest point on the given ribbon segment, to the given point.
local function closestRibbonSegPointToPoint(segIdx, ribbon, p)
  if segIdx <= ribbon.numSegs then
    local twoSegIdx = segIdx * 2
    local i1, i2, i3, i4 = twoSegIdx - 1, twoSegIdx, twoSegIdx + 1, twoSegIdx + 2
    local nodes = ribbon.nodes
    local c0, c1, c2, c3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local pT1 = p:triangleClosestPoint(c0, c1, c2)
    local pT2 = p:triangleClosestPoint(c1, c2, c3)
    local dSq1, dSq2 = p:squaredDistance(pT1), p:squaredDistance(pT2)
    if dSq2 < dSq1 then
      return pT2, dSq2
    end
    return pT1, dSq1
  end
  return nil, nil
end

-- Given a polyline and a polygon, returns sequences of consecutive indices that are inside the polygon.
local function getNodeSpansInsidePolygon(nodes, polygon)
  local spans, ctr = {}, 1
  local currentSpan = nil
  for i = 1, #nodes do
    if nodes[i]:inPolygon(polygon) then
      if not currentSpan then
        currentSpan = { i, i } -- start a new span.
      else
        currentSpan[2] = i -- extend current span.
      end
    else
      if currentSpan then
        spans[ctr] = currentSpan
        ctr = ctr + 1
        currentSpan = nil
      end
    end
  end
  if currentSpan then
    spans[ctr] = currentSpan -- Capture final span if list ends while inside.
    ctr = ctr + 1
  end
  return spans
end

-- Projects the given point onto the given spline.
-- [Returns: closest point (p), s in [0,1], t in [-inf,inf]; or nil if outside segment bounds.]
local function projectPointToSpline(pos, spline)
  local divPoints, binormals, widths = spline.divPoints, spline.binormals, spline.divWidths
  local bestDistSq, bestProj, bestS = huge, nil, 0.0
  local bestIdx, bestT, bestSegment = 1, 0.0, 1

  -- Precompute segment lengths and total
  local segLengths, totalLength = table.new(#divPoints, 0), 0.0
  for i = 1, #divPoints - 1 do
    local len = divPoints[i]:distance(divPoints[i + 1])
    segLengths[i] = len
    totalLength = totalLength + len
  end

  -- Find closest projection
  local accumulated = 0.0
  for i = 1, #divPoints - 1 do
    local p0, p1 = divPoints[i], divPoints[i + 1]
    local seg = p1 - p0
    local lenSq = seg:squaredLength()
    if lenSq > 0 then
      local t = clamp((pos - p0):dot(seg) / lenSq, 0, 1)
      local proj = p0 + seg * t
      local distSq = (proj - pos):squaredLength()
      if distSq < bestDistSq then
        bestDistSq = distSq
        bestProj = proj
        bestS = (accumulated + segLengths[i] * t) / totalLength
        bestIdx = i
        bestT = t
        bestSegment = i
      end
    end
    accumulated = accumulated + segLengths[i]
  end

  -- Reject if projected onto the first or last segment near their outer ends
  local numSegs = #divPoints - 1
  local edgeTol = 1e-3
  if (bestSegment == 1     and bestT < edgeTol) or
     (bestSegment == numSegs and bestT > 1.0 - edgeTol) then
    return nil, nil, nil
  end

  -- Interpolate binormal and width
  local bin = lerp(binormals[bestIdx], binormals[bestIdx + 1], bestT)
  bin:normalize()
  local width = widths[bestIdx] * (1 - bestT) + widths[bestIdx + 1] * bestT

  local t = 2.0 * (pos - bestProj):dot(bin) / width
  return bestProj, bestS, t
end

-- Sample along true arc-length of the given polyline, to compute the positions and Frenet frame at regular intervals.
-- [Returns: outPosns, outTans, outNormals]
local function sampleSpline(divPoints, tangents, normals, spacing, outPosns, outTans, outNormals)
  table.clear(outPosns); table.clear(outTans); table.clear(outNormals)
  local nextDist, accDist, ctr, i = 0.0, 0.0, 1, 2
  while i <= #divPoints do
    local iMinusOne = i - 1
    local p1, p2 = divPoints[iMinusOne], divPoints[i]
    tmpTangent:set(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)
    local segLen = tmpTangent:length()
    if accDist + segLen < nextDist then -- If the current segment can't reach the next sample point, move on.
      accDist = accDist + segLen
      i = i + 1
    else
      local t = (nextDist - accDist) / segLen
      tmp0:setScaled2(tmpTangent, t)
      tmp0:setAdd2(p1, tmp0)
      outPosns[ctr] = vec3(tmp0)
      outTans[ctr] = lerp(tangents[iMinusOne], tangents[i], t)
      outTans[ctr]:normalize()
      outNormals[ctr] = lerp(normals[iMinusOne], normals[i], t)
      outNormals[ctr]:normalize()
      ctr = ctr + 1
      nextDist = nextDist + spacing
    end
  end
end

-- Estimate local curvature at a point on a polyline of vec3s.
-- Returns 0 for endpoints or degenerate segments.
local function estimateCurvatureAt(points, i)
  if i <= 1 or i >= #points then
    return 0.0
  end
  tmp0:setSub2(points[i], points[i - 1])
  tmp1:setSub2(points[i + 1], points[i])
  local len0, len1 = tmp0:length(), tmp1:length()
  if len0 < 1e-6 or len1 < 1e-6 then
    return 0.0
  end
  tmp0:normalize()
  tmp1:normalize()
  local dot = clamp(tmp0:dot(tmp1), -1, 1)
  local angle = acos(dot)
  local avgLen = 0.5 * (len0 + len1)
  return avgLen < 1e-6 and 0.0 or angle / avgLen
end

-- Adaptive sampling along the given spline, to compute the positions and Frenet frame at regular intervals.
-- [Adaptive in the sense that small curvature segments are sampled more densely, and large curvature segments are sampled more sparsely.]
-- [Returns: outPosns, outTans, outNormals, outScales]
local function sampleSplineAdaptive(divPoints, tangents, normals, meshLength, outPosns, outTans, outNormals, outScales)
  table.clear(outPosns); table.clear(outTans); table.clear(outNormals); table.clear(outScales)
  local nextDist, accDist, ctr, i = 0.0, 0.0, 1, 2
  while i <= #divPoints do
    local iMinusOne = i - 1
    local p1, p2 = divPoints[iMinusOne], divPoints[i]
    tmpTangent:set(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z)
    local segLen = tmpTangent:length()
    if accDist + segLen < nextDist then -- If the current segment can't reach the next sample point, move on.
      accDist = accDist + segLen
      i = i + 1
    else
      local t = (nextDist - accDist) / segLen
      tmp0:setScaled2(tmpTangent, t)
      tmp0:setAdd2(p1, tmp0)
      outPosns[ctr] = vec3(tmp0)
      outTans[ctr] = lerp(tangents[iMinusOne], tangents[i], t)
      outTans[ctr]:normalize()
      outNormals[ctr] = lerp(normals[iMinusOne], normals[i], t)
      outNormals[ctr]:normalize()
      local curvature = estimateCurvatureAt(divPoints, i)
      outScales[ctr] = max(minScale, 1.0 / (1.0 + kappaSensitivity * curvature)) -- Maps curvature to a normalised scale [minScale, 1].
      nextDist = nextDist + meshLength * outScales[ctr]
      ctr = ctr + 1
    end
  end
end

-- Translates the given spline by the given amount on the binormal (lateral) direction.
local function translateSpline(pts, binormals, t, out)
  table.clear(out)
  for i = 1, #pts do
    local p, bin = pts[i], binormals[i]
    out[i] = vec3(p.x + bin.x * t, p.y + bin.y * t, p.z + bin.z * t)
  end
end

-- Converts curvature to banking angle in radians.
local function curvatureToBankAngle(curv, bankStrength)
  local scaled = min(curv * autoBankTuning, 1.0)
  return scaled * bankStrength * rad(maxBankDeg)
end

-- Computes a random jitter quaternion, for Z-only jitter.
local function computeRandomJitterQuat_ZOnly(jitter, nmlVec, outQuat)
  outQuat:setFromAxisAngle(nmlVec, (random() * 2 - 1) * jitter)
  return outQuat
end

-- Computes a random jitter quaternion, for component-wise jitter.
-- [The result is written into 'outQuat' (modified in-place).]
local function computeRandomJitterQuat(spline, tgt, rightVec, nmlVec, outQuat)
  outQuat:set(0, 0, 0, 1) -- Initialize to identity quaternion.
  local jitterForward, jitterRight, jitterUp = spline.jitterForward, spline.jitterRight, spline.jitterUp
  if jitterForward and jitterForward > 0.0 then
    local angleF = (random() * 2 - 1) * jitterForward
    tmpQuat:setFromAxisAngle(tgt, angleF)
    outQuat:setMul2(tmpQuat, outQuat)
  end
  if jitterRight and jitterRight > 0.0 then
    local angleR = (random() * 2 - 1) * jitterRight
    tmpQuat:setFromAxisAngle(rightVec, angleR)
    outQuat:setMul2(tmpQuat, outQuat)
  end
  if jitterUp and jitterUp > 0.0 then
    local angleU = (random() * 2 - 1) * jitterUp
    tmpQuat:setFromAxisAngle(nmlVec, angleU)
    outQuat:setMul2(tmpQuat, outQuat)
  end
  return outQuat
end

-- Computes a random jitter quaternion based on join freedom axes.
-- [The result is written into 'outQuat' (modified in-place).]
local function computeRandomJitterQuatFromFreedomAxes(spline, freedomAxes, outQuat)
  outQuat:set(0, 0, 0, 1) -- Initialize to identity.
  local jitterAmount = (spline.jitterForward + spline.jitterRight + spline.jitterUp) / 3.0
  if jitterAmount > 0.0 and freedomAxes and #freedomAxes > 0 then
    for i = 1, #freedomAxes do
      local angle = (random() * 2 - 1) * jitterAmount
      tmpQuat:setFromAxisAngle(freedomAxes[i], angle)
      outQuat:setMul2(tmpQuat, outQuat)
    end
  end
  return outQuat
end

-- Re-compute the rib points, in free-floating 3D space.
local function updateRibPointsFree(spline)
  local nodes, ribPoints = spline.nodes, spline.ribPoints
  if #nodes < 2 then
    return -- Early return if there are less than two nodes.
  end

  local widths, discMap, binormals, ctr = spline.widths, spline.discMap, spline.binormals, 1
  for i = 1, #nodes do
    local divIdx = discMap[i] -- Map the node index to the discretised geometry index.
    local bin, halfWidth = binormals[divIdx], widths[i] * 0.5
    tmp0:set(bin.x * halfWidth, bin.y * halfWidth, bin.z * halfWidth)
    local node = nodes[i]
    ribPoints[ctr] = ribPoints[ctr] or vec3()
    ribPoints[ctr]:setSub2(node, tmp0) -- Left point.
    ribPoints[ctr + 1] = ribPoints[ctr + 1] or vec3()
    ribPoints[ctr + 1]:setAdd2(node, tmp0) -- Right point.
    ctr = ctr + 2
  end

  -- Remove excess vec3 objects.
  local numRibPoints = #nodes * 2
  for i = numRibPoints + 1, #ribPoints do
    ribPoints[i] = nil
  end
end

-- Update the rib points. using vertical raycasting to conform them to the nearest surface below .
local function updateRibPointsRaycast(spline)
  local nodes, ribPoints = spline.nodes, spline.ribPoints
  if #nodes < 2 then
    return -- Early return if there are less than two nodes.
  end

  local widths, discMap, binormals, ctr = spline.widths, spline.discMap, spline.binormals, 1
  for i = 1, #nodes do
    local divIdx = discMap[i] -- Map the node index to the discretised geometry index.
    tmp0:setScaled2(binormals[divIdx], widths[i] * 0.5)
    local node = nodes[i]
    ribPoints[ctr] = ribPoints[ctr] or vec3()
    ribPoints[ctr]:setSub2(node, tmp0) -- Left point.
    ribPoints[ctr + 1] = ribPoints[ctr + 1] or vec3()
    ribPoints[ctr + 1]:setAdd2(node, tmp0) -- Right point.
    util.vertRaycast(ribPoints[ctr]) -- Conform left point to terrain.
    util.vertRaycast(ribPoints[ctr + 1]) -- Conform right point to terrain.
    ctr = ctr + 2
  end

  -- Remove excess vec3 objects.
  local numRibPoints = #nodes * 2
  for i = numRibPoints + 1, #ribPoints do
    ribPoints[i] = nil
  end
end

-- Update the bar points.
local function updateBarPoints(spline, isBarsLimits)
  local nodes, barPoints = spline.nodes, spline.barPoints
  local vals = isBarsLimits and spline.velLimits or spline.vels

  -- Ensure velocities exist for all nodes.
  if not vals or #vals == 0 then
    vals = {}
    for i = 1, #nodes do
      vals[i] = 30.0 -- Default velocity of 30 m/s.
    end
    if isBarsLimits then
      spline.velLimits = vals
    else
      spline.vels = vals
    end
  elseif #vals < #nodes then
    -- Extend velocities array if it's too short.
    for i = #vals + 1, #nodes do
      vals[i] = vals[#vals] or 30.0 -- Use last velocity or default.
    end
  end

  for i = 1, #nodes do
    util.vertRaycast(nodes[i])
    tmp1:set(nodes[i].x, nodes[i].y, nodes[i].z + vals[i] * barScale)
    barPoints[i] = barPoints[i] or vec3()
    barPoints[i]:set(tmp1)
  end

  -- Remove excess vec3 objects.
  for i = #nodes + 1, #barPoints do
    barPoints[i] = nil
  end
end

-- Update the bar points for a graph path.
-- [spline - The spline to update bar points for.]
-- [graphData - The navigation graph data.]
-- [isBarsLimit - Whether to use velLimits (true) or vels (false) for bar heights.]
local function updateBarPointsGraph(spline, graphData, isBarsLimit)
  local graphDataNodes = graphData.nodes
  local graphNodes, barPoints = spline.graphNodes, spline.barPoints
  local vals = isBarsLimit and spline.velLimits or spline.vels

  -- Ensure velocities exist for all graph nodes.
  if not vals or #vals == 0 then
    vals = {}
    for i = 1, #graphNodes do
      vals[i] = 30.0 -- Default velocity of 30 m/s.
    end
    if isBarsLimit then
      spline.velLimits = vals
    else
      spline.vels = vals
    end
  elseif #vals < #graphNodes then
    -- Extend velocities array if it's too short.
    for i = #vals + 1, #graphNodes do
      vals[i] = vals[#vals] or 30.0 -- Use last velocity or default.
    end
  end

  for i = 1, #graphNodes do
    local node = graphDataNodes[graphNodes[i]]
    util.vertRaycast(node)
    tmp1:set(node.x, node.y, node.z + vals[i] * barScale)
    barPoints[i] = barPoints[i] or vec3()
    barPoints[i]:set(tmp1)
  end

  -- Remove excess vec3 objects.
  for i = #graphNodes + 1, #barPoints do
    barPoints[i] = nil
  end
end

-- Computes the scanline spans for the given polygon.
-- [The scanline spans are the spans of the polygon on the Y-axis, in grid space.]
-- [The spans are stored in the given spansXMin, spansXMax, and spansY tables.]
local function getScanlineSpans(gMinY, gMaxY, te, tb, polygon, spansXMin, spansXMax, spansY)
  table.clear(spansXMin); table.clear(spansXMax); table.clear(spansY)
  local numPolygonNodes, ctr = #polygon, 1
  for y = gMinY, gMaxY do
    table.clear(intersections)
    tmpPoint2I.x, tmpPoint2I.y = 0, y
    local yWorld = te:gridToWorldByPoint2I(tmpPoint2I, tb).y
    local iCtr = 1
    for i = 1, numPolygonNodes do
      local a, b = polygon[i], polygon[i % numPolygonNodes + 1] -- Wrapped line segment [a, b] on polygon.
      local aX, aY, bX, bY = a.x, a.y, b.x, b.y
      if (aY <= yWorld and bY > yWorld) or (bY <= yWorld and aY > yWorld) then -- Note: Ignores odd numbers of intersections.
        local t = (yWorld - aY) / (bY - aY)
        local x = aX + t * (bX - aX)
        intersections[iCtr] = x
        iCtr = iCtr + 1
      end
    end
    table.sort(intersections)
    for i = 1, #intersections - 1, 2 do
      local x1, x2 = intersections[i], intersections[i + 1]
      tmp1:set(x1, yWorld, 0)
      te:worldToGridByPoint2I(tmp1, tmpPoint2I, tb)
      local xStart = tmpPoint2I.x
      tmp1:set(x2, yWorld, 0)
      te:worldToGridByPoint2I(tmp1, tmpPoint2I, tb)
      local xEnd = tmpPoint2I.x
      spansXMin[ctr], spansXMax[ctr], spansY[ctr] = xStart, xEnd, y
      ctr = ctr + 1
    end
  end
end

-- Computes the signed distance field (SDF) of the given mask.
local function computeSDF(mask)
  -- Initialise the distance map.
  local w, h = #mask[1], #mask
  local sdf, maxDist = {}, w + h
  for y = 1, h do
    sdf[y] = {}
    for x = 1, w do
      sdf[y][x] = mask[y][x] == 0 and 0 or maxDist
    end
  end

  -- Forward pass.
  for y = 1, h do
    for x = 1, w do
      local d = sdf[y][x]
      if x > 1 then d = min(d, sdf[y][x - 1] + 1) end
      if y > 1 then d = min(d, sdf[y - 1][x] + 1) end
      if x > 1 and y > 1 then d = min(d, sdf[y - 1][x - 1] + 1.414) end
      if x < w and y > 1 then d = min(d, sdf[y - 1][x + 1] + 1.414) end
      sdf[y][x] = d
    end
  end

  -- Backward pass.
  for y = h, 1, -1 do
    for x = w, 1, -1 do
      local d = sdf[y][x]
      if x < w then d = min(d, sdf[y][x + 1] + 1) end
      if y < h then d = min(d, sdf[y + 1][x] + 1) end
      if x < w and y < h then d = min(d, sdf[y + 1][x + 1] + 1.414) end
      if x > 1 and y < h then d = min(d, sdf[y + 1][x - 1] + 1.414) end
      sdf[y][x] = d
    end
  end

  return sdf
end

-- Fast, non-allocating version of catmullRomCentripetal
-- [If outVec is provided, sets it and returns it. Otherwise creates a new vec3.]
local function catmullRomCentripetalFast(p0, p1, p2, p3, t, s, outVec)
  outVec = outVec or vec3()
  s = s * 2
  local d1, d2, d3 = max(sqrt(p0:distance(p1)), 1e-30), max(sqrt(p1:distance(p2)), 1e-30), max(sqrt(p2:distance(p3)), 1e-30)
  local sd2, tt, t_1 = s * d2, t * t, t - 1
  local t_1sq, c21 = t_1 * t_1, s * t_1 * (t * t_1 + tt)
  local m1c, m2c = t * t_1sq * sd2, tt * t_1 * sd2
  local m1c_d1, m1c_d1d2 = m1c / d1, m1c / (d1 + d2)
  local m2c_d2d3, m2c_d3 = m2c / (d2 + d3), m2c / d3
  local t_1sq_2t1, c21_tt_2t3 = t_1sq * (2 * t + 1) - c21, c21 - tt * (2 * t - 3)
  local p0X, p0Y, p0Z = p0.x, p0.y, p0.z
  local p1X, p1Y, p1Z = p1.x, p1.y, p1.z
  local p2X, p2Y, p2Z = p2.x, p2.y, p2.z
  local p3X, p3Y, p3Z = p3.x, p3.y, p3.z
  outVec:set(
    (p1X - p0X) * m1c_d1 + (p0X - p2X) * m1c_d1d2 + (p1X - p3X) * m2c_d2d3 + (p3X - p2X) * m2c_d3 + t_1sq_2t1 * p1X + c21_tt_2t3 * p2X,
    (p1Y - p0Y) * m1c_d1 + (p0Y - p2Y) * m1c_d1d2 + (p1Y - p3Y) * m2c_d2d3 + (p3Y - p2Y) * m2c_d3 + t_1sq_2t1 * p1Y + c21_tt_2t3 * p2Y,
    (p1Z - p0Z) * m1c_d1 + (p0Z - p2Z) * m1c_d1d2 + (p1Z - p3Z) * m2c_d2d3 + (p3Z - p2Z) * m2c_d3 + t_1sq_2t1 * p1Z + c21_tt_2t3 * p2Z
  )
  return outVec
end

-- Checks if the mouse is over the given spline.
-- [Spline - The spline to check, which must have a member array 'nodes', containing the ordered points of the spline.]
local function isMouseOverSpline(spline, mousePos)
  local camPos = core_camera.getPosition()
  pLast:set(huge, huge, huge)
  local points = spline.nodes
  local numPoints, isLoop = #points, spline.isLoop
  for j = 1, numPoints - (isLoop and 0 or 1) do
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2 + numPoints) % numPoints) + 1, ((j - 1) % numPoints) + 1, (j % numPoints) + 1, ((j + 1) % numPoints) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numPoints, j + 2)
    end
    local p0, p1, p2, p3 = points[i1], points[i2], points[i3], points[i4]
    for k = 0, defaultMinNumDivisions do
      pThis:set(catmullRomCentripetalFast(p0, p1, p2, p3, k * splineGranInv, 0.5))
      if squaredSegSegDist(pThis, pLast, camPos, mousePos, tmp1, tmp2) < intermediateTolSq then
        return true, j, tmp2
      end
      pLast:set(pThis)
    end
  end
  return false, nil, nil
end

-- Interpolates the given points with Catmull-Rom splines.
local function catmullRomNodesOnly(nodes, gran)
  local granInv = 1.0 / gran
  local pts, ctr, startIdx, numNodes = {}, 1, 0, #nodes
  for j = 1, numNodes - 1 do
    local p0, p1, p2, p3 = nodes[max(1, j - 1)], nodes[j], nodes[j + 1], nodes[min(numNodes, j + 2)]
    local z0, z1, z2, z3 = p0.z, p1.z, p2.z, p3.z
    for k = startIdx, gran do
      local t = k * granInv
      pts[ctr] = pts[ctr] or vec3()
      catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5, pts[ctr])
      pts[ctr].z = monotonicSteffen(z0, z1, z2, z3, 0, 1, 2, 3, t + 1)
      ctr = ctr + 1
    end
    startIdx = 1
  end
  for i = ctr, #pts do -- Remove excess elements.
    pts[i] = nil
  end
  return pts
end

-- Interpolates the given points with Catmull-Rom splines.
-- [Only works for a single array of nodes.]
local function catmullRomNodesWidthsOnly(nodes, widths, gran, isLoop)
  local granInv = 1.0 / gran
  local pts, wds, ctr, startIdx, numNodes = {}, {}, 1, 0, #nodes
  for j = 1, numNodes - (isLoop and 0 or 1) do
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2) % numNodes) + 1, ((j - 1) % numNodes) + 1, (j % numNodes) + 1, ((j + 1) % numNodes) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numNodes, j + 2)
    end
    local p0, p1, p2, p3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local z0, z1, z2, z3 = p0.z, p1.z, p2.z, p3.z
    local w0, w1, w2, w3 = widths[i1], widths[i2], widths[i3], widths[i4]
    for k = startIdx, gran do
      local t = k * granInv
      pts[ctr] = pts[ctr] or vec3()
      catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5, pts[ctr])
      local tPlus1 = t + 1
      pts[ctr].z = monotonicSteffen(z0, z1, z2, z3, 0, 1, 2, 3, tPlus1) -- Use a monotonic spline for Z, to stop overshooting under the surface.
      wds[ctr] = monotonicSteffen(w0, w1, w2, w3, 0, 1, 2, 3, tPlus1) -- Use a monotonic spline for the width interpolation.
      ctr = ctr + 1
    end
    startIdx = 1
  end
  for i = ctr, #pts do  -- Remove excess elements.
    pts[i], wds[i] = nil, nil
  end
  return pts, wds
end

-- Interpolates the given points with Catmull-Rom splines.
-- [Only works for a single array of nodes.]
local function catmullRomNodesWidthsVelVelLimits(spline, gran)
  -- First, remove any duplicate nodes.
  local nodesRaw, widthsRaw, velocitiesRaw, velLimitsRaw, isLoop = spline.nodes, spline.widths, spline.vels, spline.velLimits, spline.isLoop
  local nodes, widths, velocities, velLimits, ctr = { nodesRaw[1] }, { widthsRaw[1] }, { velocitiesRaw[1] }, { velLimitsRaw[1] }, 2
  for i = 2, #nodesRaw do
    local p1, p2 = nodesRaw[i - 1], nodesRaw[i]
    if p1:squaredDistance(p2) > closeTolSq then
      nodes[ctr], widths[ctr], velocities[ctr], velLimits[ctr] = nodesRaw[i], widthsRaw[i], velocitiesRaw[i], velLimitsRaw[i]
      ctr = ctr + 1
    end
  end

  -- Perform spline fitting with Catmull-Rom splines.
  local granInv = 1.0 / gran
  local pts, wds, vels, lims, ctr, startIdx, numNodes = {}, {}, {}, {}, 1, 0, #nodes
  for j = 1, numNodes - (isLoop and 0 or 1) do
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2) % numNodes) + 1, ((j - 1) % numNodes) + 1, (j % numNodes) + 1, ((j + 1) % numNodes) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numNodes, j + 2)
    end
    local p0, p1, p2, p3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local z0, z1, z2, z3 = p0.z, p1.z, p2.z, p3.z
    local w0, w1, w2, w3 = widths[i1], widths[i2], widths[i3], widths[i4]
    local v0, v1, v2, v3 = velocities[i1], velocities[i2], velocities[i3], velocities[i4]
    local l0, l1, l2, l3 = velLimits[i1], velLimits[i2], velLimits[i3], velLimits[i4]
    for k = startIdx, gran do
      local t = k * granInv
      pts[ctr] = catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5)
      local tPlus1 = t + 1
      pts[ctr].z = monotonicSteffen(z0, z1, z2, z3, 0, 1, 2, 3, tPlus1) -- Use a monotonic spline for Z, to stop overshooting under the surface.
      wds[ctr] = monotonicSteffen(w0, w1, w2, w3, 0, 1, 2, 3, tPlus1) -- Use a monotonic spline for the width interpolation.
      vels[ctr] = monotonicSteffen(v0, v1, v2, v3, 0, 1, 2, 3, tPlus1) -- Use a monotonic spline for the velocity interpolation.
      lims[ctr] = monotonicSteffen(l0, l1, l2, l3, 0, 1, 2, 3, tPlus1) -- Use a monotonic spline for the velocity limit interpolation.
      ctr = ctr + 1
    end
    startIdx = 1
  end
  return pts, wds, vels, lims
end

-- Compute the local Frenet frame at each division point.
local function computeFrenetFrame(spline)
  local divPoints, tangents, binormals, normals = spline.divPoints, spline.tangents, spline.binormals, spline.normals
  local numDivPoints = #divPoints
  if spline.isLoop then -- For a looped spline, we use cyclic indexing.
    local twoMinusNumDivPoints = 2 - numDivPoints
    for i = 1, numDivPoints do
      local iPrev, iNext = ((i - twoMinusNumDivPoints) % numDivPoints) + 1, (i % numDivPoints) + 1
      tangents[i] = tangents[i] or vec3()
      binormals[i] = binormals[i] or vec3()
      tangents[i]:setSub2(divPoints[iNext], divPoints[iPrev])
      tangents[i]:normalize()
      tmp1:setCross(tangents[i], normals[i])
      tmp1:normalize()
      binormals[i]:set(tmp1)
      tmp2:setCross(binormals[i], tangents[i])
      tmp2:normalize()
      normals[i]:set(tmp2)
    end
  else -- For a non-looped spline, we use standard min/max clamp indexing.
    for i = 1, numDivPoints do
      local iPrev, iNext = max(1, i - 1), min(numDivPoints, i + 1)
      tangents[i] = tangents[i] or vec3()
      binormals[i] = binormals[i] or vec3()
      tangents[i]:setSub2(divPoints[iNext], divPoints[iPrev])
      tangents[i]:normalize()
      tmp1:setCross(tangents[i], normals[i])
      tmp1:normalize()
      binormals[i]:set(tmp1)
      tmp2:setCross(binormals[i], tangents[i])
      tmp2:normalize()
      normals[i]:set(tmp2)
    end
  end
  for i = numDivPoints + 1, #tangents do -- Remove excess elements.
    tangents[i], binormals[i] = nil, nil
  end
end

-- Interpolates the nodes and widths of the given spline with 'standard' Catmull-Rom splines to generate the secondary geometry properties.
-- [Points are raycast to the surface below.]
-- [The secondary geometry data is stored in the given spline object.]
local function catmullRomRaycast(spline, minNumDivIn)
  local minNumDivisionsFinal = minNumDivIn or defaultMinNumDivisions
  local divPoints, divWidths, normals, discMap = spline.divPoints, spline.divWidths, spline.normals, spline.discMap
  local nodes, widths, nmls = spline.nodes, spline.widths, spline.nmls
  local numNodes, startIdx, ctr = #nodes, 0, 1
  local isLoop = spline.isLoop
  for j = 1, numNodes - (isLoop and 0 or 1) do
    discMap[j] = max(1, ctr - 1)
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2) % numNodes) + 1, ((j - 1) % numNodes) + 1, (j % numNodes) + 1, ((j + 1) % numNodes) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numNodes, j + 2)
    end
    local p0, p1, p2, p3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local n0, n1, n2, n3 = nmls[i1], nmls[i2], nmls[i3], nmls[i4]
    local w0, w1, w2, w3 = widths[i1], widths[i2], widths[i3], widths[i4]
    tmp0:set(p0.x, p0.y, w0)
    tmp1:set(p1.x, p1.y, w1)
    tmp2:set(p2.x, p2.y, w2)
    tmp3:set(p3.x, p3.y, w3)
    local numDivisions = max(minNumDivisionsFinal, floor(p1:distance(p2) / maxDivisionSpacing + 0.5))
    local step = 1.0 / numDivisions
    for k = startIdx, numDivisions do
      local t = k * step
      divPoints[ctr] = divPoints[ctr] or vec3()
      normals[ctr] = normals[ctr] or vec3()
      catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5, divPoints[ctr])
      util.vertRaycast(divPoints[ctr])
      catmullRomCentripetalFast(n0, n1, n2, n3, t, 0.5, normals[ctr])
      divWidths[ctr] = monotonicSteffen(w0, w1, w2, w3, 0, 1, 2, 3, t + 1)
      ctr = ctr + 1
    end
    startIdx = 1
  end
  if not isLoop then
    discMap[#nodes] = ctr - 1 -- For the loop case, we do not set the last node->divPoint map, since the divPoints extend beyond the last node.
  end
  for i = ctr, #divPoints do -- Remove excess elements.
    divPoints[i], divWidths[i], normals[i] = nil, nil, nil
  end
  computeFrenetFrame(spline)
end

-- Interpolates the nodes and widths of the given spline with 'standard' Catmull-Rom splines to generate the secondary geometry properties.
-- [Points are conformed to the terrain.]
-- [The secondary geometry data is stored in the given spline object.]
local function catmullRomConformToTerrain(spline, minNumDivIn)
  local terrain = core_terrain.getTerrain()
  if not terrain then
    return catmullRomRaycast(spline, minNumDivIn) -- If no terrain block, use the raycast version.
  end
  local minNumDivisionsFinal = minNumDivIn or defaultMinNumDivisions
  local divPoints, divWidths, normals, discMap = spline.divPoints, spline.divWidths, spline.normals, spline.discMap
  local nodes, widths, nmls = spline.nodes, spline.widths, spline.nmls
  local numNodes, startIdx, ctr = #nodes, 0, 1
  local isLoop = spline.isLoop
  for j = 1, numNodes - (isLoop and 0 or 1) do
    discMap[j] = max(1, ctr - 1)
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2) % numNodes) + 1, ((j - 1) % numNodes) + 1, (j % numNodes) + 1, ((j + 1) % numNodes) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numNodes, j + 2)
    end
    local p0, p1, p2, p3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local n0, n1, n2, n3 = nmls[i1], nmls[i2], nmls[i3], nmls[i4]
    local w0, w1, w2, w3 = widths[i1], widths[i2], widths[i3], widths[i4]
    tmp0:set(p0.x, p0.y, w0)
    tmp1:set(p1.x, p1.y, w1)
    tmp2:set(p2.x, p2.y, w2)
    tmp3:set(p3.x, p3.y, w3)
    local numDivisions = max(minNumDivisionsFinal, floor(p1:distance(p2) / maxDivisionSpacing + 0.5))
    local step = 1.0 / numDivisions
    for k = startIdx, numDivisions do
      local t = k * step
      divPoints[ctr] = divPoints[ctr] or vec3()
      normals[ctr] = normals[ctr] or vec3()
      catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5, divPoints[ctr])
      divPoints[ctr].z = terrain:getHeight(divPoints[ctr])
      catmullRomCentripetalFast(n0, n1, n2, n3, t, 0.5, normals[ctr])
      divWidths[ctr] = monotonicSteffen(w0, w1, w2, w3, 0, 1, 2, 3, t + 1)
      ctr = ctr + 1
    end
    startIdx = 1
  end
  if not isLoop then
    discMap[#nodes] = ctr - 1 -- For the loop case, we do not set the last node->divPoint map, since the divPoints extend beyond the last node.
  end
  for i = ctr, #divPoints do -- Remove excess elements.
    divPoints[i], divWidths[i], normals[i] = nil, nil, nil
  end
  computeFrenetFrame(spline)
end

-- Interpolates the nodes and widths of the given spline with 'standard' Catmull-Rom splines to generate the secondary geometry properties.
-- [The secondary geometry data is stored in the given spline object.]
local function catmullRomFree(spline, minNumDivIn)
  local minNumDivisionsFinal = minNumDivIn or defaultMinNumDivisions
  local divPoints, divWidths, normals, discMap = spline.divPoints, spline.divWidths, spline.normals, spline.discMap
  local nodes, widths, nmls = spline.nodes, spline.widths, spline.nmls
  local numNodes, startIdx, ctr = #nodes, 0, 1
  local isLoop = spline.isLoop
  for j = 1, numNodes - (isLoop and 0 or 1) do
    discMap[j] = max(1, ctr - 1)
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2) % numNodes) + 1, ((j - 1) % numNodes) + 1, (j % numNodes) + 1, ((j + 1) % numNodes) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numNodes, j + 2)
    end
    local p0, p1, p2, p3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local n0, n1, n2, n3 = nmls[i1], nmls[i2], nmls[i3], nmls[i4]
    local z0, z1, z2, z3 = p0.z, p1.z, p2.z, p3.z
    local w0, w1, w2, w3 = widths[i1], widths[i2], widths[i3], widths[i4]
    local numDivisions = max(minNumDivisionsFinal, floor(p1:distance(p2) / maxDivisionSpacing + 0.5))
    local step = 1.0 / numDivisions
    for k = startIdx, numDivisions do
      local t = k * step
      local tPlus1 = t + 1
      divPoints[ctr] = divPoints[ctr] or vec3()
      normals[ctr] = normals[ctr] or vec3()
      catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5, divPoints[ctr])
      divPoints[ctr].z = monotonicSteffen(z0, z1, z2, z3, 0, 1, 2, 3, tPlus1)
      catmullRomCentripetalFast(n0, n1, n2, n3, t, 0.5, normals[ctr])
      divWidths[ctr] = monotonicSteffen(w0, w1, w2, w3, 0, 1, 2, 3, tPlus1)
      ctr = ctr + 1
    end
    startIdx = 1
  end
  if not isLoop then
    discMap[#nodes] = ctr - 1 -- For the loop case, we do not set the last node->divPoint map, since the divPoints extend beyond the last node.
  end
  for i = ctr, #divPoints do -- Remove excess elements.
    divPoints[i], divWidths[i], normals[i] = nil, nil, nil
  end
  computeFrenetFrame(spline)
end

-- Helper function to calculate curvature at a specific node for banking
local function calculateCurvatureAtNode(nodes, nodeIdx)
  local numNodes = #nodes
  if nodeIdx < 2 or nodeIdx > numNodes - 1 then
    return 0 -- No curvature at endpoints
  end
  
  local p0, p1, p2 = nodes[nodeIdx - 1], nodes[nodeIdx], nodes[nodeIdx + 1]
  
  -- Calculate vectors from p1 to p0 and p1 to p2 (matching original setAutoBanking logic)
  tmp1:setSub2(p1, p0)
  tmp1:normalize()
  tmp2:setSub2(p1, p2)
  tmpTangent:set(tmp2)
  tmpTangent:normalize()
  
  -- Calculate angle between the two vectors
  local unsignedAngle = acos(max(-1, min(1, tmp1:dot(tmpTangent))))
  local avgLen = 0.5 * (tmp1:length() + tmpTangent:length())
  local curvature = avgLen > 1e-5 and unsignedAngle / avgLen or 0
  
  -- Determine the sign of curvature using cross product (matching original setAutoBanking logic)
  tmpCross:setCross(tmp1, tmpTangent)
  local sign = tmpCross:dot(globalUp) >= 0 and 1 or -1
  return curvature * sign
end

-- Interpolates the nodes and widths of the given spline with Catmull-Rom splines, applying auto banking with falloff.
-- [The secondary geometry data is stored in the given spline object.]
local function catmullRomFreeWithBanking(spline, minNumDivIn, bankStrength)
  local minNumDivisionsFinal = minNumDivIn or defaultMinNumDivisions
  local divPoints, divWidths, normals, discMap = spline.divPoints, spline.divWidths, spline.normals, spline.discMap
  local nodes, widths, nmls = spline.nodes, spline.widths, spline.nmls
  local numNodes, startIdx, ctr = #nodes, 0, 1
  local isLoop = spline.isLoop
  
  for j = 1, numNodes - (isLoop and 0 or 1) do
    discMap[j] = max(1, ctr - 1)
    local i1, i2, i3, i4
    if isLoop then
      i1, i2, i3, i4 = ((j - 2) % numNodes) + 1, ((j - 1) % numNodes) + 1, (j % numNodes) + 1, ((j + 1) % numNodes) + 1
    else
      i1, i2, i3, i4 = max(1, j - 1), j, j + 1, min(numNodes, j + 2)
    end
    local p0, p1, p2, p3 = nodes[i1], nodes[i2], nodes[i3], nodes[i4]
    local n0, n1, n2, n3 = nmls[i1], nmls[i2], nmls[i3], nmls[i4]
    local z0, z1, z2, z3 = p0.z, p1.z, p2.z, p3.z
    local w0, w1, w2, w3 = widths[i1], widths[i2], widths[i3], widths[i4]
    local numDivisions = max(minNumDivisionsFinal, floor(p1:distance(p2) / maxDivisionSpacing + 0.5))
    local step = 1.0 / numDivisions
    
    for k = startIdx, numDivisions do
      local t = k * step
      local tPlus1 = t + 1
      divPoints[ctr] = divPoints[ctr] or vec3()
      normals[ctr] = normals[ctr] or vec3()
      
      catmullRomCentripetalFast(p0, p1, p2, p3, t, 0.5, divPoints[ctr])
      divPoints[ctr].z = monotonicSteffen(z0, z1, z2, z3, 0, 1, 2, 3, tPlus1)
      
      -- Interpolate base normals first
      catmullRomCentripetalFast(n0, n1, n2, n3, t, 0.5, normals[ctr])
      
               -- Apply banking with falloff for nodes 1 and 2 (the main nodes of this segment)
         if bankStrength > 0 then
                  -- Calculate banking for node 1 (i2) with falloff based on distance from t=0
          local falloff1 = max(0, 1.0 - abs(t) * (spline.autoBankFalloff or 2.0)) -- Falloff from t=0 to t=1/falloff
          if falloff1 > 0 then
            local curvature1 = calculateCurvatureAtNode(nodes, i2)
            if curvature1 ~= 0 then
              local bankAngle1 = -sign(curvature1) * curvatureToBankAngle(abs(curvature1), bankStrength) * falloff1
              local rotated1 = rotateVecAroundAxis(normals[ctr], tmpTangent, bankAngle1)
              normals[ctr]:setLerp(normals[ctr], rotated1, falloff1 * 0.5)
            end
          end
          
          -- Calculate banking for node 2 (i3) with falloff based on distance from t=1
          local falloff2 = max(0, 1.0 - abs(t - 1) * (spline.autoBankFalloff or 2.0)) -- Falloff from t=0.5 to t=1
          if falloff2 > 0 then
            local curvature2 = calculateCurvatureAtNode(nodes, i3)
            if curvature2 ~= 0 then
              local bankAngle2 = -sign(curvature2) * curvatureToBankAngle(abs(curvature2), bankStrength) * falloff2
              local rotated2 = rotateVecAroundAxis(normals[ctr], tmpTangent, bankAngle2)
              normals[ctr]:setLerp(normals[ctr], rotated2, falloff2 * 0.5)
            end
          end
       end
      
      divWidths[ctr] = monotonicSteffen(w0, w1, w2, w3, 0, 1, 2, 3, tPlus1)
      ctr = ctr + 1
    end
    startIdx = 1
  end
  
  if not isLoop then
    discMap[#nodes] = ctr - 1 -- For the loop case, we do not set the last node->divPoint map, since the divPoints extend beyond the last node.
  end
  
  for i = ctr, #divPoints do -- Remove excess elements.
    divPoints[i], divWidths[i], normals[i] = nil, nil, nil
  end
  
  computeFrenetFrame(spline)
end

-- Computes the graph path from the given nodes and populates the spline's geometry data.
local function computeGraphPathFromNodes(spline)
  local nodes, path = spline.graphNodes, spline.graphPath
  if #nodes < 2 then
    return -- Not enough nodes to compute a path.
  end

  -- Initialize the spline's geometry arrays if they don't exist.
  if not spline.divPoints then
    spline.divPoints = {}
  end
  if not spline.divWidths then
    spline.divWidths = {}
  end
  if not spline.normals then
    spline.normals = {}
  end

  -- Compute the path and populate geometry.
  local ctr, startIdx = 1, 1
  for i = 1, #nodes - 1 do
    local section = map.getPath(nodes[i], nodes[i + 1])
    for j = startIdx, #section do
      path[ctr] = section[j]

      -- Get the actual position from the navgraph
      local nodePos = map.getMap().nodes[section[j]].pos

      -- Populate the spline's geometry with the navgraph path points
      spline.divPoints[ctr] = spline.divPoints[ctr] or vec3()
      spline.divPoints[ctr]:set(nodePos)

      -- Set default width and normal for intermediate points
      spline.divWidths[ctr] = 5.0 -- Default width
      spline.normals[ctr] = spline.normals[ctr] or vec3(0, 0, 1)
      spline.normals[ctr]:set(map.surfaceNormal(nodePos, 1.0))

      ctr = ctr + 1
    end
    startIdx = 2 -- Set the start index to 2 for all [2, .., n] iterations, so as to avoid duplicates in subsequent iterations.
  end

  -- Remove excess elements from all arrays.
  for i = ctr, #path do
    path[i] = nil
  end
  for i = ctr, #spline.divPoints do
    spline.divPoints[i], spline.divWidths[i], spline.normals[i] = nil, nil, nil
  end

  -- Compute the Frenet frame for proper spline surface rendering.
  if #spline.divPoints > 1 then
    computeFrenetFrame(spline)
  end
end


-- Public interface.
M.getPreRotQuats =                                      getPreRotQuats

M.getBarScale =                                         getBarScale

M.squaredSegSegDist =                                   squaredSegSegDist

M.isMouseOverNode =                                     isMouseOverNode
M.isMouseOverSpline =                                   isMouseOverSpline
M.isMouseOverPolyline =                                 isMouseOverPolyline
M.isMouseOverRib =                                      isMouseOverRib
M.isMouseOverBar =                                      isMouseOverBar
M.isMouseOverGraphNode =                                isMouseOverGraphNode

M.getAABB =                                             getAABB
M.computeSplinePolygon =                                computeSplinePolygon
M.isPointInTriangle =                                   isPointInTriangle
M.getTerrainNormal =                                    getTerrainNormal
M.getTerrainNormalInPlace =                             getTerrainNormalInPlace
M.rotateVecAroundZ =                                    rotateVecAroundZ
M.rotateVecAroundAxis =                                 rotateVecAroundAxis
M.rotateVecAroundAxisInlined =                          rotateVecAroundAxisInlined
M.computeTurningRadius =                                computeTurningRadius

M.isLineSegIntersect =                                  isLineSegIntersect
M.intersection2LineSegs =                               intersection2LineSegs

M.angleBetweenVecsNorm =                                angleBetweenVecsNorm
M.angleBetweenVecs =                                    angleBetweenVecs
M.angleBetweenVecs2D =                                  angleBetweenVecs2D
M.signedAngleBetweenVecs =                              signedAngleBetweenVecs
M.signedAngleAroundAxis =                               signedAngleAroundAxis

M.intersectsUpQuadBarycentric =                         intersectsUpQuadBarycentric
M.pointInQuadBarycentric =                              pointInQuadBarycentric
M.computeSourcesAABB =                                  computeSourcesAABB
M.getAllQuadrilaterals =                                getAllQuadrilaterals
M.populateTreeQuads =                                   populateTreeQuads

M.splitSplineGeometry =                                 splitSplineGeometry
M.splitLoopSplineGeometry =                             splitLoopSplineGeometry
M.joinSplineGeometry =                                  joinSplineGeometry
M.flipSplineDirection =                                 flipSplineDirection

M.closestRibbonSegPointToPoint =                        closestRibbonSegPointToPoint
M.getNodeSpansInsidePolygon =                           getNodeSpansInsidePolygon

M.projectPointToSpline =                                projectPointToSpline
M.sampleSpline =                                        sampleSpline
M.sampleSplineAdaptive =                                sampleSplineAdaptive
M.translateSpline =                                     translateSpline

M.computeRandomJitterQuat_ZOnly =                       computeRandomJitterQuat_ZOnly
M.computeRandomJitterQuat =                             computeRandomJitterQuat
M.computeRandomJitterQuatFromFreedomAxes =              computeRandomJitterQuatFromFreedomAxes

M.updateRibPointsFree =                                 updateRibPointsFree
M.updateRibPointsRaycast =                              updateRibPointsRaycast
M.updateBarPoints =                                     updateBarPoints
M.updateBarPointsGraph =                                updateBarPointsGraph

M.computeSDF =                                          computeSDF
M.getScanlineSpans =                                    getScanlineSpans

M.catmullRomCentripetalFast =                           catmullRomCentripetalFast
M.catmullRomNodesOnly =                                 catmullRomNodesOnly
M.catmullRomNodesWidthsOnly =                           catmullRomNodesWidthsOnly
M.catmullRomNodesWidthsVelVelLimits =                   catmullRomNodesWidthsVelVelLimits
M.catmullRomRaycast =                                   catmullRomRaycast
M.catmullRomConformToTerrain =                          catmullRomConformToTerrain
M.catmullRomFree =                                      catmullRomFree
M.catmullRomFreeWithBanking =                           catmullRomFreeWithBanking

M.computeGraphPathFromNodes =                           computeGraphPathFromNodes

return M