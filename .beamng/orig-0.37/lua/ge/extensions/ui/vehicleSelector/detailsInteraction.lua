local M = {}

local fadeScreenDuration = 0.33

-- Button management system
M.buttonIdCounter = 0
M.buttonsInfos = {}

M.managementButtonsEnabled = true

-- Fade screen callback
local callbackAfterFade


-- Get a free button ID
local function getFreeButtonId()
  M.buttonIdCounter = M.buttonIdCounter + 1
  return M.buttonIdCounter
end

-- Clear all button functions
local function clearButtonFunctions()
  M.buttonFunctions = {}
end

-- Add a button with callback function
local function addButton(callback, meta)
  local buttonId = getFreeButtonId()
  meta = meta or {}
  meta.buttonId = buttonId

  M.buttonsInfos[buttonId] = {
    callback = callback,
    meta = meta,
  }
  return meta
end

-- Execute button callback by ID
local function executeButton(buttonId, additionalData)
  local buttonInfo = M.buttonsInfos[buttonId]
  if buttonInfo then
    local data = buttonInfo.callback(additionalData)
    if buttonInfo.meta.canClearFilters and ui_vehicleSelector.getDisplayData().filterResetOnSpawn then
      ui_vehicleSelector.clearAllFilters()
    end
    return data
  else
    log("E", "", "Button function not found for ID: " .. tostring(buttonId))
  end
end

-- Handle fade screen state changes
local function onScreenFadeState(state)
  if callbackAfterFade and state == 1 then
    callbackAfterFade()
    callbackAfterFade = nil
  end
end

local function onUiWaitingState(state)
  if callbackAfterFade then
    callbackAfterFade()
    callbackAfterFade = nil
  end
end
M.onUiWaitingState = onUiWaitingState

-- Spawn vehicle after fade screen
local function spawnVehicleAfterFade(modelKey, configKey, additionalData)
  --ui_fadeScreen.start(fadeScreenDuration)
  guihooks.trigger("app:waiting", true)
  callbackAfterFade = function()
    -- Create spawn options similar to spawnVehicle.lua
    local options = {
      config = configKey,
    }
    local paintName1, paintName2, paintName3 = nil, nil, nil
    if additionalData then
      local model = core_vehicles.getModel(modelKey)
      if model then
        options.paint = model.model.paints[additionalData.paint]
        options.paint2 = model.model.paints[additionalData.paint2]
        options.paint3 = model.model.paints[additionalData.paint3]
        paintName1 = additionalData.paint
        paintName2 = additionalData.paint2
        paintName3 = additionalData.paint3
      end
    end

    -- Sanitize and spawn the vehicle
    local sanitizedOptions = sanitizeVehicleSpawnOptions(modelKey, options)
    local vehicle = core_vehicles.spawnNewVehicle(modelKey, sanitizedOptions)
    extensions.hook("onVehicleSelectorSpawnNew", modelKey, configKey, paintName1, paintName2, paintName3)

    if vehicle then
      log("I", "", "Vehicle spawned: " .. tostring(modelKey) .. " (ID: " .. tostring(vehicle:getId()) .. ")")
      --ui_fadeScreen.stop(fadeScreenDuration)
      guihooks.trigger("app:waiting", false)
    else
      log("E", "", "Failed to spawn vehicle: " .. tostring(modelKey))
      --ui_fadeScreen.stop(fadeScreenDuration)
      guihooks.trigger("app:waiting", false)
    end
  end
end

-- Replace vehicle after fade screen
local function replaceVehicleAfterFade(modelKey, configKey, additionalData)
  --ui_fadeScreen.start(fadeScreenDuration)
  guihooks.trigger("app:waiting", true)
  callbackAfterFade = function()
    -- Create spawn options for replacement
    local options = {
      config = configKey,
    }
    local paintName1, paintName2, paintName3 = nil, nil, nil
    if additionalData then
      local model = core_vehicles.getModel(modelKey)
      if model then
        options.paint = model.model.paints[additionalData.paint]
        options.paint2 = model.model.paints[additionalData.paint2]
        options.paint3 = model.model.paints[additionalData.paint3]
        paintName1 = additionalData.paint
        paintName2 = additionalData.paint2
        paintName3 = additionalData.paint3
      end
    end

    -- Sanitize and replace the vehicle
    local sanitizedOptions = sanitizeVehicleSpawnOptions(modelKey, options)
    local vehicle = core_vehicles.replaceVehicle(modelKey, sanitizedOptions)
    extensions.hook("onVehicleSelectorReplaceCurrent", modelKey, configKey, paintName1, paintName2, paintName3)
    if vehicle then
      log("I", "", "Vehicle replaced: " .. tostring(modelKey) .. " (ID: " .. tostring(vehicle:getId()) .. ")")
      --ui_fadeScreen.stop(fadeScreenDuration)
      guihooks.trigger("app:waiting", false)
    else
      log("E", "", "Failed to replace vehicle: " .. tostring(modelKey))
      --ui_fadeScreen.stop(fadeScreenDuration)
      guihooks.trigger("app:waiting", false)
    end
  end
end

-- Clone vehicle after fade screen
local function cloneVehicleAfterFade(callback)
  --ui_fadeScreen.start(fadeScreenDuration)
  guihooks.trigger("app:waiting", true)
  callbackAfterFade = function()
    local vehicle = core_vehicles.cloneCurrent()

    if vehicle then
      log("I", "", "Vehicle cloned: (ID: " .. tostring(vehicle:getId()) .. ")")
      --ui_fadeScreen.stop(fadeScreenDuration)
      guihooks.trigger("app:waiting", false)
      if callback then callback() end
    else
      log("E", "", "Failed to clone vehicle")
      --ui_fadeScreen.stop(fadeScreenDuration)
      guihooks.trigger("app:waiting", false)
    end
  end
end

-- Create button info with standard format
local function makeSpawningButtons(configDetails)
  local buttons = {}

  -- Spawn vehicle button
  if configDetails then
    table.insert(buttons, addButton(function(...)
      guihooks.trigger("ChangeState","play")
      -- Callback for spawning a new vehicle
      local modelKey = configDetails.model_key
      local configKey = configDetails.key

      spawnVehicleAfterFade(modelKey, configKey, ...)
      ui_vehicleSelector.trackRecentVehicle(modelKey, configKey)
    end, {
      label = "Spawn New",
      icon = "carPlus",
      canClearFilters = true,
    }))

    table.insert(buttons, addButton(function(...)
      guihooks.trigger("ChangeState","play")
      -- Callback for replacing current vehicle
      local modelKey = configDetails.model_key
      local configKey = configDetails.key

      replaceVehicleAfterFade(modelKey, configKey, ...)
      ui_vehicleSelector.trackRecentVehicle(modelKey, configKey)
    end, {
      label = "Replace Current",
      icon = "carsChange",
      primary = true,
      isDoubleClickAction = true,
      canClearFilters = true,
    }))
  end

  return buttons
end

-- Get vehicle name similar to quickAccess.lua
local function getVehicleName(veh)
  if not veh then return "No vehicle" end
  local vehKey = veh.JBeam
  local vehConfig = veh.partConfig
  local vehicleNameSTR = {veh.JBeam}
  local vehMainInfo = core_vehicles.getModel(vehKey)

  if vehMainInfo then
    table.clear(vehicleNameSTR)
    local config_key = string.match(vehConfig, "vehicles/".. vehKey .."/(.*).pc")
    local configInfo = vehMainInfo.configs and vehMainInfo.configs[config_key] or vehMainInfo.model

    -- skip prop traffic

    -- build name
    table.insert(vehicleNameSTR, vehMainInfo.model["Brand"])
    table.insert(vehicleNameSTR, vehMainInfo.model["Name"])
    if vehMainInfo.configs and vehMainInfo.configs[config_key] then
      table.insert(vehicleNameSTR, configInfo["Configuration"] or "")
    end

    -- set icon
    if configInfo["Type"] then
      if configInfo["Type"]== "Trailer" then vicon = "smallTrailer" end
      if configInfo["Type"]== "Prop" then vicon = "trafficCone" end
    end
  end
  local vehicleName = table.concat(vehicleNameSTR, " ")
  return vehicleName
end

-- Get current vehicle thumbnail similar to inventory.lua
local function getCurrentVehicleThumb(veh)
  if not veh then return nil end
  local vehKey = veh.JBeam
  local vehConfig = veh.partConfig
  local vehMainInfo = core_vehicles.getModel(vehKey)

  if not vehMainInfo then return nil end

  local config_key = string.match(vehConfig, "vehicles/".. vehKey .."/(.*).pc")
  local config = vehMainInfo.configs[config_key]
  if not config then return nil end

  return config.preview
end

-- Get management details for vehicle operations
local function getManagementDetails()
  clearButtonFunctions()

  local buttons = {}

  -- Only show management buttons if they are enabled
  if M.managementButtonsEnabled then
    -- Set as default button
    table.insert(buttons, addButton(function()
      extensions.core_vehicle_partmgmt.savedefault()
      guihooks.trigger("ChangeState","play")
      extensions.hook("onVehicleSelectorSetAsDefault")
    end, {
      label = "Set as Default",
      icon = "carStarred"
    }))

    -- Load default button
    table.insert(buttons, addButton(function()
      callbackAfterFade = function()
        core_vehicles.spawnDefault();
        extensions.hook("trackNewVeh")
        guihooks.trigger("app:waiting", false)
        extensions.hook("onVehicleSelectorLoadDefault")
      end
      guihooks.trigger("ChangeState","play")
      guihooks.trigger("app:waiting", true)
    end, {
      label = "Load Default",
      icon = "starSecondary"
    }))

    -- Clone current button
    table.insert(buttons, addButton(function()
      guihooks.trigger("ChangeState","play")
      cloneVehicleAfterFade()
      extensions.hook("onVehicleSelectorCloneCurrent")
    end, {
      label = "Clone Current",
      icon = "copy"
    }))

    -- Select Random
    table.insert(buttons, addButton(function()
      extensions.hook("onVehicleSelectorSelectRandom")


      -- get a random config that passes the filters
      local data = ui_vehicleSelector.getUiData()
      ui_vehicleSelector_filters.setupValidFilters()

      local validConfigs = {}
      for _, config in pairs(data.configs) do
        if not ui_vehicleSelector_filters.passesFilters({model = config.model_key, config = config.key}) then
          goto continue
        end
        table.insert(validConfigs, config)
        ::continue::
      end

      local randomConfig = validConfigs[math.random(1, #validConfigs)]
      local model = core_vehicles.getModel(randomConfig.model_key)

      local type = randomConfig.Type or model.model.Type

      local path = {keys = {'configsForBrandSubModelOrModel', randomConfig.model_key, randomConfig.subModel or "", randomConfig.brand or "", "Type", ui_vehicleSelector_tiles.groupModeFunctions["Type"](type)}}
      -- force select the random config next time the tiles are loaded
      ui_vehicleSelector_tiles.overrideDefaultSelectedTile(randomConfig)
      return {gotoPath = path}
    end, {
      label = "Select Random",
      icon = "arrowsShuffle"
    }))

    -- Reset all button
    table.insert(buttons, addButton(function()
      resetGameplay(-1)
      guihooks.trigger("ChangeState","play")
      extensions.hook("onVehicleSelectorResetAll")
    end, {
      label = "Reset All",
      icon = "carsWrench",
      accent = "main"
    }))

    -- Remove current button
    table.insert(buttons, addButton(function()
      core_vehicles.removeCurrent();
      extensions.hook("trackNewVeh")
      guihooks.trigger("ChangeState","play")
      extensions.hook("onVehicleSelectorRemoveCurrent")
    end, {
      label = "Remove Current",
      icon = "trashBin1",
      accent = "attention"
    }))

    -- Remove others button
    table.insert(buttons, addButton(function()
      core_vehicles.removeAllExceptCurrent();
      extensions.hook("trackNewVeh")
      guihooks.trigger("ChangeState","play")
      extensions.hook("onVehicleSelectorRemoveOthers")
    end, {
      label = "Remove Others",
      icon = "broom",
      accent = "attention"
    }))

    -- Remove all button
    table.insert(buttons, addButton(function()
      core_vehicles.removeAll();
      extensions.hook("trackNewVeh")
      guihooks.trigger("ChangeState","play")
      extensions.hook("onVehicleSelectorRemoveAll")
    end, {
      label = "Remove All",
      icon = "trashBin2",
      accent = "attention"
    }))
  end

  -- Get current vehicle details
  local currentVehicle = be:getPlayerVehicle(0)
  local managementDetails = {
    currentVehicleName = getVehicleName(currentVehicle),
    currentVehicleThumb = getCurrentVehicleThumb(currentVehicle)
  }

  return {
    buttonInfo = buttons,
    details = managementDetails
  }
end

local generalSpecifications = { "Years", "Country", "Power", "Weight", "Value", }
local specificationSetup = {
  {
    label = "Performance",
    aggregatesImperial = {
      'Power',
      'Torque',
      'Weight',
      'Top Speed',
      '0-60 mph',
      '0-100 mph',
      '0-200 mph',
      '60-100 mph',
      '60-0 mph',
      '0-100 km/h',
      'Braking G',
      'Weight/Power',
      "Performance Class",
      'Off-Road Score',
    },
    aggregatesMetric = {
      'Power',
      'Torque',
      'Weight',
      'Top Speed',
      '0-100 km/h',
      '0-200 km/h',
      '0-300 km/h',
      '100-200 km/h',
      '100-0 km/h',
      'Braking G',
      'Weight/Power',
      "Performance Class",
      'Off-Road Score',
    },
    aggregates = {


    }
  },
  {
    label = "Other",
    aggregates = {
      "Type",
      "Config Type",
      "Transmission",
      "Derby Class",
      "Drivetrain",
      'Propulsion',
      'Fuel Type',
      'Induction Type',
      'Commercial Class',
    }
  }
}
local aggregateToUnit = {
  ['0-60 mph'] = 'seconds',
  ['0-100 mph'] = 'seconds',
  ['0-200 mph'] = 'seconds',
  ['60-100 mph'] = 'seconds',
  ['60-0 mph'] = 'distanceMinor',
  ['0-100 km/h'] = 'seconds',
  ['0-200 km/h'] = 'seconds',
  ['0-300 km/h'] = 'seconds',
  ['100-200 km/h'] = 'seconds',
  ['100-0 km/h'] = 'distanceMinor',
  ['Braking G'] = 'g',
  ['Torque'] = 'torque',
  ['Power'] = 'power',
  ['Top Speed'] = 'speed',
  ['Weight'] = 'weight',
  ['Weight/Power'] = 'weightPower',
  ['Years'] = 'years',
  ['Value'] = 'money',
}

-- Unit conversion constants
local CONVERSIONS = {
  -- Speed conversions (m/s to other units)
  MPS_TO_KMH = 3.6,
  MPS_TO_MPH = 2.23693629,

  -- Power conversions
  BHP_TO_PS = 1.01387,     -- bhp to PS
  PS_TO_BHP = 0.98632, -- PS to bhp

  -- Torque conversions (Nm to lb-ft)
  NM_TO_LBFT = 0.737562149,

  -- Weight conversions (kg to lb)
  KG_TO_LB = 2.20462262,

  -- Distance conversions (m to ft)
  M_TO_FT = 3.2808399,

  -- Weight/Power ratio conversions
  KGPS_TO_LBBHP = 2.20462262 / 0.98632,  -- kg/PS to lb/bhp
}


local valueToUnit = {
  value = function(value)
    if type(value) == 'table' and value.min and value.max and type(value.min) == 'number' and type(value.max) == 'number' then
      return string.format("%0.2f - %0.2f", value.min, value.max)
    else
      return tostring(value)
    end
  end,
  years = function(value)
    if type(value) == 'table' and value.min and value.max and type(value.min) == 'number' and type(value.max) == 'number' then
      return string.format("%d - %d", value.min, value.max)
    else
      return tostring(value)
    end
  end,
  money = function(value)
    -- Format with comma separators for thousands and dot for decimals
    if not type(value) == 'number' then
      return tostring(value)
    end
    local formatted = string.format("%.2f", value)
    local integerPart, decimalPart = formatted:match("([^%.]+)%.?(.*)")

    -- Add comma separators to integer part
    local len = #integerPart
    local parts = {}
    for i = len, 1, -3 do
      local start = math.max(1, i - 2)
      table.insert(parts, 1, integerPart:sub(start, i))
    end

    local result = table.concat(parts, ",")
    if decimalPart and decimalPart ~= "" then
      result = result .. "." .. decimalPart
    end

    return "$"..result
  end,
  seconds = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    return string.format("%0.2f%s", value, " s")
  end,
  g = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    return string.format("%0.3f%s", value, "")
  end, -- omit g beacause its in the name
  kmh = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    return string.format("%0.2f%s", value * CONVERSIONS.MPS_TO_KMH, " km/h")
  end,
  mph = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    return string.format("%0.2f%s", value * CONVERSIONS.MPS_TO_MPH, " mph")
  end,
  torque = function(value, modelDetails, configDetails)
    if not type(value) == 'number' then
      return tostring(value)
    end
    local metricOrImperial = settings.getValue('uiUnitLength')
    local peakRPM = configDetails['TorquePeakRPM'] or modelDetails['TorquePeakRPM']
    local unit = metricOrImperial == 'metric' and 'Nm' or 'lb-ft'
    value = metricOrImperial == 'metric' and value or value * CONVERSIONS.NM_TO_LBFT
    local decimals = value >= 100 and 0 or (value >= 10 and 1 or 2)
    -- value is in Nm
    if peakRPM then
      return {{text = string.format("%0."..decimals.."f %s", value, unit)},{text=string.format("@ %s rpm", peakRPM), italic = true}}
    else
      return string.format("%0."..decimals.."f %s", value, unit)
    end
  end,
  power = function(value, modelDetails, configDetails)
    if not type(value) == 'number' then
      return tostring(value)
    end
    local metricOrImperial = settings.getValue('uiUnitLength')
    local peakRPM = configDetails['PowerPeakRPM'] or modelDetails['PowerPeakRPM']
    local unit = metricOrImperial == 'metric' and 'PS' or 'bhp'
    -- value is already in PS, convert to bhp for imperial
    value = metricOrImperial == 'metric' and value or (value * CONVERSIONS.PS_TO_BHP)
    local decimals = value >= 100 and 0 or (value >= 10 and 1 or 2)
    if peakRPM then
      return {{text = string.format("%0."..decimals.."f %s", value, unit)},{text=string.format("@ %s rpm", peakRPM), italic = true}}
    else
      return string.format("%0."..decimals.."f %s", value, unit)
    end
  end,
  speed = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    local metricOrImperial = settings.getValue('uiUnitLength')
    -- value is in m/s
    if metricOrImperial == 'metric' then
      return string.format("%0.2f%s", value * CONVERSIONS.MPS_TO_KMH, " km/h")
    else
      return string.format("%0.2f%s", value * CONVERSIONS.MPS_TO_MPH, " mph")
    end
  end,
  weightPower = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    local metricOrImperial = settings.getValue('uiUnitLength')
    if metricOrImperial == 'metric' then
      return string.format("%0.2f kg/PS", value)
    else
      -- Convert kg/PS to lb/bhp for imperial
      local imperialValue = value * CONVERSIONS.KGPS_TO_LBBHP
      return string.format("%0.2f lb/bhp", imperialValue)
    end
  end,
  weight = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    -- value is in kg
    local metricOrImperial = settings.getValue('uiUnitLength')
    local decimals = value >= 100 and 0 or (value >= 10 and 1 or 2)
    if metricOrImperial == 'metric' then
      return string.format("%0."..decimals.."f kg", value)
    else
      -- convert kg to lb
      local lbValue = value * CONVERSIONS.KG_TO_LB
      local lbDecimals = lbValue >= 100 and 0 or (lbValue >= 10 and 1 or 2)
      return string.format("%0."..lbDecimals.."f lb", lbValue)
    end
  end,
  distanceMinor = function(value)
    if not type(value) == 'number' then
      return tostring(value)
    end
    local metricOrImperial = settings.getValue('uiUnitLength')
    -- value is in m
    if metricOrImperial == 'metric' then
      return string.format("%0.2f m", value)
    else
      return string.format("%0.2f ft", value * CONVERSIONS.M_TO_FT)
    end
  end,
}

local postIcon = {
  money = "beamCurrency",
}

local function makeSpec(modelDetails, configDetails, key, list)
  local isFromConfig = true
  local value = configDetails[key]
  if value == nil then
    isFromConfig = false
    value = modelDetails[key]
  end
  if value == nil then return nil end

  local unit = aggregateToUnit[key] or 'value'
  table.insert(list, {
    key = key,
    value = valueToUnit[unit](value, modelDetails, configDetails),
    --postIcon = postIcon[unit],
    isFromConfig = isFromConfig
  })
end
local sourceIcons = {
  ["BeamNG - Official"] = "beamNG",
  ["Mod"] = "puzzleModule",
  ["Custom"] = "wrench",
}
local function addIconTags(modelDetails, configDetails)
  local iconTags = {}

  if configDetails.Drivetrain == "AWD" then
    table.insert(iconTags, {icon = "AWD", label = "Drivetrain: All Wheel Drive"})
  elseif configDetails.Drivetrain == "RWD" then
    table.insert(iconTags, {icon = "RWD", label = "Drivetrain: Rear Wheel Drive"})
  elseif configDetails.Drivetrain == "FWD" then
    table.insert(iconTags, {icon = "FWD", label = "Drivetrain: Front Wheel Drive"})
  elseif configDetails.Drivetrain == "4WD" then
    table.insert(iconTags, {icon = "4WD", label = "Drivetrain: 4 Wheel Drive"})
  elseif configDetails.Drivetrain and type(configDetails.Drivetrain) == 'string' and string.find(configDetails.Drivetrain, "x") then
    table.insert(iconTags, {iconText = string.gsub(configDetails.Drivetrain, "x", "×"), label = "Drivetrain: "..string.gsub(configDetails.Drivetrain, "x", "×")})
  end

  if configDetails['Transmission'] == "Manual" then
    table.insert(iconTags, {icon = "transmissionM", label = "Manual Transmission"})
  elseif configDetails['Transmission'] == "Automatic" then
    table.insert(iconTags, {icon = "transmissionA", label = "Automatic Transmission"})
  elseif configDetails['Transmission'] == "Sequential" then
    table.insert(iconTags, {icon = "twoArrowsHorizontal", label = "Sequential Transmission"})
  elseif configDetails['Transmission'] == "CVT" or configDetails['Transmission'] == "DCT" then
    table.insert(iconTags, {icon = "transmissionCvt", label = "Transmission: "..configDetails['Transmission']})
  end

  if configDetails['Induction Type'] == "NA" then
    table.insert(iconTags, {icon = "intakeTrumpets", label = "Naturally Aspirated"})
  elseif configDetails['Induction Type'] == "Turbo" then
    table.insert(iconTags, {icon = "turbine", label = "Turbocharged"})
  elseif configDetails['Induction Type'] == "Turbo + N2O" then
    table.insert(iconTags, {icon = "turbine", label = "Turbocharged"})
    table.insert(iconTags, {icon = "N2OHoriz", label = "N2O"})
  elseif configDetails['Induction Type'] == "SC" then
    table.insert(iconTags, {icon = "hydroPump2", label = "Supercharged"})
  elseif configDetails['Induction Type'] == "SC + N2O" then
    table.insert(iconTags, {icon = "hydroPump2", label = "Supercharged"})
    table.insert(iconTags, {icon = "N2OHoriz", label = "N2O"})
  end

  if configDetails['Fuel Type'] == "Battery" then
    table.insert(iconTags, {icon = "charge", label = "Energy Source: Battery"})
  elseif configDetails['Fuel Type'] == "Gasoline" or configDetails['Fuel Type'] == "Diesel" then
    table.insert(iconTags, {icon = "fuelPump", label = "Energy Source: "..configDetails['Fuel Type']})
  end


  return iconTags
end



-- Get detailed config information
local function getDetails(itemDetails)
  local modelKey = itemDetails.model
  local configKey = itemDetails.config
  local modelDetails = core_vehicles.getModel(modelKey).model
  local configDetails = core_vehicles.getConfig(modelKey, configKey)
  local metricOrImperial = settings.getValue('uiUnitLength')

  extensions.hook("onVehicleSelectorViewDetails", modelKey, configKey)

  local specificationsList = {}
  local uiData = ui_vehicleSelector.getUiData()
  if uiData.displayData.includeDevInfo then
    local devSpecs = {
      label = "Dev Info",
      icon = "bug",
      specifications = {
        {
          value =  modelKey .. " / " .. configKey,
        },
      }
    }
    if configDetails.infoFilename then
      table.insert(devSpecs.specifications, {
        value = configDetails.infoFilename,
        openFolder = true,
      })
      local mod = core_modmanager.getModFromPath(configDetails.infoFilename)
      if mod then
        table.insert(devSpecs.specifications, {
          value = mod.fullpath,
          openFolder = true,
        })
      end
    end
    --MQFJ5LEYA

    if configDetails.pcFilename then
      table.insert(devSpecs.specifications, {
        value = configDetails.pcFilename,
        openFolder = true,
      })
    end
    if configDetails.preview then
      table.insert(devSpecs.specifications, {
        value = configDetails.preview,
        openFolder = true,
      })
    end
    if configDetails.Region then
      table.insert(devSpecs.specifications, {
        key = "Region",
        value = dumps(configDetails.Region),
      })
    end
    if configDetails.isAuxiliary then
      table.insert(devSpecs.specifications, {
        key = "Is Auxiliary",
        value = "Yes",
        postIcon = "bug",
      })
    end
    table.insert(specificationsList, devSpecs)
  end

  for _, specificationGroup in ipairs(specificationSetup) do
    local group = {}
    group.label = specificationGroup.label
    group.specifications = {}
    if metricOrImperial == 'metric' then
      for _, specification in ipairs(specificationGroup.aggregatesMetric or {}) do
        makeSpec(modelDetails, configDetails, specification, group.specifications)
      end
    else
      for _, specification in ipairs(specificationGroup.aggregatesImperial or {}) do
        makeSpec(modelDetails, configDetails, specification, group.specifications)
      end
    end
    for _, specification in ipairs(specificationGroup.aggregates) do
      makeSpec(modelDetails, configDetails, specification, group.specifications)
    end
    if next(group.specifications) then
      table.insert(specificationsList, group)
    end
  end

  local generalSpecs = {}
  for _, specification in ipairs(generalSpecifications) do
    makeSpec(modelDetails, configDetails, specification, generalSpecs)
  end

  local iconTags = addIconTags(modelDetails, configDetails)

  local paintData = {
    multiPaintSetups = {},
    factoryPaints = {},
  }
  for _, multiPaintSetup in ipairs(modelDetails.multiPaintSetups) do
    if multiPaintSetup.usedByConfigByKey[configKey] or multiPaintSetup.forAllConfigs then
      local setup = deepcopy(multiPaintSetup)
      if setup.isDefaultForConfigByKey[configKey] then
        setup.isDefault = true
      end
      table.insert(paintData.multiPaintSetups, setup)
    end
  end
  for _, paint in pairs(modelDetails.paints) do
    table.insert(paintData.factoryPaints, paint)
  end
  table.sort(paintData.factoryPaints, function(a, b)
    return a.name < b.name
  end)

  -- Clear previous button functions before creating new ones
  clearButtonFunctions()

  local buttonInfo = {}

  -- Use custom details buttons if provided (for challenge mode)
  if M.customDetailsButtons then
    for _, button in ipairs(M.customDetailsButtons) do
      table.insert(buttonInfo, addButton(function()
        button.callback(modelKey, configKey)
      end, button.meta))
    end
  else
    -- Use standard button info for freeroam mode
    buttonInfo = makeSpawningButtons(configDetails)
  end

  local tags = {}

  local source = configDetails.Source or modelDetails.Source
  if source == "BeamNG - Official" then
    table.insert(tags, {icon = "beamNG", label = "BeamNG - Official"})
  elseif source == "Custom" then
    table.insert(tags, {icon = "wrench", label = "Custom"})
  end

  local type = configDetails.Type or modelDetails.Type
  if type == "Automation" then
    table.insert(tags, {svg = "/ui/assets/Original/camshaft_automation_logo.svg", label = "Automation"})
  end
  if configDetails.modID then
    local mod = core_modmanager.getModNameFromID(configDetails.modID)
    if mod then
      table.insert(tags, {icon = "puzzleModule", label = configDetails.Source, goToMod = mod.modID})
    end
  end
  if configDetails.isAuxiliary then
    table.insert(tags, {icon = "bug", label = "Auxiliary", auxiliary = true})
  end
  if modelDetails.missingJbeamFiles then
    table.insert(tags, {icon = "danger", label = "Missing JBeam Files"})
  end



  return {
    configDetails = configDetails,
    buttonInfo = buttonInfo,
    isFavourite = ui_vehicleSelector.isFavourite(modelKey, configKey),
    tags = tags,
    isStandalonePC = not configDetails.infoFilename,
    modelKey = modelKey,
    configKey = configKey,
    specificationsList = specificationsList,
    iconTags = iconTags,
    generalSpecs = generalSpecs,
    paints = paintData,
  }
end

local function executeDoubleClick(itemDetails)
  local details = M.getDetails(itemDetails)
  if details and details.buttonInfo then
    for _, button in ipairs(details.buttonInfo) do
      if (button.isDoubleClickAction) or #details.buttonInfo == 1 then
        M.executeButton(button.buttonId)
        return
      end
    end
  end
end

-- Set management buttons enabled/disabled state
local function setManagementButtonsEnabled(enabled)
  M.managementButtonsEnabled = enabled
end

-- Set details button for freeroam mode
local function setDetailsButtonForFreeroam(enabled)
  M.detailsButtonForFreeroam = enabled
end

-- Set custom details buttons for challenge mode
local function setCustomDetailsButtons(buttons)
  M.customDetailsButtons = buttons
end

local function setExitCallback(callback)
  M.exitCallback = callback or nop
end
M.setExitCallback = setExitCallback
M.exitCallback = nop

local function exploreFolder(path)
  Engine.Platform.exploreFolder(path)
end
M.exploreFolder = exploreFolder

local function goToMod(modId)
  guihooks.trigger('ChangeState', {state = 'menu.mods.details', params = {modId = modId}})
end
M.goToMod = goToMod

-- Assign functions to module
M.getFreeButtonId = getFreeButtonId
M.clearButtonFunctions = clearButtonFunctions
M.addButton = addButton
M.executeButton = executeButton
M.makeSpawningButtons = makeSpawningButtons
M.getDetails = getDetails
M.getManagementDetails = getManagementDetails
M.getVehicleName = getVehicleName
M.getCurrentVehicleThumb = getCurrentVehicleThumb
M.onScreenFadeState = onScreenFadeState
M.setManagementButtonsEnabled = setManagementButtonsEnabled
M.setDetailsButtonForFreeroam = setDetailsButtonForFreeroam
M.setCustomDetailsButtons = setCustomDetailsButtons
M.executeDoubleClick = executeDoubleClick

return M