local M = {}
local function emptyProfiler()
  return {
    start = function() end,
    add = function() end,
    finish = function() end,
  }
end
M.emptyProfiler = emptyProfiler
local p = emptyProfiler()
--p = LuaProfiler("vehicleSelector Tiles Profiler")

-- Sorting functions
local function sortByNameButOtherAlwaysLast(a, b)
  local aName = a.Name or a.name or a.label or ""
  local bName = b.Name or b.name or b.label or ""

  if aName == "Other..." then
    return false
  elseif bName == "Other..." then
    return true
  end
  return aName < bName
end

local function sortByValue(a, b)
  local aValue = a.Value or a.value or 0
  local bValue = b.Value or b.value or 0
  if type(aValue) == 'table' then
    aValue = aValue.min
  end
  if type(bValue) == 'table' then
    bValue = bValue.min
  end
  if aValue == bValue then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return aValue < bValue
end

local function sortByYears(a, b)
  local aYears = a.Years or a.years or math.huge
  local bYears = b.Years or b.years or math.huge
  if type(aYears) == 'table' then
    aYears = aYears.min
  end
  if type(bYears) == 'table' then
    bYears = bYears.min
  end
  if aYears == bYears then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return aYears < bYears
end

local function sortByWeight(a, b)
  local aWeight = a.Weight or a.weight or 0
  local bWeight = b.Weight or b.weight or 0
  if aWeight == bWeight then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return aWeight < bWeight
end

local function sortByTopSpeed(a, b)
  local aTopSpeed = a['Top Speed'] or a.topSpeed or 0
  local bTopSpeed = b['Top Speed'] or b.topSpeed or 0
  if aTopSpeed == bTopSpeed then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return aTopSpeed < bTopSpeed
end

local function sortByPower(a, b)
  local aPower = a.Power or a.power or 0
  local bPower = b.Power or b.power or 0
  if aPower == bPower then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return aPower < bPower
end

local function sortByWeightPower(a, b)
  local aWeight = a.Weight or a.weight or 0
  local aPower = a.Power or a.power or 0
  local bWeight = b.Weight or b.weight or 0
  local bPower = b.Power or b.power or 0
  local aWeightPower = aWeight > 0 and aPower > 0 and aWeight / aPower or math.huge
  local bWeightPower = bWeight > 0 and bPower > 0 and bWeight / bPower or math.huge
  if aWeightPower == bWeightPower then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return aWeightPower > bWeightPower
end

local function sortBy0To60(a, b)
  local a0To60 = a['0-60 mph'] or a.zeroTo60 or math.huge
  local b0To60 = b['0-60 mph'] or b.zeroTo60 or math.huge
  if a0To60 == b0To60 then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return a0To60 > b0To60
end

local function sortBy0To100(a, b)
  local a0To100 = a['0-100 km/h'] or a.zeroTo100 or math.huge
  local b0To100 = b['0-100 km/h'] or b.zeroTo100 or math.huge
  if a0To100 == b0To100 then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  return a0To100 > b0To100
end


-- Clustering functions
local clusterModeFunctions = {
  ['brandSubModelOrModel'] = function(config)
    local model = core_vehicles.getModel(config.model_key)
    local brand = config.Brand or model.model.Brand
    local subModel = config.SubModel
    if subModel == nil then
      if model and model.model then
        subModel = model.model.SubModel
      end
    end
    subModel = subModel or config.model_key
    brand = brand or ""
    return brand .. " " .. subModel
  end,
  ['model'] = function(config)
    return config.model_key
  end,
}

local configTypeOrder = {
  ['Factory'] = 1,
  ['Service'] = 2,
  ['Race'] = 3,
  ['Drift'] = 4,
  ['Rally'] = 5,
  ['Police'] = 6,
  ['Custom'] = 7,
  ['Powerglow'] = 8,
  ['Other...'] = 9,
}

local function sortByConfigTypeName(a, b)
  local aConfigTypeName = a['Config Type'] or "Other..."
  local bConfigTypeName = b['Config Type'] or "Other..."
  if aConfigTypeName == bConfigTypeName then
    return sortByNameButOtherAlwaysLast(a, b)
  end
  local aConfigTypeOrder = configTypeOrder[aConfigTypeName]
  local bConfigTypeOrder = configTypeOrder[bConfigTypeName]
  if aConfigTypeOrder == nil then
    return false
  end
  if bConfigTypeOrder == nil then
    return true
  end
  return aConfigTypeOrder < bConfigTypeOrder
end



local function getClusteredItemsFavouriteIconPercent(clusteredItems)
  local highestFavouriteConfig, lowestRecentConfig = nil, nil
  local favouriteCount = 0
  local highestFavouriteIdx = 0
  local lowestRecentIdx = math.huge
  for _configKey, config in pairs(clusteredItems.configsByKey) do
    local favouriteIdx = ui_vehicleSelector_displayData.isFavourite(config.model_key, config.key) or 0
    local recentIdx = ui_vehicleSelector_displayData.isRecentVehicle(config.model_key, config.key) or math.huge
    if favouriteIdx > highestFavouriteIdx then
      highestFavouriteIdx = favouriteIdx
      highestFavouriteConfig = config
    end
    if recentIdx < lowestRecentIdx then
      lowestRecentIdx = recentIdx
      lowestRecentConfig = config
    end
    favouriteCount = favouriteCount + (ui_vehicleSelector_displayData.isFavourite(config.model_key, config.key) and 1 or 0)

  end
  return highestFavouriteIdx, lowestRecentIdx, favouriteCount > 0 and (favouriteCount / clusteredItems.count) or 0, highestFavouriteConfig, lowestRecentConfig
end
M.getClusteredItemsFavouriteIconPercent = getClusteredItemsFavouriteIconPercent

local function getClusteredItemsStats(clusteredItems)
  local _, config = next(clusteredItems.configsByKey)
  local model = core_vehicles.getModel(config.model_key)
  local preview = model.model.preview or model.model.preview or ("/vehicles/" .. model.model.key .. "/default.jpg")

  -- automatic sorting should try to pick the default configs preview, model, config
  local sortMode = ui_vehicleSelector.getUiData().displayData.sortMode

  if sortMode == "Automatic" or sortMode == "Name" then
    if not clusteredItems.configsByKey[model.model.default_pc] then
      local configsByConfigTypeName = {}
      for _, config in pairs(clusteredItems.configsByKey) do
        table.insert(configsByConfigTypeName, config)
      end
      table.sort(configsByConfigTypeName, sortByConfigTypeName)
      local config = configsByConfigTypeName[1]
      preview = config.preview or preview
      return preview, model.model.key, config.key
    end
    return preview, model.model.key, model.model.default_pc
  end

  -- otherwise, use the sort mode to sort the configs
  local preview, previewModel, previewConfig = nil, nil, nil
  if sortMode == 'Name' then
    table.sort(clusteredItems.list, sortByNameButOtherAlwaysLast)
  elseif sortMode == 'Value' then
    table.sort(clusteredItems.list, sortByValue)
  elseif sortMode == 'Years' then
    table.sort(clusteredItems.list, sortByYears)
  elseif sortMode == 'Weight' then
    table.sort(clusteredItems.list, sortByWeight)
  elseif sortMode == 'Top Speed' then
    table.sort(clusteredItems.list, sortByTopSpeed)
  elseif sortMode == 'Power' then
    table.sort(clusteredItems.list, sortByPower)
  elseif sortMode == 'Weight/Power' then
    table.sort(clusteredItems.list, sortByWeightPower)
  elseif sortMode == '0-60 mph' then
    table.sort(clusteredItems.list, sortBy0To60)
  elseif sortMode == '0-100 km/h' then
    table.sort(clusteredItems.list, sortBy0To100)
  end
  local last = clusteredItems.list[#clusteredItems.list]
  preview = last.preview or preview
  previewModel = last.model_key or previewModel
  previewConfig = last.key or previewConfig

  return preview, previewModel, previewConfig, last
end
M.getClusteredItemsStats = getClusteredItemsStats

local tileFromClusteredItems = {
  ['brandSubModelOrModel'] = function(clusteredItems, group)
    local _, config = next(clusteredItems.configsByKey)
    local model = core_vehicles.getModel(config.model_key)
    local subModel = config.SubModel or model.model.SubModel
    local brand = config.Brand or model.model.Brand
    local name = (brand and brand .. " " or "")
    if subModel then
      name = name .. subModel
    else
      name = name .. (model.model.Name or model.model.key)
    end
    local gotoPath = {"configsForBrandSubModelOrModel", model.model.key, subModel or "", brand or ""}
    local highestFavouriteIdx, lowestRecentIdx, showFavouriteIconPercent, highestFavouriteConfig, lowestRecentConfig = M.getClusteredItemsFavouriteIconPercent(clusteredItems)
    local preview, previewModel, previewConfig, last = M.getClusteredItemsStats(clusteredItems)
    local allAuxiliary = true
    for _, config in pairs(clusteredItems.configsByKey) do
      if not config.isAuxiliary then
        allAuxiliary = false
        break
      end
    end
    local sourcesByIconCount = {}
    for _, config in pairs(clusteredItems.configsByKey) do
      local sources = M.getSources(config, model.model, true)
      for _, source in ipairs(sources) do
        sourcesByIconCount[source] = (sourcesByIconCount[source] or 0) + 1
      end
    end
    local sources = tableKeys(sourcesByIconCount)
    table.sort(sources, function(a, b)
      return sourcesByIconCount[a] > sourcesByIconCount[b]
    end)
    local sourceIcons = {}
    for _, source in ipairs(sources) do
      if string.endswith(source, ".svg") then
        table.insert(sourceIcons, {svg = source})
      else
        table.insert(sourceIcons, {icon = source})
      end
    end
    return {
      key = string.format("%s_%s_%s", group.key, model.model.key .. (subModel or ""), previewConfig or ""),
      name = name,
      brand = brand,
      preview = preview,
      configCount = clusteredItems.count,
      favouriteIdx = highestFavouriteIdx,
      recentIdx = lowestRecentIdx,
      gotoPath = arrayConcat(gotoPath, group.gotoParams or {}),
      showFavouriteIconPercent = showFavouriteIconPercent,
      doubleClickDetails = {model = previewModel, config = previewConfig},
      highestFavouriteConfig = highestFavouriteConfig,
      lowestRecentConfig = lowestRecentConfig,
      doubleClickMode = "capture",
      Value = last and last.Value or 0,
      Weight = last and last.Weight or 0,
      ['Top Speed'] = last and last['Top Speed'] or 0,
      Power = last and last.Power or 0,
      ['Power/Weight'] = last and last.Power and last.Weight and last.Weight > 0 and last.Power > 0 and last.Power / last.Weight or math.huge,
      ['0-60 mph'] = last and last['0-60 mph'] or math.huge,
      ['0-100 km/h'] = last and last['0-100 km/h'] or math.huge,
      isAuxiliary = allAuxiliary,
      sourceIcons = sourceIcons,
    }
  end,
  ['model'] = function(clusteredItems, group)
    local _, config = next(clusteredItems.configsByKey)
    local model = core_vehicles.getModel(config.model_key)
    local brand = model.model.Brand
    local name = (brand and brand .. " " or "") .. (model.model.Name or model.model.key)
    local gotoPath = {"configsForBrandSubModelOrModel", model.model.key, "", ""}
    local highestFavouriteIdx, lowestRecentIdx, showFavouriteIconPercent, highestFavouriteConfig, lowestRecentConfig = M.getClusteredItemsFavouriteIconPercent(clusteredItems)
    local preview, previewModel, previewConfig, last = M.getClusteredItemsStats(clusteredItems)
    local allAuxiliary = true
    for _, config in pairs(clusteredItems.configsByKey) do
      if not config.isAuxiliary then
        allAuxiliary = false
        break
      end
    end
    local sourcesByIconCount = {}
    for _, config in pairs(clusteredItems.configsByKey) do
      local sources = M.getSources(config, model.model, true)
      for _, source in ipairs(sources) do
        sourcesByIconCount[source] = (sourcesByIconCount[source] or 0) + 1
      end
    end
    local sources = tableKeys(sourcesByIconCount)
    table.sort(sources, function(a, b)
      return sourcesByIconCount[a] > sourcesByIconCount[b]
    end)
    local sourceIcons = {}
    for _, source in ipairs(sources) do
      if string.endswith(source, ".svg") then
        table.insert(sourceIcons, {svg = source})
      else
        table.insert(sourceIcons, {icon = source})
      end
    end
    return {
      key = string.format("%s_%s_%s", group.key, model.model.key, previewConfig or ""),
      name = name,
      brand = brand,
      preview = preview,
      configCount = clusteredItems.count,
      favouriteIdx = highestFavouriteIdx,
      recentIdx = lowestRecentIdx,
      gotoPath = arrayConcat(gotoPath, group.gotoParams or {}),
      showFavouriteIconPercent = showFavouriteIconPercent,
      doubleClickDetails = {model = previewModel, config = previewConfig},
      highestFavouriteConfig = highestFavouriteConfig,
      lowestRecentConfig = lowestRecentConfig,
      doubleClickMode = "capture",
      Value = last and last.Value or 0,
      Weight = last and last.Weight or 0,
      ['Top Speed'] = last and last['Top Speed'] or 0,
      Power = last and last.Power or 0,
      ['Power/Weight'] = last and last.Power and last.Weight and last.Weight > 0 and last.Power > 0 and last.Power / last.Weight or math.huge,
      ['0-60 mph'] = last and last['0-60 mph'] or math.huge,
      ['0-100 km/h'] = last and last['0-100 km/h'] or math.huge,
      isAuxiliary = allAuxiliary,
      sourceIcons = sourceIcons,
    }
  end,
}


local function getSources(config, model, onlyIcons)
  local sources = {}
  local source = config.Source or model.Source
  if source == "BeamNG - Official" then
    if not onlyIcons then
      table.insert(sources, "BeamNG - Official")
    end
    table.insert(sources, "beamNG")
  elseif source == "Custom" then
    if not onlyIcons then
      table.insert(sources, "Custom")
    end
    table.insert(sources, "wrench")
  end
  if config.Type == "Automation" or model.Type == "Automation" then
    if not onlyIcons then
      table.insert(sources, "Automation")
    end
    table.insert(sources, "/ui/assets/Original/camshaft_automation_logo.svg")
  end
  if config.modID then
    if not onlyIcons then
      table.insert(sources, config.Source)
    end
    table.insert(sources, "puzzleModule")
  end
  if model.missingJbeamFiles then
    if not onlyIcons then
      table.insert(sources, "Missing JBeam Files")
    end
    table.insert(sources, "danger")
  end
  return sources
end
M.getSources = getSources

local function configToTile(config, fullName)
  local model = core_vehicles.getModel(config.model_key).model
  local type = config.Type or model.Type
  local sources = M.getSources(config, model, true) or {}
  local sourceIcons = {}
  for _, source in ipairs(sources) do
    if string.endswith(source, ".svg") then
      table.insert(sourceIcons, {svg = source})
    else
      table.insert(sourceIcons, {icon = source})
    end
  end
  return {
    key = config.model_key .. "/" .. config.key,
    name = fullName and (config.Name or config.key) or (config.Configuration or config.key),
    isConfig = true,
    preview = config.preview or ("/vehicles/" .. config.model_key .. "/default.jpg"),
    model_key = config.model_key,
    config_key = config.key,
    configType = config['Config Type'] or "Other...",
    showDetails = {model = config.model_key, config = config.key},
    doubleClickDetails = {model = config.model_key, config = config.key},
    doubleClickMode = "",
    configCount = 0,
    favouriteIdx = ui_vehicleSelector_displayData.isFavourite(config.model_key, config.key) or 0,
    recentIdx = ui_vehicleSelector_displayData.isRecentVehicle(config.model_key, config.key) or math.huge,
    showFavouriteIconPercent = ui_vehicleSelector_displayData.isFavourite(config.model_key, config.key) and 1 or 0,
    sourceIcons = sourceIcons,
    isAuxiliary = config.isAuxiliary,
    Value = config.Value or model.Value,
    Weight = config.Weight or model.Weight,
    ['Top Speed'] = config['Top Speed'] or model['Top Speed'],
    Power = config.Power or model.Power,
    ['Power/Weight'] = config.Power and config.Weight and config.Weight > 0 and config.Power > 0 and config.Power / config.Weight or math.huge,
    ['0-60 mph'] = config['0-60 mph'] or config.zeroTo60 or math.huge,
    ['0-100 km/h'] = config['0-100 km/h'] or config.zeroTo100 or math.huge,
  }
end

local function clusterItems(configs)
  local clusteredItems = {}
  local clusterMode = ui_vehicleSelector.getUiData().displayData.clusterMode
  for _, config in pairs(configs) do
    local group = clusterModeFunctions[clusterMode](config) or "No Data"
    if not clusteredItems[group] then
      clusteredItems[group] = {configsByKey = {}, count = 0, list = {}}
    end
    clusteredItems[group].configsByKey[config.key] = config
    clusteredItems[group].count = clusteredItems[group].count + 1
    clusteredItems[group].list[clusteredItems[group].count] = config
    local years = config.Years or config.years or math.huge
    if type(years) == "table" then
      years = years.min
    end
    clusteredItems[group].years = math.min(years, clusteredItems[group].years or math.huge)
    local value = config.Value or config.value or 0
    if type(value) == "table" then
      value = value.min
    end
    clusteredItems[group].value = math.min(value, clusteredItems[group].value or math.huge)
  end
  return clusteredItems
end

-- Group mode functions
local typeOrder = {
  ['Car'] = {"Cars and Trucks", 1},
  ['Truck'] = {"Cars and Trucks", 2},
  ['Aircraft'] = {"Other Vehicles", 3},
  ['Boat'] = {"Other Vehicles", 4},
  ['Automation'] = {"Automation", 3},
  ['Trailer'] = {"Trailers", 20},
  ['Prop'] = {"Props", 30},
}

local isRange = {
  ['Years'] = true,
  ['Value'] = true,
}

local groupModeFunctions = {
  ['Type'] = function(type)
    local typeInfo = typeOrder[type]
    return typeInfo and typeInfo[1] or "Other...", typeInfo and typeInfo[2] or 999
  end,
  ['Brand'] = function(brand)
    return brand, 0
  end,
  ['Country'] = function(country)
    return country, 0
  end,
  ['Config Type'] = function(configType)
    return configType, 0
  end,
  ['Derby Class'] = function(derbyClass)
    return derbyClass, 0
  end,
  ['Body Style'] = function(bodyStyle)
    return bodyStyle, 0
  end,
  ['Source'] = function(source)
    return source, 0
  end,
}
M.groupModeFunctions = groupModeFunctions

local groupsForRange = {
  ['Years'] = function(years)
    if not years or not years.min or not years.max then
      return {{groupName = "Other...", groupOrder = 999}}
    end

    local decades = {}
    local startDecade = math.floor(years.min / 10) * 10
    local endDecade = math.floor(years.max / 10) * 10

    for decade = startDecade, endDecade, 10 do
      table.insert(decades, {
        groupName = tostring(decade) .. "s",
        groupOrder = 0
      })
    end

    return decades
  end,
  ['Value'] = function(value)
    local price = value
    if type(value) == 'table' then
      price = value.min
    end
    if not price or price == "Other..." then
      return {{groupName = "Other...", groupOrder = 999}}
    end

    local groups = {}

    if price < 10000 then
      table.insert(groups, {groupName = "Misc ($0-$10k)", groupOrder = 1})
    elseif price < 20000 then
      table.insert(groups, {groupName = "$10k-$20k", groupOrder = 2})
    elseif price < 50000 then
      table.insert(groups, {groupName = "$20k-$50k", groupOrder = 3})
    elseif price < 100000 then
      table.insert(groups, {groupName = "$50k-$100k", groupOrder = 4})
    elseif price < 250000 then
      table.insert(groups, {groupName = "$100k-$250k", groupOrder = 5})
    elseif price < 500000 then
      table.insert(groups, {groupName = "$250k-$500k", groupOrder = 6})
    elseif price < 1000000 then
      table.insert(groups, {groupName = "$500k-$1M", groupOrder = 7})
    else
      table.insert(groups, {groupName = "$1M+", groupOrder = 8})
    end

    return groups
  end
}

local function getConfigOrModelPropValue(config, prop)
  local value = config[prop]
  if value == nil then
    local model = core_vehicles.getModel(config.model_key)
    if model and model.model then
      value = model.model[prop]
    end
  end
  if value == nil then return nil end
  return value
end
M.getConfigOrModelPropValue = getConfigOrModelPropValue

local overrideDefaultSelectedTile = nil
M.overrideDefaultSelectedTile = function(tile)
  overrideDefaultSelectedTile = tile
end

-- Main getTiles function
local function getTiles(path, pathChanged)
  p:start()
  local data = ui_vehicleSelector.getUiData()
  p:add("getUiData")
  path = path or {keys = {}}
  local pathType = path.keys[1]
  local clusterMode = data.displayData.clusterMode
  ui_vehicleSelector_filters.setupValidFilters()
  p:add("setupValidFilters")

  if pathType == "allModels" then
    -- first, filter the configs
    local validConfigs = {}
    p:add("setupValidFilters")
    for _, config in pairs(data.configs) do

      if not ui_vehicleSelector_filters.passesFilters({model = config.model_key, config = config.key}) then
        goto continue
      end
      table.insert(validConfigs, config)
      ::continue::
    end
    p:add("apply filters to configs")
    -- first, create all the groups. ie check which configs are in which groups
    local groups = {}
    local favouriteGroup, recentGroup = {tiles = {}}, {tiles = {}}
    for _, config in pairs(validConfigs) do
      local groupsForConfig = {}
      if not isRange[data.displayData.groupMode] then
        local value = getConfigOrModelPropValue(config, data.displayData.groupMode) or "Other..."
        local groupName, groupOrder = groupModeFunctions[data.displayData.groupMode](value)
        table.insert(groupsForConfig, {groupName = groupName, groupOrder = groupOrder})
      else
        local value = getConfigOrModelPropValue(config, data.displayData.groupMode) or "Other..."
        local rangeGroups = groupsForRange[data.displayData.groupMode](value)
        if rangeGroups then
          for _, group in ipairs(rangeGroups) do
            table.insert(groupsForConfig, group)
          end
        else
          table.insert(groupsForConfig, {groupName = "Other...", groupOrder = 0})
        end
      end
      if data.displayData.showFavouritesMode ~= 'hidden' and ui_vehicleSelector_displayData.isFavourite(config.model_key, config.key) then
        table.insert(groupsForConfig, {groupName = "Favourites", groupOrder = -1, isFavouriteGroup = true})
      end
      if data.displayData.showRecentMode ~= 'hidden' and ui_vehicleSelector_displayData.isRecentVehicle(config.model_key, config.key) then
        table.insert(groupsForConfig, {groupName = "Recent", groupOrder = -2, isRecentGroup = true})
      end
      for _, group in pairs(groupsForConfig) do
        local groupName, groupOrder = group.groupName, group.groupOrder
        if not groups[groupName] then
          groups[groupName] = {
            key = groupName,
            label = groupName,
            unclusteredConfigs = {},
            tiles = {},
            order = groupOrder,
            gotoParams = {data.displayData.groupMode, groupName},
            isFavouriteGroup = group.isFavouriteGroup,
            isRecentGroup = group.isRecentGroup
          }
          if group.isFavouriteGroup then
            groups[groupName].gotoParams = {"Favourites"}
            favouriteGroup = groups[groupName]
          end
          if group.isRecentGroup then
            groups[groupName].gotoParams = {"Recent"}
            recentGroup = groups[groupName]
          end
        end
        -- skip adding the config to the group if we are in complete clusters mode - they will be added later
        if group.isFavouriteGroup and data.displayData.showFavouritesMode == 'completeClusters'
        or group.isRecentGroup and data.displayData.showRecentMode == 'completeClusters' then
          goto continue
        end
        table.insert(groups[groupName].unclusteredConfigs, config)
        ::continue::
      end
      p:add("put config in group")
    end
    -- then, create the tiles for each group
    if data.displayData.showFavouritesMode == 'completeClusters' then
      favouriteGroup.unclusteredConfigs = {}
      favouriteGroup.tiles = {}
    end
    if data.displayData.showRecentMode == 'completeClusters' then
      recentGroup.unclusteredConfigs = {}
      recentGroup.tiles = {}
    end
    for _, group in pairs(groups) do
      -- first, cluster the items. ie which configs belong to which tile/model
      local itemsClustered = clusterItems(group.unclusteredConfigs)
      group.unclusteredConfigs = nil
      -- then, create the tiles for each cluster
      for _, clusteredItems in pairs(itemsClustered) do
        local tiles = {}
        if clusteredItems.count > data.displayData.expandGroups then
          tiles[1] = tileFromClusteredItems[clusterMode](clusteredItems, group)
        else
          for i, config in pairs(clusteredItems.configsByKey) do
            local tile = configToTile(config, true)
            table.insert(tiles, tile)
          end
        end
        for _, tile in pairs(tiles) do
          table.insert(group.tiles, tile)
          if data.displayData.showFavouritesMode == 'completeClusters' and tile.favouriteIdx > 0 then
            local favouriteTile = deepcopy(tile)
            favouriteTile.key = favouriteTile.key .. "_" .. tile.favouriteIdx
            if favouriteTile.highestFavouriteConfig then
              favouriteTile.doubleClickDetails.config = favouriteTile.highestFavouriteConfig.key
              favouriteTile.preview = favouriteTile.highestFavouriteConfig.preview
            end
            table.insert(favouriteGroup.tiles, favouriteTile)
            favouriteTile.highestFavouriteConfig = nil
            favouriteTile.lowestRecentConfig = nil
          end
          if data.displayData.showRecentMode == 'completeClusters' and tile.recentIdx < math.huge then
            local recentTile = deepcopy(tile)
            recentTile.key = recentTile.key .. "_" .. tile.recentIdx
            if recentTile.lowestRecentConfig then
              recentTile.doubleClickDetails.config = recentTile.lowestRecentConfig.key
              recentTile.preview = recentTile.lowestRecentConfig.preview
            end
            table.insert(recentGroup.tiles, recentTile)
            recentTile.highestFavouriteConfig = nil
            recentTile.lowestRecentConfig = nil
          end
          tile.highestFavouriteConfig = nil
          tile.lowestRecentConfig = nil
        end
      end
      p:add("cluster items in group")
    end
    -- sort tiles in groups
    for _, group in pairs(groups) do
      if data.displayData.sortMode == 'Automatic' or group.isRecentGroup then
        if group.isRecentGroup then
          table.sort(group.tiles, function(a, b)
            return a.recentIdx < b.recentIdx
          end)
        elseif group.isFavouriteGroup then
          table.sort(group.tiles, function(a, b)
            return a.favouriteIdx > b.favouriteIdx
          end)
        elseif data.displayData.groupMode == 'Value' then
          table.sort(group.tiles, sortByValue)
        elseif data.displayData.groupMode == 'Years' then
          table.sort(group.tiles, sortByYears)
        else
          table.sort(group.tiles, sortByNameButOtherAlwaysLast)
        end
      end
      p:add("sort tiles in group (auto)")
    end
    -- remove tiles from recent group until we have the correct amount
    local recentTileCount = #recentGroup.tiles
    while recentTileCount > data.displayData.recentAmount do
      table.remove(recentGroup.tiles, recentTileCount)
      recentTileCount = recentTileCount - 1
    end
    for _, group in pairs(groups) do
      if data.displayData.sortMode == 'Name' then
        table.sort(group.tiles, sortByNameButOtherAlwaysLast)
      elseif data.displayData.sortMode == 'Value' then
        table.sort(group.tiles, sortByValue)
      elseif data.displayData.sortMode == 'Years' then
        table.sort(group.tiles, sortByYears)
      elseif data.displayData.sortMode == 'Weight' then
        table.sort(group.tiles, sortByWeight)
      elseif data.displayData.sortMode == 'Top Speed' then
        table.sort(group.tiles, sortByTopSpeed)
      elseif data.displayData.sortMode == 'Power' then
        table.sort(group.tiles, sortByPower)
      elseif data.displayData.sortMode == 'Weight/Power' then
        table.sort(group.tiles, sortByWeightPower)
      elseif data.displayData.sortMode == '0-60 mph' then
        table.sort(group.tiles, sortBy0To60)
      elseif data.displayData.sortMode == '0-100 km/h' then
        table.sort(group.tiles, sortBy0To100)
      end
      p:add("sort tiles in group (manual)")
    end

    local groupsList = {}
    for _, group in pairs(groups) do
      if #group.tiles > 0 then
        table.insert(groupsList, group)
      end
    end
    table.sort(groupsList, function(a, b)
      if a.order == b.order then
        return sortByNameButOtherAlwaysLast(a, b)
      end
      return a.order < b.order
    end)
    p:add("sort groups")
    p:add("lua function finished, sending groups to UI...")

    if pathChanged then
      extensions.hook("onVehicleSelectorGetTiles", pathType)
    end
    p:finish(true)
    return groupsList
  end

  if pathType == "configsForBrandSubModelOrModel" then
    local modelKey, modelSubKey, brandKey, groupMode, groupName
    modelKey = path.keys[2]
    modelSubKey = path.keys[3]
    brandKey = path.keys[4]
    groupMode = path.keys[5]
    groupName = path.keys[6]
    local model = core_vehicles.getModel(modelKey)
    extensions.hook("onVehicleSelectorGetTiles", pathType, modelKey, modelSubKey, brandKey, groupMode, groupName)
    if model then

      local group = {
        key = "configsForBrandSubModelOrModel",
        label = nil,
        tiles = {}
      }


      for _, config in pairs(model.configs) do
        if modelSubKey and modelSubKey ~= "" then
          local subModel = config.SubModel or model.model.SubModel
          if subModel ~= modelSubKey then
            goto continue
          end
        end
        if brandKey and brandKey ~= "" then
          local brand = config.Brand or model.model.Brand
          if brand ~= brandKey then
            goto continue
          end
        end
        if config.isAuxiliary and not data.displayData.showAuxContent then
          goto continue
        end
                -- basic filter
        local match = ui_vehicleSelector_filters.passesFilters({model = config.model_key, config = config.key})
        p:add("passesFilters")
        -- see if the config is in the group that we want to display
        if groupMode and groupName then
          local validGroups = {}
          if not isRange[groupMode] then
            local value = getConfigOrModelPropValue(config, groupMode) or "Other..."
            local groupName, _ = groupModeFunctions[groupMode](value)
            validGroups[groupName] = true
          else
            local value = getConfigOrModelPropValue(config, groupMode) or "Other..."
            local rangeGroups = groupsForRange[groupMode](value)
            for _, group in ipairs(rangeGroups) do
              validGroups[group.groupName] = true
            end
          end
          match = match and validGroups[groupName]
        end
        if groupMode == "Favourites" then
          match = ui_vehicleSelector_displayData.isFavourite(config.model_key, config.key)
        elseif groupMode == "Recent" then
          match = ui_vehicleSelector_displayData.isRecentVehicle(config.model_key, config.key)
        end
        if match then
          table.insert(group.tiles, configToTile(config))
        end
        p:add("configToTile")
        ::continue::
      end



      -- Sort the configs by name
      if data.displayData.sortMode == 'Automatic' then
        if groupMode == "Favourites" then
          table.sort(group.tiles, function(a, b)
            return a.favouriteIdx > b.favouriteIdx
          end)
        elseif groupMode == "Recent" then
          table.sort(group.tiles, function(a, b)
            return a.recentIdx < b.recentIdx
          end)
        else
          table.sort(group.tiles, sortByValue)
        end
      end
      if data.displayData.sortMode == 'Name' then
        table.sort(group.tiles, sortByNameButOtherAlwaysLast)
      elseif data.displayData.sortMode == 'Value' then
        table.sort(group.tiles, sortByValue)
      elseif data.displayData.sortMode == 'Years' then
        table.sort(group.tiles, sortByYears)
      elseif data.displayData.sortMode == 'Weight' then
        table.sort(group.tiles, sortByWeight)
      elseif data.displayData.sortMode == 'Top Speed' then
        table.sort(group.tiles, sortByTopSpeed)
      elseif data.displayData.sortMode == 'Power' then
        table.sort(group.tiles, sortByPower)
      elseif data.displayData.sortMode == 'Weight/Power' then
        table.sort(group.tiles, sortByWeightPower)
      elseif data.displayData.sortMode == '0-60 mph' then
        table.sort(group.tiles, sortBy0To60)
      elseif data.displayData.sortMode == '0-100 km/h' then
        table.sort(group.tiles, sortBy0To100)
      end
      p:add("sorting")
      -- figure out the default selected tile
      local defaultTile = nil
      if data.displayData.sortMode == "Automatic" or data.displayData.sortMode == "Name" then
        if model.model.default_pc then
          for _, tile in ipairs(group.tiles) do
            if tile.config_key == model.model.default_pc then
              defaultTile = tile
              break
            end
          end
        end
      end
      if overrideDefaultSelectedTile then
        for _, tile in ipairs(group.tiles) do
          if tile.config_key == overrideDefaultSelectedTile.key then
            defaultTile = tile
            defaultTile.forceAutoFocus = true
            break
          end
        end
      end
      if not defaultTile then
        defaultTile = group.tiles[#group.tiles]
      end
      if defaultTile then
        defaultTile.isDefaultSelected = true
      end
      overrideDefaultSelectedTile = nil

      -- Return the single group
      p:add("returning group")
      p:finish(true)
      return {group}
    end
  end
  return {}
end

-- Export functions
M.getTiles = getTiles
M.configToTile = configToTile
M.clusterItems = clusterItems
M.sortByNameButOtherAlwaysLast = sortByNameButOtherAlwaysLast
M.sortByValue = sortByValue
M.sortByYears = sortByYears

return M