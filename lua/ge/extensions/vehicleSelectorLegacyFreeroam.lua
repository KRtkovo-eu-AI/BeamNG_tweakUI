local M = {}
M.dependencies = {"core_vehicles", "ui_vehicleSelector", "ui_missionInfo"}

local logTag = "vehicleSelectorLegacyFreeroam"

local patchedCore = false
local patchedUi = false

local originalCoreOpenSelector
local originalUiOpenFreeroam
local originalUiOpenFreeroamWithMod

local selectionContext
local selectionActive = false

local function openLegacyFreeroam()
  local vehicles = extensions.core_vehicles
  if not vehicles or not vehicles.openSelectorUI_legcay then
    log("E", logTag, "Legacy vehicle selector is not available")
    return
  end

  vehicles.openSelectorUI_legcay()
  extensions.hook("onVehicleSelectorOpen")
end

local function openModernFreeroam(modId)
  if modId and originalUiOpenFreeroamWithMod then
    originalUiOpenFreeroamWithMod(modId)
    return
  end

  if originalUiOpenFreeroam then
    originalUiOpenFreeroam()
    return
  end

  if originalCoreOpenSelector then
    originalCoreOpenSelector()
    return
  end

  log("E", logTag, "Modern vehicle selector entry point unavailable")
end

local function closeSelectionDialog()
  local missionInfo = extensions.ui_missionInfo
  if missionInfo and missionInfo.closeDialogue then
    missionInfo.closeDialogue()
  end
end

local function finalizeSelection(choice)
  local context = selectionContext or {}
  selectionContext = nil
  selectionActive = false

  closeSelectionDialog()

  if choice == "legacy" then
    if context.modId then
      log("I", logTag, string.format("Opening legacy selector (ignoring mod filter '%s')", tostring(context.modId)))
    end
    openLegacyFreeroam()
  else
    openModernFreeroam(context.modId)
  end
end

local function commandForChoice(choice)
  return string.format("extensions.vehicleSelectorLegacyFreeroam.choose(%q)", choice)
end

local function showSelectionDialog(context)
  local missionInfo = extensions.ui_missionInfo
  if not missionInfo or not missionInfo.openDialogue then
    log("W", logTag, "Mission info UI unavailable, opening modern selector by default")
    openModernFreeroam(context and context.modId)
    return
  end

  if selectionActive then
    selectionContext = nil
    selectionActive = false
    closeSelectionDialog()
  end

  selectionContext = context or {}
  selectionActive = true

  local description
  if selectionContext.modId then
    description = string.format("Mod filter: %s. Choose which selector to open (legacy ignores filter).", tostring(selectionContext.modId))
  else
    description = "Choose which vehicle selector interface to open."
  end

  local content = {
    title = "Vehicle Selector",
    typeName = description,
    buttons = {
      {
        action = "legacy",
        text = "Classic (0.36)",
        cmd = commandForChoice("legacy")
      },
      {
        action = "modern",
        text = "Modern (0.37)",
        cmd = commandForChoice("modern")
      }
    }
  }

  missionInfo.openDialogue(content)
end

local function openChoiceFreeroam()
  showSelectionDialog()
end

local function openChoiceFreeroamWithMod(modId)
  showSelectionDialog({modId = modId})
end

function M.choose(choice)
  if not selectionActive then
    log("W", logTag, string.format("Received selection '%s' without an active dialog", tostring(choice)))
    if choice == "legacy" then
      openLegacyFreeroam()
    else
      openModernFreeroam()
    end
    return
  end

  finalizeSelection(choice)
end

local function patchCore()
  if patchedCore then return true end

  local vehicles = extensions.core_vehicles
  if not vehicles then
    return false
  end

  originalCoreOpenSelector = originalCoreOpenSelector or vehicles.openSelectorUI
  vehicles.openSelectorUI = openChoiceFreeroam
  patchedCore = true
  return true
end

local function patchUi()
  if patchedUi then return true end

  local uiSelector = extensions.ui_vehicleSelector
  if not uiSelector then
    return false
  end

  originalUiOpenFreeroam = originalUiOpenFreeroam or uiSelector.openVehicleSelectorForFreeroam
  originalUiOpenFreeroamWithMod = originalUiOpenFreeroamWithMod or uiSelector.openVehicleSelectorForFreeroamWithMod

  uiSelector.openVehicleSelectorForFreeroam = openChoiceFreeroam

  if uiSelector.openVehicleSelectorForFreeroamWithMod then
    uiSelector.openVehicleSelectorForFreeroamWithMod = openChoiceFreeroamWithMod
  end

  patchedUi = true
  log("I", logTag, "Freeroam vehicle selector now offers legacy and modern options")
  return true
end

local function applyPatch()
  local coreDone = patchCore()
  local uiDone = patchUi()

  return coreDone and uiDone
end

function M.onMissionInfoChangedState(_, newState)
  if newState == "closed" and selectionActive then
    selectionActive = false
    selectionContext = nil
  end
end

function M.onExtensionLoaded()
  patchedCore = false
  patchedUi = false
  applyPatch()
end

function M.onUpdate(dt)
  if patchedCore and patchedUi then return end
  applyPatch()
end

function M.onClientStartMission()
  patchedCore = false
  patchedUi = false
end

function M.onExtensionUnloaded()
  local vehicles = extensions.core_vehicles
  if vehicles and originalCoreOpenSelector then
    vehicles.openSelectorUI = originalCoreOpenSelector
  end

  local uiSelector = extensions.ui_vehicleSelector
  if uiSelector then
    if originalUiOpenFreeroam then
      uiSelector.openVehicleSelectorForFreeroam = originalUiOpenFreeroam
    end
    if originalUiOpenFreeroamWithMod then
      uiSelector.openVehicleSelectorForFreeroamWithMod = originalUiOpenFreeroamWithMod
    end
  end

  selectionContext = nil
  selectionActive = false
  patchedCore = false
  patchedUi = false
end

return M
