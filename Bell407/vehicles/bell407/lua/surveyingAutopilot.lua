local M = {}

local moduleName = "surveyingAutopilot"
local autopController = nil
local cachedPlan = nil
local lastPreview = nil
local groundMarker = nil
local homePosition = nil
local lastMarkerRequest = 0
local lastInstallReported = nil
local cachedMapModule = rawget(_G, "map")

local function copyTable(data)
        if type(data) ~= "table" then return data end
        local result = {}
        for k, v in pairs(data) do
                if type(v) == "table" then
                        result[k] = copyTable(v)
                else
                        result[k] = v
                end
        end
        return result
end

local function toPoint(value)
        if not value then return nil end
        if value.x then
                return {x = value.x, y = value.y, z = value.z or 0}
        end
        if value[1] then
                return {x = value[1], y = value[2], z = value[3] or 0}
        end
        return nil
end

local function to2DComponents(value)
        if not value then return nil, nil end
        if value.x then
                return value.x, value.y
        end
        if value[1] then
                return value[1], value[2]
        end
        return nil, nil
end

local function extendBounds(bounds, point)
        if not point then return end
        local x, y = to2DComponents(point)
        if not x or not y then return end
        if not bounds.minX or x < bounds.minX then bounds.minX = x end
        if not bounds.maxX or x > bounds.maxX then bounds.maxX = x end
        if not bounds.minY or y < bounds.minY then bounds.minY = y end
        if not bounds.maxY or y > bounds.maxY then bounds.maxY = y end
end

local function computePlanBounds(startPoint, patternPoints, home, finalHover)
        local bounds = {minX = nil, maxX = nil, minY = nil, maxY = nil}
        extendBounds(bounds, startPoint)
        extendBounds(bounds, home)
        extendBounds(bounds, finalHover)
        if patternPoints then
                for _, entry in ipairs(patternPoints) do
                        if entry and entry.pos then
                                extendBounds(bounds, entry.pos)
                        elseif entry then
                                extendBounds(bounds, entry)
                        end
                end
        end
        if not bounds.minX then
                return nil
        end
        local spanX = (bounds.maxX or bounds.minX) - bounds.minX
        local spanY = (bounds.maxY or bounds.minY) - bounds.minY
        local padding = math.max(40, math.max(spanX, spanY) * 0.25)
        bounds.minX = bounds.minX - padding
        bounds.maxX = bounds.maxX + padding
        bounds.minY = bounds.minY - padding
        bounds.maxY = bounds.maxY + padding
        bounds.padding = padding
        return bounds
end

local function getMapData()
        local mapModule = rawget(_G, "map") or cachedMapModule
        if mapModule and mapModule.getMap then
                cachedMapModule = mapModule
                return mapModule.getMap()
        end
        return nil
end

local function collectMapSegments(bounds)
        if not bounds then return {} end
        local nav = getMapData()
        if not nav or not nav.nodes then
                return {}
        end
        local minX, maxX, minY, maxY = bounds.minX, bounds.maxX, bounds.minY, bounds.maxY
        if not (minX and maxX and minY and maxY) then
                return {}
        end
        local segments = {}
        local seen = {}
        for nodeId, node in pairs(nav.nodes) do
                local pos = node and node.pos
                local px, py = to2DComponents(pos)
                if px and py and px >= minX and px <= maxX and py >= minY and py <= maxY then
                        local links = node.links
                        if links then
                                for targetId, _ in pairs(links) do
                                        local other = nav.nodes[targetId]
                                        local ox, oy = to2DComponents(other and other.pos)
                                        if ox and oy and ox >= minX and ox <= maxX and oy >= minY and oy <= maxY then
                                                local a, b = tostring(nodeId), tostring(targetId)
                                                if a > b then
                                                        a, b = b, a
                                                end
                                                local key = a .. "|" .. b
                                                if not seen[key] then
                                                        seen[key] = true
                                                        local dx = ox - px
                                                        local dy = oy - py
                                                        if dx * dx + dy * dy > 0.01 then
                                                                segments[#segments + 1] = {{px, py}, {ox, oy}}
                                                                if #segments >= 400 then
                                                                        return segments
                                                                end
                                                        end
                                                end
                                        end
                                end
                        end
                end
        end
        return segments
end

local function updateInstallState(installed)
        local value = installed
        if value == nil then
                value = autopController ~= nil
        end
        value = value and true or false
        if lastInstallReported == value then
                return
        end
        lastInstallReported = value
        if guihooks and guihooks.trigger then
                guihooks.trigger("bell407SurveyInstallState", {installed = value, module = moduleName})
        end
end

local function ensureController()
        if not autopController then
                autopController = controller.getController("407surveyAutopilot")
                if autopController then
                        updateInstallState(true)
                end
        end
        return autopController
end

local function isInstalled()
        local installed = ensureController() ~= nil
        updateInstallState(installed)
        return installed
end

local function sendPreview(payload)
        if guihooks and guihooks.trigger then
                guihooks.trigger("bell407SurveyPreview", payload)
        end
end

local function sendStatus(payload)
        if guihooks and guihooks.trigger then
                guihooks.trigger("bell407SurveyStatus", payload)
        end
end

local function requestGroundMarker()
        if not obj or not obj.getId then return end
        local now = os.clock and os.clock() or 0
        if now - lastMarkerRequest < 0.25 then return end
        lastMarkerRequest = now
        local command = string.format([[local veh = be:getObjectByID(%d)
if not veh then return end
local pos = core_groundMarkers and core_groundMarkers.getTargetPos()
if pos then
  veh:queueLuaCommand(string.format("extensions.%s._setGroundMarker(%%f,%%f,%%f)", pos.x, pos.y, pos.z))
else
  veh:queueLuaCommand("extensions.%s._setGroundMarker()")
end
]], obj:getId(), moduleName, moduleName)
        obj:queueGameEngineLua(command)
end

function M._setGroundMarker(x, y, z)
        if x then
                groundMarker = {x = x, y = y, z = z}
        else
                groundMarker = nil
        end
end

local function ensureGroundMarker()
	if not groundMarker then
		requestGroundMarker()
	end
	return groundMarker
end

local function ensureReady(options)
	local ctrl = ensureController()
	if not ctrl then
		updateInstallState(false)
		return nil, "missingPart"
	end

	local requireMarker = true
	if options and options.requireMarker ~= nil then
		requireMarker = options.requireMarker and true or false
	end

	if requireMarker then
		local marker = ensureGroundMarker()
		if not marker then
			return nil, "noTarget"
		end
	end

	return ctrl
end

local function getGroundHeight(pos)
        if not obj or not obj.castRayStatic then
                return pos.z
        end
        local origin = vec3(pos.x, pos.y, pos.z + 50)
        local hit = obj:castRayStatic(origin, vec3(0, 0, -1), 200)
        if hit and hit > 0 and hit < 200 then
                return origin.z - hit
        end
        return pos.z
end

local function computeHome()
        if obj and obj.getSpawnWorldOOBB then
                local oobb = obj:getSpawnWorldOOBB()
                if oobb then
                        local center = oobb:getCenter()
                        homePosition = {x = center.x, y = center.y, z = center.z}
                        homePosition.groundZ = getGroundHeight(homePosition)
                        return
                end
        end
        if obj and obj.getPosition then
                local pos = obj:getPosition()
                if pos then
                        homePosition = {x = pos.x, y = pos.y, z = pos.z}
                        homePosition.groundZ = getGroundHeight(homePosition)
                end
        end
end


local function getHome()
        if not homePosition then
                computeHome()
        end
        if not homePosition then return nil end
        return copyTable(homePosition)
end


local function buildPatternPlan(params)
	if not params then
		return nil, "missingParams"
	end

	local explicitStart = toPoint(params.startPoint)
	local ctrl, err = ensureReady({requireMarker = explicitStart == nil})
	if not ctrl then
		return nil, err
	end

	local startPoint = explicitStart or toPoint(groundMarker)
	if not startPoint then
		local marker = ensureGroundMarker()
		if marker then
			startPoint = toPoint(marker)
		end
	end
	if not startPoint then
		return nil, explicitStart and "invalidStart" or "noTarget"
	end

        local altitude = params.altitude or startPoint.z or 0
        startPoint.z = altitude

        local length = params.length or 0
        local spacing = params.spacing or 0
        local rows = math.max(1, math.floor(params.rows or 1))
        local speed = params.speed or 12
        local finishMode = params.finishMode or "hover"
        local holdTime = params.holdTime or 2.0
        local rotorRPM = params.rotorRPM or 380
        local landingClearance = params.landingClearance or 0.45
        local angleRad = math.rad(params.angle or 0)

        local baseDir = {x = math.cos(angleRad), y = math.sin(angleRad)}
        if math.abs(baseDir.x) < 1e-6 and math.abs(baseDir.y) < 1e-6 then
                baseDir.x, baseDir.y = 1, 0
        end

        local lengthSign = length >= 0 and 1 or -1
        local spacingSign = spacing >= 0 and 1 or -1
        local lengthMag = math.abs(length)
        local spacingMag = math.abs(spacing)

        if lengthMag < 0.1 then lengthMag = 0.1 end

        local forwardDir = {x = baseDir.x * lengthSign, y = baseDir.y * lengthSign}
        local perpendicular = {x = -forwardDir.y, y = forwardDir.x}
        local offsetDir = {x = perpendicular.x * spacingSign, y = perpendicular.y * spacingSign}

        local patternPoints = {}
        local previewWaypoints = {}
        previewWaypoints[1] = {startPoint.x, startPoint.y, startPoint.z}

        local currentPos = {x = startPoint.x, y = startPoint.y, z = altitude}
        local firstHeading = math.atan2(forwardDir.y, forwardDir.x)
        local totalLength = 0

        for row = 1, rows do
                local legEnd = {
                        x = currentPos.x + forwardDir.x * lengthMag,
                        y = currentPos.y + forwardDir.y * lengthMag,
                        z = altitude
                }
                local legHeading = math.atan2(forwardDir.y, forwardDir.x)
                patternPoints[#patternPoints + 1] = {
                        pos = legEnd,
                        heading = legHeading,
                        speed = speed,
                        length = lengthMag
                }
                previewWaypoints[#previewWaypoints + 1] = {legEnd.x, legEnd.y, legEnd.z}
                totalLength = totalLength + lengthMag
                currentPos = {x = legEnd.x, y = legEnd.y, z = altitude}

                if row == rows then
                        break
                end

                if spacingMag > 1e-4 then
                        local midOffset = spacingMag * 0.5
                        if midOffset > 1e-4 then
                                local midPos = {
                                        x = currentPos.x + offsetDir.x * midOffset,
                                        y = currentPos.y + offsetDir.y * midOffset,
                                        z = altitude
                                }
                                patternPoints[#patternPoints + 1] = {
                                        pos = midPos,
                                        heading = math.atan2(offsetDir.y, offsetDir.x),
                                        speed = speed * 0.6,
                                        length = midOffset
                                }
                                previewWaypoints[#previewWaypoints + 1] = {midPos.x, midPos.y, midPos.z}
                                totalLength = totalLength + midOffset
                                currentPos = {x = midPos.x, y = midPos.y, z = altitude}
                        end

                        local remainingOffset = spacingMag - midOffset
                        if remainingOffset > 1e-4 then
                                local nextStart = {
                                        x = currentPos.x + offsetDir.x * remainingOffset,
                                        y = currentPos.y + offsetDir.y * remainingOffset,
                                        z = altitude
                                }
                                local nextDir = {x = -forwardDir.x, y = -forwardDir.y}
                                patternPoints[#patternPoints + 1] = {
                                        pos = nextStart,
                                        heading = math.atan2(nextDir.y, nextDir.x),
                                        speed = speed * 0.6,
                                        length = remainingOffset
                                }
                                previewWaypoints[#previewWaypoints + 1] = {nextStart.x, nextStart.y, nextStart.z}
                                totalLength = totalLength + remainingOffset
                                currentPos = {x = nextStart.x, y = nextStart.y, z = altitude}
                        end
                end

                forwardDir.x = -forwardDir.x
                forwardDir.y = -forwardDir.y
        end

        local finalHover = {x = currentPos.x, y = currentPos.y, z = altitude}
        local finalHeading = math.atan2(forwardDir.y, forwardDir.x)

        local home = homePosition and copyTable(homePosition) or {x = startPoint.x, y = startPoint.y, z = altitude}
        if not home.z then home.z = altitude end

        local plan = {
                id = params.planId,
                start = startPoint,
                startHeading = firstHeading,
                altitude = altitude,
                speed = speed,
                transitSpeed = params.transitSpeed,
                holdTime = holdTime,
                finishMode = finishMode,
                rotorRPM = rotorRPM,
                landingClearance = landingClearance,
                home = home,
                homeHeading = firstHeading,
                homeGround = home.groundZ or home.z,
                finalHoverPos = finalHover,
                finalHeading = finalHeading,
                patternPoints = patternPoints,
                totalLength = totalLength
        }

        local bounds = computePlanBounds(plan.start, plan.patternPoints, plan.home, plan.finalHoverPos)
        if bounds then
                plan.bounds = copyTable(bounds)
        end

        local mapSegments = collectMapSegments(bounds)
        if mapSegments and #mapSegments > 0 then
                plan.mapSegments = copyTable(mapSegments)
        end

        local preview = {
                ok = true,
                start = {startPoint.x, startPoint.y, startPoint.z},
                home = {home.x, home.y, home.z},
                altitude = altitude,
                heading = firstHeading,
                finishMode = finishMode,
                speed = speed,
                rotorRPM = rotorRPM,
                waypoints = previewWaypoints
        }

        if bounds then
                preview.bounds = {minX = bounds.minX, maxX = bounds.maxX, minY = bounds.minY, maxY = bounds.maxY}
        end

        if mapSegments and #mapSegments > 0 then
                preview.mapSegments = copyTable(mapSegments)
        end

        return plan, preview
end

local function previewPattern(params)
        local plan, preview = buildPatternPlan(params)
        if not plan then
                sendPreview({ok = false, reason = preview or "invalid"})
                return false, preview or "invalid"
        end
        lastPreview = {plan = plan, preview = preview}
        cachedPlan = plan
        sendPreview(preview)
        return true
end

local function configurePattern(params)
        local plan, preview = buildPatternPlan(params)
        if not plan then
                sendStatus({ok = false, reason = preview or "invalid"})
                return false, preview or "invalid"
        end
        cachedPlan = plan
        lastPreview = {plan = plan, preview = preview}
        local ctrl = ensureController()
        if not ctrl then
                sendStatus({ok = false, reason = "missingPart"})
                return false, "missingPart"
        end
        local ok, reason = ctrl.setPatternPlan(plan)
        if not ok then
                sendStatus({ok = false, reason = reason or "setFailed"})
                return false, reason or "setFailed"
        end
        sendPreview(preview)
        return true
end

local function activate()
        local requireMarker = not cachedPlan or not cachedPlan.start
        local ctrl, reason = ensureReady({requireMarker = requireMarker})
        if not ctrl then
                sendStatus({ok = false, reason = reason})
                return false, reason
        end
        if not cachedPlan then
                sendStatus({ok = false, reason = "noPlan"})
                return false, "noPlan"
        end
        local ok, err = ctrl.arm(cachedPlan)
        if not ok then
                sendStatus({ok = false, reason = err or "armFailed"})
                return false, err or "armFailed"
        end
        return true
end

local function startSurvey()
        local requireMarker = not cachedPlan or not cachedPlan.start
        local ctrl, reason = ensureReady({requireMarker = requireMarker})
        if not ctrl then
                sendStatus({ok = false, reason = reason})
                return false, reason
        end
        local ok, err = ctrl.beginPattern()
        if not ok then
                sendStatus({ok = false, reason = err or "beginFailed"})
                return false, err or "beginFailed"
        end
        return true
end

local function cancel(reason)
        local ctrl = ensureController()
        if not ctrl then
                sendStatus({ok = false, reason = "missingPart"})
                return false, "missingPart"
        end
        ctrl.abort(reason or "cancelled")
        return true
end

local function onInit()
        autopController = nil
        lastInstallReported = nil
        computeHome()
        requestGroundMarker()
        updateInstallState()
end

local function onReset()
        computeHome()
        requestGroundMarker()
end

local function onExtensionUnloaded()
        autopController = nil
        cachedPlan = nil
        lastPreview = nil
        lastInstallReported = nil
        updateInstallState(false)
end

M.onInit = onInit
M.onReset = onReset
M.onExtensionUnloaded = onExtensionUnloaded
M.isInstalled = isInstalled
M.getHome = getHome
M.previewPattern = previewPattern
M.configurePattern = configurePattern
M.activate = activate
M.startSurvey = startSurvey
M.cancel = cancel

return M
