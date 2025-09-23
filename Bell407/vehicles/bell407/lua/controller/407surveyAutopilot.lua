local M = {}
M.type = "auxiliary"
M.defaultOrder = 60

local isEnabled = false
local holdPosition = {x = 0, y = 0, z = 0}
local holdHeading = 0

local function captureHoldReference()
        local pos = obj and obj.getPosition and obj:getPosition()
        if pos then
                holdPosition.x, holdPosition.y, holdPosition.z = pos.x or 0, pos.y or 0, pos.z or 0
        else
                holdPosition.x, holdPosition.y, holdPosition.z = 0, 0, 0
        end

        local _, _, yaw = 0, 0, 0
        if obj and obj.getRollPitchYaw then
                _, _, yaw = obj:getRollPitchYaw()
        end
        holdHeading = yaw or 0
end

local function init(jbeamData)
        isEnabled = jbeamData and jbeamData.defaultEnabled or isEnabled
        captureHoldReference()
end

local function reset(jbeamData)
        if jbeamData and jbeamData.resetEnabled ~= nil then
                isEnabled = jbeamData.resetEnabled and true or false
        else
                isEnabled = false
        end
        captureHoldReference()
end

local function toggle(state, captureReference)
        if state == nil then
                isEnabled = not isEnabled
        else
                isEnabled = state and true or false
        end

        if isEnabled and captureReference ~= false then
                captureHoldReference()
        end
end

local function setParameters(params)
        if not params then return end

        if params.enabled ~= nil then
                toggle(params.enabled, params.captureOnEnable)
        end

        if params.toggle then
                toggle(nil, params.captureOnToggle)
        end

        if params.captureReference then
                captureHoldReference()
        end
end

local function updateGFX(dt)
        local active = isEnabled and 1 or 0
        electrics.values["b407_survey_autopilot_active"] = active
        electrics.values["b407_survey_autopilot_targetX"] = holdPosition.x
        electrics.values["b407_survey_autopilot_targetY"] = holdPosition.y
        electrics.values["b407_survey_autopilot_targetZ"] = holdPosition.z
        electrics.values["b407_survey_autopilot_targetHeading"] = holdHeading
end

local function getState()
        return {
                enabled = isEnabled,
                target = {holdPosition.x, holdPosition.y, holdPosition.z},
                heading = holdHeading
        }
end

M.init = init
M.reset = reset
M.setParameters = setParameters
M.updateGFX = updateGFX
M.getState = getState
M.toggle = toggle

return M
