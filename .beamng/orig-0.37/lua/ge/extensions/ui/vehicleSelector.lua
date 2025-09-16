local M = {}
M.dependencies = {
  "core_vehicles",
  "ui_vehicleSelector_detailsInteraction",
  "ui_vehicleSelector_filters",
  "ui_vehicleSelector_displayData",
  "ui_vehicleSelector_tiles"
}
local function emptyProfiler()
  return {
    start = function() end,
    add = function() end,
    finish = function() end,
  }
end
M.emptyProfiler = emptyProfiler
M.p = emptyProfiler()
--M.p = LuaProfiler("vehicleSelector Profiler")
--[[
  M.p = LuaProfiler("vehicleSelector Profiler")
  ]]
-- Vehicle data storage
local uiData = nil
-- Initialize vehicle data from core module
local function initializeVehicleData()
  local p = M.emptyProfiler()
  --p = LuaProfiler("initializeVehicleData")
  p:start()
  local uiData = {}
  -- Get fresh display data from the extension
  local displayData = ui_vehicleSelector_displayData.getDisplayData()

  uiData = {
    models = {},
    configs = {},
    filterList = {},
    activeFilters = {}, -- Currently applied filters
    lockedFiltersByProp = {}, -- Locked filters that cannot be modified
    displayData = displayData,
  }
  local modelList, configList, modelAndConfigList = {}, {}, {}
  p:add("displayData")
  for modelName, _ in pairs(core_vehicles.getModelsData()) do
    table.insert(modelList, core_vehicles.getModel(modelName).model)
    table.insert(modelAndConfigList, core_vehicles.getModel(modelName).model)
    for _, config in pairs(core_vehicles.getModel(modelName).configs or {}) do
      table.insert(configList, config)
      table.insert(modelAndConfigList, config)
    end
  end
  p:add("vehicle and config list")
  uiData.filterList, uiData.filterByProp = ui_vehicleSelector_filters.createFilters(modelAndConfigList)
  p:add("filterList")
  -- Update uiData
  uiData.models = modelList
  uiData.configs = configList
  uiData.displayInfo = core_vehicles.displayInfo
  p:add("uiData finished")
  p:finish(true)
  return uiData
end
local vehicleDataChanged = false
M.onModDeactivated = function() vehicleDataChanged = true end
M.onModActivated = function() vehicleDataChanged = true end
M.onModManagerReady = function() vehicleDataChanged = true end

-- Getter for uiData that initializes if needed
local function getUiData()
  if vehicleDataChanged then
    log("I","","Reloading vehicle data for vehicle selector")
    uiData = initializeVehicleData()
    vehicleDataChanged = false
  end
  uiData = uiData or initializeVehicleData()
  return uiData
end
M.getUiData = getUiData

local function closedFromUI()
  extensions.hook("onVehicleSelectorClosed")
end
M.closedFromUI = closedFromUI

M.getFilters = function(...) return ui_vehicleSelector_filters.getFilters(...) end
M.getSearchText = function(...) return ui_vehicleSelector_filters.getSearchText(...) end
M.setSearchText = function(...) return ui_vehicleSelector_filters.setSearchText(...) end
M.getTiles = function(...) return ui_vehicleSelector_tiles.getTiles(...) end
M.getDisplayData = function(...) return ui_vehicleSelector_displayData.getDisplayData(...) end
M.getDisplayDataOptions = function(...) return ui_vehicleSelector_displayData.getDisplayDataOptions(...) end
M.setDisplayDataOption = function(...) return ui_vehicleSelector_displayData.setDisplayDataOption(...) end
M.resetDisplayDataToDefaults = function(...) return ui_vehicleSelector_displayData.resetDisplayDataToDefaults(...) end
M.toggleFavourite = function(...) return ui_vehicleSelector_displayData.toggleFavourite(...) end

M.updateFilters = function(...) return ui_vehicleSelector_filters.updateFilters(...) end
M.toggleFilter = function(...) return ui_vehicleSelector_filters.toggleFilter(...) end
M.updateRangeFilter = function(...) return ui_vehicleSelector_filters.updateRangeFilter(...) end
M.resetRangeFilter = function(...) return ui_vehicleSelector_filters.resetRangeFilter(...) end
M.resetSetFilter = function(...) return ui_vehicleSelector_filters.resetSetFilter(...) end
M.clearAllFilters = function(...) return ui_vehicleSelector_filters.clearAllFilters(...) end


M.lockFilter = function(...) return ui_vehicleSelector_filters.lockFilter(...) end
M.unlockFilter = function(...) return ui_vehicleSelector_filters.unlockFilter(...) end
M.isFilterLocked = function(...) return ui_vehicleSelector_filters.isFilterLocked(...) end
M.lockFilterMode = function(...) return ui_vehicleSelector_filters.lockFilterMode(...) end
M.lockFilterModeExclusive = function(...) return ui_vehicleSelector_filters.lockFilterModeExclusive(...) end
M.clearLockedFilters = function(...) return ui_vehicleSelector_filters.clearLockedFilters(...) end
M.calculateActiveFilters = function(...) return ui_vehicleSelector_filters.calculateActiveFilters(...) end
M.setupValidFilters = function(...) return ui_vehicleSelector_filters.setupValidFilters(...) end
M.createFilters = function(...) return ui_vehicleSelector_filters.createFilters(...) end
M.passesFilters = function(...) return ui_vehicleSelector_filters.passesFilters(...) end


M.isFavourite = function(...) return ui_vehicleSelector_displayData.isFavourite(...) end
M.isRecentVehicle = function(...) return ui_vehicleSelector_displayData.isRecentVehicle(...) end
M.trackRecentVehicle = function(...) return ui_vehicleSelector_displayData.trackRecentVehicle(...) end

-- Get screen header title based on current path and filter state
local function getScreenHeaderTitleAndPath(path)
  local title = ""
  local pathSegments = {{label = "Menu", gotoAngularState = "menu.mainmenu"}}
  local pathType = path and path.keys and path.keys[1]

  table.insert(pathSegments, {label = "Vehicle Selector", gotoPath = {'allModels'}, clearFilters = true, clearSearch = true})

  -- Check if any filters or search are active
  local uiData = getUiData()
  local activeFilters, _ = ui_vehicleSelector_filters.calculateActiveFilters()
  local searchText = ui_vehicleSelector_filters.getSearchText()
  local isFiltered = #activeFilters > 0 or (searchText and searchText ~= "")
  local searchSegmentText = {}
  if #activeFilters > 0 then
    table.insert(searchSegmentText, "Filtered")
  end
  if searchText and searchText ~= "" then
    table.insert(searchSegmentText, "Search: " .. searchText)
  end
  if #searchSegmentText > 0 then
    table.insert(pathSegments, {label = table.concat(searchSegmentText, ", "), gotoPath = {'allModels'}})
  end

  if pathType == "allModels" then
    title = "All Vehicles"
  elseif pathType == "configsForBrandSubModelOrModel" then
    local modelKey = path.keys[2]
    local modelSubKey = path.keys[3]
    local brandKey = path.keys[4]
    local groupMode = path.keys[5]
    local groupName = path.keys[6]
    local lastSegmentName = ""
    if modelKey then
      local model = core_vehicles.getModel(modelKey)
      if model then
        local brand = brandKey and brandKey ~= "" and brandKey or (model.model.Brand or "")
        local subModel = modelSubKey and modelSubKey ~= "" and modelSubKey or (model.model.SubModel or "")
        local modelName = model.model.Name or modelKey

        if brand and brand ~= "" then
          title = brand
          if subModel and subModel ~= "" then
            title = title .. " " .. subModel
          else
            title = title .. " " .. modelName
          end
        else
          if subModel and subModel ~= "" then
            title = subModel
          else
            title = modelName
          end
        end
        lastSegmentName = title
        -- Add group context if available
        if groupMode then
          if groupMode == "Favourites" then
            title = title .. " (Favourites)"
            --lastSegmentName = "Favourites / " .. lastSegmentName
          elseif groupMode == "Recent" then
            title = title .. " (Recent)"
            --lastSegmentName = "Recent / " .. lastSegmentName
          elseif groupName then
            title = title .. " (" .. groupMode .. " is " .. groupName .. ")"
            --lastSegmentName = groupName .. " / " .. lastSegmentName
          else
            title = title .. " (" .. groupMode .. ")"
            --lastSegmentName = groupMode .. " / " .. lastSegmentName
          end
        end
      else
        lastSegmentName = "Unknown Model"
        title = "Unknown Model"
      end
    else
      lastSegmentName = "Vehicle Configurations"
      title = "Vehicle Configurations"
    end
    table.insert(pathSegments, {label = lastSegmentName, gotoPath = path.keys})
  else
    title = "Vehicle Selector"
  end

  if isFiltered then
    title = title .. " (Filtered)"
  end
  return {
    title = title,
    isFiltered = isFiltered,
    pathSegments = pathSegments
  }
end
M.getScreenHeaderTitleAndPath = getScreenHeaderTitleAndPath

local function profilerFinish(tag)
  if not M.p or not M.p.timer then return end
  if tag and tag ~= "" and tag ~= "undefined" then
    M.p:add(tag)
  else
    M.p:add("profilerFinish (no tag, UI is now ready)")
    M.p:finish(true)
  end
end
M.profilerFinish = profilerFinish


-- opening the vehicle selector
local function openVehicleSelectorForFreeroam()
  M.getUiData() -- Initialize if needed
  ui_vehicleSelector_filters.clearLockedFilters()
  ui_vehicleSelector_detailsInteraction.setManagementButtonsEnabled(true)
  ui_vehicleSelector_detailsInteraction.setDetailsButtonForFreeroam(true)
  ui_vehicleSelector_detailsInteraction.setCustomDetailsButtons()
  ui_vehicleSelector_detailsInteraction.setExitCallback(nop)
  guihooks.trigger("ChangeState", "menu.vehiclesnew")
  guihooks.trigger("vehicleSelectorRefreshAll")
  extensions.hook("onVehicleSelectorOpen")
end
M.openVehicleSelectorForFreeroam = openVehicleSelectorForFreeroam

-- opening the vehicle selector
local function openVehicleSelectorForFreeroamWithMod(modId)
  local mod = getModById(modId)
  M.getUiData() -- Initialize if needed

  ui_vehicleSelector_filters.clearLockedFilters()
  ui_vehicleSelector_filters.toggleFilter("Source",{"Mod: " ..mod.modname})
  ui_vehicleSelector_detailsInteraction.setManagementButtonsEnabled(true)
  ui_vehicleSelector_detailsInteraction.setDetailsButtonForFreeroam(true)
  ui_vehicleSelector_detailsInteraction.setCustomDetailsButtons()
  ui_vehicleSelector_detailsInteraction.setExitCallback(nop)
  guihooks.trigger("ChangeState", "menu.vehiclesnew")
  guihooks.trigger("vehicleSelectorRefreshAll")
  extensions.hook("onVehicleSelectorOpen")
end
M.openVehicleSelectorForFreeroamWithMod = openVehicleSelectorForFreeroamWithMod

local function openVehicleSelectorForChallenge(callback)
  --[[
  M.getUiData() -- Initialize if needed
  ui_vehicleSelector_filters.clearLockedFilters()
  ui_vehicleSelector_filters.lockFilterModeExclusive("Type",{"Car","Truck"})
  ui_vehicleSelector_detailsInteraction.setManagementButtonsEnabled(false)
  ui_vehicleSelector_detailsInteraction.setCustomDetailsButtons({{
    callback = callback,
    meta = {
      label = "Select Vehicle",
      icon = "car"
    }
  }})
  ui_vehicleSelector_detailsInteraction.setExitCallback(function()
    print("exit callback")
    callback()
  end)
  guihooks.trigger("ChangeState", "vehicle-selector")
  guihooks.trigger("vehicleSelectorRefreshAll")
  extensions.hook("onVehicleSelectorOpen")
  ]]
end
M.openVehicleSelectorForChallenge = openVehicleSelectorForChallenge


return M