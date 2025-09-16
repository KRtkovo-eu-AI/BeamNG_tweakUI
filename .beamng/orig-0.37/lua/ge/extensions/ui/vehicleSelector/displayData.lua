local M = {}

-- Display data storage
local dataFile = "/settings/vehicleSelectorData.json"
local favourites = {}
local recentVehicles = {}
local maxRecentVehicles = 100
local displayData = nil

local currentVersion = 10

-- Default display data structure
local displayDataOptions = {
  {
    label = "Group by:",
    key = "groupMode",
    default = "Type",
    type = "dropdown",
    description = "Controls the large groups of vehicles in the grid.",
    save = true,
    showInModes = {default = true, filter = true, displayControls = true},
    options = {
      {label = "Type", value = "Type"},
      {label = "Brand", value = "Brand"},
      {label = "Country", value = "Country"},
      {label = "Config Type", value = "Config Type"},
      {label = "Derby Class", value = "Derby Class"},
      {label = "Body Style", value = "Body Style"},
      {label = "Years", value = "Years"},
      {label = "Value", value = "Value"},
      {label = "Source", value = "Source"},
    },
  },
  {
    label = "Sort by:",
    key = "sortMode",
    default = "Automatic",
    type = "dropdown",
    description = "Controls how vehicles are sorted within each group.",
    save = true,
    showInModes = {default = true, filter = true, displayControls = true},
    options = {
      {label = "Automatic", value = "Automatic"},
      {label = "Name", value = "Name"},
      --{label = "Year", value = "Years"},
      {label = "Value", value = "Value"},
      {label = "Weight", value = "Weight"},
      {label = "Top Speed", value = "Top Speed"},
      {label = "Power", value = "Power"},
      {label = "Weight/Power", value = "Weight/Power"},
      {label = "0-60 mph", value = "0-60 mph"},
      {label = "0-100 km/h", value = "0-100 km/h"},
    },
  },
  {
    label = "Cluster by:",
    key = "clusterMode",
    default = "model",
    type = "dropdown",
    description = "Controls how individual configs are clustered into tiles.",
    save = false,
    showInModes = {displayControls = false},
    options = {
      {label = "Brand/Model", value = "brandSubModelOrModel"},
      {label = "Legacy (Model)", value = "model"},
    },
  },
  {
    label = "Expand configs:",
    key = "expandGroups",
    default = 0,
    type = "dropdown",
    description = "If a tile would represent less configs than this, it will be expanded to show the configs directly.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Never", value = 0},
      {label = "Single config", value = 1},
      {label = "Groups of 2", value = 2},
      {label = "Groups of 3", value = 3},
      {label = "Groups of 4", value = 4},
      {label = "Groups of 5", value = 5},
      {label = "Always", value = 999},
    },
  },
  {
    label = "Display size:",
    key = "displaySize",
    default = "medium",
    type = "dropdown",
    description = "Controls the size of the tiles in the grid.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "List", value = "list"},
      {label = "Tiny", value = "tiny"},
      {label = "Small", value = "small"},
      {label = "Medium", value = "medium"},
      {label = "Large", value = "large"},
      {label = "Huge", value = "huge"},
    },
  },

  {
    label = "Filter Reset on Spawn:",
    key = "filterResetOnSpawn",
    default = false,
    type = "checkbox",
    description = "Controls when filters are reset when a vehicle is spawned, replaced or selected.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Reset", value = true},
      {label = "Keep", value = false},
    },
  },
  {
    label = "Recent Selections:",
    key = "showRecentMode",
    default = "completeClusters",
    type = "dropdown",
    description = "Controls how recent selections are displayed",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Hidden", value = "hidden"},
      {label = "Reduced Clusters", value = "reducedClusters"},
      {label = "Complete Clusters", value = "completeClusters"},
    },
  },
  {
    label = "Recent Amount:",
    key = "recentAmount",
    default = 7,
    min = 1,
    max = 25,
    type = "number",
    description = "Controls how many recent selections are shown in the grid.",
    save = true,
    showInModes = {displayControls = true},
  },
  {
    label = "Favourites:",
    key = "showFavouritesMode",
    default = "reducedClusters",
    type = "dropdown",
    description = "Controls how favourites are shown in the grid. To favourite a vehicle, click the star icon in the details panel.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Hidden", value = "hidden"},
      {label = "Reduced Clusters", value = "reducedClusters"},
      {label = "Complete Clusters", value = "completeClusters"},
    },
  },
  {
    label = "Include Standalone PC Files:",
    key = "showCustomPCFiles",
    --settingsKey = "showStandalonePcs",
    default = true,
    type = "checkbox",
    description = "Controls whether custom PC files are shown in the grid.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Included", value = true},
      {label = "Excluded", value = false},
    },
  },
  {
    label = "Include Aux Content:",
    key = "showAuxContent",
    default = true,
    hidden = false,
    type = "checkbox",
    description = "Controls whether auxiliary debug content is shown in the grid. This is useful for developers.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Included", value = true},
      {label = "Excluded", value = false},
    },
  },
  {
    label = "Include Dev Info:",
    key = "includeDevInfo",
    default = false,
    type = "checkbox",
    description = "Controls whether developer information is shown in the vehicle details panel.",
    save = true,
    showInModes = {displayControls = true},
    options = {
      {label = "Show", value = true},
      {label = "Hide", value = false},
    },
  },
}
local displayOptionKeyToType = {}
for _, option in ipairs(displayDataOptions) do
  displayOptionKeyToType[option.key] = option.type
end

local displayOptionSettingsKeyByKey = {}
for _, option in ipairs(displayDataOptions) do
  if option.settingsKey then
    displayOptionSettingsKeyByKey[option.key] = option.settingsKey
  end
end

M.getDisplayDataOptions = function()
  local displayData = M.getDisplayData()
  local data = {}
  for _, option in ipairs(displayDataOptions) do
    local value = nil
    if option.key == 'searchText' then
      value = ui_vehicleSelector_filters.getSearchText()
    else
      value = displayData[option.key]
    end
    if option.settingsKey then
      value = settings.getValue(option.settingsKey)
    end
    table.insert(data, {
      label = option.label,
      key = option.key,
      type = option.type,
      min = option.min,
      max = option.max,
      value = value,
      options = option.options,
      showInModes = option.showInModes,
      description = option.description,
    })
  end
  return data
end


-- Save all data to file
local function saveAllData(displayData)
  local data = {
    favourites = favourites,
    recentVehicles = recentVehicles,
    version = currentVersion,
    displayData = displayData
  }
  for _, option in ipairs(displayDataOptions) do
    if option.save then
      data.displayData[option.key] = displayData[option.key]
    end
  end
  jsonWriteFile(dataFile, data, true, nil, true)
end

local function updateDisplayData(data, version)
  while version < currentVersion do
    version = version + 1
    if version == 2 then
      data.expandGroups = 0
      data.clusterMode = "brandSubModelOrModel"
    elseif version == 3 then
      data.showFavouritesMode = "completeClusters"
      data.showRecentMode = "completeClusters"
    elseif version == 8 then
      data.clusterMode = "model"
    elseif version == 9 then
      data.filterResetOnSpawn = false
    end
  end
  log("I", "", "Display data updated to version " .. tostring(version))
  return data
end

-- Load all data from file
local function loadAllData()
  local data = jsonReadFile(dataFile) or {}
  data.displayData = data.displayData or {}
  data.version = data.version or 0



  if data then
    if data.version == nil or data.version < currentVersion then
      data.version = 0
      data.displayData = updateDisplayData(data.displayData, data.version)
    end
    favourites = data.favourites or {}
    recentVehicles = data.recentVehicles or {}
    return data.displayData or {}
  end
  return {}
end

-- Initialize display data
local function initializeDisplayData()
  local savedDisplayData = loadAllData()
  local displayData = {}


  -- Copy default values
  for _, option in ipairs(displayDataOptions) do
    displayData[option.key] = option.default
    if savedDisplayData[option.key] ~= nil then
      displayData[option.key] = savedDisplayData[option.key]
    end
    if option.type == "number" then
      displayData[option.key] = tonumber(displayData[option.key])
    end
    if option.settingsKey then
      displayData[option.key] = settings.getValue(option.settingsKey)
    end
    -- default for aux data depends on shipping status
    if option.key == "showAuxContent" then
      displayData[option.key] = not shipping_build
    end
  end

  return displayData
end

-- Get display data
local function getDisplayData()
  if not displayData then
    displayData = initializeDisplayData()
  end
  return displayData
end

-- Set display data
local function setDisplayDataOption(key, value)
  local displayData = getDisplayData()
  local hasChanges = false
  local type = displayOptionKeyToType[key]
  if type == "number" then
    value = tonumber(value)
  end
  if key and value ~= nil and value ~= "undefined" then
    displayData[key] = value
    hasChanges = true
    extensions.hook("onVehicleSelectorDisplayDataChanged", key, value)
  end

  local optionKey = displayOptionSettingsKeyByKey[key]
  if optionKey then
    settings.setValue(optionKey, value)
    dump(settings.getValue(optionKey))
  end

  if hasChanges then
    saveAllData(displayData)
  end

  return displayData
end

-- Reset all display data to default values
local function resetDisplayDataToDefaults()
  local displayData = getDisplayData()
  local hasChanges = false

  -- Reset all options to their default values
  for _, option in ipairs(displayDataOptions) do
    if option.save then
      local defaultValue = option.default
      if option.type == "number" then
        defaultValue = tonumber(defaultValue)
      end
      if displayData[option.key] ~= defaultValue then
        displayData[option.key] = defaultValue
        hasChanges = true
        extensions.hook("onVehicleSelectorDisplayDataChanged", option.key, defaultValue)
      end
    end
  end

  if hasChanges then
    saveAllData(displayData)
  end

  return displayData
end

local function clearAllFavourites()
  favourites = {}
  local displayData = getDisplayData()
  saveAllData(displayData)
end

local function clearAllRecentVehicles()
  recentVehicles = {}
  local displayData = getDisplayData()
  saveAllData(displayData)
end


-- Favourite management
local function toggleFavourite(model, config)
  if favourites[model.."/"..config] then
    favourites[model.."/"..config] = nil
  else
    favourites[model.."/"..config] = os.time()
  end
  extensions.hook("onVehicleSelectorFavouriteToggled", model, config, favourites[model.."/"..config] ~= nil)
  local displayData = getDisplayData()
  saveAllData(displayData)
end

local function isFavourite(model, config)
  return favourites[model.."/"..config]
end

-- Recent vehicles management
local function isRecentVehicle(model, config)
  return arrayFindValueIndex(recentVehicles, model.."/"..config) or false
end

local function trackRecentVehicle(model, config)
  local idx = arrayFindValueIndex(recentVehicles, model.."/"..config)
  if idx then
    table.remove(recentVehicles, idx)
  end
  table.insert(recentVehicles, 1, model.."/"..config)
  while #recentVehicles > maxRecentVehicles do
    table.remove(recentVehicles, #recentVehicles)
  end
  local displayData = getDisplayData()
  saveAllData(displayData)
end

-- Export functions
M.getDisplayData = getDisplayData
M.setDisplayData = setDisplayData
M.setDisplayDataOption = setDisplayDataOption
M.resetDisplayDataToDefaults = resetDisplayDataToDefaults
M.toggleFavourite = toggleFavourite
M.isFavourite = isFavourite
M.isRecentVehicle = isRecentVehicle
M.trackRecentVehicle = trackRecentVehicle
M.initializeDisplayData = initializeDisplayData
M.clearAllFavourites = clearAllFavourites
M.clearAllRecentVehicles = clearAllRecentVehicles

return M