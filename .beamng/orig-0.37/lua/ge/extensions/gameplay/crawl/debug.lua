-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local logTag = "crawl_debug"
M.dependencies = { 'ui_imgui' }

local debugWindowOpen = true
local debugData = {}
local enableDebugWindow = true

local im = ui_imgui

local function formatTime(seconds)
  if not seconds then return "N/A" end
  local minutes = math.floor(seconds / 60)
  local secs = seconds % 60
  return string.format("%02d:%06.3f", minutes, secs)
end

local function getBoundaryStatus(crawlerData, trail)
  if not trail or not crawlerData then return "No trail" end

  local site = nil
  if trail.siteId then
    site = gameplay_crawl_saveSystem.getSiteById(trail.siteId)
  end

  if not site then return "No site" end

  local vehiclePos = crawlerData.dynamicData.vehPos
  if not vehiclePos then return "No vehicle position" end

  if site.containsPoint2D then
    local inside = site:containsPoint2D(vehiclePos)
    return inside and "Inside" or "Outside"
  end

  return "Invalid site"
end

local function drawDebugWindow()
  if not debugWindowOpen or not enableDebugWindow then
    return
  end

  local shouldKeepOpen = im.Begin("Crawl Debug Window", im.BoolPtr(debugWindowOpen))
  if not shouldKeepOpen then
    debugWindowOpen = false
    return
  end

  if not debugData.trail or not debugData.crawlerData then
    im.Text("No active trail data")
    im.End()
    return
  end

  im.TextColored(im.ImVec4(1, 1, 0, 1), "=== TRAIL INFO ===")
  im.Text("Trail ID: " .. (debugData.trail.id or "Unknown"))
  im.Text("Trail Name: " .. (debugData.trail.name or "Unknown"))
  im.Text("Duration: " .. formatTime(debugData.currentTime))
  im.Separator()

  im.TextColored(im.ImVec4(0, 1, 0, 1), "=== VEHICLE INFO ===")
  if debugData.crawlerData and debugData.crawlerData.dynamicData then
    local vd = debugData.crawlerData.dynamicData
    im.Text("Position: " .. string.format("%.2f, %.2f, %.2f", vd.vehPos.x, vd.vehPos.y, vd.vehPos.z))
    im.Text("Velocity: " .. string.format("%.2f m/s", vd.vehVelocity:length()))
    im.Text("Boundary Status: " .. getBoundaryStatus(debugData.crawlerData, debugData.trail))
  end
  im.Separator()

  im.TextColored(im.ImVec4(0, 0, 1, 1), "=== NODES ===")
  local path = nil
  if debugData.trail.pathId then
    path = gameplay_crawl_saveSystem.getPathById(debugData.trail.pathId)
  end

  if path and path.nodes then
    local pathnodes = path.nodes
    im.Text("Total Nodes: " .. #pathnodes)
    im.Text("Current Index: " .. (debugData.currentPathnodeIndex or "N/A"))
    im.Text("Completed: " .. (debugData.completedCount or 0) .. "/" .. #pathnodes)
    im.Separator()

    if im.CollapsingHeader1("Node Details", im.TreeNodeFlags_DefaultOpen) then
      for i, pathnode in ipairs(pathnodes) do
        local isCompleted = debugData.completedPathnodes and debugData.completedPathnodes[i]
        local isCurrent = debugData.currentPathnodeIndex == i
        local color = isCompleted and im.ImVec4(0, 1, 0, 1) or (isCurrent and im.ImVec4(1, 1, 0, 1) or im.ImVec4(1, 1, 1, 1))

        im.TextColored(color, string.format("%d. %s", i, pathnode.name or "Unknown"))
        im.SameLine()
        im.TextColored(color, string.format("(%.1f, %.1f, %.1f)", pathnode.pos.x, pathnode.pos.y, pathnode.pos.z))

        if isCompleted and debugData.pathnodeTimings and debugData.pathnodeTimings[i] then
          im.SameLine()
          im.TextColored(color, " - " .. formatTime(debugData.pathnodeTimings[i]))
        end
      end
    end
  else
    im.Text("No nodes available")
  end
  im.Separator()

  if debugData.eventLog and #debugData.eventLog > 0 then
    im.TextColored(im.ImVec4(1, 0, 1, 1), "=== EVENT LOG ===")
    if im.CollapsingHeader1("Recent Events", im.TreeNodeFlags_DefaultOpen) then
      for i = math.max(1, #debugData.eventLog - 9), #debugData.eventLog do
        local event = debugData.eventLog[i]
        local eventText = event.type
        if event.pathnodeId then
          eventText = eventText .. " - " .. event.pathnodeId
        end
        if event.time then
          eventText = eventText .. " at " .. formatTime(event.time)
        end
        im.Text(eventText)
      end
    end
  end

  im.Separator()
  im.TextColored(im.ImVec4(1, 0.5, 0, 1), "=== TRAIL STATUS ===")
  if debugData.isCompleting then
    im.TextColored(im.ImVec4(0, 1, 0, 1), "COMPLETING - Waiting for results...")
  elseif debugData.isFinished then
    im.TextColored(im.ImVec4(0, 1, 0, 1), "FINISHED")
  else
    im.TextColored(im.ImVec4(1, 1, 0, 1), "ACTIVE")
  end

  im.End()
end

local function updateDebugData(crawlerId)
  if not enableDebugWindow then return end

  local utils = gameplay_crawl_utils
  if not utils then return end

  local state = utils.getCrawlState(crawlerId)
  if not state then return end

  debugData = {
    trail = state.trail,
    crawlerData = state.crawlerData,
    currentTime = state.currentTime,
    currentPathnodeIndex = state.currentPathnodeIndex,
    completedPathnodes = state.completedPathnodes,
    pathnodeTimings = state.pathnodeTimings,
    eventLog = state.eventLog,
    isCompleting = state.isCompleting,
    isFinished = state.isFinished,
    completedCount = 0
  }

  if debugData.completedPathnodes then
    for _ in pairs(debugData.completedPathnodes) do
      debugData.completedCount = debugData.completedCount + 1
    end
  end
end

local function onCrawlStarted(eventData)
  if not enableDebugWindow then return end

  debugWindowOpen = true
  log('I', logTag, 'Debug window opened for crawl')
end

local function onCrawlComplete(eventData)
  if debugData then
    debugData.isFinished = true
  end
  log('I', logTag, 'Crawl completed - debug data preserved')
end

local function onCrawlDisqualified(eventData)
  if debugData then
    debugData.isFinished = true
  end
  log('I', logTag, 'Crawl disqualified - debug data preserved')
end

local function onExtensionLoaded()
  debugWindowOpen = false
  debugData = {}
  log('I', logTag, 'Debug extension loaded')
end

local function onExtensionUnloaded()
  debugWindowOpen = false
  debugData = {}
  log('I', logTag, 'Debug extension unloaded')
end

local function onPreRender(dtReal, dtSim, dtRaw)
  if not enableDebugWindow then return end

  local utils = gameplay_crawl_utils
  if utils then
    local allStates = utils.getAllCrawlStates()
    if allStates then
      for crawlerId, state in pairs(allStates) do
        if state and state.active then
          updateDebugData(crawlerId)
          break
        end
      end
    end
  end

  drawDebugWindow()
end

M.setEnableDebugWindow = function(enabled)
  enableDebugWindow = enabled
  if not enabled then
    debugWindowOpen = false
    debugData = {}
  end
  log('I', logTag, 'Debug window ' .. (enabled and 'enabled' or 'disabled'))
end

M.getEnableDebugWindow = function()
  return enableDebugWindow
end

M.clearDebugData = function()
  debugData = {}
  log('I', logTag, 'Debug data cleared')
end

M.onCrawlStarted = onCrawlStarted
M.onCrawlComplete = onCrawlComplete
M.onCrawlDisqualified = onCrawlDisqualified
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onPreRender = onPreRender

return M