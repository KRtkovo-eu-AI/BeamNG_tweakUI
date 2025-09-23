local M = {}
M.type = "auxiliary"
M.defaultOrder = 50

local angleOffset = -2.7

local pitchOffset = vec3(0, -0.0003, 0)
local rollOffset = vec3(-0.001, -0.00015, 0)
local yawOffset = vec3(0, 0, 0)

local pitchInputMul = 0.1
local rollInputMul = 0.07
local yawInputMul = 0.02
local liftInputMul = 0.021

local collectiveMul = 0.05
local upAccelMul = 0.011

local tailRotorRoll = 2

local noLoadYaw = 0.0025
local engineLoadYaw = -0.020

local torqueInput = vec3()

local function init(jbeamData)
	pitchInputMul = jbeamData.pitchInputMul or pitchInputMul
	rollInputMul = jbeamData.rollInputMul or rollInputMul
	yawInputMul = jbeamData.yawInputMul or yawInputMul
	liftInputMul = jbeamData.liftInputMul or liftInputMul

	angleOffset = jbeamData.angleOffset or angleOffset

	pitchOffset = jbeamData.pitchOffset and vec3(jbeamData.pitchOffset) or pitchOffset
	rollOffset = jbeamData.rollOffset and vec3(jbeamData.rollOffset) or rollOffset
	yawOffset = jbeamData.yawOffset and vec3(jbeamData.yawOffset) or yawOffset

	collectiveMul = jbeamData.collectiveMul or collectiveMul
	upAccelMul = jbeamData.upAccelMul or upAccelMul

	tailRotorRoll = jbeamData.tailRotorRoll or tailRotorRoll

	noLoadYaw = jbeamData.noLoadYaw or noLoadYaw
	engineLoadYaw = jbeamData.engineLoadYaw or engineLoadYaw

	-- Movement input states
	input.state["b407_lift"] =  {val = 0, filter = 0, smootherKBD = newTemporalSmoothing(3, 3, 5, 0), smootherPAD = newTemporalSmoothing(10, 10, nil, 0), minLimit = -1, maxLimit = 1}
	input.state["b407_pitch"] = {val = 0, filter = 0, smootherKBD = newTemporalSmoothing(3, 3, 5, 0), smootherPAD = newTemporalSmoothing(10, 10, nil, 0), minLimit = -1, maxLimit = 1}
	input.state["b407_roll"] =  {val = 0, filter = 0, smootherKBD = newTemporalSmoothing(3, 3, 5, 0), smootherPAD = newTemporalSmoothing(10, 10, nil, 0), minLimit = -1, maxLimit = 1}
	input.state["b407_yaw"] =   {val = 0, filter = 0, smootherKBD = newTemporalSmoothing(3, 3, 5, 0), smootherPAD = newTemporalSmoothing(10, 10, nil, 0), minLimit = -1, maxLimit = 1}
end

local function updateGFX(dt)
	-- Vehicle data
	local vehRot = quatFromDir(-obj:getDirectionVector(), obj:getDirectionVectorUp())
	local vehRotInv = vehRot:inversed()

	local vehVel = obj:getVelocity()
	local vehVelLocal = vehVel:rotated(vehRotInv)
	
	local liftInput = electrics.values["b407_lift_input"] or 0
	torqueInput.x = electrics.values["b407_pitch_input"] or 0
	torqueInput.y = electrics.values["b407_roll_input"] or 0
	torqueInput.z = electrics.values["b407_yaw_input"] or 0

	torqueInput.x = torqueInput.x * pitchInputMul
	torqueInput.y = torqueInput.y * rollInputMul
	torqueInput.z = torqueInput.z * yawInputMul

	local gz = sensors.gz
	local mul = 1 - gz*upAccelMul + liftInput*collectiveMul

	local pitchVelMul = (pitchOffset*mul):componentMul(vehVelLocal)
	local rollVelMul = (rollOffset*mul):componentMul(vehVelLocal)
	local yawVelMul = (yawOffset*mul):componentMul(vehVelLocal)

	torqueInput.x = torqueInput.x + pitchVelMul.x + pitchVelMul.y + pitchVelMul.z
	torqueInput.z = torqueInput.z + yawVelMul.x + yawVelMul.y + yawVelMul.z + (electrics.values.engineLoad or 0)*engineLoadYaw + noLoadYaw
	torqueInput.y = torqueInput.y + rollVelMul.x + rollVelMul.y + rollVelMul.z + torqueInput.z*tailRotorRoll
	
	
	torqueInput:setRotate(quatFromAxisAngle(vec3(0,0,1), angleOffset))
	
	if liftInput > -0.01 and liftInput < 0.01 then
		local rayLen = obj:getInitialHeight()/2 + 0.2
		local height = obj:castRayStatic(obj:getCenterPosition(), -obj:getDirectionVectorUp(), rayLen)

		if height < rayLen then
			liftInput = -0.3
		end
	end

	liftInput = liftInput * liftInputMul

	electrics.values["hydro_f"] = -torqueInput.x + liftInput
	electrics.values["hydro_b"] = torqueInput.x*0.7 + liftInput
	electrics.values["hydro_l"] = torqueInput.y + liftInput
	electrics.values["hydro_r"] = -torqueInput.y + liftInput
	electrics.values["hydro_yaw"] = -torqueInput.z
end

-- public interface
M.init      = init
M.updateGFX = updateGFX

return M