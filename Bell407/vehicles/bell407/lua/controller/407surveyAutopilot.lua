local M = {}
M.type = "auxiliary"
M.defaultOrder = 60

local states = {
        idle = "idle",
        armed = "armed",
        engineStart = "engineStart",
        spinup = "spinup",
        takeoff = "takeoff",
        transitStart = "transitStart",
        holding = "holding",
        pattern = "pattern",
        finishHover = "finishHover",
        returnStart = "returnStart",
        returnHome = "returnHome",
        landing = "landing",
        complete = "complete"
}

local plan = nil
local state = states.idle
local stateTimer = 0
local status = {
        state = states.idle,
        planLoaded = false,
        armed = false,
        active = false,
        waypointIndex = 0,
        waypointCount = 0,
        progress = 0,
        finishMode = nil,
        target = nil,
        planId = nil,
        event = nil,
        rotorRPM = 0,
        altitude = 0,
        altitudeASL = 0,
        awaitingPatternStart = false
}
local statusDirty = false
local statusUpdateTimer = 0

local altitudeHoldPID = newPIDParallel(0.85, 0.18, 0.24, -3.5, 3.5)
local verticalSpeedPID = newPIDParallel(0.58, 0.12, 0.18, -1, 1)

local pitchAnglePID = newPIDParallel(2.6, 0.3, 0.64, -1.4, 1.4)
local rollAnglePID = newPIDParallel(2.4, 0.28, 0.6, -1.4, 1.4)
local yawAnglePID = newPIDParallel(2.0, 0.2, 0.65, -1.2, 1.2)

local pitchRatePID = newPIDParallel(1.25, 0.2, 0.22, -1, 1)
local rollRatePID = newPIDParallel(1.15, 0.2, 0.22, -1, 1)
local yawRatePID = newPIDParallel(1.1, 0.18, 0.22, -1, 1)

local pitchSmoother = newTemporalSmoothingNonLinear(6)
local rollSmoother = newTemporalSmoothingNonLinear(6)
local yawSmoother = newTemporalSmoothingNonLinear(6)
local altitudeSmoother = newTemporalSmoothingNonLinear(10)
local pitchRateSmoother = newTemporalSmoothingNonLinear(6)
local rollRateSmoother = newTemporalSmoothingNonLinear(6)
local yawRateSmoother = newTemporalSmoothingNonLinear(6)
local accelSmootherX = newTemporalSmoothingNonLinear(8)
local accelSmootherY = newTemporalSmoothingNonLinear(8)
local accelSmootherZ = newTemporalSmoothingNonLinear(8)

local gravity = 9.81

local rotorSpinThreshold = 380
local rotorStableTime = 1.5
local holdDuration = 2.0
local positionTolerance = 1.5
local waypointTolerance = 3.0
local landingDescentRate = 0.6

local currentWaypoint = 1
local currentTargetPos = nil
local currentTargetHeading = nil
local currentTargetSpeed = 0
local landingTargetAltitude = nil
local takeoffAnchor = nil
local spinupTimer = 0
local holdTimer = 0
local holdStableTimer = 0
local holdReadyAnnounced = false

local lastOutputs = {lift = 0, pitch = 0, roll = 0, yaw = 0}

local controlRateLimits = {
        lift = 3.6,
        pitch = 1.6,
        roll = 1.6,
        yaw = 2.1
}

local controlBindings = {
        lift = {input = "b407_lift", electric = "b407_lift_input"},
        pitch = {input = "b407_pitch", electric = "b407_pitch_input"},
        roll = {input = "b407_roll", electric = "b407_roll_input"},
        yaw = {input = "b407_yaw", electric = "b407_yaw_input"}
}

local controlDirections = {lift = 1, pitch = 1, roll = 1, yaw = 1}

local liftOrientationState = {locked = false, failTimer = 0, successTimer = 0, lastAltitude = nil, lastAltitudeError = nil}
local kinematicHistory = {pitch = nil, roll = nil, yaw = nil, velX = nil, velY = nil, velZ = nil}

local planIdCounter = 0

local defaultControlContext = {
        maxTilt = 0.22,
        yawClamp = 0.38,
        altitudeFocus = 0.35,
        altitudeRange = 8,
        minHorizontal = 0.1,
        positionGain = 0.014,
        velocityGain = 0.11,
        lateralPositionGain = 0.016,
        lateralVelocityGain = 0.11,
        levelCompensation = 0.2,
        verticalDamping = 0.12,
        verticalClamp = 0.28,
        headingTolerance = 0.18,
        pitchRateDamping = 0.18,
        rollRateDamping = 0.18,
        yawRateDamping = 0.12,
        forwardAccelDamping = 0.022,
        lateralAccelDamping = 0.022,
        verticalAccelDamping = 0.08,
        pitchGuardLimit = 0.22,
        rollGuardLimit = 0.22,
        yawGuardLimit = 0.45,
        pitchGuardStrength = 0.62,
        rollGuardStrength = 0.62,
        yawGuardStrength = 0.44,
        pitchGuardRate = 1.0,
        rollGuardRate = 1.0,
        yawGuardRate = 1.5,
        verticalHoldFactor = 1,
        verticalHoldThreshold = nil,
        lockHeadingWhenVertical = false,
        recoveryHorizontalFactor = 0.15,
        levelHoldGain = 1.0,
        verticalSettleTolerance = 0.6,
        verticalSettleRate = 0.6,
        verticalHorizontalLimit = 0.7,
        verticalYawRateLimit = 0.8,
        verticalClimbMin = nil
}

local stateControlContexts = {}

stateControlContexts[states.takeoff] = {
        maxTilt = 0.1,
        yawClamp = 0.14,
        altitudeFocus = 1.0,
        altitudeRange = 12,
        minHorizontal = 0.0,
        positionGain = 0.01,
        velocityGain = 0.09,
        lateralPositionGain = 0.012,
        lateralVelocityGain = 0.09,
        levelCompensation = 0.18,
        verticalDamping = 0.12,
        verticalClamp = 0.24,
        headingTolerance = 0.16,
        pitchRateDamping = 0.26,
        rollRateDamping = 0.26,
        yawRateDamping = 0.16,
        forwardAccelDamping = 0.034,
        lateralAccelDamping = 0.034,
        verticalAccelDamping = 0.14,
        verticalHoldThreshold = 4,
        verticalHoldFactor = 0,
        lockHeadingWhenVertical = true,
        pitchGuardLimit = 0.1,
        rollGuardLimit = 0.1,
        yawGuardLimit = 0.22,
        pitchGuardStrength = 0.92,
        rollGuardStrength = 0.92,
        yawGuardStrength = 0.72,
        pitchGuardRate = 0.72,
        rollGuardRate = 0.72,
        yawGuardRate = 0.74,
        recoveryHorizontalFactor = 0,
        levelHoldGain = 1.4,
        verticalSettleTolerance = 0.5,
        verticalSettleRate = 0.45,
        verticalHorizontalLimit = 0.35,
        verticalYawRateLimit = 0.45,
        verticalClimbMin = 1.4,
        forceVerticalOnly = true
}

stateControlContexts[states.transitStart] = {
        maxTilt = 0.2,
        yawClamp = 0.32,
        altitudeFocus = 0.6,
        altitudeRange = 9,
        minHorizontal = 0.15,
        positionGain = 0.014,
        velocityGain = 0.11,
        lateralPositionGain = 0.016,
        lateralVelocityGain = 0.11,
        levelCompensation = 0.2,
        verticalDamping = 0.12,
        verticalClamp = 0.28,
        headingTolerance = 0.18,
        pitchRateDamping = 0.18,
        rollRateDamping = 0.18,
        yawRateDamping = 0.12
}

stateControlContexts[states.holding] = {
        maxTilt = 0.16,
        yawClamp = 0.28,
        altitudeFocus = 0.75,
        altitudeRange = 7,
        minHorizontal = 0.12,
        positionGain = 0.013,
        velocityGain = 0.1,
        lateralPositionGain = 0.015,
        lateralVelocityGain = 0.1,
        levelCompensation = 0.22,
        verticalDamping = 0.12,
        verticalClamp = 0.26,
        headingTolerance = 0.14,
        pitchRateDamping = 0.2,
        rollRateDamping = 0.2,
        yawRateDamping = 0.12,
        forwardAccelDamping = 0.028,
        lateralAccelDamping = 0.028,
        levelHoldGain = 1.2,
        verticalSettleTolerance = 0.45,
        verticalSettleRate = 0.4,
        verticalHorizontalLimit = 0.4,
        verticalYawRateLimit = 0.5
}

stateControlContexts[states.pattern] = {
        maxTilt = 0.26,
        yawClamp = 0.42,
        altitudeFocus = 0.4,
        altitudeRange = 7,
        minHorizontal = 0.2,
        positionGain = 0.014,
        velocityGain = 0.12,
        lateralPositionGain = 0.016,
        lateralVelocityGain = 0.12,
        levelCompensation = 0.18,
        verticalDamping = 0.13,
        verticalClamp = 0.3,
        headingTolerance = 0.18,
        pitchRateDamping = 0.17,
        rollRateDamping = 0.17,
        yawRateDamping = 0.12
}

stateControlContexts[states.returnStart] = {
        maxTilt = 0.24,
        yawClamp = 0.4,
        altitudeFocus = 0.55,
        altitudeRange = 8,
        minHorizontal = 0.18,
        positionGain = 0.014,
        velocityGain = 0.11,
        lateralPositionGain = 0.016,
        lateralVelocityGain = 0.11,
        levelCompensation = 0.2,
        verticalDamping = 0.12,
        verticalClamp = 0.28,
        headingTolerance = 0.16,
        pitchRateDamping = 0.18,
        rollRateDamping = 0.18,
        yawRateDamping = 0.12
}

stateControlContexts[states.returnHome] = stateControlContexts[states.returnStart]

stateControlContexts[states.finishHover] = {
        maxTilt = 0.18,
        yawClamp = 0.3,
        altitudeFocus = 0.8,
        altitudeRange = 6,
        minHorizontal = 0.05,
        positionGain = 0.012,
        velocityGain = 0.1,
        lateralPositionGain = 0.014,
        lateralVelocityGain = 0.1,
        levelCompensation = 0.24,
        verticalDamping = 0.12,
        verticalClamp = 0.26,
        headingTolerance = 0.14,
        pitchRateDamping = 0.22,
        rollRateDamping = 0.22,
        yawRateDamping = 0.12,
        forwardAccelDamping = 0.03,
        lateralAccelDamping = 0.03,
        verticalAccelDamping = 0.12,
        levelHoldGain = 1.25,
        verticalSettleTolerance = 0.4,
        verticalSettleRate = 0.4,
        verticalHorizontalLimit = 0.35,
        verticalYawRateLimit = 0.55
}

stateControlContexts[states.landing] = {
        maxTilt = 0.18,
        yawClamp = 0.32,
        altitudeFocus = 0.9,
        altitudeRange = 6,
        minHorizontal = 0.05,
        positionGain = 0.012,
        velocityGain = 0.1,
        lateralPositionGain = 0.014,
        lateralVelocityGain = 0.1,
        levelCompensation = 0.24,
        verticalDamping = 0.18,
        verticalClamp = 0.3,
        headingTolerance = 0.16,
        pitchRateDamping = 0.24,
        rollRateDamping = 0.24,
        yawRateDamping = 0.14,
        forwardAccelDamping = 0.03,
        lateralAccelDamping = 0.03,
        verticalAccelDamping = 0.14,
        levelHoldGain = 1.2,
        verticalSettleTolerance = 0.35,
        verticalSettleRate = 0.35,
        verticalHorizontalLimit = 0.35,
        verticalYawRateLimit = 0.6
}

local function getControlContextForState(stateName)
        return stateControlContexts[stateName] or defaultControlContext
end

local function copyVec3(vec)
        if not vec then return nil end
        if vec.x then
                local copy = {x = vec.x, y = vec.y, z = vec.z}
                if vec.groundZ ~= nil then copy.groundZ = vec.groundZ end
                if vec.altitudeAGL ~= nil then copy.altitudeAGL = vec.altitudeAGL end
                return copy
        end
        local copy = {x = vec[1] or 0, y = vec[2] or 0, z = vec[3] or 0}
        if vec.groundZ ~= nil then copy.groundZ = vec.groundZ end
        if vec.altitudeAGL ~= nil then copy.altitudeAGL = vec.altitudeAGL end
        return copy
end

local function normalizeAngle(angle)
        if not angle then return nil end
        angle = (angle + math.pi) % (math.pi * 2)
        return angle - math.pi
end

local function distance(a, b)
        local dx = a.x - b.x
        local dy = a.y - b.y
        local dz = a.z - b.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distance2D(a, b)
        local dx = a.x - b.x
        local dy = a.y - b.y
        return math.sqrt(dx * dx + dy * dy)
end

local groundRayDirection = vec3(0, 0, -1)
local groundSampleOffset = 80
local groundSampleDistance = 320

local function sampleGroundHeight(pos)
        if not obj or not obj.castRayStatic or not pos then
                return nil
        end

        local origin = vec3(pos.x, pos.y, (pos.z or 0) + groundSampleOffset)
        local hit = obj:castRayStatic(origin, groundRayDirection, groundSampleDistance)
        if hit and hit > 0 and hit < groundSampleDistance then
                return origin.z - hit
        end

        return nil
end

local function clamp(val, min, max)
        if val < min then return min end
        if val > max then return max end
        return val
end

local function getContextValue(context, key)
        if context and context[key] ~= nil then
                return context[key]
        end
        return defaultControlContext[key]
end

local function asinClamped(value)
        if value ~= value then return 0 end
        if value >= 1 then return math.pi * 0.5 end
        if value <= -1 then return -math.pi * 0.5 end
        return math.asin(value)
end

local function readRollPitchYaw()
        if not obj then return 0, 0, 0 end

        local rollRad, pitchRad
        if obj.getRollPitchYawRad then
                rollRad, pitchRad = obj:getRollPitchYawRad()
        end

        local roll, pitch, yaw
        if obj.getRollPitchYaw then
                local r, p, y = obj:getRollPitchYaw()
                yaw = y or yaw
                roll = rollRad ~= nil and rollRad or r
                pitch = pitchRad ~= nil and pitchRad or p

                if roll == nil and r ~= nil then
                        roll = r
                end
                if pitch == nil and p ~= nil then
                        pitch = p
                end

                if roll ~= nil and pitch ~= nil and (not obj.getRollPitchYawRad) then
                        if math.abs(roll) <= 1 and math.abs(pitch) <= 1 then
                                roll = asinClamped(roll)
                                pitch = asinClamped(pitch)
                        end
                end
        end

        if yaw == nil and obj.getYaw then
                yaw = obj:getYaw()
        end

        return roll or 0, pitch or 0, yaw or 0
end

local function measureLocalAcceleration(cosYaw, sinYaw, velXRaw, velYRaw, velZRaw, dt)
        local dtSafe = math.max(dt or 0, 1e-3)
        local ax, ay, az
        if obj and obj.getLinearAccelerationXYZ then
                ax, ay, az = obj:getLinearAccelerationXYZ()
                if type(ax) == "table" then
                        ay = ax.y or ax[2] or ay
                        az = ax.z or ax[3] or az
                        ax = ax.x or ax[1] or ax
                end
        end

        local localForward, localLateral, localVertical
        if ax ~= nil then
                localForward = accelSmootherX:get(cosYaw * (ax or 0) + sinYaw * (ay or 0), dt)
                localLateral = accelSmootherY:get(-sinYaw * (ax or 0) + cosYaw * (ay or 0), dt)
                localVertical = accelSmootherZ:get(az or 0, dt)
        else
                local accelXRaw = 0
                local accelYRaw = 0
                local accelZRaw = 0
                if kinematicHistory.velX then
                        accelXRaw = (velXRaw - kinematicHistory.velX) / dtSafe
                        accelYRaw = (velYRaw - kinematicHistory.velY) / dtSafe
                        accelZRaw = (velZRaw - kinematicHistory.velZ) / dtSafe
                end
                localForward = accelSmootherX:get(cosYaw * accelXRaw + sinYaw * accelYRaw, dt)
                localLateral = accelSmootherY:get(-sinYaw * accelXRaw + cosYaw * accelYRaw, dt)
                localVertical = accelSmootherZ:get(accelZRaw, dt)
        end

        kinematicHistory.velX = velXRaw
        kinematicHistory.velY = velYRaw
        kinematicHistory.velZ = velZRaw

        return localForward or 0, localLateral or 0, localVertical or 0
end

local function isAttitudeStable(pitchLimit, rollLimit, yawRateLimit)
        if not obj then
                return false
        end

        local roll, pitch = readRollPitchYaw()
        roll = roll or 0
        pitch = pitch or 0

        if pitchLimit and math.abs(pitch) > pitchLimit then
                return false
        end
        if rollLimit and math.abs(roll) > rollLimit then
                return false
        end

        if yawRateLimit and yawRateLimit > 0 and obj.getRollPitchYawAngularVelocity then
                local _, _, yawRate = obj:getRollPitchYawAngularVelocity()
                if math.abs(yawRate or 0) > yawRateLimit then
                        return false
                end
        end

        return true
end

local function applyAxisGuard(output, angle, rate, limit, rateLimit, strength)
        if not strength or strength <= 0 then
                return output
        end

        if not limit or limit <= 0 then
                return output
        end

        local currentAngle = angle or 0
        local absAngle = math.abs(currentAngle)
        if absAngle <= limit then
                return output
        end

        local direction = currentAngle >= 0 and 1 or -1
        local normalizedAngle = math.min(1, (absAngle - limit) / math.max(limit, 1e-3))
        local correction = strength * normalizedAngle
        local rateExcess = 0

        if rateLimit and rateLimit > 0 then
                local absRate = math.abs(rate or 0)
                if absRate > rateLimit then
                        rateExcess = math.min(1, (absRate - rateLimit) / math.max(rateLimit, 1e-3))
                        correction = correction + (strength * 0.5) * rateExcess
                end
        end

        if correction <= 0 then
                return clamp(output, -1, 1)
        end

        if output * direction > 0 then
                local suppression = math.min(1, correction + normalizedAngle * 0.5)
                output = output * (1 - suppression)
        end

        output = output - direction * correction

        if absAngle > limit * 1.4 then
                local brake = math.min(1, normalizedAngle * 0.75 + rateExcess * 0.5)
                output = output - direction * (strength * 0.5 * brake + 0.1 * brake)
        end

        return clamp(output, -1, 1)
end

local function applyYawGuard(output, yawError, yawRate, limit, rateLimit, strength)
        if not strength or strength <= 0 then
                return output
        end

        local correction = 0
        local direction = 0

        if limit and limit > 0 then
                local currentError = yawError or 0
                local absError = math.abs(currentError)
                if absError > limit then
                        direction = currentError >= 0 and 1 or -1
                        correction = correction + strength * math.min(1, (absError - limit) / math.max(limit, 1e-3))
                end
        end

        if rateLimit and rateLimit > 0 then
                local currentRate = yawRate or 0
                local absRate = math.abs(currentRate)
                if absRate > rateLimit then
                        if direction == 0 then
                                direction = currentRate >= 0 and 1 or -1
                        end
                        correction = correction + (strength * 0.5) * math.min(1, (absRate - rateLimit) / math.max(rateLimit, 1e-3))
                end
        end

        if correction == 0 or direction == 0 then
                return output
        end

        if output * direction > 0 then
                output = output * (1 - math.min(0.85, correction))
        end

        return clamp(output - direction * correction, -1, 1)
end

local function applyControlOutput(controlName, value, dt)
        local binding = controlBindings[controlName]
        if not binding then
                return
        end

        local direction = controlDirections[controlName] or 1
        local desired = clamp((value or 0) * direction, -1, 1)
        local current = lastOutputs[controlName] or 0
        if dt and controlRateLimits[controlName] then
                local maxDelta = controlRateLimits[controlName] * dt
                if desired > current + maxDelta then
                        desired = current + maxDelta
                elseif desired < current - maxDelta then
                        desired = current - maxDelta
                end
        end
        lastOutputs[controlName] = desired

        if input and input.event then
                input.event(binding.input, lastOutputs[controlName], -1)
        end

        if electrics and electrics.values then
                electrics.values[binding.electric] = lastOutputs[controlName]
        end
end

local function getVelocityComponents()
        if not obj or not obj.getVelocityXYZ then
                return 0, 0, 0
        end

        local vx, vy, vz = obj:getVelocityXYZ()

        if type(vx) == "number" then
                return vx or 0, vy or 0, vz or 0
        end

        if vx then
                local valueType = type(vx)
                local x, y, z
                if valueType == "table" then
                        x = vx.x or vx[1]
                        y = vx.y or vx[2]
                        z = vx.z or vx[3]
                else
                        x = vx.x
                        y = vx.y
                        z = vx.z
                end
                return x or 0, y or 0, z or 0
        end

        return 0, 0, 0
end

local function resetLiftOrientationTracking(forceDirection)
        liftOrientationState.failTimer = 0
        liftOrientationState.successTimer = 0
        liftOrientationState.lastAltitude = nil
        liftOrientationState.lastAltitudeError = nil
        if forceDirection then
                controlDirections.lift = forceDirection
                liftOrientationState.locked = false
        else
                liftOrientationState.locked = (controlDirections.lift ~= 1)
        end
end

local function resetKinematicHistory()
        kinematicHistory.pitch = nil
        kinematicHistory.roll = nil
        kinematicHistory.yaw = nil
        kinematicHistory.velX = nil
        kinematicHistory.velY = nil
        kinematicHistory.velZ = nil
end

local function resetControllers(forceDefaultLift)
        altitudeHoldPID:reset()
        verticalSpeedPID:reset()
        pitchAnglePID:reset()
        rollAnglePID:reset()
        yawAnglePID:reset()
        pitchRatePID:reset()
        rollRatePID:reset()
        yawRatePID:reset()

        pitchSmoother:reset()
        rollSmoother:reset()
        yawSmoother:reset()
        altitudeSmoother:reset()
        pitchRateSmoother:reset()
        rollRateSmoother:reset()
        yawRateSmoother:reset()
        accelSmootherX:reset()
        accelSmootherY:reset()
        accelSmootherZ:reset()

        resetLiftOrientationTracking(forceDefaultLift and 1 or nil)
        resetKinematicHistory()
        lastOutputs.lift = 0
        lastOutputs.pitch = 0
        lastOutputs.roll = 0
        lastOutputs.yaw = 0
end

local function releaseControls()
        applyControlOutput("lift", 0)
        applyControlOutput("pitch", 0)
        applyControlOutput("roll", 0)
        applyControlOutput("yaw", 0)
end

local function updateStatusFromPlan()
        status.planLoaded = plan ~= nil
        status.planId = plan and plan.id or nil
        status.finishMode = plan and plan.finishMode or nil
        status.waypointCount = plan and plan.segmentCount or 0
end

local function markStatusEvent(eventType, extra)
        status.event = extra or {}
        status.event.type = eventType
        statusDirty = true
end

local function pushStatus()
        status.rotorRPM = electrics.values.rotorrpm or 0
        local pos = obj and obj.getPosition and obj:getPosition()
        if pos then
                local absoluteAltitude = pos.z or 0
                local ground = sampleGroundHeight(pos)
                if ground then
                        status.altitude = math.max(0, absoluteAltitude - ground)
                else
                        status.altitude = absoluteAltitude
                end
                status.altitudeASL = absoluteAltitude
        else
                status.altitude = 0
                status.altitudeASL = 0
        end
        if currentTargetPos then
                status.target = {currentTargetPos.x, currentTargetPos.y, currentTargetPos.z}
        else
                status.target = nil
        end
        local payload = {}
        for k, v in pairs(status) do
                payload[k] = v
        end
        if payload.event then
                local eventCopy = {}
                for k, v in pairs(payload.event) do
                        eventCopy[k] = v
                end
                payload.event = eventCopy
                status.event = nil
        end
        if guihooks and guihooks.trigger then
                guihooks.trigger("bell407SurveyStatus", payload)
        end
        statusDirty = false
        statusUpdateTimer = 0.25
end

local function setState(newState, reason)
        if state == newState then
                return
        end
        state = newState
        stateTimer = 0
        status.state = newState
        status.armed = newState == states.armed
        status.active = newState ~= states.idle and newState ~= states.armed and newState ~= states.complete
        markStatusEvent("state", {state = newState, reason = reason})

if newState ~= states.holding then
status.awaitingPatternStart = false
holdReadyAnnounced = false
holdStableTimer = 0
end

        if newState == states.idle then
                currentWaypoint = 1
                currentTargetPos = nil
                currentTargetHeading = nil
                currentTargetSpeed = 0
                takeoffAnchor = nil
                landingTargetAltitude = nil
                spinupTimer = 0
                holdTimer = 0
                status.progress = 0
                status.waypointIndex = 0
                releaseControls()
                resetControllers(true)
        elseif newState == states.armed then
                currentWaypoint = 1
                currentTargetPos = nil
                currentTargetHeading = plan and plan.startHeading or nil
                currentTargetSpeed = 0
                resetControllers()
        elseif newState == states.engineStart then
                resetControllers()
                spinupTimer = 0
        elseif newState == states.spinup then
                spinupTimer = 0
        elseif newState == states.takeoff then
                resetControllers()
                resetLiftOrientationTracking(1)
                local pos = obj and obj.getPosition and obj:getPosition()
                local planHeading = plan and plan.startHeading or currentTargetHeading
                local targetAltitude = plan and (plan.altitude or ((plan.homeGround or (pos and pos.z) or 0) + (plan.altitudeAGL or 0))) or (pos and pos.z)
                if pos then
                        local desiredZ = targetAltitude or pos.z
                        takeoffAnchor = {x = pos.x, y = pos.y, z = desiredZ}
                        currentTargetPos = {x = takeoffAnchor.x, y = takeoffAnchor.y, z = desiredZ}
                end
                if obj then
                        local _, _, currentYaw = readRollPitchYaw()
                        if currentYaw then
                                currentTargetHeading = currentYaw
                        else
                                currentTargetHeading = planHeading
                        end
                else
                        currentTargetHeading = planHeading
                end
                currentTargetSpeed = 0
        elseif newState == states.transitStart then
                resetControllers()
                currentTargetPos = plan and copyVec3(plan.start) or nil
                if currentTargetPos then
                        currentTargetPos.z = plan.altitude
                end
                currentTargetHeading = plan and plan.startHeading or currentTargetHeading
                currentTargetSpeed = plan and (plan.transitSpeed or plan.speed * 0.6) or 0
elseif newState == states.holding then
resetControllers()
holdTimer = 0
holdStableTimer = 0
holdReadyAnnounced = false
status.awaitingPatternStart = false
                currentTargetPos = plan and copyVec3(plan.start) or nil
                if currentTargetPos then
                        currentTargetPos.z = plan.altitude
                end
                currentTargetHeading = plan and plan.startHeading or currentTargetHeading
                currentTargetSpeed = 0
        elseif newState == states.pattern then
                resetControllers()
                currentWaypoint = 1
                currentTargetSpeed = plan and plan.speed or 0
                if plan and plan.patternPoints and plan.patternPoints[1] then
                        currentTargetPos = copyVec3(plan.patternPoints[1].pos)
                        currentTargetHeading = plan.patternPoints[1].heading
                end
        elseif newState == states.finishHover then
                resetControllers()
                if plan then
                        currentTargetPos = plan.finalHoverPos and copyVec3(plan.finalHoverPos) or copyVec3(plan.start)
                        currentTargetPos.z = plan.altitude
                        currentTargetHeading = plan.finalHeading or plan.startHeading
                        currentTargetSpeed = 0
                end
        elseif newState == states.returnStart then
                resetControllers()
                if plan then
                        currentTargetPos = copyVec3(plan.start)
                        currentTargetPos.z = plan.altitude
                        currentTargetHeading = plan.startHeading
                        currentTargetSpeed = plan.speed * 0.7
                end
        elseif newState == states.returnHome then
                resetControllers()
                if plan then
                        currentTargetPos = plan.home and copyVec3(plan.home) or copyVec3(plan.start)
                        currentTargetPos.z = plan.altitude
                        currentTargetHeading = plan.homeHeading or plan.startHeading
                        currentTargetSpeed = plan.speed * 0.7
                end
        elseif newState == states.landing then
                resetControllers()
                if plan then
                        currentTargetPos = plan.home and copyVec3(plan.home) or copyVec3(plan.start)
                        currentTargetHeading = plan.homeHeading or plan.startHeading
                        currentTargetSpeed = plan.speed * 0.4
                        landingTargetAltitude = plan.homeGround or (currentTargetPos.z - 0.3)
                        landingTargetAltitude = landingTargetAltitude + (plan.landingClearance or 0.45)
                end
        elseif newState == states.complete then
                currentTargetSpeed = 0
                releaseControls()
                resetControllers(true)
        end
end

local function validatePlan(newPlan)
        if type(newPlan) ~= "table" then return false, "invalid" end
        if not newPlan.start or not newPlan.patternPoints or #newPlan.patternPoints == 0 then
                return false, "noWaypoints"
        end
        return true
end

local function setPatternPlan(newPlan)
        local ok, reason = validatePlan(newPlan)
        if not ok then
                return false, reason
        end

        planIdCounter = planIdCounter + 1
        plan = {
                id = newPlan.id or planIdCounter,
                start = copyVec3(newPlan.start),
                startHeading = newPlan.startHeading or 0,
                altitude = newPlan.altitude or (newPlan.start and newPlan.start.z) or 0,
                altitudeAGL = newPlan.altitudeAGL,
                speed = newPlan.speed or 10,
                transitSpeed = newPlan.transitSpeed,
                holdTime = newPlan.holdTime or holdDuration,
                finishMode = newPlan.finishMode or "hover",
                home = newPlan.home and copyVec3(newPlan.home) or copyVec3(newPlan.start),
                homeHeading = newPlan.homeHeading or newPlan.startHeading or 0,
                homeGround = newPlan.homeGround or (newPlan.home and (newPlan.home.groundZ or newPlan.home.z)) or (newPlan.start and (newPlan.start.groundZ or newPlan.start.z)) or newPlan.altitude or 0,
                landingClearance = newPlan.landingClearance or 0.45,
                rotorRPM = newPlan.rotorRPM or rotorSpinThreshold,
                finalHoverPos = newPlan.finalHoverPos and copyVec3(newPlan.finalHoverPos) or copyVec3(newPlan.start),
                finalHeading = newPlan.finalHeading or newPlan.startHeading,
                segmentCount = #newPlan.patternPoints,
                totalLength = 0,
                patternPoints = {}
        }

        if plan.altitudeAGL == nil then
                plan.altitudeAGL = math.max(0, plan.altitude - (plan.homeGround or 0))
        end

        local previous = copyVec3(newPlan.start)
        previous.z = plan.altitude
        for i, wp in ipairs(newPlan.patternPoints) do
                local entry = {
                        pos = copyVec3(wp.pos or wp),
                        heading = wp.heading or plan.startHeading,
                        speed = wp.speed or plan.speed,
                        length = wp.length or distance(previous, wp.pos or wp)
                }
                entry.pos.z = (wp.pos and wp.pos.z) or plan.altitude
                plan.patternPoints[i] = entry
                previous = copyVec3(entry.pos)
                plan.totalLength = plan.totalLength + (entry.length or 0)
        end

        plan.finalHoverPos.z = plan.altitude

        if newPlan.totalLength then
                plan.totalLength = newPlan.totalLength
        end

        rotorSpinThreshold = plan.rotorRPM or rotorSpinThreshold
        holdDuration = plan.holdTime or holdDuration

        updateStatusFromPlan()
        status.progress = 0
        status.waypointIndex = 0
        markStatusEvent("plan", {planId = plan.id})
        return true
end

local function arm(patternPlan)
        if patternPlan then
                local ok, reason = setPatternPlan(patternPlan)
                if not ok then
                        return false, reason
                end
        elseif not plan then
                return false, "noPlan"
        end

        setState(states.armed)
        return true
end

local function beginPattern()
        if state == states.holding then
                if not status.awaitingPatternStart then
                        return false, "notReady"
                end
                status.awaitingPatternStart = false
                holdReadyAnnounced = false
                holdStableTimer = 0
                setState(states.pattern, "resume")
                return true
        end

        if state ~= states.armed then
                return false, "notReady"
        end

        status.awaitingPatternStart = false
        holdReadyAnnounced = false
        holdStableTimer = 0
        setState(states.engineStart, "launch")
        return true
end

local function abort(reason)
        reason = reason or "user"
        markStatusEvent("abort", {reason = reason})
        setState(states.idle, reason)
        return true
end

local function copyTable(tbl)
        if type(tbl) ~= "table" then return tbl end
        local result = {}
        for k, v in pairs(tbl) do
                if type(v) == "table" then
                        result[k] = copyTable(v)
                else
                        result[k] = v
                end
        end
        return result
end

local function getStatus()
        local snapshot = copyTable(status)
        snapshot.event = nil
        return snapshot
end

local function getHeadingToTarget(currentPos, targetPos)
        local dx = targetPos.x - currentPos.x
        local dy = targetPos.y - currentPos.y
        return math.atan2(dy, dx)
end

local function updateLiftOrientation(command, targetAltitude, currentAltitude, verticalVelocity, dt)
        if liftOrientationState.locked then
                return
        end

        if not targetAltitude or not currentAltitude then
                resetLiftOrientationTracking()
                return
        end

        if not liftOrientationState.lastAltitude then
                liftOrientationState.lastAltitude = currentAltitude
                liftOrientationState.lastAltitudeError = targetAltitude - currentAltitude
                return
        end

        local altitudeError = targetAltitude - currentAltitude
        local absCommand = math.abs(command or 0)

        if absCommand < 0.3 or math.abs(altitudeError) < 0.5 then
                liftOrientationState.failTimer = math.max(0, liftOrientationState.failTimer - dt)
                liftOrientationState.successTimer = math.max(0, liftOrientationState.successTimer - dt)
                liftOrientationState.lastAltitude = currentAltitude
                liftOrientationState.lastAltitudeError = altitudeError
                return
        end

        local desiredDir = command >= 0 and 1 or -1

        if altitudeError * desiredDir <= 0 then
                liftOrientationState.failTimer = math.max(0, liftOrientationState.failTimer - dt)
                liftOrientationState.successTimer = math.max(0, liftOrientationState.successTimer - dt)
                liftOrientationState.lastAltitude = currentAltitude
                liftOrientationState.lastAltitudeError = altitudeError
                return
        end

        local altitudeDelta = currentAltitude - liftOrientationState.lastAltitude
        local effectiveVelocity = verticalVelocity or 0

        if math.abs(altitudeDelta) > 1e-4 then
                local derivedVelocity = altitudeDelta / math.max(dt, 1e-3)
                if math.abs(derivedVelocity) > math.abs(effectiveVelocity) then
                        effectiveVelocity = derivedVelocity
                end
        end

        local directionalVelocity = effectiveVelocity * desiredDir
        local directionalAltitudeDelta = altitudeDelta * desiredDir
        local previousError = liftOrientationState.lastAltitudeError or altitudeError
        local directionalErrorDelta = (altitudeError - previousError) * desiredDir

        liftOrientationState.lastAltitude = currentAltitude
        liftOrientationState.lastAltitudeError = altitudeError

        local improving = directionalAltitudeDelta > 0.02 or directionalErrorDelta < -0.05
        local degrading = directionalAltitudeDelta < -0.02 or directionalErrorDelta > 0.05

        if degrading and directionalVelocity < -0.05 then
                liftOrientationState.failTimer = liftOrientationState.failTimer + dt
                liftOrientationState.successTimer = math.max(0, liftOrientationState.successTimer - dt * 0.5)
                if liftOrientationState.failTimer > 0.35 then
                        controlDirections.lift = -controlDirections.lift
                        liftOrientationState.locked = true
                        liftOrientationState.failTimer = 0
                        liftOrientationState.successTimer = 0
                        markStatusEvent("liftOrientation", {direction = controlDirections.lift})
                end
        elseif improving and directionalVelocity > 0.02 then
                liftOrientationState.successTimer = liftOrientationState.successTimer + dt
                liftOrientationState.failTimer = math.max(0, liftOrientationState.failTimer - dt * 0.5)
                if liftOrientationState.successTimer > 0.4 then
                        liftOrientationState.locked = true
                        liftOrientationState.failTimer = 0
                        liftOrientationState.successTimer = 0
                end
        else
                liftOrientationState.failTimer = math.max(0, liftOrientationState.failTimer - dt * 0.5)
                liftOrientationState.successTimer = math.max(0, liftOrientationState.successTimer - dt * 0.5)
        end
end

local function controlToTarget(dt, context)
        if not currentTargetPos or not obj then
                return
        end

        local pos = obj:getPosition()
        if not pos then return end

        local velXRaw, velYRaw, velZRaw = getVelocityComponents()
        local roll, pitch, yaw = readRollPitchYaw()

        local yawSmoothed = yawSmoother:get(yaw, dt)
        local pitchSmoothed = pitchSmoother:get(pitch, dt)
        local rollSmoothed = rollSmoother:get(roll, dt)
        local dtSafe = math.max(dt or 0, 1e-3)

        local pitchRateRaw = 0
        local rollRateRaw = 0
        local yawRateRaw = 0
        local rollAV, pitchAV, yawAV
        if obj.getRollPitchYawAngularVelocity then
                rollAV, pitchAV, yawAV = obj:getRollPitchYawAngularVelocity()
        end

        if pitchAV ~= nil then
                pitchRateRaw = pitchAV or 0
        elseif kinematicHistory.pitch then
                pitchRateRaw = normalizeAngle(pitch - kinematicHistory.pitch) / dtSafe
        end

        if rollAV ~= nil then
                rollRateRaw = rollAV or 0
        elseif kinematicHistory.roll then
                rollRateRaw = normalizeAngle(roll - kinematicHistory.roll) / dtSafe
        end

        if yawAV ~= nil then
                yawRateRaw = yawAV or 0
        elseif kinematicHistory.yaw then
                yawRateRaw = normalizeAngle(yaw - kinematicHistory.yaw) / dtSafe
        end

        local pitchRate = pitchRateSmoother:get(pitchRateRaw, dt)
        local rollRate = rollRateSmoother:get(rollRateRaw, dt)
        local yawRate = yawRateSmoother:get(yawRateRaw, dt)

        kinematicHistory.pitch = pitch
        kinematicHistory.roll = roll
        kinematicHistory.yaw = yaw
        local altitude = altitudeSmoother:get(pos.z, dt)

        context = context or getControlContextForState(state)
        local maxTilt = context.maxTilt or defaultControlContext.maxTilt
        local yawClamp = context.yawClamp or defaultControlContext.yawClamp
        local posGainX = context.positionGain or defaultControlContext.positionGain
        local velGainX = context.velocityGain or defaultControlContext.velocityGain
        local posGainY = context.lateralPositionGain or context.positionGain or defaultControlContext.lateralPositionGain
        local velGainY = context.lateralVelocityGain or context.velocityGain or defaultControlContext.lateralVelocityGain
        local levelComp = context.levelCompensation or defaultControlContext.levelCompensation or 0
        local verticalDampingGain = context.verticalDamping or defaultControlContext.verticalDamping
        local verticalClamp = context.verticalClamp or defaultControlContext.verticalClamp or 0.28
        local pitchGuardLimit = getContextValue(context, "pitchGuardLimit")
        local rollGuardLimit = getContextValue(context, "rollGuardLimit")
        local yawGuardLimit = getContextValue(context, "yawGuardLimit")
        local pitchGuardStrength = getContextValue(context, "pitchGuardStrength")
        local rollGuardStrength = getContextValue(context, "rollGuardStrength")
        local yawGuardStrength = getContextValue(context, "yawGuardStrength")
        local pitchGuardRate = getContextValue(context, "pitchGuardRate")
        local rollGuardRate = getContextValue(context, "rollGuardRate")
        local yawGuardRate = getContextValue(context, "yawGuardRate")
        local lockHeading = getContextValue(context, "lockHeadingWhenVertical")
        local verticalHoldThreshold = getContextValue(context, "verticalHoldThreshold")
        local verticalHoldFactor = getContextValue(context, "verticalHoldFactor")
        local recoveryHorizontalFactor = getContextValue(context, "recoveryHorizontalFactor")

        local altitudeTarget = currentTargetPos.z or altitude
        local altitudeError = altitudeTarget - altitude
        local verticalTargetSpeed = altitudeHoldPID:get(altitude, altitudeTarget, dt)

        local sinYaw = math.sin(yaw)
        local cosYaw = math.cos(yaw)

        local dx = currentTargetPos.x - pos.x
        local dy = currentTargetPos.y - pos.y

        local localX =  cosYaw * dx + sinYaw * dy
        local localY = -sinYaw * dx + cosYaw * dy

        local velX =  cosYaw * velXRaw + sinYaw * velYRaw
        local velY = -sinYaw * velXRaw + cosYaw * velYRaw

        local accelForward, accelLateral, accelVertical = measureLocalAcceleration(cosYaw, sinYaw, velXRaw, velYRaw, velZRaw, dt)

        local dist2 = math.sqrt(localX * localX + localY * localY)
        local desiredSpeed = currentTargetSpeed or 0
        local slowdownRadius = math.max(3, desiredSpeed * 0.8)
        if dist2 < slowdownRadius then
                desiredSpeed = desiredSpeed * (dist2 / slowdownRadius)
        end
        if dist2 < 0.2 then
                desiredSpeed = 0
        end

        local dirX, dirY = 0, 0
        if dist2 > 0 then
                dirX = localX / dist2
                dirY = localY / dist2
        end

        local desiredVelX = dirX * desiredSpeed
        local desiredVelY = dirY * desiredSpeed

        local targetHeading = currentTargetHeading
        if not targetHeading then
                targetHeading = getHeadingToTarget(pos, currentTargetPos)
        end
        local headingTolerance = context.headingTolerance or defaultControlContext.headingTolerance or 0.18
        local headingAligned = true
        if targetHeading then
                headingAligned = math.abs(normalizeAngle(targetHeading - yawSmoothed)) < headingTolerance
        end

        local horizontalFactor = 1
        local forceVerticalOnly = getContextValue(context, "forceVerticalOnly")
        if context.altitudeFocus and context.altitudeFocus > 0 and context.altitudeRange and context.altitudeRange > 0 then
                local ratio = math.min(1, math.abs(altitudeError) / context.altitudeRange)
                horizontalFactor = 1 - ratio * context.altitudeFocus
                local minimum = context.minHorizontal or 0
                if horizontalFactor < minimum then
                        horizontalFactor = minimum
                end
        end

        if forceVerticalOnly then
                horizontalFactor = 0
        end

        local verticalClimbMin = getContextValue(context, "verticalClimbMin")
        local climbFloor = verticalClimbMin
        if not climbFloor and state == states.takeoff then
                climbFloor = 0.8
        end
        if climbFloor then
                if altitudeError > 0 and verticalTargetSpeed < climbFloor then
                        verticalTargetSpeed = climbFloor
                elseif altitudeError < 0 and verticalTargetSpeed > -climbFloor * 0.5 then
                        verticalTargetSpeed = -climbFloor * 0.5
                end
        else
                if altitudeError > 0 and verticalTargetSpeed < 0 then
                        verticalTargetSpeed = math.max(verticalTargetSpeed, 0.3)
                elseif altitudeError < 0 and verticalTargetSpeed > 0 then
                        verticalTargetSpeed = math.min(verticalTargetSpeed, -0.3)
                end
        end

        if verticalHoldThreshold and math.abs(altitudeError) > verticalHoldThreshold then
                local holdFactor = verticalHoldFactor
                if holdFactor == nil then
                        holdFactor = 0
                end
                horizontalFactor = math.min(horizontalFactor, holdFactor)
        end

        local verticalHold = state == states.takeoff and math.abs(altitudeError) > 0.35
        local headingHold = state == states.transitStart and not headingAligned

        if verticalHold then
                horizontalFactor = 0
        end
        if recoveryHorizontalFactor then
                if pitchGuardLimit and math.abs(pitchSmoothed) > pitchGuardLimit then
                        horizontalFactor = math.min(horizontalFactor, recoveryHorizontalFactor)
                end
                if rollGuardLimit and math.abs(rollSmoothed) > rollGuardLimit then
                        horizontalFactor = math.min(horizontalFactor, recoveryHorizontalFactor)
                end
        end
        if headingHold then
                horizontalFactor = 0
        end

        desiredSpeed = desiredSpeed * horizontalFactor
        desiredVelX = desiredVelX * horizontalFactor
        desiredVelY = desiredVelY * horizontalFactor

        if horizontalFactor <= 1e-4 or headingHold then
                desiredSpeed = 0
                desiredVelX = 0
                desiredVelY = 0
        end

        local pitchLimit = maxTilt
        local rollLimit = maxTilt
        if pitchGuardLimit and pitchGuardLimit > 0 then
                pitchLimit = math.min(pitchLimit, pitchGuardLimit)
        end
        if rollGuardLimit and rollGuardLimit > 0 then
                rollLimit = math.min(rollLimit, rollGuardLimit)
        end

        local levelHoldGain = getContextValue(context, "levelHoldGain") or 1.0
        local verticalOnly = horizontalFactor <= 1e-4 or headingHold or verticalHold or forceVerticalOnly

        local emergencyRecovery = false
        local emergencyPitchLimit = pitchGuardLimit and pitchGuardLimit * 1.2 or (maxTilt and maxTilt * 1.2)
        local emergencyRollLimit = rollGuardLimit and rollGuardLimit * 1.2 or (maxTilt and maxTilt * 1.2)
        if emergencyPitchLimit and math.abs(pitchSmoothed) > emergencyPitchLimit then
                emergencyRecovery = true
        end
        if emergencyRollLimit and math.abs(rollSmoothed) > emergencyRollLimit then
                emergencyRecovery = true
        end
        if emergencyRecovery then
                horizontalFactor = 0
                verticalOnly = true
        end

        local pitchTarget = 0
        local rollTarget = 0

        if not verticalOnly then
                local forwardPosition = clamp(localX * (posGainX or 0.015), -0.3, 0.3) * horizontalFactor
                local forwardVelocity = clamp((desiredVelX - velX) * (velGainX or 0.12), -0.28, 0.28)
                local lateralPosition = clamp(localY * (posGainY or 0.015), -0.3, 0.3) * horizontalFactor
                local lateralVelocity = clamp((desiredVelY - velY) * (velGainY or 0.12), -0.28, 0.28)

                pitchTarget = clamp(-(forwardPosition + forwardVelocity), -pitchLimit, pitchLimit)
                rollTarget = clamp(lateralPosition + lateralVelocity, -rollLimit, rollLimit)

                if levelComp and levelComp > 0 then
                        pitchTarget = clamp(pitchTarget - pitchSmoothed * levelComp, -pitchLimit, pitchLimit)
                        rollTarget = clamp(rollTarget - rollSmoothed * levelComp, -rollLimit, rollLimit)
                end
        else
                local accelCorrectionPitch = clamp(accelForward / gravity, -0.18, 0.18)
                local accelCorrectionRoll = clamp(accelLateral / gravity, -0.18, 0.18)
                local recoveryGain = levelHoldGain
                if emergencyRecovery then
                        recoveryGain = recoveryGain + 1.15
                end
                pitchTarget = clamp((-pitchSmoothed * recoveryGain) - accelCorrectionPitch, -pitchLimit, pitchLimit)
                rollTarget = clamp((-rollSmoothed * recoveryGain) + accelCorrectionRoll, -rollLimit, rollLimit)
        end

        if lockHeading and horizontalFactor <= 1e-3 and state ~= states.transitStart then
                targetHeading = yawSmoothed
        end

        local pitchRateTarget = pitchAnglePID:get(pitchSmoothed, pitchTarget, dt)
        local rollRateTarget = rollAnglePID:get(rollSmoothed, rollTarget, dt)

        local forwardAccelGain = context.forwardAccelDamping or defaultControlContext.forwardAccelDamping or 0
        local lateralAccelGain = context.lateralAccelDamping or defaultControlContext.lateralAccelDamping or 0
        if forwardAccelGain ~= 0 then
                local damp = clamp(accelForward * forwardAccelGain, -0.6, 0.6)
                pitchRateTarget = clamp(pitchRateTarget - damp, -1.8, 1.8)
        end
        if lateralAccelGain ~= 0 then
                local damp = clamp(accelLateral * lateralAccelGain, -0.6, 0.6)
                rollRateTarget = clamp(rollRateTarget - damp, -1.8, 1.8)
        end

        local pitchRateGain = context.pitchRateDamping or defaultControlContext.pitchRateDamping or 0
        local rollRateGain = context.rollRateDamping or defaultControlContext.rollRateDamping or 0
        if pitchRateGain ~= 0 then
                pitchRateTarget = clamp(pitchRateTarget - pitchRate * pitchRateGain, -1.8, 1.8)
        end
        if rollRateGain ~= 0 then
                rollRateTarget = clamp(rollRateTarget - rollRate * rollRateGain, -1.8, 1.8)
        end

        if emergencyRecovery then
                pitchRateTarget = clamp(pitchRateTarget - pitchRate * 0.35, -1.8, 1.8)
                rollRateTarget = clamp(rollRateTarget - rollRate * 0.35, -1.8, 1.8)
        end

        local pitchOutput = clamp(pitchRatePID:get(pitchRate, pitchRateTarget, dt), -1, 1)
        local rollOutput = clamp(rollRatePID:get(rollRate, rollRateTarget, dt), -1, 1)

        local yawOutput = lastOutputs.yaw or 0
        local yawSetpointError = 0
        local yawRateTarget = 0
        if targetHeading then
                local yawSetpoint = yaw + clamp(normalizeAngle(targetHeading - yaw), -yawClamp, yawClamp)
                yawSetpointError = normalizeAngle(yawSetpoint - yawSmoothed)
                yawRateTarget = yawAnglePID:get(yawSmoothed, yawSetpoint, dt)
        end

        local yawRateGain = context.yawRateDamping or defaultControlContext.yawRateDamping or 0
        if yawRateGain ~= 0 then
                yawRateTarget = clamp(yawRateTarget - yawRate * yawRateGain, -1.5, 1.5)
        end
        yawOutput = clamp(yawRatePID:get(yawRate, yawRateTarget, dt), -1, 1)

        if forceVerticalOnly then
                yawOutput = clamp(yawOutput, -0.35, 0.35)
        end

        if emergencyRecovery then
                yawOutput = clamp(yawOutput, -0.5, 0.5)
        end

        local verticalDamping = clamp(-velZRaw * (verticalDampingGain or 0.12), -verticalClamp, verticalClamp)
        local verticalAccelGain = context.verticalAccelDamping or defaultControlContext.verticalAccelDamping or 0
        if verticalAccelGain ~= 0 then
                local damp = clamp(accelVertical * verticalAccelGain, -verticalClamp, verticalClamp)
                verticalDamping = clamp(verticalDamping - damp, -verticalClamp, verticalClamp)
        end

        local liftCommand = verticalSpeedPID:get(velZRaw, verticalTargetSpeed, dt)
        local liftOutput = clamp(liftCommand + verticalDamping, -1, 1)

        pitchOutput = applyAxisGuard(pitchOutput, pitchSmoothed, pitchRate, pitchGuardLimit, pitchGuardRate, pitchGuardStrength)
        rollOutput = applyAxisGuard(rollOutput, rollSmoothed, rollRate, rollGuardLimit, rollGuardRate, rollGuardStrength)
        yawOutput = applyYawGuard(yawOutput, yawSetpointError, yawRate, yawGuardLimit, yawGuardRate, yawGuardStrength)

        updateLiftOrientation(liftOutput, currentTargetPos.z, altitude, velZRaw, dt)

        applyControlOutput("lift", liftOutput, dt)
        applyControlOutput("pitch", pitchOutput, dt)
        applyControlOutput("roll", rollOutput, dt)
        applyControlOutput("yaw", yawOutput, dt)
end

local function isHeadingAligned(threshold)
        if not currentTargetHeading or not obj then
                return true
        end
        local _, _, yaw = readRollPitchYaw()
        if not yaw then
                return true
        end
        local diff = math.abs(normalizeAngle(currentTargetHeading - yaw))
        return diff < (threshold or 0.2)
end

local function updateProgress()
        if not plan or not plan.segmentCount or plan.segmentCount == 0 then
                status.progress = 0
                return
        end

        local completed = math.max(0, currentWaypoint - 1)
        local partial = 0
        if currentTargetPos and obj then
                local pos = obj:getPosition()
                if pos then
                        local previousPos = plan.start
                        if plan.patternPoints[currentWaypoint] then
                                previousPos = currentWaypoint == 1 and plan.start or plan.patternPoints[currentWaypoint - 1].pos
                        elseif plan.patternPoints[#plan.patternPoints] then
                                previousPos = plan.patternPoints[#plan.patternPoints].pos
                        end
                        local totalSegment = 0
                        local targetInfo = plan.patternPoints[currentWaypoint]
                        if targetInfo then
                                totalSegment = targetInfo.length or distance(previousPos, targetInfo.pos)
                                if totalSegment > 0 then
                                        partial = clamp(1 - (distance(pos, currentTargetPos) / totalSegment), 0, 1)
                                end
                        end
                end
        end
        status.progress = clamp((completed + partial) / plan.segmentCount, 0, 1)
end

local function updateEngineStart(dt)
        local ignition = electrics.values.ignitionLevel or 0
        if ignition < 3 then
                electrics.setIgnitionLevel(3)
        end
        if stateTimer > 0.8 then
                setState(states.spinup)
        end
end

local function updateSpinup(dt)
        local rpm = electrics.values.rotorrpm or 0
        local ignition = electrics.values.ignitionLevel or 0
        if ignition < 3 then
                electrics.setIgnitionLevel(3)
        end

        if rpm >= (plan and plan.rotorRPM or rotorSpinThreshold) * 0.85 then
                spinupTimer = spinupTimer + dt
        else
                spinupTimer = 0
        end

        if spinupTimer > rotorStableTime then
                electrics.setIgnitionLevel(2)
                setState(states.takeoff)
        end
end

local function updateTakeoff(dt)
        if not currentTargetPos then return end
        local context = getControlContextForState(states.takeoff)
        controlToTarget(dt, context)
        if not obj then return end

        local pos = obj:getPosition()
        if not pos then return end

        local velX, velY, velZ = getVelocityComponents()
        local horizontalSpeed = math.sqrt((velX or 0) * (velX or 0) + (velY or 0) * (velY or 0))
        local altitudeDelta = math.abs((pos.z or 0) - (currentTargetPos.z or pos.z))

        local settleTolerance = getContextValue(context, "verticalSettleTolerance") or 0.6
        local settleRate = getContextValue(context, "verticalSettleRate") or 0.6
        local horizontalLimit = getContextValue(context, "verticalHorizontalLimit") or 0.6
        local yawRateLimit = getContextValue(context, "verticalYawRateLimit")

        local pitchLimit = getContextValue(context, "pitchGuardLimit") or context.maxTilt or defaultControlContext.maxTilt
        local rollLimit = getContextValue(context, "rollGuardLimit") or context.maxTilt or defaultControlContext.maxTilt
        local headingTolerance = context.headingTolerance or defaultControlContext.headingTolerance or 0.18

        local stableAttitude = isAttitudeStable(pitchLimit and pitchLimit * 0.85 or 0.18, rollLimit and rollLimit * 0.85 or 0.18, yawRateLimit)
        local headingAligned = isHeadingAligned(headingTolerance * 0.75)

        if altitudeDelta < settleTolerance and math.abs(velZ or 0) < settleRate and horizontalSpeed < horizontalLimit and stableAttitude and headingAligned then
                setState(states.transitStart)
        end
end

local function updateTransitStart(dt)
        if not currentTargetPos then return end
        controlToTarget(dt, getControlContextForState(states.transitStart))
        if obj then
                local pos = obj:getPosition()
                if pos and distance(pos, currentTargetPos) < positionTolerance then
                        setState(states.holding)
                end
        end
end

local function updateHolding(dt)
        if not currentTargetPos then return end
        holdTimer = holdTimer + dt
        local context = getControlContextForState(states.holding)
        controlToTarget(dt, context)

        local headingTolerance = (stateControlContexts[states.holding] and stateControlContexts[states.holding].headingTolerance) or defaultControlContext.headingTolerance
        local headingAligned = isHeadingAligned(headingTolerance)

        local pos = obj and obj:getPosition()
        local nearTarget = false
        if pos then
                local separation = distance(pos, currentTargetPos)
                nearTarget = separation < (positionTolerance * 0.65)
        end

        local velXRaw, velYRaw, velZRaw = getVelocityComponents()
        local horizontalSpeed = math.sqrt(velXRaw * velXRaw + velYRaw * velYRaw)
        local settleRate = getContextValue(context, "verticalSettleRate") or 0.35
        local verticalSettled = math.abs(velZRaw) < settleRate
        local horizontalLimit = getContextValue(context, "verticalHorizontalLimit") or 0.6

        local pitchLimit = getContextValue(context, "pitchGuardLimit") or context.maxTilt or defaultControlContext.maxTilt
        local rollLimit = getContextValue(context, "rollGuardLimit") or context.maxTilt or defaultControlContext.maxTilt
        local yawRateLimit = getContextValue(context, "verticalYawRateLimit")
        local attitudeStable = isAttitudeStable(pitchLimit and pitchLimit * 0.9 or 0.18, rollLimit and rollLimit * 0.9 or 0.18, yawRateLimit)

        if nearTarget and headingAligned and verticalSettled and horizontalSpeed < horizontalLimit and attitudeStable then
                holdStableTimer = holdStableTimer + dt
        else
                holdStableTimer = 0
        end

        if holdStableTimer >= math.max(0.8, (plan and plan.holdTime or holdDuration) * 0.35) then
                if not status.awaitingPatternStart then
                        status.awaitingPatternStart = true
                        holdReadyAnnounced = true
                        markStatusEvent("awaitPattern", {ready = true})
                end
        elseif status.awaitingPatternStart or holdReadyAnnounced then
                status.awaitingPatternStart = false
                holdReadyAnnounced = false
                if holdStableTimer <= 0 then
                        markStatusEvent("awaitPattern", {ready = false})
                end
        end
end

local function updatePattern(dt)
        if not plan or not plan.patternPoints or not plan.patternPoints[currentWaypoint] then
                setState(states.finishHover)
                return
        end

        local waypoint = plan.patternPoints[currentWaypoint]
        currentTargetPos = copyVec3(waypoint.pos)
        currentTargetHeading = waypoint.heading or plan.startHeading
        currentTargetSpeed = waypoint.speed or plan.speed

        controlToTarget(dt, getControlContextForState(states.pattern))

        status.waypointIndex = currentWaypoint

        if obj then
                local pos = obj:getPosition()
                if pos and distance(pos, currentTargetPos) < waypointTolerance then
                        currentWaypoint = currentWaypoint + 1
                        if currentWaypoint > #plan.patternPoints then
                                if plan.finishMode == "return_start" then
                                        setState(states.returnStart)
                                elseif plan.finishMode == "return_home_land" then
                                        setState(states.returnHome)
                                else
                                        setState(states.finishHover)
                                end
                        end
                end
        end
end

local function updateReturnStart(dt)
        if not currentTargetPos then return end
        controlToTarget(dt, getControlContextForState(states.returnStart))
        if obj then
                local pos = obj:getPosition()
                if pos and distance(pos, currentTargetPos) < waypointTolerance then
                        plan.finalHoverPos = copyVec3(plan.start)
                        plan.finalHoverPos.z = plan.altitude
                        setState(states.finishHover)
                end
        end
end

local function updateReturnHome(dt)
        if not currentTargetPos then return end
        controlToTarget(dt, getControlContextForState(states.returnHome))
        if obj then
                local pos = obj:getPosition()
                if pos and distance(pos, currentTargetPos) < waypointTolerance then
                        setState(states.landing)
                end
        end
end

local function updateLanding(dt)
        if not currentTargetPos then return end
        currentTargetPos.z = math.max(landingTargetAltitude or currentTargetPos.z, currentTargetPos.z - landingDescentRate * dt)
        controlToTarget(dt, getControlContextForState(states.landing))
        if obj then
                local pos = obj:getPosition()
                local _, _, velZ = getVelocityComponents()
                if pos then
                        if math.abs(pos.z - (landingTargetAltitude or pos.z)) < 0.25 and math.abs(velZ) < 0.5 then
                                setState(states.complete)
                        end
                end
        end
end

local function updateFinishHover(dt)
        if not currentTargetPos then return end
        controlToTarget(dt, getControlContextForState(states.finishHover))
end

local function updateActiveState(dt)
        if state == states.engineStart then
                updateEngineStart(dt)
        elseif state == states.spinup then
                updateSpinup(dt)
        elseif state == states.takeoff then
                updateTakeoff(dt)
        elseif state == states.transitStart then
                updateTransitStart(dt)
        elseif state == states.holding then
                updateHolding(dt)
        elseif state == states.pattern then
                updatePattern(dt)
        elseif state == states.returnStart then
                updateReturnStart(dt)
        elseif state == states.returnHome then
                updateReturnHome(dt)
        elseif state == states.landing then
                updateLanding(dt)
        elseif state == states.finishHover then
                updateFinishHover(dt)
        end
end

local function updateGFX(dt)
        electrics.values["b407_survey_autopilot_active"] = (state ~= states.idle and state ~= states.complete and state ~= states.armed) and 1 or 0

        stateTimer = stateTimer + dt
        statusUpdateTimer = statusUpdateTimer - dt

        if state == states.idle or state == states.complete then
                status.active = false
        end

        if state ~= states.idle and state ~= states.armed and state ~= states.complete then
                updateActiveState(dt)
        end

        if plan then
                updateProgress()
        end

        if statusUpdateTimer <= 0 or statusDirty then
                pushStatus()
        end
end

local function init()
        plan = nil
        setState(states.idle)
        status.planLoaded = false
        status.progress = 0
        status.waypointIndex = 0
        status.waypointCount = 0
        status.finishMode = nil
        status.planId = nil
        status.altitude = 0
        status.rotorRPM = 0
        status.event = {type = "init"}
        statusDirty = true
end

local function reset()
        setState(states.idle)
        updateStatusFromPlan()
        status.progress = 0
        status.waypointIndex = 0
        status.event = {type = "reset"}
        statusDirty = true
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.setPatternPlan = setPatternPlan
M.arm = arm
M.beginPattern = beginPattern
M.abort = abort
M.getStatus = getStatus

return M
