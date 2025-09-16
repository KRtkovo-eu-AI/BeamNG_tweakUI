-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
local M = {}

local MODULE_NAME = "ui_topBar"

M.dependencies = {'ui_topBar_config'}

local Config = extensions.ui_topBar_config

local topBarState = {
  visible = false,
  visibleItems = nil,
  activeItem = nil,
  currentUIState = nil
}

local executeItemAction = function(item)
  if item.targetState then
    guihooks.trigger("ChangeState", {
      state = item.targetState
    })
  elseif item.action then
    item.action()
  else
    log("W", "", "ui_topBar: executeItemAction: item has no action or targetState: " .. item.id)
  end
end

local setActiveItem = function(item)
  if M.state.activeItem == item then
    return
  end

  M.state.activeItem = item
  guihooks.trigger(MODULE_NAME .. "_activeItemChanged", item)
end

local selectItem = function(item)
  local itemId = type(item) == "table" and item.id or item
  local selectedItem = Config.TopBarEntries[itemId]
  if selectedItem then
    M.setActiveItem(itemId)
    executeItemAction(selectedItem)
  else
    log("W", "", "ui_topBar: selectItem: item not found: " .. itemId)
  end
end

local selectPreviousItem = function(loop)
  if not M.state.visibleItems or #M.state.visibleItems == 0 then
    return
  end

  local activeIndex = M.state.activeItem and arrayFindValueIndex(M.state.visibleItems, M.state.activeItem) or 1

  if not activeIndex then
    log("W", "", "ui_topBar: selectPreviousItem: activeItem not found in visibleItems: " .. M.state.activeItem)
    return
  end

  if activeIndex > 1 then
    M.selectItem(M.state.visibleItems[activeIndex - 1])
  elseif loop then
    M.selectItem(M.state.visibleItems[#M.state.visibleItems])
  end
end

local selectNextItem = function(loop)
  if not M.state.visibleItems or #M.state.visibleItems == 0 then
    return
  end

  local activeIndex = M.state.activeItem and arrayFindValueIndex(M.state.visibleItems, M.state.activeItem) or 1

  if activeIndex < #M.state.visibleItems then
    M.selectItem(M.state.visibleItems[activeIndex + 1])
  elseif loop then
    M.selectItem(M.state.visibleItems[1])
  end
end

local show = function()
  M.state.visible = true
  guihooks.trigger(MODULE_NAME .. "_show")
end

local hide = function()
  M.state.visible = false
  guihooks.trigger(MODULE_NAME .. "_hide")
end

local addEntry = function(entryKey, entry)
  Config.TopBarEntries[entry] = entry
  guihooks.trigger(MODULE_NAME .. "_entryAdded", entry)
end

local removeEntry = function(entryKey)
  Config.TopBarEntries[entryKey] = nil
  guihooks.trigger(MODULE_NAME .. "_entryRemoved", entryKey)
end

local updateEntry = function(entryKey, entry)
  if Config.TopBarEntries[entryKey] then
    Config.TopBarEntries[entryKey] = entry
    guihooks.trigger(MODULE_NAME .. "_entryChanged", entryKey)
  else
    addEntry(entryKey, entry)
  end
end

local updateEntries = function(entries)
  Config.TopBarEntries = entries
  guihooks.trigger(MODULE_NAME .. "_entriesChanged", entries)
end

local getEntry = function(entryKey)
  return Config.TopBarEntries[entryKey]
end

local getEntries = function()
  return Config.TopBarEntries
end

local getGameState = function()
  return {
    isInGame = getMissionFilename() ~= "",
    isCareerActive = extensions.career_career and extensions.career_career.isActive(),
    isGarageActive = extensions.gameplay_garageMode and extensions.gameplay_garageMode.isActive(),
    isMissionActive = extensions.gameplay_missions_missionManager and
        extensions.gameplay_missions_missionManager.getForegroundMissionId() ~= nil,
    isScenarioActive = extensions.scenario_scenarios and extensions.scenario_scenarios.getScenario() ~= nil
  }
end

local requestData = function()
  local gameState = getGameState()
  local data = {
    items = Config.TopBarEntries
  }
  tableMerge(data, gameState)
  tableMerge(data, M.state)
  guihooks.trigger(MODULE_NAME .. "_dataRequested", data)
end

local requestGameState = function()
  local gameState = getGameState()
  guihooks.trigger(MODULE_NAME .. "_gameStateChanged", gameState)
end

local requestEntries = function()
  log("D", "", "requestEntries")
  M.updateVisibleItems()
  guihooks.trigger(MODULE_NAME .. "_entriesChanged", Config.TopBarEntries)
end

local updateVisibleItems = function()
  local visibleItemObjects = {}
  for _, item in pairs(Config.TopBarEntries) do
    local isBlacklisted = item.blackListStates and M.state.currentUIState and
                              tableContains(item.blackListStates, M.state.currentUIState)
    local isHidden = item.isHidden and item.isHidden()
    local isOnlyIngame = item.onlyIngame and getMissionFilename() == ""
    if not isBlacklisted and not isHidden and not isOnlyIngame then
      table.insert(visibleItemObjects, item)
    end
  end

  table.sort(visibleItemObjects, function(a, b)
    local aOrder = a.order or 0
    local bOrder = b.order or 0
    return aOrder < bOrder
  end)

  local visibleItems = {}
  for _, item in pairs(visibleItemObjects) do
    table.insert(visibleItems, item.id)
  end

  topBarState.visibleItems = visibleItems
  guihooks.trigger(MODULE_NAME .. "_visibleItemsChanged", visibleItems)
end

local updateActiveItem = function()
  -- check if any of the key matches the state
  M.state.activeItem = nil

  -- check if any substate matches the state
  for _, item in pairs(Config.TopBarEntries) do
    if item.targetState == M.state.currentUIState then
      M.state.activeItem = item.id
      break
    elseif item.substates and #item.substates > 0 then
      for _, substate in pairs(item.substates) do
        if string.sub(M.state.currentUIState, 1, #substate) == substate then
          M.state.activeItem = item.id
          break
        end
      end
    end
  end

  guihooks.trigger(MODULE_NAME .. "_activeItemChanged", M.state.activeItem)
end

M.state = topBarState
M.setActiveItem = setActiveItem
M.selectItem = selectItem
M.selectPreviousItem = selectPreviousItem
M.selectNextItem = selectNextItem
M.show = show
M.hide = hide
M.addEntry = addEntry
M.removeEntry = removeEntry
M.updateEntry = updateEntry
M.updateEntries = updateEntries
M.getEntries = getEntries
M.getEntry = getEntry
M.requestData = requestData
M.requestEntries = requestEntries
M.requestGameState = requestGameState
M.updateVisibleItems = updateVisibleItems
M.updateActiveItem = updateActiveItem

M.onExtensionLoaded = function()
  -- disable automatic unload
  setExtensionUnloadMode(M, "manual")
end

M.onGameStateUpdate = function(state)
  -- dump("ui_topbar: onGameStateUpdate ", state)
  M.requestGameState()
end

M.onAnyMissionChanged = function(state, mission)
  M.requestGameState()
end

M.onUiChangedState = function(state)
  -- dump("ui_topbar: onUiChangedState ", state)
end

M.onUIStateTriggered = function(state, opened, stack)
  -- dump("ui_topbar: onUIStateTriggered ", {state, opened, stack})

  -- -- remove leading slash from state
  -- if type(state) == "string" and string.sub(state, 1, 1) == "/" then
  --   state = string.sub(state, 2)
  -- end

  -- -- TODO: popup check is a hack for now. maybe we can check popup state from lua instead
  -- if not opened or M.state.currentUIState == state or (type(state) == "string" and string.sub(state, 1, 5) == "popup") then
  --   return
  -- end

  -- if state == "menu.mainmenu" and getMissionFilename() == "" then
  --   M.hide()
  -- else
  --   M.show()
  -- end

  -- M.state.currentUIState = state
  -- M.updateVisibleItems()
  -- M.updateActiveItem()
end
-- End Extension hooks

return M
