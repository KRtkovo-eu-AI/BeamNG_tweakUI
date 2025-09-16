-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.dependencies = {'career_career', 'career_modules_payment', 'career_modules_playerAttributes'}

local plInsuranceData
local plInsuranceHistory

local insuranceData = {
  name = "Insurance",
  insuranceScoreIncreasePerRepair = 0.05,
  minimumInsuranceScore = 0.5,
  insuranceScoreDecreaseEvery = 20000,
  insuranceScoreDecreaseAmount = 0.05,
  baseRepairCost = 500,
  resetInsuranceScorePrice = {money = {amount = 1000, canBeNegative = false}},
  resetInsuranceScoreMinScore = 1.5,
}


local plInsuranceDataFileName = "insurance"

local testDriveClaimPrice = {money = { amount = 500, canBeNegative = true}}
local quickRepairExtraPrice = 1000

-- to calculate distance driven
local vec3Zero = vec3(0,0,0)
local lastPos = vec3(0,0,0)

local function savePoliciesData(currentSavePath)
  local dataToSave =
  {
    plInsuranceData = plInsuranceData,
    plInsuranceHistory = plInsuranceHistory,
  }

  career_saveSystem.jsonWriteFileSafe(currentSavePath .. "/career/"..plInsuranceDataFileName..".json", dataToSave, true)
end

local function setDefaultPlData()
  plInsuranceHistory = {
    claims = {},
    testDriveClaims = {},
    insuranceScoreDecreases = {},
  }
  plInsuranceData = {
    insuranceScore = 1,
    metersToDriveToInsuranceScoreDecrease = insuranceData.insuranceScoreDecreaseEvery,
  }
end

local function loadPoliciesData()
  local saveSlot, savePath = career_saveSystem.getCurrentSaveSlot()
  if not saveSlot then return end

  local savedPlInsuranceData = (savePath and jsonReadFile(savePath .. "/career/"..plInsuranceDataFileName..".json"))
  local saveInfo = jsonReadFile(savePath .. "/info.json")

  if savedPlInsuranceData == nil or saveInfo.version < career_saveSystem.getSaveSystemVersion() then -- first load ever or old save that needs to be reset
    setDefaultPlData()
  else
    plInsuranceHistory = savedPlInsuranceData.plInsuranceHistory
    plInsuranceData = savedPlInsuranceData.plInsuranceData
  end
end

local function inventoryVehNeedsRepair(vehInvId)
  local vehInfo = career_modules_inventory.getVehicles()[vehInvId]
  if not vehInfo then return end
  return career_modules_valueCalculator.partConditionsNeedRepair(vehInfo.partConditions)
end

local function repairPartConditions(data)
  if not data.partConditions then return end
  if data.paintRepair == nil then data.paintRepair = true end

  for partPath, info in pairs(data.partConditions) do
    if info.integrityValue then
      if info.integrityValue == 0 then

        local inventoryPart
        if data.inventoryId then
          local partId = career_modules_partInventory.getPartPathToPartIdMap()[data.inventoryId][partPath]
          inventoryPart = career_modules_partInventory.getInventory()[partId]
          inventoryPart.repairCount = inventoryPart.repairCount or 0
          inventoryPart.repairCount = inventoryPart.repairCount + 1
          local vehicle = career_modules_inventory.getVehicles()[data.inventoryId]
          vehicle.changedSlots[inventoryPart.containingSlot] = true
        end

        -- reset the paint
        if info.visualState then
          if info.visualState.paint and info.visualState.paint.originalPaints then
            if data.paintRepair then
              info.visualState = {paint = {originalPaints = info.visualState.paint.originalPaints}}
            else
              local numberOfPaints = tableSize(info.visualState.paint.originalPaints)
              info.visualState = {paint = {originalPaints = {}}}
              for index = 1, numberOfPaints do
                info.visualState.paint.originalPaints[index] = career_modules_painting.getPrimerColor()
              end

              if inventoryPart then
                inventoryPart.primered = true
              end
            end
            info.visualState.paint.odometer = 0
          else
            -- if we dont have a replacement paint, just set visualState to nil
            info.visualState = nil
            info.visualValue = 1
          end
        end
      end

      if info.integrityState and info.integrityState.energyStorage then
        -- keep the fuel level
        for _, tankData in pairs(info.integrityState.energyStorage) do
          for attributeName, value in pairs(tankData) do
            if attributeName ~= "storedEnergy" then
              tankData[attributeName] = nil
            end
          end
        end
      else
        info.integrityState = nil
      end
      info.integrityValue = 1
    end
  end
end

local function makeRepairClaim(invVehId, price, addedInsuranceScore)
  local totalAddedInsuranceScore = (addedInsuranceScore or 0) + insuranceData.insuranceScoreIncreasePerRepair
  plInsuranceData.insuranceScore = plInsuranceData.insuranceScore + totalAddedInsuranceScore

  local claim = {
    deductible = price,
    newInsuranceScore = plInsuranceData.insuranceScore,
    insuranceScoreChange = totalAddedInsuranceScore,
    vehInfo = {
      niceName = career_modules_inventory.getVehicles()[invVehId].niceName,
    },
    time = os.time(),
  }

  plInsuranceData.metersToDriveToInsuranceScoreDecrease = insuranceData.insuranceScoreDecreaseEvery

  table.insert(plInsuranceHistory.claims, claim)
  extensions.hook("onInsuranceRepairClaim")
end

-- when you damage a test drive vehicle, insurance needs to know
local function makeTestDriveDamageClaim(vehId)
  local label = string.format("Test drive vehicle damaged: -%i$", testDriveClaimPrice.money.amount)
  ui_message(label, '4', 'testDriveDamage')

  career_modules_payment.pay(testDriveClaimPrice, {label = label})
  local claim = {
    time = os.time(),
    price = testDriveClaimPrice,
    vehName = "ibishu n"
  }

  table.insert(plInsuranceHistory.testDriveClaims, claim)
end


local function onAfterVehicleRepaired(vehInfo)
  career_modules_inventory.setVehicleDirty(vehInfo.id)
  local vehId = career_modules_inventory.getVehicleIdFromInventoryId(vehInfo.id)
  if vehId then
    career_modules_fuel.minimumRefuelingCheck(vehId)
    if gameplay_walk.isWalking() then
      local veh = getObjectByID(vehId)
      gameplay_walk.setRot(veh:getPosition() - getPlayerVehicle(0):getPosition())
    end
  end

  career_saveSystem.saveCurrent({vehInfo.id})
end

local startRepairVehInfo
local function startRepairDelayed(vehInfo, repairTime)
  if career_modules_inventory.getVehicleIdFromInventoryId(vehInfo.id) then -- vehicle is currently spawned
    if vehInfo.id == career_modules_inventory.getCurrentVehicle() then
      startRepairVehInfo = {inventoryId = vehInfo.id, repairTime = repairTime}
      gameplay_walk.setWalkingMode(true)
      return -- This function gets called again after the player left the vehicle
    end
    career_modules_inventory.removeVehicleObject(vehInfo.id)
  end
  career_modules_inventory.delayVehicleAccess(vehInfo.id, repairTime, "repair")
  onAfterVehicleRepaired(vehInfo)
end

local function missionStartRepairCallback(vehInfo)
  guihooks.trigger('MenuOpenModule','menu.careermission')
  guihooks.trigger('gameContextPlayerVehicleDamageInfo', {needsRepair = inventoryVehNeedsRepair(vehInfo.id)})
end

local function startRepairInstant(vehInfo, callback, skipSound)
  if not skipSound then
    Engine.Audio.playOnce('AudioGui', 'event:>UI>Missions>Vehicle_Recover')
  end

  if career_modules_inventory.getVehicleIdFromInventoryId(vehInfo.id) then -- vehicle is currently spawned
    career_modules_inventory.spawnVehicle(vehInfo.id, 2, callback and
    function()
      callback(vehInfo)
      onAfterVehicleRepaired(vehInfo)
    end)
    if callback then return end
  end
  onAfterVehicleRepaired(vehInfo)
end


local function startRepair(inventoryId, repairOptionData, callback)
  inventoryId = inventoryId or career_modules_inventory.getCurrentVehicle()
  repairOptionData = (repairOptionData and type(repairOptionData) == "table") and repairOptionData or {}

  local vehInfo = career_modules_inventory.getVehicles()[inventoryId]
  if not vehInfo then return end

  if repairOptionData.price then
    career_modules_payment.pay(repairOptionData.price, {label="Repaired a vehicle: id " .. inventoryId})
    Engine.Audio.playOnce('AudioGui', 'event:>UI>Career>Buy_01')
  end

  if repairOptionData.useInsurance then -- the player can repair on his own without insurance
    makeRepairClaim(inventoryId, repairOptionData.price, repairOptionData.addedInsuranceScoreIncrease)
  end

  -- the actual repair
  local paintRepair = repairOptionData.useInsurance
  local data = {
    partConditions = vehInfo.partConditions,
    paintRepair = paintRepair,
    inventoryId = inventoryId
  }
  repairPartConditions(data)


  M.closeMenu(true)
  if (repairOptionData.repairTime or 0) > 0 then
    startRepairDelayed(vehInfo, repairOptionData.repairTime)
  else
    startRepairInstant(vehInfo, callback, false)
  end
end


local function startRepairInGarage(vehInvInfo, repairOptionData)
  local price = {}

  -- format
  local key, value = next(repairOptionData.price)
  price[key] = {amount = value.amount, canBeNegative = repairOptionData.canBeNegative}
  repairOptionData.price = price

  local vehId = career_modules_inventory.getVehicleIdFromInventoryId(vehInvInfo.id)
  extensions.hook("onRepairInGarage", vehInvInfo)
  return startRepair(vehInvInfo.id, repairOptionData, (vehId and repairOptionData.repairTime<= 0) and
    function(vehInfo)
      local vehObj = getObjectByID(vehId)
      if not vehObj then return end
      freeroam_facilities.teleportToGarage(career_modules_inventory.getClosestGarage().id, vehObj, false)
    end)
end

local function genericVehNeedsRepair(vehId, callback)
  local veh = getObjectByID(vehId)
  if not veh then return end

  core_vehicleBridge.requestValue(veh,
    function(res)
      local needsRepair = career_modules_valueCalculator.partConditionsNeedRepair(res.result)
      callback(needsRepair)
    end,
    'getPartConditions')
end

local helper = {}
local function showMessage(message)
  helper = {
    ttl = 3,
    msg = message,
    category = "t",
    clear = false
  }
  guihooks.trigger('Message',helper)
end


local function decreaseInsuranceScore()
  plInsuranceData.insuranceScore = plInsuranceData.insuranceScore - insuranceData.insuranceScoreDecreaseAmount
  if plInsuranceData.insuranceScore < insuranceData.minimumInsuranceScore then
    plInsuranceData.insuranceScore = insuranceData.minimumInsuranceScore
  end
  plInsuranceData.metersToDriveToInsuranceScoreDecrease = insuranceData.insuranceScoreDecreaseEvery
  table.insert(plInsuranceHistory.insuranceScoreDecreases, {time = os.time(), change = -insuranceData.insuranceScoreDecreaseAmount, newValue = plInsuranceData.insuranceScore})

  showMessage("Insurance not sollicited, insurance penalty score decreased to " .. plInsuranceData.insuranceScore)
end

-- used to renew insurance policies
local function updateDistanceDriven(dtReal)
  local plId = be:getPlayerVehicleID(0)
  if not career_modules_inventory.getInventoryIdFromVehicleId(plId) then return end

  local vehicleData = map.objects[plId]
  if not vehicleData then return end

  if lastPos ~= vec3Zero then
    local dist = lastPos:distance(vehicleData.pos)
    if(dist < 0.001) then return end --should use some dt to more accurately discard low numbers when stationary

    plInsuranceData.metersToDriveToInsuranceScoreDecrease = plInsuranceData.metersToDriveToInsuranceScoreDecrease - dist
    if plInsuranceData.metersToDriveToInsuranceScoreDecrease <= 0 then
      decreaseInsuranceScore()
    end
  end

  lastPos:set(vehicleData.pos)
end


local originComputerId
local vehicleToRepairData
-- used in the garage computer
local function getRepairData()
  local data = {}
  local vehInfo = deepcopy(vehicleToRepairData)

  vehInfo.thumbnail = career_modules_inventory.getVehicleThumbnail(vehInfo.id) .. "?" .. (vehInfo.dirtyDate or "")

  local repairDetails = career_modules_valueCalculator.getRepairDetails(vehInfo)

  -- base prices
  local basePrivateMoneyPrice = repairDetails.price
  local baseInsuranceMoneyPrice = insuranceData.baseRepairCost * plInsuranceData.insuranceScore

  -- quick repair prices (with surcharge)
  local quickPrivateMoneyPrice = basePrivateMoneyPrice + quickRepairExtraPrice
  local quickInsuranceMoneyPrice = baseInsuranceMoneyPrice + quickRepairExtraPrice -- Insurance covers quick repair surcharge

  -- price structures for different combinations
  local voucherPrice = {vouchers = { amount = 1, canBeNegative = false}}
  local privateMoneyPrice = {money = { amount = basePrivateMoneyPrice, canBeNegative = false}}
  local privateQuickMoneyPrice = {money = { amount = quickPrivateMoneyPrice, canBeNegative = false}}
  local insuranceMoneyPrice = {money = { amount = baseInsuranceMoneyPrice, canBeNegative = true}}
  local insuranceQuickMoneyPrice = {money = { amount = quickInsuranceMoneyPrice, canBeNegative = true}}

  voucherPrice.vouchers.canPay = career_modules_payment.canPay(voucherPrice)
  privateMoneyPrice.money.canPay = career_modules_payment.canPay(privateMoneyPrice)
  privateQuickMoneyPrice.money.canPay = career_modules_payment.canPay(privateQuickMoneyPrice)
  insuranceMoneyPrice.money.canPay = career_modules_payment.canPay(insuranceMoneyPrice)
  insuranceQuickMoneyPrice.money.canPay = career_modules_payment.canPay(insuranceQuickMoneyPrice)

  local newRepairOptions = {
    isCarDamaged = repairDetails.price > 0,
    options = {
      repairMethods = {
        choices = {
          insuranceRepair = {
            icon = "shieldCheckmark",
            order = 1,
            choiceLabel = "Insurance",
            name = "Insurance",
            description = "Repair your vehicle using the insurance.",
            costLabel = "Deductible",
            baseInsuranceScoreIncrease = insuranceData.insuranceScoreIncreasePerRepair,
            useInsurance = true,
          },
          privateRepair = {
            icon = "wrench",
            order = 2,
            choiceLabel = "Private",
            name = "Private",
            description = "Repair your vehicle using your own money.",
            costLabel = "Repair cost",
            useInsurance = false,
          },
        }
      },
      repairTypes = {
        name = "Repair types",
        choices = {
          quickRepair = {
            order = 2,
            choiceLabel = "Quick repair",
            name = "Quick",
            description = "Repair your vehicle quickly.",
            repairTime = 0,
            effects = {
              insuranceRepair = {
                insuranceScoreIncrease = 0.05,
              },
              privateRepair = {
                addedMoneyPrice = quickRepairExtraPrice,
              }
            }
          },
          standardRepair = {
            order = 1,
            choiceLabel = "Standard repair (10 Min.)",
            name = "Standard",
            description = "Repair your vehicle at a normal speed.",
            repairTime = 600,
          },
        }
      },
      paymentOptions = {
        name = "Payment options",
        choices = {
          payWithMoney = {
            order = 1,
            name = "Money",
            choiceLabel = "Pay with money",
            prices = {
              insurance = {
                standard = insuranceMoneyPrice,
                quick = insuranceQuickMoneyPrice
              },
              private = {
                standard = privateMoneyPrice,
                quick = privateQuickMoneyPrice
              }
            }
          },
          payWithVouchers = {
            order = 2,
            name = "Vouchers",
            choiceLabel = "Pay with vouchers",
            prices = {
              insurance = {
                standard = voucherPrice,
                quick = voucherPrice
              },
              private = {
                standard = voucherPrice,
                quick = voucherPrice
              }
            }
          }
        }
      }
    }
  }

  data.newRepairOptions = newRepairOptions
  data.currentDeductible = insuranceData.baseRepairCost * plInsuranceData.insuranceScore
  data.baseDeductible = insuranceData.baseRepairCost
  data.insuranceScore = plInsuranceData.insuranceScore
  data.vehicle = vehInfo
  data.playerAttributes = career_modules_playerAttributes.getAllAttributes()
  data.numberOfBrokenParts = career_modules_valueCalculator.getNumberOfBrokenParts(career_modules_inventory.getVehicles()[vehInfo.id].partConditions)
  return data
end

local insurancePoliciesMenuOpen = false
local closeMenuAfterSaving

local function onUpdate(dtReal, dtSim, dtRaw)
  if not gameplay_missions_missionManager.getForegroundMissionId() and not gameplay_walk.isWalking() then -- we don't track when in a mission
    updateDistanceDriven(dtReal)
  end
end

local function onEnterVehicleFinished()
  if startRepairVehInfo then
    local vehInfo = career_modules_inventory.getVehicles()[startRepairVehInfo.vehId]
    career_modules_inventory.removeVehicleObject(startRepairVehInfo.vehId)
    startRepairDelayed(vehInfo)
    startRepairVehInfo = nil
  end
end

local function onCareerModulesActivated(alreadyInLevel)
  loadPoliciesData()
end

local function onSaveCurrentSaveSlot(currentSavePath)
  savePoliciesData(currentSavePath)
end

local function sortByTimeReverse(a,b) return a.time > b.time end
local function buildInsuranceHistory()
  local list = {}

  -- repair claims event
  for _, claim in ipairs(plInsuranceHistory.claims) do
    local effectText = {}
    for currency, amount in pairs(claim.deductible) do
      table.insert(effectText, {
        label = currency == "money" and "Money" or "Bonus star",
        value = -amount.amount
      })
    end
    table.insert(effectText, {
      label = "Insurance score changed",
      value = ((claim.insuranceScoreChange > 0 and "+ ") or "") .. claim.insuranceScoreChange,
    })
    table.insert(effectText, {
      label = "New Insurance score",
      value = claim.newInsuranceScore
    })
    table.insert(list, {
      time = os.date("%c",claim.time),
      event = translateLanguage("insurance.history.event.vehicleRepaired.name", "insurance.history.event.vehicleRepaired.name", true) .. claim.vehInfo.niceName,
      effect = effectText
    })
  end

  -- insurance score decrease events
  for _, bonusDecreaseEvent in ipairs(plInsuranceHistory.insuranceScoreDecreases) do
    local effectText = {
      {
        label = "Insurance score changed",
        value = ((bonusDecreaseEvent.change > 0 and "+ ") or "") .. bonusDecreaseEvent.change,
      },
      {
        label = "New Insurance score",
        value = bonusDecreaseEvent.newValue,
      },
    }
    table.insert(list, {
      time = os.date("%c",bonusDecreaseEvent.time),
      event = translateLanguage("insurance.history.event.insuranceScoreDecreased.name", "insurance.history.event.insuranceScoreDecreased.name", true),
      effect = effectText
    })
  end

  table.sort(list, sortByTimeReverse)

  return list
end

local function sendUIData()
  insurancePoliciesMenuOpen = true

  local data =
  {
    plInsuranceData = plInsuranceData,
    plInsuranceHistory = buildInsuranceHistory(),
    careerMoney = career_modules_playerAttributes.getAttributeValue("money"),
    careerVouchers = career_modules_playerAttributes.getAttributeValue("vouchers"),
  }

  guihooks.trigger('insurancePoliciesData', data)
end

local function openRepairMenu(vehicle, _originComputerId)
  vehicleToRepairData = vehicle
  originComputerId = _originComputerId
  guihooks.trigger('ChangeState', {state = 'repair', params = {}})
end


-- close the insurances computer menu
local function closeMenu(_closeMenuAfterSaving)
  closeMenuAfterSaving = career_career.isAutosaveEnabled() and _closeMenuAfterSaving

  if not closeMenuAfterSaving then
    if originComputerId then
      local computer = freeroam_facilities.getFacility("computer", originComputerId)
      career_modules_computer.openMenu(computer)
    else
      career_career.closeAllMenus()
    end
  end
end

local function onVehicleSaveFinished()
  if closeMenuAfterSaving then
    closeMenu()
    closeMenuAfterSaving = nil
  end
end

-- open the insurances computer menu
local function openMenu(_originComputerId)
  originComputerId = _originComputerId
  if originComputerId then
    guihooks.trigger('ChangeState', {state = 'insurancePolicies', params = {}})
    extensions.hook("onComputerInsurance")
  end
end

local function onExitInsurancePoliciesList()
  insurancePoliciesMenuOpen = false
end

local function onComputerAddFunctions(menuData, computerFunctions)
  if menuData.computerFacility.functions["insurancePolicies"] then
    local computerFunctionData = {
      id = "insurancePolicies",
      label = "Vehicle Insurance",
      callback = function() openMenu(menuData.computerFacility.id) end,
      order = 15
    }
    if menuData.tutorialPartShoppingActive or menuData.tutorialTuningActive then
      computerFunctionData.disabled = true
      computerFunctionData.reason = career_modules_computer.reasons.tutorialActive
    end
    computerFunctions.general[computerFunctionData.id] = computerFunctionData
  end

  if menuData.computerFacility.functions["vehicleInventory"] then
    for _, vehicleData in ipairs(menuData.vehiclesInGarage) do
      local inventoryId = vehicleData.inventoryId
      local computerFunctionData = {
        id = "repair",
        label = "Repair",
        callback = function() openRepairMenu(career_modules_inventory.getVehicles()[inventoryId], menuData.computerFacility.id) end,
        order = 5
      }
      -- tutorial
      if menuData.tutorialPartShoppingActive or menuData.tutorialTuningActive then
        computerFunctionData.disabled = true
        computerFunctionData.reason = {
          type = "text",
          label = "Disabled during tutorial. Use the recovery prompt instead."
        }
      end

      -- generic gameplay reason
      local reason = career_modules_permissions.getStatusForTag({"vehicleRepair"}, {inventoryId = inventoryId})
      if not reason.allow then
        computerFunctionData.disabled = true
      end
      if reason.permission ~= "allowed" then
        computerFunctionData.reason = reason
      end

      computerFunctions.vehicleSpecific[inventoryId][computerFunctionData.id] = computerFunctionData
    end
  end
end

local function payInsuranceScoreReset()
  if plInsuranceData.insuranceScore > insuranceData.resetInsuranceScoreMinScore and career_modules_payment.canPay(insuranceData.resetInsuranceScorePrice) then
    local label = string.format("Insurance score decreased.")
    career_modules_payment.pay(insuranceData.resetInsuranceScorePrice, {label=label})
    plInsuranceData.insuranceScore = 1
    sendUIData()
  end
end

M.getInsuranceDeductible = function(vehInvId)
  return insuranceData.baseRepairCost
end

M.getRepairTime = function(vehInvId)
  return 500
end

local function getQuickRepairExtraPrice()
  return quickRepairExtraPrice
end

local function expediteRepair(inventoryId, price)
  if career_modules_payment.pay({money = {amount = price, canBeNegative = false}}, {label="Expedited repair"}) then
    local vehInfo = career_modules_inventory.getVehicles()[inventoryId]
    vehInfo.timeToAccess = nil
    vehInfo.delayReason = nil
    career_modules_inventory.setVehicleDirty(inventoryId)
  end
end

M.isRoadSideAssistanceFree = function(invVehId)
  return true
end

-- For UI

M.getTestDriveClaimPrice = function()
  return testDriveClaimPrice.money.amount
end
M.getPlHistory = function()
  return plInsuranceHistory
end

M.genericVehNeedsRepair = genericVehNeedsRepair
M.makeRepairClaim = makeRepairClaim
M.makeTestDriveDamageClaim = makeTestDriveDamageClaim
M.startRepairInstant = startRepairInstant
M.startRepair = startRepair
M.inventoryVehNeedsRepair = inventoryVehNeedsRepair
M.missionStartRepairCallback = missionStartRepairCallback
M.openRepairMenu = openRepairMenu
M.getRepairData = getRepairData
M.closeMenu = closeMenu
M.repairPartConditions = repairPartConditions
M.payInsuranceScoreReset = payInsuranceScoreReset
M.getQuickRepairExtraPrice = getQuickRepairExtraPrice
M.expediteRepair = expediteRepair

M.startRepairInGarage = startRepairInGarage
M.openMenu = openMenu
M.sendUIData = sendUIData

-- hooks
M.onUpdate = onUpdate
M.onCareerModulesActivated = onCareerModulesActivated
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onComputerAddFunctions = onComputerAddFunctions
M.onEnterVehicleFinished = onEnterVehicleFinished
M.onExitInsurancePoliciesList = onExitInsurancePoliciesList
M.onVehicleSaveFinished = onVehicleSaveFinished

-- career debug
M.resetPlPolicyData = function()
  setDefaultPlData()
end

return M