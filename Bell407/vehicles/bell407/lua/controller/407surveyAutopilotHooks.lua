local M = {}
M.type = "auxiliary"
M.defaultOrder = 61

local autopStateKey = "b407_survey_autopilot_active"
local indicatorKey = "b407_survey_autopilot_indicator"

local function init(jbeamData)
        autopStateKey = jbeamData and jbeamData.stateKey or autopStateKey
        indicatorKey = jbeamData and jbeamData.indicatorKey or indicatorKey
end

local function reset(jbeamData)
        electrics.values[indicatorKey] = 0
end

local function updateGFX(dt)
        electrics.values[indicatorKey] = electrics.values[autopStateKey] or 0
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
