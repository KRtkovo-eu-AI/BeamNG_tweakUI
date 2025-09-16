local M = {}
M.dependencies = {"core_vehicles", "ui_vehicleSelector"}

local logTag = "vehicleSelectorLegacyFreeroam"

local patchedCore = false
local patchedUi = false

local function openLegacyFreeroam()
  local vehicles = extensions.core_vehicles
  if not vehicles or not vehicles.openSelectorUI_legcay then
    log("E", logTag, "Legacy vehicle selector is not available")
    return
  end

  vehicles.openSelectorUI_legcay()
  extensions.hook("onVehicleSelectorOpen")
end

local function patchCore()
  if patchedCore then return true end

  local vehicles = extensions.core_vehicles
  if not vehicles or not vehicles.openSelectorUI_legcay then
    return false
  end

  if vehicles.openSelectorUI ~= openLegacyFreeroam then
    log("I", logTag, "Redirecting core_vehicles.openSelectorUI to legacy dialog")
  end

  vehicles.openSelectorUI = openLegacyFreeroam
  patchedCore = true
  return true
end

local function patchUi()
  if patchedUi then return true end

  local uiSelector = extensions.ui_vehicleSelector
  if not uiSelector then
    return false
  end

  uiSelector.openVehicleSelectorForFreeroam = openLegacyFreeroam

  if uiSelector.openVehicleSelectorForFreeroamWithMod then
    uiSelector.openVehicleSelectorForFreeroamWithMod = function(modId)
      log("W", logTag, string.format("Legacy selector ignores mod filter request (modId: %s)", tostring(modId)))
      openLegacyFreeroam()
    end
  end

  patchedUi = true
  log("I", logTag, "Freeroam vehicle selector redirected to legacy dialog")
  return true
end

local function applyPatch()
  local coreDone = patchCore()
  local uiDone = patchUi()

  return coreDone and uiDone
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

return M
