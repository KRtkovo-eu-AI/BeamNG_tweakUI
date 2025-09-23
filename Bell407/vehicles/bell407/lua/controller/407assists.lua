local M = {}
M.type = "auxiliary"
M.defaultOrder = 10

-- Auto Hover
local maxPitchAngle = 0.5
local maxRollAngle = 0.5

local pitchPID = newPIDParallel(20, 20, 20, -1, 1)
local rollPID = newPIDParallel(10, 10, 5, -1, 1)

-- Angle Stabilize
local pitchRate = 0.5
local rollRate = 0.8
local yawRate = 1

local pitchAVPID = newPIDParallel(5, 5, 0, -1, 1)
local rollAVPID = newPIDParallel(2, 2, 0, -1, 1)
local yawAVPID = newPIDParallel(2, 2, 0, -1, 1)

local pitchSmoother = newTemporalSmoothingNonLinear(10)
local rollSmoother = newTemporalSmoothingNonLinear(10)
local yawSmoother = newTemporalSmoothingNonLinear(10)

local pitchAVSmoother = newTemporalSmoothingNonLinear(5)
local rollAVSmoother = newTemporalSmoothingNonLinear(5)
local yawAVSmoother = newTemporalSmoothingNonLinear(10)

local updateFunc = nop

local function init(jbeamData)
	-- Auto Hover
	maxPitchAngle = jbeamData.maxPitchAngle or maxPitchAngle
	maxRollAngle = jbeamData.maxRollAngle or maxRollAngle

	if jbeamData.pitchPID then pitchPID:setConfig(jbeamData.pitchPID[1], jbeamData.pitchPID[2], jbeamData.pitchPID[3]) end
	if jbeamData.rollPID then rollPID:setConfig(jbeamData.rollPID[1], jbeamData.rollPID[2], jbeamData.rollPID[3]) end

	-- Angle Stabilize
	pitchRate = jbeamData.pitchRate or pitchRate
	rollRate = jbeamData.rollRate or rollRate
	yawRate = jbeamData.yawRate or yawRate

	if jbeamData.pitchAVPID then pitchAVPID:setConfig(jbeamData.pitchAVPID[1], jbeamData.pitchAVPID[2], jbeamData.pitchAVPID[3]) end
	if jbeamData.rollAVPID then rollAVPID:setConfig(jbeamData.rollAVPID[1], jbeamData.rollAVPID[2], jbeamData.rollAVPID[3]) end
	if jbeamData.yawAVPID then yawAVPID:setConfig(jbeamData.yawAVPID[1], jbeamData.yawAVPID[2], jbeamData.yawAVPID[3]) end

	pitchSmoother = jbeamData.pitchSmoother and newTemporalSmoothingNonLinear(jbeamData.pitchSmoother) or pitchSmoother
	rollSmoother = jbeamData.rollSmoother and newTemporalSmoothingNonLinear(jbeamData.rollSmoother) or rollSmoother
	yawSmoother = jbeamData.yawSmoother and newTemporalSmoothingNonLinear(jbeamData.yawSmoother) or yawSmoother

	pitchAVSmoother = jbeamData.pitchAVSmoother and newTemporalSmoothingNonLinear(jbeamData.pitchAVSmoother) or pitchAVSmoother
	rollAVSmoother = jbeamData.rollAVSmoother and newTemporalSmoothingNonLinear(jbeamData.rollAVSmoother) or rollAVSmoother
	yawAVSmoother = jbeamData.yawAVSmoother and newTemporalSmoothingNonLinear(jbeamData.yawAVSmoother) or yawAVSmoother
end

local function reset(jbeamData)
	pitchPID:reset()
	rollPID:reset()

	pitchAVPID:reset()
	rollAVPID:reset()
	yawAVPID:reset()

	pitchSmoother:reset()
	rollSmoother:reset()
	yawSmoother:reset()

	pitchAVSmoother:reset()
	rollAVSmoother:reset()
	yawAVSmoother:reset()
end

local function updateAutoCenter(dt)
	
	-- Turn off if we are on the ground
	local rayLen = obj:getInitialHeight()/2 + 0.2
	local height = obj:castRayStatic(obj:getCenterPosition(), -obj:getDirectionVectorUp(), rayLen)
	if height < rayLen then
		return
	end
	
	local roll, pitch, yaw = obj:getRollPitchYaw()
	local rollAV, pitchAV, yawAV = obj:getRollPitchYawAngularVelocity()

	pitch = pitchSmoother:get(pitch, dt)
	roll = rollSmoother:get(roll, dt)

	yawAV = yawAVSmoother:get(yawAV, dt)

	local desiredYawAV = electrics.values["b407_yaw_input"]*yawRate

	electrics.values["b407_pitch_input"] = pitchPID:get(-electrics.values["b407_pitch_input"]*maxPitchAngle - pitch, 0, dt)
	electrics.values["b407_roll_input"] = rollPID:get(-electrics.values["b407_roll_input"]*maxRollAngle - roll, 0, dt)
	electrics.values["b407_yaw_input"] = yawAVPID:get(yawAV, desiredYawAV, dt)
end

local function updateAngleStabilize(dt)
	-- Turn off if we are on the ground
	local rayLen = obj:getInitialHeight()/2 + 0.2
	local height = obj:castRayStatic(obj:getCenterPosition(), -obj:getDirectionVectorUp(), rayLen)
	if height < rayLen then
		return
	end

	local rollAV, pitchAV, yawAV = obj:getRollPitchYawAngularVelocity()

	pitchAV = pitchAVSmoother:get(pitchAV, dt)
	rollAV = rollAVSmoother:get(rollAV, dt)
	yawAV = yawAVSmoother:get(yawAV, dt)

	local desiredPitchAV = electrics.values["b407_pitch_input"]*pitchRate
	local desiredRollAV = electrics.values["b407_roll_input"]*rollRate
	local desiredYawAV = electrics.values["b407_yaw_input"]*yawRate

	electrics.values["b407_pitch_input"] = pitchAVPID:get(-pitchAV, desiredPitchAV, dt)
	electrics.values["b407_roll_input"] = rollAVPID:get(rollAV, desiredRollAV, dt)
	electrics.values["b407_yaw_input"] = yawAVPID:get(yawAV, desiredYawAV, dt)
end

local function updateGFX(dt)
	updateFunc(dt)
end

local function setParameters(parameters)
	--dump(parameters)
	
	if parameters.mode == "autocenter" then
		updateFunc = updateAutoCenter
		--print("1")
	elseif parameters.mode == "stabilize" then
		updateFunc = updateAngleStabilize
		--print("2")
	elseif parameters.mode == "off" then
		updateFunc = nop
		--print("3")
	end
end

-- public interface
M.init          = init
M.reset         = reset
M.updateGFX     = updateGFX
M.setParameters = setParameters

return M