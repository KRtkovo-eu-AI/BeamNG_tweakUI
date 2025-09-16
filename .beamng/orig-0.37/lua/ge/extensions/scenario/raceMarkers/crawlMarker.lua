-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local C = {}
local basePrefix = "base_marker_"
local arrowPrefix = "arrow_marker_"
local baseShape = "art/shapes/interface/checkpoint_marker_base.dae"
local arrowShape = "/art/shapes/interface/s_mm_arrow_ribbon_down.dae"

local modeInfos = {
  default = {
    color = {1, 1, 1},
    baseColor = {1, 1, 1},
    showBase = true,
  },
  inactive = {
    color = {0.5, 0.5, 0.5},
    baseColor = {0.5, 0.5, 0.5},
    showBase = true,
  },
  current = {
    color = {1, 0.07, 0},
    baseColor = {1, 1, 1},
    showBase = true,
  },
  final = {
    color = {0.1, 0.3, 1},
    baseColor = {1, 1, 1},
    showBase = true,
  },
  finished = {
    color = {0.4, 1, 0.2},
    baseColor = {1, 1, 1},
    showBase = false,
  },
  hidden = {
    color = {0, 0, 0},
    baseColor = {0, 0, 0},
    showBase = false,
  }
}

local fadeNear = 5
local fadeFar = 25
local arrowHeight = 3
local arrowStartHeight = -2
local baseVisibleRadius = 25

local function inverseLerp(min, max, value)
 if math.abs(max - min) < 1e-30 then return min end
 return (value - min) / (max - min)
end

-- todo: replace this by a HSV-lerp if blending with non-gray colors
local function lerpColor(a,b,t)
  return {lerp(a[1],b[1],t),lerp(a[2],b[2],t),lerp(a[3],b[3],t)}
end

-- called when this object is created. initialize variables here (but dont spawn objects)
function C:init(id)
  self.id = id
  self.visible = false

  self.pos = nil
  self.radius = nil
  self.color = nil

  self.fadeNear = fadeNear
  self.fadeFar = fadeFar

  self.colorTimer = 0
  self.colorLerpDuration = 0.5

  self.base = nil
  self.arrow = nil

  self.mode = 'hidden'
  self.oldMode = 'hidden'
  self.modeInfos = deepcopy(modeInfos)

  -- Arrow animation variables
  self.arrowHeightSmoother = newTemporalSpring()
  self.baseVisibilitySmoother = newTemporalSpring()
end

-- called every frame to update the visuals.
function C:update(dt, dtSim)
  self.colorTimer = self.colorTimer + dt
  if self.colorTimer >= self.colorLerpDuration then
    if self.mode == 'hidden' then
      self:hide()
    end
  end
  if not self.visible then return end

  local playerPosition = vec3(0,0,0)
  playerPosition:set(core_camera.getPosition())

  local distanceFromMarker = self.pos:distance(playerPosition)

  local t = clamp(self.colorTimer / self.colorLerpDuration,0,1)
  local color = lerpColor(self.modeInfos[self.oldMode or 'default'].color, self.modeInfos[self.mode or 'default'].color, t)
  local baseColor = lerpColor(self.modeInfos[self.oldMode or 'default'].baseColor, self.modeInfos[self.mode or 'default'].baseColor, t)

  self.currentColor = ColorF(color[1],color[2],color[3],color[4] or 1)
  self.currentColor.a = self.currentColor.a * (clamp(inverseLerp(self.fadeNear,self.fadeFar,distanceFromMarker),0,1))

  if self.base then
    local showBase = self.modeInfos[self.mode or 'inactive'].showBase


    local targetVisibility = showBase and (distanceFromMarker > baseVisibleRadius and 0 or 1) or 0
    local baseVisibility = math.min(self.baseVisibilitySmoother:get(targetVisibility, dtSim), 1)

    -- Set alpha based on visibility factor and distance
    self.base.instanceColor = ColorF(baseColor[1],baseColor[2],baseColor[3],baseVisibility):asLinear4F()

    -- Set z position based on visibility factor (0 = 1m below, 1 = marker position)
    local baseZ = lerp(-1, 0, baseVisibility)-0.5
    self.base:setPosition(vec3(self.pos.x, self.pos.y, self.pos.z + baseZ))

    self.base:updateInstanceRenderData()
    --simpleDebugText3d(string.format("Base Visibility: %.2f", baseVisibility), self.pos, self.radius)
  end

  if self.arrow then
    local fwd = (playerPosition-self.pos)
    local rot = quatFromDir(fwd:z0()):toTorqueQuat()
    self.arrow:setField('rotation', 0, rot.x .. ' ' .. rot.y .. ' ' .. rot.z .. ' ' .. rot.w)

    -- Only show arrow if not hidden
    if self.mode == 'hidden' then
      self.arrow.instanceColor = ColorF(0,0,0,0):asLinear4F()
      self.arrow.instanceColor1 = ColorF(0,0,0,0):asLinear4F()
    else
      self.arrow.instanceColor = self.currentColor:asLinear4F()
      self.arrow.instanceColor1 = ColorF(1,1,1,self.currentColor.a):asLinear4F()
    end

    -- Linear smoother animation for arrow position
    local currentTime = os.clock()
    self.delay = self.delay - dtSim
    local baseTargetHeight = self.delay < 0 and arrowHeight or arrowStartHeight

    -- Visibility check for current and final markers - apply to base height before smoothing
    local targetHeight = baseTargetHeight
    if self.mode == 'current' or self.mode == 'final' then
      local testHeight = baseTargetHeight
      local maxTestHeight = 100
      local heightIncrement = 2

      while testHeight <= maxTestHeight do
        local arrowPos = vec3(self.pos.x, self.pos.y, self.pos.z + testHeight)
        local rayDirection = playerPosition - arrowPos
        local rayLength = rayDirection:length()
        --simpleDebugText3d(string.format("Ray Length: %.2f", rayLength), arrowPos, 1)
        -- Check if arrow is visible from camera position
        if castRayStatic(arrowPos, rayDirection, rayLength, nil) >= rayLength then
          targetHeight = testHeight
          break
        end

        testHeight = testHeight + heightIncrement
      end
    end

    -- Apply sin movement on top of the visibility-adjusted height
    local sinOffset = self.delay < 0 and math.sin(currentTime * 1.9 + self.originalDelay) * 0.4 or 0
    targetHeight = targetHeight + sinOffset

    local currentArrowHeight = self.arrowHeightSmoother:get(targetHeight, dtSim)
    self.arrow:setPosition(vec3(0,0,currentArrowHeight)+self.pos)
    self.arrow:updateInstanceRenderData()

    -- Distance-based arrow scaling: very close = small scale, far = large scale
    local veryCloseDistance = 15
    local minDistance = 50
    local maxDistance = 650
    local veryCloseScale = 0.25
    local minScale = 2.0
    local maxScale = 10.0

    local scaleFactor = 1.0
    if distanceFromMarker <= veryCloseDistance then
      -- Very close range: scale down from minScale to veryCloseScale
      local t = clamp(inverseLerp(0, veryCloseDistance, distanceFromMarker), 0, 1)
      scaleFactor = lerp(veryCloseScale, minScale, t)
    elseif distanceFromMarker <= minDistance then
      -- Close range: maintain normal scale
      scaleFactor = minScale
    else
      -- Far range: scale up from minScale to maxScale
      local t = clamp(inverseLerp(minDistance, maxDistance, distanceFromMarker), 0, 1)
      scaleFactor = lerp(minScale, maxScale, t)
    end

    self.arrow:setScale(vec3(scaleFactor, scaleFactor, scaleFactor))
    --simpleDebugText3d(string.format("Scale Factor: %.2f", scaleFactor), self.pos, self.radius)
  end
end

-- setting it to represent checkpoints. mode can be:
-- inactive (grayed out, no base marker)
-- current (red, shows base marker)
-- finalInactive (blue arrow, no base marker)
-- finalActive (blue arrow and base marker)
-- finished (green, no base marker)
-- hidden (transparent, no base marker)
local baseFactor = 1.9
function C:setToCheckpoint(wp)
  self.pos = vec3(wp.pos)
  self.radius = wp.radius

  self.fadeNear = wp.fadeNear or self.fadeNear
  self.fadeFar = wp.fadeFar or self.fadeFar
  self.delay = wp.delay or 0
  self.originalDelay = self.delay
  if self.base then
    self.base:setPosition(vec3(self.pos))
    self.base:setScale(vec3(self.radius*baseFactor, self.radius*baseFactor, self.radius*baseFactor))
    -- Reset base visibility smoother when setting checkpoint
    self.baseVisibilitySmoother:set(0)
  end
  if self.arrow then
    -- Reset arrow animation when setting checkpoint
    self.arrowHeightSmoother:set(arrowStartHeight)
    self.arrow:setPosition(vec3(0,0,arrowStartHeight)+self.pos)
    self.arrow:setScale(vec3(1,1,1))
  end
end
function C:drawOnMinimap(td)
  if self.mode == 'hidden' then
    return
  end
  ui_apps_minimap_utils.simpleCircle(self.pos, color(self.currentColor.r*255, self.currentColor.g*255, self.currentColor.b*255, 255))
end

function C:setMode(mode)
  if mode ~= 'hidden' then
    self:show()
  else
    self:hide()
  end
  if self.oldMode ~= self.mode then

  end
  self.oldMode = self.mode
  self.mode = mode
  self.colorTimer = 0

  self:update(0,0)
end

-- visibility management
function C:setVisibility(v)
  self.visible = v

  if self.base then
    self.base.hidden = not v
  end
  if self.arrow then
    self.arrow.hidden = not v
  end
end

function C:hide() self:setVisibility(false) end
function C:show() self:setVisibility(true)  end

-- marker management
function C:createObject(shapeName, objectName)
  local marker =  createObject('TSStatic')
  marker:setField('shapeName', 0, shapeName)
  marker:setPosition(vec3(0, 0, 0))
  marker.scale = vec3(1, 1, 1)
  marker:setField('rotation', 0, '1 0 0 0')
  marker.useInstanceRenderData = true
  marker:setField('instanceColor', 0, '1 1 1 1')
  marker:setInternalName('marker')
  marker.canSave = false
  marker.hidden = true
  marker:registerObject(objectName)

  local scenarioObjectsGroup = scenetree.ScenarioObjectsGroup
  if scenarioObjectsGroup then
    scenarioObjectsGroup:addObject(marker)
  end

  return marker
end

-- creates neccesary objects
function C:createMarkers()
  self:clearMarkers()
  self._ids = {}
  if not self.base then
    self.base = self:createObject(baseShape,basePrefix..self.id)
    table.insert(self._ids, self.base:getId())
  end
  if not self.arrow then
    self.arrow = self:createObject(arrowShape,arrowPrefix..self.id)
    table.insert(self._ids, self.arrow:getId())
  end
end

-- destorys/cleans up all objects created by this
function C:clearMarkers()
  for _, id in ipairs(self._ids or {}) do
    local obj = scenetree.findObjectById(id)
    if obj then
      obj:delete()
    end
  end
  self._ids = nil
  self.base = nil
  self.arrow = nil
end

return function(...)
  local o = {}
  setmetatable(o, C)
  C.__index = C
  o:init(...)
  return o
end