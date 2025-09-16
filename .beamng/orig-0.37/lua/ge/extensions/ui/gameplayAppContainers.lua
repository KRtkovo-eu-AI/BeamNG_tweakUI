-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local logTag = 'gameplayAppContainers'
local verboseLogging = false
local debug = false
local gameplayAppContainerMounted = false
-- ImGui reference (initialized when needed)
local im = ui_imgui

local FLASH_MESSAGE_QUEUE_LIMIT = 50

-- Flash message queue system using dtSim accumulation pattern
local flashMessageQueue = {}
local currentMessage = nil

local appContainersById = {
  ['gameplayApps'] = {
    apps = {
      rally = { visible = false },
      drift = { visible = false },
      drag = { visible = false },
      pointsBar = { visible = false },
      flashMessage = { visible = false },
      countdown = { visible = false },
    },
    trigger = 'setGameplayAppVisibility',
  }
}

local function setAppVisibility(containerId, appId, visible)
  if not appContainersById[containerId] then
    log('E', logTag, 'container not found: ' .. containerId)
    return
  end
  local container = appContainersById[containerId]
  if not container.apps[appId] then
    log('E', logTag, 'app not found: ' .. appId .. ' for container: ' .. containerId)
    return
  end

  container.apps[appId].visible = visible

  guihooks.trigger(container.trigger, {
    appId = appId,
    visible = visible,
    allApps = container.apps
  })
end

local function getAppVisibility(containerId, appId)
  if not appContainersById[containerId] then
    log('E', logTag, 'container not found: ' .. containerId)
    return false
  end
  local container = appContainersById[containerId]
  if not container.apps[appId] then
    log('E', logTag, 'app not found: ' .. appId .. ' for container: ' .. containerId)
    return false
  end
  return container.apps[appId].visible
end

local function hideAllApps(containerId)
  if not appContainersById[containerId] then
    log('E', logTag, 'container not found: ' .. containerId)
    return
  end
    local container = appContainersById[containerId]
  for appId, app in pairs(container.apps) do
    app.visible = false
  end
  guihooks.trigger(container.trigger, {
    hideAll = true,
    allApps = container.apps
  })
  extensions.hook("onUIContainerAppsHidden", containerId)
end

local function showApp(containerId, appId)
  setAppVisibility(containerId, appId, true)
end

local function hideApp(containerId, appId)
  setAppVisibility(containerId, appId, false)
end

local function toggleApp(containerId, appId)
  local currentVisibility = getAppVisibility(containerId, appId)
  setAppVisibility(containerId, appId, not currentVisibility)
end

local function getVisibleApps(containerId)
  if not appContainersById[containerId] then
    log('E', logTag, 'container not found: ' .. containerId)
    return {}
  end
  local container = appContainersById[containerId]
  local visibleApps = {}
  for appId, app in pairs(container.apps) do
    if app.visible then
      table.insert(visibleApps, appId)
    end
  end
  return visibleApps
end

local function onSerialize()
  local data = {}
  for containerId, container in pairs(appContainersById) do
    data[containerId] = {}
    for appId, app in pairs(container.apps) do
      data[containerId][appId] = app.visible
    end
  end
  return data
end

local function onDeserialize(data)
  for containerId, apps in pairs(data) do
    for appId, visible in pairs(apps) do
      setAppVisibility(containerId, appId, visible)
    end
  end
end

local function getAvailableApps(containerId)
  if not appContainersById[containerId] then
    log('E', logTag, 'container not found: ' .. containerId)
    return {}
  end
  local apps = {}
  for appId, app in pairs(appContainersById[containerId].apps) do
    apps[appId] = app
  end
  return apps
end

-- Legacy context-based functions for backward compatibility
local function setContainerContext(containerId, context)
  if verboseLogging then
    log('W', logTag, 'setContainerContext is deprecated, use setAppVisibility instead')
  else
    log('D', logTag, 'setContainerContext is deprecated, use setAppVisibility instead')
  end
  if not context then
    hideAllApps(containerId)
    return
  end
  hideAllApps(containerId)
  showApp(containerId, context)
end

local function resetContainerContext(containerId)
  if verboseLogging then
    log('W', logTag, 'resetContainerContext is deprecated, use hideAllApps instead')
  else
    log('D', logTag, 'resetContainerContext is deprecated, use hideAllApps instead')
  end
  hideAllApps(containerId)
end

local function getContainerContext(containerId)
  if verboseLogging then
    log('W', logTag, 'getContainerContext is deprecated, use getVisibleApps instead')
  else
    log('D', logTag, 'getContainerContext is deprecated, use getVisibleApps instead')
  end
  local visibleApps = getVisibleApps(containerId)
  return visibleApps[1] or nil  -- Return first visible app for compatibility
end

local function setDebug(enabled)
  debug = enabled and true or false
end

-- Verbose logging toggle (separate from debug UI)
local function setVerboseLogging(enabled)
  verboseLogging = enabled and true or false
end

-- Extension lifecycle
local function onExtensionLoaded()
  -- Extension loaded successfully
end

-- Automatic flash message visibility control
local function onScenarioFlashMessage(data)
  -- Show flashMessage app when flash messages are triggered
  if data and #data > 0 then
    showApp('gameplayApps', 'flashMessage')
  end

  -- Detect scenario countdown sequences and control countdown app from backend
  local isCountdown = false
  local goTtl = nil
  if type(data) == 'table' then
    for i = 1, #data do
      local head = data[i] and data[i][1]
      if type(head) == 'number' or head == 'ui.scenarios.go' then
        isCountdown = true
      end
      if head == 'ui.scenarios.go' then
        goTtl = (data[i][2] or 1)
      end
    end
  end

  if isCountdown then
    showApp('gameplayApps', 'countdown')
    if goTtl then
      M._countdownHideTimer = goTtl
    end
  end
end

local function onScenarioFlashMessageClear()
  -- Hide flashMessage app when messages are cleared
  hideApp('gameplayApps', 'flashMessage')
end

local function onScenarioNotRunning()
  -- Hide flashMessage app when scenario ends
  hideApp('gameplayApps', 'flashMessage')
end

-- Add message to queue
local function queueFlashMessage(messageData, source)
  local duration = 3.0 -- default duration
  if messageData and messageData[1] and messageData[1][2] then
    duration = messageData[1][2] -- extract duration from message format {{msg, duration, 0, false}}
  end

  local message = {
    data = messageData,
    source = source,
    duration = duration,
    timer = 0
  }
  if #flashMessageQueue >= FLASH_MESSAGE_QUEUE_LIMIT then
    table.remove(flashMessageQueue, 1)
  end
  table.insert(flashMessageQueue, message)
end

-- Process next message in queue
local function processNextMessage()
  if #flashMessageQueue > 0 and not currentMessage then
    currentMessage = table.remove(flashMessageQueue, 1) -- Remove first message (FIFO)
    currentMessage.timer = 0 -- Reset timer for this message

    -- Show flash message app and send data to UI
    showApp('gameplayApps', 'flashMessage')
    guihooks.trigger('GameplayAppsFlashMessage', currentMessage.data)
  end
end

-- Clear messages from a specific source (for apps that need to control their message lifecycle)
local function clearMessagesFromSource(source)
  -- Clear queued messages from this source
  for i = #flashMessageQueue, 1, -1 do
    if flashMessageQueue[i].source == source then
      table.remove(flashMessageQueue, i)
    end
  end

  -- Clear current message if it's from this source
  if currentMessage and currentMessage.source == source then
    currentMessage = nil

    -- Hide flash message app if no more messages in queue
    if #flashMessageQueue == 0 then
      hideApp('gameplayApps', 'flashMessage')
    else
      -- Process next message immediately
      processNextMessage()
    end
  end

  -- Messages cleared from source
end

-- Clear all flash messages and hide the flash message app
local function clearAllFlashMessages()
  flashMessageQueue = {}
  currentMessage = nil
  hideApp('gameplayApps', 'flashMessage')
end

-- Intelligent flash message routing - handles all game flash messages in Lua
local function onGameplayFlashMessage(data)
  if not data or not data.source then
    if verboseLogging then
      log('W', logTag, 'Invalid flash message data received')
    else
      log('D', logTag, 'Invalid flash message data received')
    end
    return
  end

  local appId = (function()
    local sourceToAppId = { drift = 'drift', drag = 'drag' }
    return sourceToAppId[data.source]
  end)()

  if not appId then
    if verboseLogging then
      log('W', logTag, 'Unknown flash message source: ' .. tostring(data.source))
    else
      log('D', logTag, 'Unknown flash message source: ' .. tostring(data.source))
    end
    return
  end

  -- Only queue message if the source app is currently visible
  if getAppVisibility('gameplayApps', appId) then
    queueFlashMessage(data.data, data.source)
    processNextMessage() -- Try to start processing immediately if no current message
  end
end

-- Update function for dtSim timer accumulation and queue processing
local function onUpdate(dtReal, dtSim, dtRaw)
  -- Process current flash message timer using dtSim (pauses with game simulation)
  if currentMessage then
    currentMessage.timer = currentMessage.timer + dtSim
    if currentMessage.timer >= currentMessage.duration then
      -- Current message TTL expired
      currentMessage = nil

      -- Hide flash message app if no more messages in queue
      if #flashMessageQueue == 0 then
        hideApp('gameplayApps', 'flashMessage')
      else
        -- Process next message immediately
        processNextMessage()
      end
    end
  else
    -- No current message, try to process next one
    processNextMessage()
  end

  -- Handle countdown auto-hide timing using dtSim
  if M._countdownHideTimer and M._countdownHideTimer > 0 then
    M._countdownHideTimer = M._countdownHideTimer - dtSim
    if M._countdownHideTimer <= 0 then
      hideApp('gameplayApps', 'countdown')
      M._countdownHideTimer = nil
    end
  end

  -- Debug UI (only if debug enabled)
  if debug and im then
    im.Begin("Gameplay App Containers Debug")

    for containerId, container in pairs(appContainersById) do
      im.Text("Container: " .. containerId)

      -- Show visible apps count
      local visibleApps = getVisibleApps(containerId)
      im.Text("Visible Apps: " .. #visibleApps .. "/" .. tableSize(container.apps))

      -- Show individual app controls
      im.Text("App Controls:")
      for _, appId in ipairs(tableKeysSorted(container.apps)) do
        local app = container.apps[appId]
        local isVisible = app.visible

        -- Toggle button for each app using Button instead of Checkbox
        local buttonText = (isVisible and "Hide " or "Show ") .. appId
        if im.Button(buttonText .. "##" .. containerId .. "_" .. appId) then
          setAppVisibility(containerId, appId, not isVisible)
        end

        -- Show current state
        im.SameLine()
        im.Text(isVisible and "✓" or "✗")
      end

      -- Bulk actions
      im.Separator()
      if im.Button("Hide All##" .. containerId) then
        hideAllApps(containerId)
      end
      im.SameLine()
      if im.Button("Show All##" .. containerId) then
        for appId, _ in pairs(container.apps) do
          showApp(containerId, appId)
        end
      end

      -- Flash message testing
      if containerId == 'gameplayApps' then
        im.Separator()
        im.Text("Flash Message Testing:")

        if im.Button("Test Drift Message (3s)##" .. containerId) then
          -- Simulate drift app visible and send test message
          showApp(containerId, 'drift')
          onGameplayFlashMessage({
            source = 'drift',
            data = {{'Drift Combo x5!', 3.0, 0, false}}
          })
        end

        im.SameLine()
        if im.Button("Test Drag Message (5s)##" .. containerId) then
          -- Simulate drag app visible and send test message
          showApp(containerId, 'drag')
          onGameplayFlashMessage({
            source = 'drag',
            data = {{'Perfect Launch!', 5.0, 0, false}}
          })
        end

        if im.Button("Quick Message (1s)##" .. containerId) then
          showApp(containerId, 'drift')
          onGameplayFlashMessage({
            source = 'drift',
            data = {{'Quick Test!', 1.0, 0, false}}
          })
        end

        im.SameLine()
        if im.Button("Long Message (8s)##" .. containerId) then
          showApp(containerId, 'drift')
          onGameplayFlashMessage({
            source = 'drift',
            data = {{'This is a longer message for testing!', 8.0, 0, false}}
          })
        end

        -- Show current flash message state and queue
        im.Separator()
        im.Text("Flash Message Queue State:")
        im.Text("Queue Size: " .. #flashMessageQueue)
        im.Text("Current Message: " .. (currentMessage and "Active" or "None"))

        if currentMessage then
          im.Text(string.format("Timer: %.2f / %.2f", currentMessage.timer, currentMessage.duration))
          local remaining = currentMessage.duration - currentMessage.timer
          im.Text(string.format("Remaining: %.2f seconds", remaining))
          im.Text("Source: " .. currentMessage.source)
          if currentMessage.data and currentMessage.data[1] then
            im.Text("Text: " .. tostring(currentMessage.data[1][1]))
          end
        end

        if #flashMessageQueue > 0 then
          im.Text("Queued Messages:")
          for i, msg in ipairs(flashMessageQueue) do
            local text = (msg.data and msg.data[1] and msg.data[1][1]) or "Unknown"
            im.Text(string.format("  %d. [%s] %.1fs: %s", i, msg.source, msg.duration, text))
          end
        end

        if im.Button("Clear Queue##" .. containerId) then
          clearAllFlashMessages()
        end

        im.SameLine()
        if im.Button("Clear Drag Messages##" .. containerId) then
          clearMessagesFromSource('drag')
        end
      end

      -- Show currently visible apps
      if #visibleApps > 0 then
        im.Text("Currently Visible:")
        for _, appId in ipairs(visibleApps) do
          im.BulletText(appId)
        end
      end
    end

    im.End()
  end
end

local function onExtensionUnloaded()
  -- Clean up flash message queue state
  flashMessageQueue = {}
  currentMessage = nil
end

local function onGameplayAppContainerMounted()
  gameplayAppContainerMounted = true
end

local function onGameplayAppContainerUnmounted()
  gameplayAppContainerMounted = false
end

local function getGameplayAppContainerMounted()
  return gameplayAppContainerMounted
end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onUpdate = onUpdate
M.onGameplayFlashMessage = onGameplayFlashMessage
M.clearMessagesFromSource = clearMessagesFromSource
M.clearAllFlashMessages = clearAllFlashMessages
M.onScenarioFlashMessage = onScenarioFlashMessage
M.onScenarioFlashMessageClear = onScenarioFlashMessageClear
M.onScenarioNotRunning = onScenarioNotRunning

M.onGameplayAppContainerMounted = onGameplayAppContainerMounted
M.onGameplayAppContainerUnmounted = onGameplayAppContainerUnmounted
M.getGameplayAppContainerMounted = getGameplayAppContainerMounted


M.setVerboseLogging = setVerboseLogging
M.setDebug = setDebug

-- Legacy API (deprecated)
M.setContainerContext = setContainerContext
M.getContainerContext = getContainerContext
M.resetContainerContext = resetContainerContext
M.getAvailableContexts = getAvailableApps  -- Redirect to new function

  -- New API
M.setAppVisibility = setAppVisibility
M.getAppVisibility = getAppVisibility
M.showApp = showApp
M.hideApp = hideApp
M.toggleApp = toggleApp
M.hideAllApps = hideAllApps
M.getVisibleApps = getVisibleApps
M.getAvailableApps = getAvailableApps


M.onSerialize = onSerialize
M.onDeserialize = onDeserialize
return M