local M = {}
M.type = "auxiliary"
M.defaultOrder = 100

--STROBE LIGHT SYSTEM STAGES--
local mainStrobeStage0 = {
    electric = "flash",
    duration = 0.75,
    value = 0,
    valueEnd = 0
}

local mainStrobeStage1 = {
    electric = "flash",
    duration = 0.22,
    value = 1,
    valueEnd = 0
}

local mainStrobeStage2 = {
    electric = "flash",
    duration = 0.05,
    value = 0,
    valueEnd = 0
}

local redStrobeStage0 = {
    electric = "redflash",
    duration = 0.75,
    value = 0,
    valueEnd = 0
    
}

local redStrobeStage1 = {
    electric = "redflash",
    duration = 0.22,
    value = 1,
    valueEnd = 0
}

local greenStrobeStage0 = {
    electric = "greenflash",
    duration = 0.75,
    value = 0,
    valueEnd = 0
}

local greenStrobeStage1 = {
    electric = "greenflash",
    duration = 0.22,
    value = 1,
    valueEnd = 0
}
--STROBE LIGHT SYSTEM STAGES END--
--STROBE LIGHT SYSETM DATA--
local currentStrobeStage = 1
local currentStrobeStageTime = 0
local strobeStages = {redStrobeStage0,redStrobeStage1,greenStrobeStage0,greenStrobeStage1,mainStrobeStage0,mainStrobeStage1,mainStrobeStage2,mainStrobeStage1}
--STROBE LIGHT SYSETM DATA END--

local vsi_e = newTemporalSmoothingNonLinear(100)

local function init(jbeamData)
	electrics.values['rotorrpm'] = 0
  electrics.values['altitude100'] = 0
  electrics.values['altitude1000'] = 0
  electrics.values['flash'] = 0
  electrics.values['aspd'] = 0
  electrics.values['heading'] = 0
  electrics.values['roll'] = 0
end

local function updateGFX(dt)
  --STROBE SYSTEM--
  currentStrobeStageTime = currentStrobeStageTime + dt
  local lowbeamsOn = (electrics.values["lowhighbeam"] == 1)
  if lowbeamsOn then
    if currentStrobeStageTime > strobeStages[currentStrobeStage].duration then
        electrics.values[strobeStages[currentStrobeStage].electric] = strobeStages[currentStrobeStage].valueEnd
        currentStrobeStage = currentStrobeStage + 1
        if currentStrobeStage > #strobeStages then currentStrobeStage = 1 end
        electrics.values[strobeStages[currentStrobeStage].electric] = strobeStages[currentStrobeStage].value
        currentStrobeStageTime = 0
    end
  else
    for k,strb in pairs(strobeStages) do
        electrics.values[strb.electric] = 0
    end
  end
  --STROBE SYSTEM END--

  local alt_ft = obj:getAltitude() * 3.28084
  local roll, pitch, yaw = obj:getRollPitchYaw()
  local velX, velY, velZ = obj:getVelocityXYZ()

  electrics.values['heading'] = (yaw * 57.2958) % 360
  electrics.values['roll'] = roll * 57.2958
  electrics.values['altitude_ft100'] = alt_ft % 1000
  electrics.values['altitude_ft1000'] = alt_ft % 10000
  electrics.values['altitude_ft'] = alt_ft
  
  local rotorId = wheels.wheelIDs["FP"]
  if rotorId then
    electrics.values['rotorrpm'] = wheels.wheels[rotorId].angularVelocity * 9.5423
  end

  -- 15kts = 0, 20kts = 13, 40kts = 69, 60kts = 125, 80kts = 180, 100kts = 228, 120kts = 266, 140kts = 301, 160kts = 340
  local kts = electrics.values['airspeed'] * 1.94384
  electrics.values['aspd'] = kts < 90 and (kts - 15) * 2.75 or 206.25 + (kts - 90) * 1.9

  electrics.values['vsi'] = vsi_e:get(velZ * 196.85, dt)

  -- force gearbox into drive if we are in arcade mode
  local ctrlState = controller.mainController.getState and controller.mainController.getState()
  if ctrlState and ctrlState.grb_bhv == "arcade" then
    controller.mainController.shiftToGearIndex(2)
  end
end

M.updateGFX = updateGFX
M.init      = init
return M