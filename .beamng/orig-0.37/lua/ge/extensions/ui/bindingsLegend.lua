-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local im = ui_imgui
local debugMode = false

M.dependencies = {
  "core_input_actions",
  "core_input_bindings"
}

local actionJsonFilePath = "ui/bindingAppActions.json"

local MODIFIER_L_SHIFT = 1
local MODIFIER_R_SHIFT = 2
local MODIFIER_L_CTRL = 4
local MODIFIER_R_CTRL = 8
local MODIFIER_L_ALT = 16
local MODIFIER_R_ALT = 32
local MODIFIER1 = 64
local MODIFIER2 = 128
local MODIFIER3 = 256
local MODIFIER4 = 512
local MODIFIER5 = 1024
local MODIFIER6 = 2048

local actionLimit = 50

local actionData = {}
local actionCategoryActive = {}
local modifiersActive = {}

local jsonActions = {}

-- Fade control state (real-time based)
local fadeDelaySeconds = 7
local fadeDelayTimer = 0
local isFaded = false

-- Debug ImGui window to test fade behavior quickly
local function setDebug(enabled)
  debugMode = enabled
end

local function shouldFade()
  if fadeDelayTimer < fadeDelaySeconds then return false end
  if actionCategoryActive["vehicleSpecific"] then return false end
  if not tableIsEmpty(modifiersActive) then return false end
  return true
end

local function dispatchFadeIfChanged(forceValue)
  local newValue = forceValue
  if newValue == nil then
    newValue = shouldFade()
  end
  if isFaded ~= newValue then
    isFaded = newValue
    guihooks.trigger("setBindingsLegendFade", isFaded)
  end
end

local function resetFade()
  fadeDelayTimer = 0
end

local function fadeUpdate(dtReal)
  -- Evaluate fade while visible; when already faded we wait for explicit activity to unfade
  fadeDelayTimer = fadeDelayTimer + dtReal
  dispatchFadeIfChanged()
end

local function drawDebugWindow()
  if not debugMode or not im then return end
  if im.Begin("BindingsLegend Debug") then
    local var = im.FloatPtr(fadeDelaySeconds)
    im.PushItemWidth(120)
    if im.InputFloat("Fade delay (sec)", var, 0.5, 1.0, "%.1f", im.InputTextFlags_EnterReturnsTrue) then
      fadeDelaySeconds = math.max(0, var[0])
    end

    im.Separator()
    im.Text("Delay Timer: " .. string.format("%.2f", fadeDelayTimer))
    im.Text("VehicleSpecific visible: " .. tostring(actionCategoryActive["vehicleSpecific"]))
    im.Text("Should fade:   " .. tostring(shouldFade()))
    im.Text("Is faded:      " .. tostring(isFaded))

    if im.Button("Force Unfade") then
      dispatchFadeIfChanged(false)
    end
    im.SameLine()
    if im.Button("Force Fade") then
      dispatchFadeIfChanged(true)
    end

    im.Separator()
    im.Text("Categories (active state, priority, highest):")

    local dbgHighestPrio = 0
    for _, dataSet in ipairs(actionData) do
      if dataSet.additionalData and dataSet.additionalData.priority and dataSet.additionalData.priority > dbgHighestPrio then
        dbgHighestPrio = dataSet.additionalData.priority
      end
    end

    local combinedSet = {}
    for name, _ in pairs(actionCategoryActive) do combinedSet[name] = true end
    for name, _ in pairs(jsonActions) do combinedSet[name] = true end
    local combinedList = {}
    for name, _ in pairs(combinedSet) do table.insert(combinedList, name) end
    table.sort(combinedList, function(a, b) return a < b end)

    for _, categoryName in ipairs(combinedList) do
      im.Separator()
      local actions = jsonActions[categoryName] or {}
      local isActive = not not actionCategoryActive[categoryName]
      local currentPriority = nil
      for _, dataSet in ipairs(actionData) do
        if dataSet.label == categoryName and dataSet.additionalData then
          currentPriority = dataSet.additionalData.priority
          break
        end
      end
      local isHighest = (currentPriority ~= nil and currentPriority == dbgHighestPrio and dbgHighestPrio > 0)
      local prioTxt = currentPriority and tostring(currentPriority) or "n/a"
      local suffix = isHighest and " [HIGHEST]" or ""
      im.Text(categoryName .. " (" .. tostring(#actions) .. " actions) - Active: " .. tostring(isActive) .. " | priority: " .. prioTxt .. suffix)
      im.SameLine()
      if not tableIsEmpty(actions) and im.Button("Show##" .. categoryName) then
        M.addActions(categoryName, actions, {priority = 5})
      end

      if isActive then
        im.SameLine()
        if im.Button("Hide##" .. categoryName) then
          M.addActions(categoryName, {})
        end
      end

      for _, a in ipairs(actions) do
        local actionName = a.action or "(nil)"
        im.Text("  - " .. actionName)
      end
    end

  end
  im.End()
end

local function getVehicleSpecificActions()
  local result = {}
  local actionsByName = {}
  local activeActions = core_input_actions.getActiveActions()
  for _, device in ipairs(core_input_bindings.bindings) do
    for _, binding in ipairs(device.contents.bindings) do
      local actionInfo = activeActions[binding.action]
      if actionInfo and actionInfo.cat == "vehicle_specific" and not core_input_actionFilter.isActionBlocked(binding.action) then
        -- Get the title from the action definition
        if (not actionInfo.actionMap or isActionMapActive(actionInfo.actionMap)) then
          if actionsByName[binding.action] then
            table.insert(actionsByName[binding.action].bindings, {device = device.devname, control = binding.control})
          else
            local action = {}
            action.label = actionInfo.title
            action.order = actionInfo.order or 999  -- fallback to 999 if no order defined
            action.cat = actionInfo.cat
            action.action = binding.action
            action.bindings = {}
            action.inputActionOnClick = true
            table.insert(action.bindings, {device = device.devname, control = binding.control})

            actionsByName[action.action] = action
          end
        end
      end
    end
  end

  for _, action in pairs(actionsByName) do
    table.insert(result, action)
  end
  return result
end

local function getActionDataSetByLabel(label)
  for i, actionDataSet in ipairs(actionData) do
    if actionDataSet.label == label then
      return actionDataSet
    end
  end
end

local function sortActions(actions)
  -- Sort actions by category first, then by order
  table.sort(actions, function(a, b)
    if a.cat ~= b.cat then
      return (a.cat or "") > (b.cat or "")
    end
    if a.order ~= b.order then
      return (a.order or 999) < (b.order or 999)
    end
    return a.action < b.action
  end)
end

local function isActionMapActive(actionMapName)
  local name = actionMapName.."ActionMap"
  for _, actionMap in ipairs(ActionMap:getList().active) do
    if actionMap.enabled and actionMap.name == name then
      return true
    end
  end
  return false
end

local function getBoundModifierActions()
  local result = {}
  for i = 1, 6 do
    for _, device in ipairs(core_input_bindings.bindings) do
      for _, binding in ipairs(device.contents.bindings) do
        if binding.action == "customModifier" .. i then
          table.insert(result, {
            action = "customModifier" .. i,
          })
          goto continueBoundModifierActions
        end
      end
    end
    ::continueBoundModifierActions::
  end
  return result
end

local function setActionDefaults(actions)
  local activeActions = core_input_actions.getActiveActions()
  for _, action in ipairs(actions) do
    if action.inputActionOnClick == nil then
      action.inputActionOnClick = true
    end
    if action.label == nil then
      action.label = activeActions[action.action].title
    end
  end
end

local function sendDataToUI()
  local uiData = {actions = {}, constantActions = {}, additionalData = {}}

  local highestPriority = 0
  local highestPriorityIndex
  for i, actionDataSet in ipairs(actionData) do
    if actionDataSet.additionalData and actionDataSet.additionalData.priority and actionDataSet.additionalData.priority > highestPriority then
      highestPriority = actionDataSet.additionalData.priority
      highestPriorityIndex = i
    end
  end

  -- construct uiData table
  for i, actionDataSet in ipairs(actionData) do
    if actionDataSet.additionalData then
      tableMerge(uiData.additionalData, actionDataSet.additionalData)
    end
    if not (highestPriorityIndex and actionDataSet.additionalData.priority ~= highestPriority) then
      sortActions(actionDataSet.actions)
      arrayConcat(uiData.actions, actionDataSet.actions)
    end
  end

  if actionCategoryActive["vehicleSpecific"] then
    uiData.additionalData.vehicleSpecificStatus = "enabled"
  else
    arrayConcat(uiData.constantActions, getBoundModifierActions())
    uiData.additionalData.vehicleSpecificStatus = "disabled"
  end

  if not tableIsEmpty(getVehicleSpecificActions()) then
    table.insert(uiData.constantActions, {
      action = "toggleShowVehicleSpecificActions",
      label = "Vehicle Specific Actions",
    })
  end

  for i = #uiData.actions, 1, -1 do
    local action = uiData.actions[i]
    if core_input_actionFilter.isActionBlocked(action.action) then
      table.remove(uiData.actions, i)
    end
  end

  setActionDefaults(uiData.constantActions)

  if #uiData.actions + #uiData.constantActions > actionLimit then
    -- Cut the list to actionLimit size
    local trimmedActions = {}
    for i = #uiData.actions - actionLimit, #uiData.actions do
      table.insert(trimmedActions, uiData.actions[i])
    end
    uiData.actions = trimmedActions
  end

  guihooks.trigger("setActionsForLegend", uiData)
  -- New data pushed to UI: unfade and restart inactivity delay
  resetFade()
end

local function removeActionCategoryByLabel(label)
  for i, actionDataSet in ipairs(actionData) do
    if actionDataSet.label == label then
      table.remove(actionData, i)
    end
  end
  actionCategoryActive[label] = nil
end

-- Removes action sets with "removeIfOverwrittenWithHigherPriority" when their priority is lower than the provided newPriority.
local function removeLowerPriorityOptInActionSets(newPriority)
  if not newPriority then return end
  for i = #actionData, 1, -1 do
    local actionSet = actionData[i]
    if actionSet and actionSet.additionalData and actionSet.additionalData.removeIfOverwrittenWithHigherPriority then
      local actionSetPriority = actionSet.additionalData.priority or 0
      if actionSetPriority < newPriority then
        actionCategoryActive[actionSet.label] = nil
        table.remove(actionData, i)
      end
    end
  end
end

local function addActions(label, actions, additionalData)
  removeActionCategoryByLabel(label)
  if not tableIsEmpty(actions) then
    setActionDefaults(actions)
    removeLowerPriorityOptInActionSets(additionalData and additionalData.priority)

    table.insert(actionData, {actions = actions, additionalData = additionalData, label = label})
    actionCategoryActive[label] = true
  end
  sendDataToUI()
end

local function addConstantActions(actions)
  for _, action in ipairs(actions) do
    table.insert(actionData, {actions = {action}, additionalData = {priority = 10}, label = "constant"})
  end
end

local modifierCategories = {
  vehicle_specific = true,
  vehicle = true,
  gameplay = true,
  slowmotion = true,
  camera = true,
  menu = true,
}

local function getBindingsByDeviceName(deviceName)
  for _, device in ipairs(core_input_bindings.bindings) do
    if device.devname == deviceName then
      return device.contents.bindings
    end
  end
end

local function onModifierChanged(newModifiers)
  local modifierNames = {}
  --if bit.band(newModifiers, MODIFIER_L_SHIFT) == MODIFIER_L_SHIFT or bit.band(newModifiers, MODIFIER_R_SHIFT) == MODIFIER_R_SHIFT then table.insert(modifierNames, "shift") end
  --if bit.band(newModifiers, MODIFIER_L_CTRL) == MODIFIER_L_CTRL or bit.band(newModifiers, MODIFIER_R_CTRL) == MODIFIER_R_CTRL then table.insert(modifierNames, "ctrl") end
  --if bit.band(newModifiers, MODIFIER_L_ALT) == MODIFIER_L_ALT or bit.band(newModifiers, MODIFIER_R_ALT) == MODIFIER_R_ALT then table.insert(modifierNames, "alt") end
  if bit.band(newModifiers, MODIFIER1) == MODIFIER1 then table.insert(modifierNames, "modifier1") end
  if bit.band(newModifiers, MODIFIER2) == MODIFIER2 then table.insert(modifierNames, "modifier2") end
  if bit.band(newModifiers, MODIFIER3) == MODIFIER3 then table.insert(modifierNames, "modifier3") end
  if bit.band(newModifiers, MODIFIER4) == MODIFIER4 then table.insert(modifierNames, "modifier4") end
  if bit.band(newModifiers, MODIFIER5) == MODIFIER5 then table.insert(modifierNames, "modifier5") end
  if bit.band(newModifiers, MODIFIER6) == MODIFIER6 then table.insert(modifierNames, "modifier6") end

  local actions = {}
  local bindingsByAction = {}

  if not tableIsEmpty(modifierNames) then
    local activeActions = core_input_actions.getActiveActions()
    for _, deviceName in ipairs(core_input_bindings.getRecentDevices()) do
      local bindingsByDevice = getBindingsByDeviceName(deviceName)
      for _, binding in ipairs(bindingsByDevice or {}) do
        local actionInfo = activeActions[binding.action]

        if actionInfo and actionInfo.title and modifierCategories[actionInfo.cat] and not core_input_actionFilter.isActionBlocked(binding.action) then
          -- Check if binding.control contains exactly these modifiers
          local normalizedControl = string.gsub(binding.control, "%-", " ")
          local controlParts = string.split(normalizedControl)
          local bindingModifiers = {}

          -- Get all parts except the last (which is the actual control)
          for i = 1, #controlParts - 1 do
            table.insert(bindingModifiers, controlParts[i])
          end

          -- Check if modifiers match exactly
          local modifiersMatch = #bindingModifiers == #modifierNames
          if modifiersMatch then
            for _, modifier in ipairs(modifierNames) do
              if not tableContains(bindingModifiers, modifier) then
                modifiersMatch = false
                break
              end
            end
          end

          if modifiersMatch and #modifierNames > 0 then
            -- Get the title from the action definition
            if (not actionInfo.actionMap or isActionMapActive(actionInfo.actionMap)) then
              if bindingsByAction[binding.action] then
                --table.insert(bindingsByAction[binding.action], {device = deviceName, control = binding.control})
              else
                local action = {}
                action.action = binding.action
                action.label = actionInfo.title
                action.order = actionInfo.order or 999  -- fallback to 999 if no order defined
                action.cat = actionInfo.cat
                bindingsByAction[binding.action] = {{device = deviceName, control = binding.control}}
                action.bindings = bindingsByAction[binding.action]
                table.insert(actions, action)
              end
            end
          end
        end
      end
    end
  end

  table.clear(modifiersActive)
  for _, modifier in ipairs(modifierNames) do
    modifiersActive[modifier] = true
  end

  local additionalData = {
    modifiersActive = modifiersActive,
    priority = 9
  }

  addActions("modified", actions, additionalData)
end

local idleCounter = 0
local vehVelocity = vec3()
local skipParkingSpeedCheck
local function onUpdate(dtReal, dtSim, dtRaw)
  fadeUpdate(dtReal)

  if not getPlayerVehicle(0) then return end
  vehVelocity:set(getPlayerVehicle(0):getVelocityXYZ())
  local vehicleSpeed = vehVelocity:len()

  local isAtParkingSpeed = true
  if skipParkingSpeedCheck then
    -- skip parking speed check for a few frames
    skipParkingSpeedCheck = skipParkingSpeedCheck - 1
    if skipParkingSpeedCheck == 0 then
      skipParkingSpeedCheck = nil
    end
  else
    isAtParkingSpeed = vehicleSpeed < 1
  end

  for _, actionDataSet in ipairs(actionData) do
    if actionDataSet.additionalData then
      if actionDataSet.additionalData.ttl then
        if not actionDataSet.additionalData.timerStarted and not isAtParkingSpeed then
          actionDataSet.additionalData.timerStarted = true
        end
        if actionDataSet.additionalData.timerStarted then
        actionDataSet.additionalData.ttl = actionDataSet.additionalData.ttl - dtReal
          if actionDataSet.additionalData.ttl <= 0 then
            removeActionCategoryByLabel(actionDataSet.label)
            sendDataToUI()
          end
        end
      end
    end
  end
  if not actionCategoryActive["idle"] and isAtParkingSpeed then
    idleCounter = idleCounter + dtReal
    if idleCounter > 3 then
      addActions("idle", jsonActions.idle, {priority = 5})
    end
  elseif actionCategoryActive["idle"] and not isAtParkingSpeed then
    removeActionCategoryByLabel("idle")
    sendDataToUI()
    idleCounter = 0
  end

  drawDebugWindow()
end

local function enableShowVehicleSpecificActions(enable)
  if (not enable) == (not actionCategoryActive["vehicleSpecific"]) then
    return
  end
  local vehicleSpecificActions
  if enable then
    vehicleSpecificActions = getVehicleSpecificActions()
    if tableIsEmpty(vehicleSpecificActions) then
      return
    end
  end

  if enable then
    addActions("vehicleSpecific", vehicleSpecificActions, {priority = 10})
  else
    removeActionCategoryByLabel("vehicleSpecific")
  end
  sendDataToUI()
end

local function toggleShowVehicleSpecificActions()
  enableShowVehicleSpecificActions(not actionCategoryActive["vehicleSpecific"])
end

local function onClientStartMission()
end

local function onClientEndMission()
  table.clear(actionData)
  table.clear(actionCategoryActive)
end

local function onVehicleSwitched(oldId, newId, player)
  if oldId ~= newId then
    enableShowVehicleSpecificActions(false)
    local vehicleSpecificActions = getVehicleSpecificActions()
    if not tableIsEmpty(vehicleSpecificActions) then
      addActions("vehicleSpecific", vehicleSpecificActions, {priority = 8, removeIfOverwrittenWithHigherPriority = true, ttl = 10})
    end
    sendDataToUI()
  end
end

local function onExtensionLoaded()
  local bindingAppActions = jsonReadFile(actionJsonFilePath)
  if bindingAppActions then
    jsonActions = bindingAppActions
  end
end

local function triggerInputAction(action, value)
  local activeActions = core_input_actions.getActiveActions()
  core_input_actions.executeCommand(activeActions[action], value, be:getPlayerVehicleID(0))
end

local function onDeviceChanged()
  sendDataToUI()
end

local function onVehicleSpawned(id)
  -- skip parking speed check for 5 frames after a vehicle is spawned
  skipParkingSpeedCheck = 5
end

M.addActions = addActions
M.sendDataToUI = sendDataToUI
M.toggleShowVehicleSpecificActions = toggleShowVehicleSpecificActions
M.enableShowVehicleSpecificActions = enableShowVehicleSpecificActions
M.setDebug = setDebug
M.triggerInputAction = triggerInputAction

M.onModifierChanged = onModifierChanged
M.onClientStartMission = onClientStartMission
M.onClientEndMission = onClientEndMission
M.onVehicleSwitched = onVehicleSwitched
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onDeviceChanged = onDeviceChanged
M.onVehicleSpawned = onVehicleSpawned

return M
