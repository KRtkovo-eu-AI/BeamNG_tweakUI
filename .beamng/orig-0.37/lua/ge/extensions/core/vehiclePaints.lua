-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt


local M = {}

local debugLog = nop
local debugModelKey, debugConfigKey
local debugLogFun = function(message)
  if debugConfigKey == nil or debugConfigKey == "4x4_carrier_petrol" then
    log("I","", string.format("%s %s: %s", debugModelKey and debugModelKey .. " " or "", debugConfigKey and "config " .. debugConfigKey or "", message))
  end
end

local paintsByIdCache = nil
local paintsByNameAsListCache = nil
local paintCollectionsByIdCache = nil
local multiPaintSetupsByIdCache = nil
local missingPaint = {
  name = "Missing Paint",
  id = "_missing_paint_",
  baseColor = {0.5, 0.5, 0.5, 0.5},
  clearcoat = 0.5,
  clearcoatRoughness = 0.5,
  metallic = 0.5,
  roughness = 0.5,
}
local function buildPaintCaches()
  paintsByIdCache = { _missing_paint_ = missingPaint }
  paintsByNameAsListCache = { }
  paintCollectionsByIdCache = {}
  multiPaintSetupsByIdCache = {}
  for _, paintFilePath in pairs(core_vehicles.getPaintFiles()) do
    local paintFile = core_vehicles.getFilesParsed()[paintFilePath]

    for id, paint in pairs(paintFile.paints or {}) do
      paint.sources = nil
      if paintsByIdCache[id] then
        log('E', 'vehicles', 'duplicate paint id: ' .. id .. ' in ' .. paintFilePath)
      else
        paintsByIdCache[id] = paint
      end
      if not paintsByNameAsListCache[paint.name] then
        paintsByNameAsListCache[paint.name] = {}
      end
      table.insert(paintsByNameAsListCache[paint.name], paint)
    end
    for id, collection in pairs(paintFile.collections or {}) do
      for _, paintName in pairs(collection.paints) do
        paintCollectionsByIdCache[id] = collection
      end
    end
    for id, setup in pairs(paintFile.multiPaintSetups or {}) do
      multiPaintSetupsByIdCache[id] = setup
      for i = 1, 3 do
        local paintKey = "paint" .. i
        if type(setup[paintKey]) == 'string' then
          if not paintsByIdCache[setup[paintKey]] then
            log('E', 'vehicles', 'paint ' .. setup[paintKey] .. ' not found in ' .. paintFilePath .. ' for multiPaintSetup ' .. id)
            setup[paintKey] = nil
          end
        end
      end
    end
  end
  for cId, collection in pairs(paintCollectionsByIdCache) do
    local cleanCollection = {}
    for pId, paint in pairs(collection.paints) do
      if type(paint) == 'string' then paint = {id = paint} end
      if not paintsByIdCache[paint.id] then
        log('E', 'vehicles', "paint " .. paint.id .. " not found in " .. collection.name)
      else
        table.insert(cleanCollection, tableMerge(paint, paintsByIdCache[paint.id]))
      end
    end
    paintCollectionsByIdCache[cId] = cleanCollection
  end
  for id, paint in pairs(paintsByIdCache) do
    paint.id = id
  end
  local multiNames = 0
  for name, paints in pairs(paintsByNameAsListCache) do
    if #paints > 1 then
      multiNames = multiNames + 1
    end
  end
  log("I","",string.format("Found %d paints, %d paint collections, %d multiPaintSetups in %d paint libraries, %d same-name paint names", #tableKeys(paintsByIdCache), #tableKeys(paintCollectionsByIdCache), #tableKeys(multiPaintSetupsByIdCache), #tableKeys(core_vehicles.getPaintFiles()), multiNames))
end

local function getPaintById(id)
  if not paintsByIdCache then buildPaintCaches() end
  return deepcopy(paintsByIdCache[id])
end

local function getPaintCollectionById(id)
  if not paintCollectionsByIdCache then buildPaintCaches() end
  return deepcopy(paintCollectionsByIdCache[id])
end


local function resolvePaintHelper(modelPaints, paintKeyOrPaint, paintIdsToPaintNames)
  local paint = nil

  if type(paintKeyOrPaint) == 'string' then
    debugLog("resolving paint " .. dumps(paintKeyOrPaint))
    paint = modelPaints[paintKeyOrPaint]
  elseif type(paintKeyOrPaint) == 'table' then
    debugLog("resolving paint " .. dumps(paintKeyOrPaint.name))
    paint = paintKeyOrPaint
  end
  if paint then
    debugLog("paint found: " .. dumps(paint.name))
    if not modelPaints[paint.name] then
      debugLog("added paint " .. dumps(paint.name) .. " to model. This paint was explicitly defined")
      paint.class = 'custom'
      modelPaints[paint.name] = paint
      return paint, true
    end
    return paint
  end

  if not paint then
    local paintName = paintIdsToPaintNames[paintKeyOrPaint]
    if paintName then
      paint = modelPaints[paintName]
      if paint then
        debugLog("paint found: " .. dumps(paint.name) .. ". Paint was already added to the model")
        return paint
      end
    end
  end
  if not paint then
    paint = getPaintById(paintKeyOrPaint)
    if paint then
      paint.class = 'custom'
      modelPaints[paint.name] = paint
      paintIdsToPaintNames[paintKeyOrPaint] = paint.name
      debugLog("adding paint to model: " .. dumps(paint.id) .. "/" .. dumps(paint.name) .. " (from library) ")
      return paint, true
    end
  end
  if not paint then
    local paints = paintsByNameAsListCache[paintKeyOrPaint]
    if paints then
      log("W", "vehicles", "paint " .. dumps(paintKeyOrPaint) .. " from config " .. dumps(debugModelKey) .. "/" .. dumps(debugConfigKey) .. " not found in the model file. But found by name in the paint library.. Please use the id instead: " .. dumps(paints[1].id) .. " or add the paint to the model file.")
      paint = deepcopy(paints[1])
      paint.class = 'custom'
      modelPaints[paint.name] = paint
      paintIdsToPaintNames[paint.id] = paint.name
      return paint, true
    end
  end
  return paint
end

local function resolveMultiPaintSetupHelper(model, multiPaintSetupKeyOrMultiPaintSetup, paintIdsToPaintNames, multiPaintSetupsByIdOrName)
  local multiPaintSetup = nil
  if type(multiPaintSetupKeyOrMultiPaintSetup) == 'string' then
    if multiPaintSetupsByIdOrName[multiPaintSetupKeyOrMultiPaintSetup] then
      multiPaintSetup = multiPaintSetupsByIdOrName[multiPaintSetupKeyOrMultiPaintSetup]
      return multiPaintSetup
    else
      multiPaintSetup = deepcopy(multiPaintSetupsByIdCache[multiPaintSetupKeyOrMultiPaintSetup])
    end
    if not multiPaintSetup then
      log("E", "vehicles", "multiPaintSetup " .. dumps(multiPaintSetupKeyOrMultiPaintSetup) .. " not found in any paint library or model " ..dumps(debugModelKey) .. " " .. dumps(debugConfigKey))
      return nil
    end
  elseif type(multiPaintSetupKeyOrMultiPaintSetup) == 'table' then
    multiPaintSetup = multiPaintSetupKeyOrMultiPaintSetup
  end
  local multiPaintSetupWithNames = {
    name = multiPaintSetup.name,
    usedByConfigByKey = {},
    isDefaultForConfigByKey = {},
    isDefaultForModel = multiPaintSetup.defaultForModel,
  }

  debugLog("resolving multiPaintSetup: " .. dumps(multiPaintSetupWithNames.name))
  for i = 1, 3 do
    local defaultPaintKey = "paint" .. i
    if multiPaintSetup[defaultPaintKey] and multiPaintSetup[defaultPaintKey] ~= "" then
      local paint, _
      paint, _ = resolvePaintHelper(model.paints, multiPaintSetup[defaultPaintKey], paintIdsToPaintNames)
      if paint then
        multiPaintSetup[defaultPaintKey] = paint.name
        multiPaintSetupWithNames['paintName' .. i] = paint.name
      else
        log("E", "vehicles", "paint " .. dumps(multiPaintSetup[defaultPaintKey]) .. " not found in default paint list or any library for model " .. dumps(key) .. ", used as " ..dumps(defaultPaintKey) .. " in multiPaintSetup " .. dumps(multiPaintSetup.name or "unknown"))
      end
    else
      debugLog("paint " .. dumps(multiPaintSetup[defaultPaintKey]) .. " not found in default paint list or any library for model " .. dumps(key) .. ", used as " ..dumps(defaultPaintKey) .. " in multiPaintSetup " .. dumps(multiPaintSetup.name or "unknown"))
    end
  end

  multiPaintSetupWithNames.paintName2 = multiPaintSetupWithNames.paintName2 or multiPaintSetupWithNames.paintName1
  multiPaintSetupWithNames.paintName3 = multiPaintSetupWithNames.paintName3 or multiPaintSetupWithNames.paintName1

  if (multiPaintSetupWithNames.paintName1 or multiPaintSetupWithNames.paintName2 or multiPaintSetupWithNames.paintName3) then
    table.insert(model.multiPaintSetups, multiPaintSetupWithNames)
    return multiPaintSetupWithNames
  end
  return nil
end

local function setupPaints(model, configs)
  debugModelKey = model.key
  debugConfigKey = nil
  --debugLog = model.key == 'simple_traffic' and debugLogFun or nop
  debugLog("setupPaints for model " .. dumps(model.key))

  local paintIdsToPaintNames = {}
  local multiPaintIdsToMultiPaintSetups = {}


  -- create paint list if it doesn't exist
  model.paints = model.paints or {}
  debugLog("Model has " .. #tableKeys(model.paints) .. " explicit paints: " .. table.concat(tableKeysSorted(model.paints), ", "))

  -- add names to old paint format
  for name, paint in pairs(model.paints) do
    paint.name = name
  end

  -- convert paint names from library to actual paint data
  for _, paint in pairs(model.libraryPaints or {}) do
    if type(paint) == 'string' then paint = {id = paint} end
    local paintFromLibrary = getPaintById(paint.id)
    if paintFromLibrary then
      debugLog("adding paint from model.libraryPaints to model: " .. dumps(paintFromLibrary.id) .. "/" .. dumps(paintFromLibrary.name) .. " (from library) ")
      tableMerge(paintFromLibrary, paint)
      model.paints[paintFromLibrary.name] = paintFromLibrary
      paintIdsToPaintNames[paintFromLibrary.id] = paintFromLibrary.name
    else
      log('E', 'vehicles', "paint " .. dumps(paint.id) .. " not found in any paint library for model " .. dumps(key))
    end
  end
  model.libraryPaints = nil

  -- convert paint collections to actual paint data
  for _, collectionId in pairs(model.paintCollections or {}) do
    local collection = getPaintCollectionById(collectionId)
    if collection then
      for _, paint in pairs(collection) do
        debugLog("adding paint from model.paintCollections to model: " .. dumps(paint.id) .. "/" .. dumps(paint.name) .. " (from collection " .. dumps(collectionId) .. ")")
        tableMerge(paint, paintsByIdCache[paint.id])
        model.paints[paint.name] = paint
        paintIdsToPaintNames[paint.id] = paint.name
      end
    else
      log('E', 'vehicles', "paint collection " .. dumps(collectionId) .. " not found for model " .. dumps(key))
    end
  end
  model.paintCollections = nil

  -- process multiPaintSetups
  local multiPaintSetupsToProcess = model.multiPaintSetups or {}
  model.multiPaintSetups = {}
  local multiPaintSetupsByIdOrName = {}
  -- process all the setups already in the model
  for _, multiPaintSetup in pairs(multiPaintSetupsToProcess) do
    local multiPaintSetupWithNames = resolveMultiPaintSetupHelper(model, multiPaintSetup, paintIdsToPaintNames, multiPaintSetupsByIdOrName)
    if multiPaintSetupWithNames then
      if not multiPaintSetupWithNames.id then
        multiPaintSetupWithNames.id = multiPaintSetup.name
      end
      if multiPaintSetupWithNames.id then
        multiPaintSetupsByIdOrName[multiPaintSetupWithNames.id] = multiPaintSetupWithNames
      end
      multiPaintSetupWithNames.forAllConfigs = true
    end
  end
  table.clear(multiPaintSetupsToProcess)

  -- add a setup for the default paints of the model
  local defaultMultiPaintSetup = model.defaultMultiPaintSetup
  if not defaultMultiPaintSetup then
    debugLog("no defaultMultiPaintSetup found for model " .. dumps(model.key)..". Using defaultPaintName1, defaultPaintName2, defaultPaintName3: " .. dumps(model.defaultPaintName1) .. ", " .. dumps(model.defaultPaintName2) .. ", " .. dumps(model.defaultPaintName3))
    defaultMultiPaintSetup = {
      name = model.Name .. " default paints",
      paint1 = model.defaultPaintName1,
      paint2 = model.defaultPaintName2 or model.defaultPaintName1,
      paint3 = model.defaultPaintName3 or model.defaultPaintName1,
    }
  end
  local defaultMultiPaintSetupWithNames = resolveMultiPaintSetupHelper(model, defaultMultiPaintSetup, paintIdsToPaintNames, multiPaintSetupsByIdOrName)
  if defaultMultiPaintSetupWithNames then
    if not model.defaultMultiPaintSetup then
      defaultMultiPaintSetupWithNames.name = model.Name .. " default paints"
    end
    defaultMultiPaintSetupWithNames.defaultForModel = true

    model.defaultPaintName1 = defaultMultiPaintSetupWithNames.paintName1
    model.defaultPaintName2 = defaultMultiPaintSetupWithNames.paintName2
    model.defaultPaintName3 = defaultMultiPaintSetupWithNames.paintName3

    local paint1 = model.paints[model.defaultPaintName1]
    model.defaultPaint = paint1 or {}
  end

  -- process configs
  for _, config in pairs(configs) do
    debugConfigKey = config.key
    if config.defaultPaintName1 and config.defaultMultiPaintSetup then
      log("W","", model.key .. " " .. dumps(config.key) .. ": defaultPaintName1 overriden by defaultMultiPaintSetup")
    end
    -- add a setup for the default paints of the config
    local defaultMultiPaintSetup = config.defaultMultiPaintSetup
    if not defaultMultiPaintSetup then
      for i = 1, 3 do
        local defaultPaintKey = "defaultPaintName" .. i
        if config[defaultPaintKey] == nil or config[defaultPaintKey] == "" then
          config[defaultPaintKey] = i == 1 and model.defaultPaintName1 or config.defaultPaintName1
        end
      end
      defaultMultiPaintSetup = {
        name = config.Name .. " default paints",
        paint1 = config.defaultPaintName1,
        paint2 = config.defaultPaintName2,
        paint3 = config.defaultPaintName3,
      }
      debugLog("no defaultMultiPaintSetup found for config " .. dumps(config.key)..". Using defaultPaintName1, defaultPaintName2, defaultPaintName3: " .. dumps(defaultMultiPaintSetup.paint1) .. ", " .. dumps(defaultMultiPaintSetup.paint2) .. ", " .. dumps(defaultMultiPaintSetup.paint3))
    end
    local defaultMultiPaintSetupWithNames = resolveMultiPaintSetupHelper(model, defaultMultiPaintSetup, paintIdsToPaintNames, multiPaintSetupsByIdOrName)
    if defaultMultiPaintSetupWithNames then
      if not config.defaultMultiPaintSetup then
        defaultMultiPaintSetupWithNames.name = config.Name .. " default paints"
      end
      defaultMultiPaintSetupWithNames.isDefaultForConfigByKey[config.key] = true
      defaultMultiPaintSetupWithNames.usedByConfigByKey[config.key] = true


      config.defaultPaintName1 = defaultMultiPaintSetupWithNames.paintName1
      config.defaultPaintName2 = defaultMultiPaintSetupWithNames.paintName2
      config.defaultPaintName3 = defaultMultiPaintSetupWithNames.paintName3

      config.defaultPaint = model.paints[config.defaultPaintName1] or {}
    end
  end

  -- validate paints and set up factory and custom paints lists
  for _, paint in pairs(model.paints) do
    if not paint.class then
      paint.class = 'factory'
    end
  end

  debugLog("Finished: Model has " .. #tableKeys(model.paints) .. " paints: " .. table.concat(tableKeysSorted(model.paints), ", "))




  --[[
  model.factoryPaintNames = {}
  model.customPaintNames = {}
  for _, paint in pairs(model.paints) do
    if paint.class == 'factory' then
      table.insert(model.factoryPaintNames, paint.name)
    elseif paint.class == 'custom' then
      table.insert(model.customPaintNames, paint.name)
    end
  end
  if model.key == 'pickup' then
    log("I", "vehicles", "model " .. dumps(key) .. "Factory paints: " .. table.concat(model.factoryPaintNames, ", "))
    log("I", "vehicles", "model " .. dumps(key) .. "Custom paints: " .. table.concat(model.customPaintNames, ", "))
  end
  ]]
end
M.setupPaints = setupPaints




local function setupRandomPaintHelper(model_key)
  local modelData = core_vehicles.getModel(model_key)
  local model = modelData.model
  local configs = modelData.configs


  -- random paint distribution
  local defaultRandomPaintProbability = model.defaultRandomPaintProbability or 1
  local defaultRandomMultiPaintProbability = model.defaultRandomMultiPaintProbability or 1

  -- first, remap every paint in randomPaintDistribution to use the paint names
  model.randomPaintDistribution = model.randomPaintDistribution or {}
  local newRandomPaintDistributionModel = {}
  for paintNameOrId, probability in pairs(model.randomPaintDistribution) do
    local paint = model.paints[paintNameOrId]
    if not paint then
      paint = paintsByIdCache[paintNameOrId]
    end
    if paint then
      newRandomPaintDistributionModel[paint.name] = probability
    end
  end
  -- then add all the remaining paint names with 1 probability
  for paintName, _ in pairs(model.paints) do
    newRandomPaintDistributionModel[paintName] = newRandomPaintDistributionModel[paintName] or defaultRandomPaintProbability
  end


  local multiPaintSetupsByName = {}
  for _, multiPaintSetup in ipairs(model.multiPaintSetups) do
    multiPaintSetupsByName[multiPaintSetup.name] = multiPaintSetup
  end

  -- then do the same for randomMultiPaintDistribution
  model.randomMultiPaintDistribution = model.randomMultiPaintDistribution or {}
  local newRandomMultiPaintDistributionModel = {}
  for multiPaintSetupNameOrId, probability in pairs(model.randomMultiPaintDistribution) do
    local multiPaintSetup = multiPaintSetupsByName[multiPaintSetupNameOrId]
    if not multiPaintSetup then
      multiPaintSetup = multiPaintSetupsByIdCache[multiPaintSetupNameOrId]
      multiPaintSetup = multiPaintSetupsByName[multiPaintSetup.name]
    end
    if multiPaintSetup then
      newRandomMultiPaintDistributionModel[multiPaintSetup.name] = probability
      multiPaintSetupsByName[multiPaintSetup.name] = multiPaintSetup
    end
  end
  for _, multiPaintSetup in ipairs(model.multiPaintSetups) do
    if multiPaintSetup.forAllConfigs then
      newRandomMultiPaintDistributionModel[multiPaintSetup.name] = newRandomMultiPaintDistributionModel[multiPaintSetup.name] or defaultRandomMultiPaintProbability
    end
  end

  -- finally, add all results into one list and add the sum of all probabilities
  local totalProbability = 0
  local allPaintResults = {}
  for paintName, probability in pairs(newRandomPaintDistributionModel) do
    totalProbability = totalProbability + probability
    if probability > 0 then
      table.insert(allPaintResults, {
        type = 'paint',
        paintName1 = paintName,
        paintName2 = paintName,
        paintName3 = paintName,
        probability = probability,
      })
    end
  end
  for multiPaintSetupName, probability in pairs(newRandomMultiPaintDistributionModel) do
    totalProbability = totalProbability + probability
    local multiPaintSetup = multiPaintSetupsByName[multiPaintSetupName]
    if probability > 0 then
      table.insert(allPaintResults, {
        type = 'multiPaintSetup',
        paintName1 = multiPaintSetup.paintName1,
        paintName2 = multiPaintSetup.paintName2,
        paintName3 = multiPaintSetup.paintName3,
        probability = probability,
      })
    end
  end
  model.randomPaintHelper = {
    allPaintResults = allPaintResults,
    totalProbability = totalProbability,
  }
  if debugLog ~= nop then
    debugLog("model " .. dumps(key) .. " has " .. #allPaintResults .. " paint results with total probability " .. totalProbability)
    for _, paintResult in pairs(allPaintResults) do
      debugLog("paint result: " .. dumps(paintResult.type) .. ", " .. dumps(paintResult.paintName1) .. ", " .. dumps(paintResult.paintName2) .. ", " .. dumps(paintResult.paintName3) .. ", probability: " .. dumps(paintResult.probability))
    end
  end

  -- now do the same for each config
  for _, config in pairs(configs) do
    debugConfigKey = config.key

    local defaultRandomPaintProbability = config.defaultRandomPaintProbability or model.defaultRandomPaintProbability or 1
    local defaultRandomMultiPaintProbability = config.defaultRandomMultiPaintProbability or model.defaultRandomMultiPaintProbability or 1

    -- first, remap every paint in randomPaintDistribution to use the paint names
    local newRandomPaintDistributionConfig = {}
    for paintNameOrId, probability in pairs(config.randomPaintDistribution or {}) do
      local paint = model.paints[paintNameOrId]
      if not paint then
        paint = paintsByIdCache[paintNameOrId]
      end
      if paint then
        newRandomPaintDistributionConfig[paint.name] = probability
      end
    end
    -- add the probabilities from the model
    if not config.ignoreModelRandomPaintDistribution then
      for paintName, probability in pairs(newRandomPaintDistributionModel) do
        newRandomPaintDistributionConfig[paintName] = newRandomPaintDistributionConfig[paintName] or newRandomPaintDistributionModel[paintName] or probability
      end
    end
    -- then add all the remaining paint names with 1 probability
    for paintName, _ in pairs(model.paints) do
      newRandomPaintDistributionConfig[paintName] = newRandomPaintDistributionConfig[paintName] or defaultRandomPaintProbability
    end


     -- then do the same for randomMultiPaintDistribution
    local newRandomMultiPaintDistributionConfig = {}
    for multiPaintSetupNameOrId, probability in pairs(config.randomMultiPaintDistribution or {}) do
      local multiPaintSetup = multiPaintSetupsByName[multiPaintSetupNameOrId]
      if not multiPaintSetup then
        multiPaintSetup = multiPaintSetupsByIdCache[multiPaintSetupNameOrId]
        multiPaintSetup = multiPaintSetupsByName[multiPaintSetup.name]
      end
      if multiPaintSetup then
        newRandomMultiPaintDistributionConfig[multiPaintSetup.name] = probability
        multiPaintSetupsByName[multiPaintSetup.name] = multiPaintSetup
      end
    end
    -- add the probabilities from the model
    if not config.ignoreModelRandomMultiPaintDistribution then
      for multiPaintSetupName, probability in pairs(newRandomMultiPaintDistributionConfig) do
        newRandomMultiPaintDistributionConfig[multiPaintSetupName] = newRandomMultiPaintDistributionModel[multiPaintSetupName] or probability
      end
    end
    -- then add all the remaining multiPaintSetups with 1 probability
    for _, multiPaintSetup in ipairs(model.multiPaintSetups) do
      if multiPaintSetup.forAllConfigs then
        newRandomMultiPaintDistributionConfig[multiPaintSetup.name] = newRandomMultiPaintDistributionConfig[multiPaintSetup.name] or defaultRandomMultiPaintProbability
      end
    end

    -- finally, add all results into one list and add the sum of all probabilities
    local totalProbability = 0
    local allPaintResults = {}
    for paintName, probability in pairs(newRandomPaintDistributionConfig) do
      totalProbability = totalProbability + probability
      if probability > 0 then
        table.insert(allPaintResults, {
          type = 'paint',
          paintName1 = paintName,
          paintName2 = paintName,
          paintName3 = paintName,
          probability = probability,
        })
      end
    end
    for multiPaintSetupName, probability in pairs(newRandomMultiPaintDistributionConfig) do
      totalProbability = totalProbability + probability
      local multiPaintSetup = multiPaintSetupsByName[multiPaintSetupName]
      if probability > 0 then
        table.insert(allPaintResults, {
          type = 'multiPaintSetup',
          paintName1 = multiPaintSetup.paintName1,
          paintName2 = multiPaintSetup.paintName2,
          paintName3 = multiPaintSetup.paintName3,
          probability = probability,
        })
      end
    end
    config.randomPaintHelper = {
      allPaintResults = allPaintResults,
      totalProbability = totalProbability,
    }

    if debugLog ~= nop  and config.key == 'van_delivery' then
      debugLog("config " .. dumps(config.key) .. " has " .. #allPaintResults .. " paint results with total probability " .. totalProbability)
      for _, paintResult in pairs(allPaintResults) do
        debugLog("paint result: " .. dumps(paintResult.type) .. ", " .. dumps(paintResult.paintName1) .. ", " .. dumps(paintResult.paintName2) .. ", " .. dumps(paintResult.paintName3) .. ", probability: " .. dumps(paintResult.probability))
      end
    end
  end
end

-- gets random paint data, given a model key and a config key
local function getRandomPaints(model_key, config_key)
  local modelData = core_vehicles.getModel(model_key)
  local model = modelData.model
  if not model.randomPaintHelper then
    setupRandomPaintHelper(model_key)
  end
  local paintHelper = model.randomPaintHelper
  if config_key then
    local config = modelData.configs[config_key]
    paintHelper = config.randomPaintHelper
  end

  local randomNum = math.random() * paintHelper.totalProbability
  local sum = 0
  for _, paintResult in ipairs(paintHelper.allPaintResults) do
    sum = sum + paintResult.probability
    if randomNum < sum then
      return paintResult
    end
  end
end
M.getRandomPaints = getRandomPaints

-- gets random paints to use for an existing vehicle
local function getRandomPaintsByVehicle(vehId)
  local obj = getObjectByID(vehId or 0)
  local model = obj and obj.jbeam
  local config = obj and tostring(obj.partConfig)
  config  = string.match(config, "vehicles/".. model .."/(.*).pc")
  if not obj or not config then
    log('W', 'getRandomPaint', 'Vehicle not found, now using default paint data')
    return {'White', 'White', 'White'}
  end
  local paints = getRandomPaints(model, config)
  --log("I","",string.format("Selected for model %s, config %s: %s %s %s", model, config, paints.paintName1, paints.paintName2, paints.paintName3))
  return {paints.paintName1, paints.paintName2, paints.paintName3} -- returns as an array so that the function setVehicleColorsNames can use it
end
M.getRandomPaintsByVehicle = getRandomPaintsByVehicle

-- tests paint distribution
local function testRandomPaint(model_key, config_key, amount)
  local resultsByName = {}
  for i = 1, amount do
    local paintResult = getRandomPaints(model_key, config_key)
    local name = string.format("%s: %s %s %s", paintResult.type, paintResult.paintName1, paintResult.paintName2, paintResult.paintName3)
    resultsByName[name] = (resultsByName[name] or 0) + 1
  end

  log("I", "vehicles", "Random Paint Test Results")
  log("I", "vehicles", "Total samples: " .. amount)
  log("I", "vehicles", "Amount | Percent | Paint Configuration")
  log("I", "vehicles", "----------------------------------------")

  local sortedResults = {}
  for name, count in pairs(resultsByName) do
    table.insert(sortedResults, {name = name, count = count})
  end
  table.sort(sortedResults, function(a,b) return a.count > b.count end)

  for _, result in ipairs(sortedResults) do
    local percentage = (result.count / amount) * 100
    log("I", "vehicles", string.format("%5d | %6.1f%% | %s", result.count, percentage, result.name))
  end
end
M.testRandomPaint = testRandomPaint


return M