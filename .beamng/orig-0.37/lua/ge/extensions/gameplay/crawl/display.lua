-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local logTag = "crawl_display"

local crawlUILayout = "crawl"

local function setCrawlUILayout(value)
  -- if value then
  --   core_gamestate.setGameState('freeroam', crawlUILayout, 'freeroam')
  -- else
  --   core_gamestate.setGameState('freeroam', 'freeroam', 'freeroam')
  -- end
end

local function onCrawlStarted()
  log('I', logTag, 'Crawl started, changing UI layout to crawl')
  setCrawlUILayout(true)
end

local function onCrawlComplete()
  setCrawlUILayout(false)
end

local function onCrawlResultsShown()

end

local function onExtensionLoaded()

end

local function onExtensionUnloaded()
  setCrawlUILayout(false)
end

-- UI Message functions moved from utils.lua
local function showPointsMessage(points)
  ui_message({txt="ui.crawl.penaltyPoints", context={points=points}}, 600, "points")
end

local function clearPointsMessage()
  ui_message("", nil, "points")
end

local function showCrawlCompletedMessage(time, points, damage)
  ui_message("ui.crawl.crawlCompleted", nil, "crawlCompleted")
  ui_message({txt="ui.crawl.crawlResults", context={time=string.format("%.3f", time), points=points, damage=damage}}, 10, "crawlCompleted")
end

local function showSkippedCheckpointsMessage(skippedCount)
  ui_message({txt="ui.crawl.skippedCheckpoints", context={skippedCount=skippedCount, penaltyPoints=skippedCount * gameplay_crawl_utils.infractionPoints.skippedCheckpoint}}, nil, "skippedCheckpoints")
end

local function showGateReachedMessage()
  ui_message("ui.crawl.gateReached", nil, "gateReached")
end

local function showStartedCrawlMessage()
  ui_message("ui.crawl.startedCrawl", nil, "startedCrawl")
end

local function showDisqualifiedMessage()
  ui_message("ui.crawl.disqualified", nil, "disqualified")
end

local function showTooMuchZAccMessage()
  ui_message({txt="ui.crawl.tooMuchZAcc", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.tooMuchZAcceleration}}, nil, "tooMuchZAcc")
end

local function showDrivingBackwardsMessage()
  ui_message({txt="ui.crawl.drivingBackwards", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.drivingBackwards}}, nil, "drivingBackwards")
end

local function showDamageThreshold1000Message()
  ui_message({txt="ui.crawl.damageThreshold1000", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.damageThreshold1}}, nil, "damageThreshold1000")
end

local function showDamageThreshold4000Message()
  ui_message({txt="ui.crawl.damageThreshold4000", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.damageThreshold2}}, nil, "damageThreshold4000")
end

local function showVehicleFlippedUprightMessage()
  ui_message({txt="ui.crawl.vehicleFlippedUpright", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.vehicleFlippedUpright}}, nil, "vehicleFlippedUpright")
end

local function showVehicleResetMessage()
  ui_message({txt="ui.crawl.vehicleReset", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.vehicleReset}}, nil, "vehicleReset")
end

local function showBoundaryViolationMessage()
  ui_message({txt="ui.crawl.boundaryViolation", context={penaltyPoints=gameplay_crawl_utils.infractionPoints.boundaryViolation}}, nil, "boundaryViolation")
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onCrawlStarted = onCrawlStarted
M.onCrawlComplete = onCrawlComplete
M.onCrawlResultsShown = onCrawlResultsShown

-- Export UI message functions
M.showPointsMessage = showPointsMessage
M.clearPointsMessage = clearPointsMessage
M.showCrawlCompletedMessage = showCrawlCompletedMessage
M.showSkippedCheckpointsMessage = showSkippedCheckpointsMessage
M.showGateReachedMessage = showGateReachedMessage
M.showStartedCrawlMessage = showStartedCrawlMessage
M.showDisqualifiedMessage = showDisqualifiedMessage
M.showTooMuchZAccMessage = showTooMuchZAccMessage
M.showDrivingBackwardsMessage = showDrivingBackwardsMessage
M.showDamageThreshold1000Message = showDamageThreshold1000Message
M.showDamageThreshold4000Message = showDamageThreshold4000Message
M.showVehicleFlippedUprightMessage = showVehicleFlippedUprightMessage
M.showVehicleResetMessage = showVehicleResetMessage
M.showBoundaryViolationMessage = showBoundaryViolationMessage

return M