local M = {}

-- Filter-related data
local filtersWhiteList = {
  "Drivetrain",
  "Config Type",
  "Body Style",
  "Transmission",


  "Weight",
  "Top Speed",
  "0-100 km/h",
  "0-60 mph",
  "Power",
  "Torque",
  "Weight/Power",


  "Years",
  "Value",
  "Brand",
  "Country",
  "Source",


  "Type",
  "Derby Class",
  "Performance Class",
  "Off-Road Score",
  'Propulsion',
  'Fuel Type',
  'Induction Type',
  'Commercial Class'
}
local rangeFilters = tableValuesAsLookupDict({
  "Value",
  "Weight",
  "Top Speed",
  "0-100 km/h",
  "0-60 mph",
  "Power",
  "Torque",
  "Weight/Power",
  "Off-Road Score",
  "Years",
})

local validFilters = {}

-- Store search text here
local searchText = ""

local function getSearchText()
  return searchText
end

local function setSearchText(val)
  searchText = val or ""
end

-- Check if a filter option is locked
local function isFilterLocked(propName, option)
  local uiData = ui_vehicleSelector.getUiData()
  if not uiData.lockedFiltersByProp[propName] then
    return false
  end

  if option then
    -- Check if specific option is locked
    return uiData.lockedFiltersByProp[propName][option] ~= nil
  else
    -- Check if any option for this property is locked
    for _, _ in pairs(uiData.lockedFiltersByProp[propName]) do
      return true
    end
    return false
  end
end

local commonFilters = {
  {"Type", "Car"},
  {"Type", "Truck"},
  {"Type", "Trailer"},
  {"Type", "Prop"},
  {"Drivetrain", "4WD"},
  {"Drivetrain", "RWD"},
  {"Drivetrain", "FWD"},
  {"Drivetrain", "AWD"},
  {"Config Type", "Factory"},
  {"Config Type", "Drift"},
  {"Config Type", "Rally"},
  {"Config Type", "Race"},
  {"Config Type", "Police"},
  {"Config Type", "Service"},
  {"Transmission", "Manual"},
  {"Transmission", "Automatic"},
  {"Transmission", "Sequential"},
}

-- Create a lookup table for common filters for efficient checking
local commonFiltersLookup = {}
for _, commonFilter in ipairs(commonFilters) do
  local propName, option = commonFilter[1], commonFilter[2]
  if not commonFiltersLookup[propName] then
    commonFiltersLookup[propName] = {}
  end
  commonFiltersLookup[propName][option] = true
end


local function calculateActiveFilters()
  local uiData = ui_vehicleSelector.getUiData()
  local activeFilters = {}
  local hasNonCommonFilters = false
  --[[
  if searchText and searchText ~= "" then
    table.insert(activeFilters, {
      propName = "searchText",
      propValue = searchText,
      displayText = "Search: " .. searchText,
      isActive = true,
      iconType = 'search',
      isSearch = true
    })
  end]]


  -- Go through filterList to maintain proper ordering
  for _, filterItem in ipairs(uiData.filterList) do
    local propName = filterItem.propName
    local filterOptions = uiData.filterByProp[propName]

    -- Skip if this property doesn't exist in filterByProp
    if not filterOptions then
      goto continue
    end

    -- Handle different filter types
    if filterItem.type == 'range' then
      -- Range filter: compare min/max values to defaults
      local currentMin = filterOptions.min
      local currentMax = filterOptions.max
      local defaultMin = filterItem.min
      local defaultMax = filterItem.max

      -- Check if current values differ from defaults
      if currentMin > defaultMin or currentMax < defaultMax then
        local displayText, propValue, isActive, iconType

        if currentMin > defaultMin and currentMax < defaultMax then
          displayText = string.format("%s: %s - %s", propName, currentMin, currentMax)
          propValue = string.format("%s,%s", currentMin, currentMax)
        elseif currentMin > defaultMin then
          displayText = string.format("%s: > %s", propName, currentMin)
          propValue = string.format("> %s", currentMin)
        else
          displayText = string.format("%s: < %s", propName, currentMax)
          propValue = string.format("< %s", currentMax)
        end

        table.insert(activeFilters, {
          propName = propName,
          propValue = propValue,
          displayText = displayText,
          isActive = true,
          iconType = 'checkmark'
        })

        -- Range filters are not common filters
        hasNonCommonFilters = true
      end
    else
      -- Set filter: use existing logic for option-based filters
      if type(filterOptions) ~= 'table' or filterOptions == nil then
        goto continue
      end

      -- Get all options for this property, maintaining order from filterList
      local allOptions = {}
      if filterItem.options then
        -- Use the order from filterList if available
        for _, option in ipairs(filterItem.options) do
          local optionName = option.name or option
          if filterOptions[optionName] ~= nil then
            table.insert(allOptions, optionName)
          end
        end
      else
        -- Fallback to iterating through keys if no options structure in filterList
        for key, _ in pairs(filterOptions) do
          if key ~= 'min' and key ~= 'max' then
            table.insert(allOptions, key)
          end
        end
      end

      local enabledOptions = {}
      local disabledOptions = {}

      for _, option in ipairs(allOptions) do
        if filterOptions[option] == true then
          table.insert(enabledOptions, option)
        elseif filterOptions[option] == false then
          table.insert(disabledOptions, option)
        end
      end

      -- Skip if all options are enabled (no filtering)
      if #enabledOptions == #allOptions then
        goto continue
      end

      -- Handle case where no options are enabled (all disabled)
      if #enabledOptions == 0 then
        table.insert(activeFilters, {
          propName = propName,
          propValue = 'all',
          displayText = string.format("%s: None!", propName),
          isActive = false,
          iconType = 'xmark'
        })
        goto continue
      end

      -- Create only one entry per property
      if #enabledOptions > 0 or #disabledOptions > 0 then
        local displayText, propValue, isActive, iconType

        -- If more elements are enabled than disabled, show the disabled names in red
        if #enabledOptions > #disabledOptions then
          displayText = string.format("%s: %s", propName, table.concat(disabledOptions, ', '))
          propValue = table.concat(disabledOptions, ',')
          isActive = false
          iconType = 'abandon'
        else
          -- If more elements are disabled than enabled, show the enabled names in green
          displayText = string.format("%s: %s", propName, table.concat(enabledOptions, ', '))
          propValue = table.concat(enabledOptions, ',')
          isActive = true
          iconType = 'checkmark'
        end

        table.insert(activeFilters, {
          propName = propName,
          propValue = propValue,
          displayText = displayText,
          isActive = isActive,
          iconType = iconType
        })

        -- Check if this filter contains any non-common options
        local hasNonCommonOption = false
        for _, option in ipairs(enabledOptions) do
          if not commonFiltersLookup[propName] or not commonFiltersLookup[propName][option] then
            hasNonCommonOption = true
            break
          end
        end
        for _, option in ipairs(disabledOptions) do
          if not commonFiltersLookup[propName] or not commonFiltersLookup[propName][option] then
           -- hasNonCommonOption = true
            break
          end
        end

        if hasNonCommonOption then
          hasNonCommonFilters = true
        end
      end
    end

    ::continue::
  end

  return activeFilters, hasNonCommonFilters
end



-- Get available filters
local function getFilters()
  local uiData = ui_vehicleSelector.getUiData()
  local activeFilters, hasNonCommonFilters = calculateActiveFilters()
  return {
    filterList = uiData.filterList,
    filterByProp = uiData.filterByProp,
    commonFilters = commonFilters,
    lockedFiltersByProp = uiData.lockedFiltersByProp,
    activeFilters = activeFilters,
    onlyCommonFilters = not hasNonCommonFilters
  }
end

-- Update active filters
local function updateFilters(newFilters)
  local uiData = ui_vehicleSelector.getUiData()
  -- Preserve locked filters when updating
  for propName, lockedOptions in pairs(uiData.lockedFiltersByProp) do
    if newFilters[propName] then
      if type(lockedOptions) == 'table' then
        -- For set filters, preserve locked options
        for option, lockedValue in pairs(lockedOptions) do
          if newFilters[propName][option] ~= nil then
            newFilters[propName][option] = lockedValue
          end
        end
      else
        -- For range filters, preserve locked min/max values
        if lockedOptions.min ~= nil then
          newFilters[propName].min = lockedOptions.min
        end
        if lockedOptions.max ~= nil then
          newFilters[propName].max = lockedOptions.max
        end
      end
    end
  end

  uiData.activeFilters = newFilters
end

local function toggleFilter(propName, option)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Toggling filter: %s, option: %s", propName, option))

  -- Check if the filter is locked
  if isFilterLocked(propName, option) then
    log("W","",string.format("Cannot toggle locked filter: %s, option: %s", propName, option))
    return
  end

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter or not filter.options then
    return
  end

  -- Check if all items are currently enabled
  local allEnabled = true
  for _, opt in ipairs(filter.options) do
    if uiData.filterByProp[propName][opt] ~= true then
      allEnabled = false
      break
    end
  end

  if allEnabled then
    -- If all items were enabled, enable only the clicked item and disable all others
    for _, opt in ipairs(filter.options) do
            -- Only modify if not locked
      if not isFilterLocked(propName, opt) then
        uiData.filterByProp[propName][opt] = (opt == option)
      end
    end
  else
    -- If at least one item was disabled, simply flip the clicked item
    local currentValue = uiData.filterByProp[propName][option]
    uiData.filterByProp[propName][option] = not currentValue
  end
  -- Check if all items are now false after the toggle
  local allFalse = true
  for _, opt in ipairs(filter.options) do
    if uiData.filterByProp[propName][opt] ~= false then
      allFalse = false
      break
    end
  end

  -- If all items are false, set all to true instead
  if allFalse then
    for _, opt in ipairs(filter.options) do
      -- Only modify if not locked
      if not isFilterLocked(propName, opt) then
        uiData.filterByProp[propName][opt] = true
      end
    end
  end
end

local function updateRangeFilter(propName, min, max)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Updating range filter: %s, min: %s, max: %s", propName, min, max))

  -- Check if the filter is locked
  if isFilterLocked(propName) then
    log("W","",string.format("Cannot update locked range filter: %s", propName))
    return
  end

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter or filter.type ~= 'range' then
    return
  end

  -- Ensure values are within the allowed range
  min = math.max(filter.min, math.min(filter.max, min))
  max = math.max(filter.min, math.min(filter.max, max))

  -- Ensure min <= max
  if min > max then
    min, max = max, min
  end

  -- Update the filter values
  if not uiData.filterByProp[propName] then
    uiData.filterByProp[propName] = {}
  end
  uiData.filterByProp[propName].min = min
  uiData.filterByProp[propName].max = max
end

local function resetRangeFilter(propName)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Resetting range filter: %s", propName))

  -- Check if the filter is locked
  if isFilterLocked(propName) then
    log("W","",string.format("Cannot reset locked range filter: %s", propName))
    return
  end

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter or filter.type ~= 'range' then
    return
  end

  -- Reset to original min/max values
  if not uiData.filterByProp[propName] then
    uiData.filterByProp[propName] = {}
  end
  uiData.filterByProp[propName].min = filter.min
  uiData.filterByProp[propName].max = filter.max
end

local function resetSetFilter(propName)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Resetting set filter: %s", propName))

  -- Check if the filter is locked
  if isFilterLocked(propName) then
    log("W","",string.format("Cannot reset locked set filter: %s", propName))
    return
  end

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter or filter.type ~= 'set' then
    return
  end

  -- Reset all options to true (enabled)
  if not uiData.filterByProp[propName] then
    uiData.filterByProp[propName] = {}
  end

  for _, option in ipairs(filter.options) do
    -- Only reset if not locked
    if not isFilterLocked(propName, option) then
      uiData.filterByProp[propName][option] = true
    end
  end
end

local function clearAllFilters()
  local uiData = ui_vehicleSelector.getUiData()
  for _, filter in ipairs(uiData.filterList) do
    if filter.type == 'range' then
      M.resetRangeFilter(filter.propName)
    end
    if filter.type == 'set' then
      M.resetSetFilter(filter.propName)
    end
  end
  setSearchText("")
end


-- Lock a filter to prevent modification
local function lockFilter(propName, options)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Locking filter: %s", propName))

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter then
    return
  end

  -- Initialize locked filters for this property if it doesn't exist
  if not uiData.lockedFiltersByProp[propName] then
    uiData.lockedFiltersByProp[propName] = {}
  end

  if filter.type == 'range' then
    -- For range filters, lock the current min/max values
    if not uiData.filterByProp[propName] then
      uiData.filterByProp[propName] = {}
    end
    uiData.lockedFiltersByProp[propName].min = uiData.filterByProp[propName].min or filter.min
    uiData.lockedFiltersByProp[propName].max = uiData.filterByProp[propName].max or filter.max
  else
    -- For set filters, lock specific options or all options
    if options then
      -- Lock specific options
      for _, option in ipairs(options) do
        if uiData.filterByProp[propName] and uiData.filterByProp[propName][option] ~= nil then
          uiData.lockedFiltersByProp[propName][option] = uiData.filterByProp[propName][option]
        end
      end
    else
      -- Lock all current options
      if uiData.filterByProp[propName] then
        for option, value in pairs(uiData.filterByProp[propName]) do
          uiData.lockedFiltersByProp[propName][option] = value
        end
      end
    end
  end
end

-- Unlock a filter to allow modification
local function unlockFilter(propName, options)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Unlocking filter: %s", propName))

  if not uiData.lockedFiltersByProp[propName] then
    return uiData.lockedFiltersByProp
  end

  if options then
    -- Unlock specific options
    for _, option in ipairs(options) do
      uiData.lockedFiltersByProp[propName][option] = nil
    end
    -- Remove the property entirely if no options are locked
    local hasLockedOptions = false
    for _, _ in pairs(uiData.lockedFiltersByProp[propName]) do
      hasLockedOptions = true
      break
    end
    if not hasLockedOptions then
      uiData.lockedFiltersByProp[propName] = nil
    end
  else
    -- Unlock all options for this property
    uiData.lockedFiltersByProp[propName] = nil
  end
end

-- Lock a filter into a specific mode (set specific options to true/false)
local function lockFilterMode(propName, options)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Locking filter mode: %s", propName))

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter then
    return
  end

  -- Initialize locked filters for this property if it doesn't exist
  if not uiData.lockedFiltersByProp[propName] then
    uiData.lockedFiltersByProp[propName] = {}
  end

  if filter.type == 'range' then
    -- For range filters, lock the specified min/max values
    if not uiData.filterByProp[propName] then
      uiData.filterByProp[propName] = {}
    end

    if options.min ~= nil then
      uiData.filterByProp[propName].min = options.min
      uiData.lockedFiltersByProp[propName].min = options.min
    end
    if options.max ~= nil then
      uiData.filterByProp[propName].max = options.max
      uiData.lockedFiltersByProp[propName].max = options.max
    end
  else
    -- For set filters, set specific options to true/false and lock them
    if not uiData.filterByProp[propName] then
      uiData.filterByProp[propName] = {}
    end

    -- First, set all options to false (disabled)
    for _, option in ipairs(filter.options) do
      uiData.filterByProp[propName][option] = false
      uiData.lockedFiltersByProp[propName][option] = false
    end

    -- Then, set the specified options to true (enabled)
    if options then
      for option, enabled in pairs(options) do
        if uiData.filterByProp[propName][option] ~= nil then
          uiData.filterByProp[propName][option] = enabled
          uiData.lockedFiltersByProp[propName][option] = enabled
        end
      end
    end
  end
end

-- Lock a filter into exclusive mode (set all options to false except specified ones)
local function lockFilterModeExclusive(propName, allowedOptions)
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Locking filter mode exclusive: %s", propName))

  local filter = nil
  for _, f in ipairs(uiData.filterList) do
    if f.propName == propName then
      filter = f
      break
    end
  end

  if not filter then
    return
  end

  -- Only works with set filters
  if filter.type ~= 'set' then
    log("W","",string.format("lockFilterModeExclusive only works with set filters, got: %s", filter.type))
    return
  end

  -- Initialize locked filters for this property if it doesn't exist
  if not uiData.lockedFiltersByProp[propName] then
    uiData.lockedFiltersByProp[propName] = {}
  end

  if not uiData.filterByProp[propName] then
    uiData.filterByProp[propName] = {}
  end

  -- Set all options to false (disabled) and lock them
  for _, option in ipairs(filter.options) do
    uiData.filterByProp[propName][option] = false
    uiData.lockedFiltersByProp[propName][option] = false
  end

  -- Then, set only the allowed options to true (enabled) but DON'T lock them
  if allowedOptions then
    for _, option in ipairs(allowedOptions) do
      if uiData.filterByProp[propName][option] ~= nil then
        uiData.filterByProp[propName][option] = true
        -- Don't lock the allowed options - remove them from locked filters
        uiData.lockedFiltersByProp[propName][option] = nil
      end
    end
  end

  return
end

-- Clear all locked filters
local function clearLockedFilters()
  local uiData = ui_vehicleSelector.getUiData()
  log("D","",string.format("Clearing all locked filters"))

  uiData.lockedFiltersByProp = {}
end

local function setupValidFilters()
  local uiData = ui_vehicleSelector.getUiData()
  table.clear(validFilters)
  for _, filterData in ipairs(uiData.filterList) do
    local propFilter = uiData.filterByProp[filterData.propName]
    if filterData.type == 'range' then
      if propFilter.min > filterData.min or propFilter.max < filterData.max then
        table.insert(validFilters, filterData)
      end
    else
      for _, option in ipairs(filterData.options) do
        if propFilter[option] == false then
          table.insert(validFilters, filterData)
        end
      end
    end
  end
end

local function createFilters(configList)
  local filterByProp = {}

  if configList then
    for _, config in pairs(configList) do
      for _, propName in pairs(filtersWhiteList) do
        local propVal = config[propName]
        if propVal ~= nil then
          if rangeFilters[propName] then
            local min, max = propVal, propVal
            if type(propVal) == 'table' then
              min = propVal.min
              max = propVal.max
            end
            if type(min) == 'number' and type(max) == 'number' then
              if not filterByProp[propName] then
                filterByProp[propName] = {
                  min = min,
                  max = max,
                }
              end
              filterByProp[propName].min = math.min(min, filterByProp[propName].min)
              filterByProp[propName].max = math.max(max, filterByProp[propName].max)
            end
          else
            if not filterByProp[propName] then
              filterByProp[propName] = {}
            end
            -- exclude powerglow for filters
            if propVal ~= 'Powerglow' then
              filterByProp[propName][propVal] = true
            end

          end
        end
      end
    end
  end

  local filterUiData = {}
  for _, propName in pairs(filtersWhiteList) do
    if filterByProp[propName] then
      local filterData = {
        propName = propName,
        options = {}
      }
      if filterByProp[propName].min and filterByProp[propName].max then
        filterData.type = 'range'
        filterData.min = filterByProp[propName].min
        filterData.max = filterByProp[propName].max
      else
        filterData.type = 'set'
        for _, key in ipairs(tableKeysSorted(filterByProp[propName])) do
          table.insert(filterData.options, key)
        end
        table.insert(filterData.options, 'Other...')
        filterByProp[propName]['Other...'] = true
      end
      table.insert(filterUiData, filterData)
    end
  end

  return filterUiData, filterByProp
end

local function passesFilters(itemData)
  local uiData = ui_vehicleSelector.getUiData()
  local model = core_vehicles.getModel(itemData.model).model
  local config = core_vehicles.getConfig(itemData.model, itemData.config)
  local configOrModel = config or model -- this is the case if no config exist (standalone pc)
  if not config then
    log("W","",string.format("No config found for model: %s, config: %s", itemData.model, itemData.config))
  end
  if not uiData.displayData.showCustomPCFiles and (not config.infoFilename) then
    return false
  end
  if not uiData.displayData.showAuxContent and (configOrModel.isAuxiliary or model.missingJbeamFiles) then
    return false
  end

  -- explicitly exclude powerglow configs
  if configOrModel['Config Type'] == 'Powerglow' then
    return false
  end

  if searchText and searchText ~= "" then
    local searchTextLower = string.lower(searchText)
    local configNameLower = string.lower(configOrModel.Name or "")
    local modelNameLower = string.lower(model.Name or "")
    local fileNameLower = string.lower(configOrModel.infoFilename or "")
    local match = false
    for _, propKey in ipairs(filtersWhiteList) do
      local propVal = configOrModel[propKey]
      if propVal == nil then
        propVal = model[propKey]
      end
      if type(propVal) == 'string' then
        if string.find(string.lower(propVal), searchTextLower, 1, true) then
          match = true
          break
        end
      end
      if match then
        break
      end
    end
    match = match or string.find(configNameLower, searchTextLower, 1, true) or string.find(modelNameLower, searchTextLower, 1, true) or string.find(fileNameLower, searchTextLower, 1, true)
    if not match then
      return false
    end
  end

  for _, filter in ipairs(validFilters) do
    local propFilter = uiData.filterByProp[filter.propName]
    local propVal = configOrModel[filter.propName]
    if propVal == nil then
      propVal = model[filter.propName]
    end
    if propVal == nil then
      propVal = "Other..."
    end
    if filter.type == 'set' then
      for _, option in pairs(filter.options) do
        if propVal == option and not propFilter[option] then
          return false
        end
      end
    end
    if filter.type == 'range' then
      if propVal == "Other..." or not type(propVal) == 'number' then
        return false
      end
      if type(propVal) == 'table' then
        if (propVal.min and propVal.min < propFilter.min) or (propVal.max and propVal.max > propFilter.max) then
          return false
        end
        if (propFilter.min > filter.min and not propVal.min) or (propFilter.max < filter.max and not propVal.max) then
          return false
        end
      else
        if (propVal < propFilter.min) or (propVal > propFilter.max) then
          return false
        end
      end
    end
  end
  return true
end

-- Export functions
M.getFilters = getFilters
M.updateFilters = updateFilters
M.toggleFilter = toggleFilter
M.updateRangeFilter = updateRangeFilter
M.resetRangeFilter = resetRangeFilter
M.resetSetFilter = resetSetFilter
M.clearAllFilters = clearAllFilters
M.lockFilter = lockFilter
M.unlockFilter = unlockFilter
M.isFilterLocked = isFilterLocked
M.lockFilterMode = lockFilterMode
M.lockFilterModeExclusive = lockFilterModeExclusive
M.clearLockedFilters = clearLockedFilters
M.calculateActiveFilters = calculateActiveFilters
M.setupValidFilters = setupValidFilters
M.createFilters = createFilters
M.passesFilters = passesFilters
M.getSearchText = getSearchText
M.setSearchText = setSearchText

return M