-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- User constants.
local rdpTol = 1.0 -- The tolerance used when simplifying the nodes of a spline.

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local M = {}

-- Module dependencies.
local splineMgr = require('editor/drivePathEditor/splineMgr')
local geom = require('editor/toolUtilities/geom')
local rdp = require('editor/toolUtilities/rdp')

-- Module state.
local playing = {}
local timer, time, totalTime = hptimer(), 0.0, 0.0


-- Gets the current playback time.
local function getPlaybackTime() return totalTime end

-- Starts playback of all linked drive path splines/vehicles.
-- [Adds all vehicles to the playing table if they have a valid link to a spline.]
-- [Note: Execution wont start until the update function is called, where delayTime is used to start the playback.]
local function startPlayback(splines, vehicles)
  table.clear(playing)
  for i = 1, #vehicles do
    local vehicle = vehicles[i]
    if vehicle then
      local spline = nil
      for j = 1, #splines do
        if splines[j].isVehicleLink and splines[j].id == vehicle.linkSplineId and splines[j].linkVehId == vehicle.vid then -- Validity check per spline <-> vehicle.
          spline = splines[j]
          break
        end
      end

      -- Add the vehicle/spline pair to the playing table. Only enabled splines are added.
      if spline and spline.isEnabled then
        local vid = vehicle.vid
        playing[vid] = { spline = spline, vehicle = vehicle, isStarted = false }
        splineMgr.resetVehiclePose(spline, vehicle) -- Move the vehicle to the starting position.
      end
    end
  end
  -- Reset the timers.
  time = 0.0
  totalTime = 0.0
  timer:stopAndReset()
end

-- Stops playback of all linked drive path splines/vehicles, and resets the vehicles to their starting positions.
local function stopPlayback()
  -- Disable the AI for all vehicles in the playing table.
  for _, v in pairs(playing) do
    v.vehicle.veh:queueLuaCommand('ai.setState({mode = "stop"})')
  end

  -- Reset the vehicles to their starting positions.
  for _, d in pairs(playing) do
    splineMgr.resetVehiclePose(d.spline, d.vehicle)
  end

  -- Tidy up for next time.
  table.clear(playing)
  time = 0.0
  totalTime = 0.0
  timer:stopAndReset()
end

-- Handles playback of all the active drive path splines/vehicles.
local function handlePlayback()
  for _, d in pairs(playing) do
    local isStarted = d.isStarted
    if not isStarted then
      local spline, vehicle = d.spline, d.vehicle
      if time >= spline.delayTime then
        local aggression = spline.aggression -- Ensure all properties are in the correct format.
        local routeSpeed = spline.routeSpeed
        local routeSpeedMode = spline.isRouteSpeedLimit and 'limit' or 'set'
        local driveInLane = spline.isDriveInLane and 'on' or 'off'
        local avoidCars = spline.isAvoidCars and 'on' or 'off'
        local noOfLaps = spline.isLoop and spline.numLaps or nil

        -- The execution for this vehicle can now begin, so set it up based on mode.
        if spline.isFreeMode then -- CASE: FREE MODE.
          local nodes, widths, vels, velLimits = geom.catmullRomNodesWidthsVelVelLimits(spline, 10)
          for i = 1, #widths do
            widths[i] = widths[i] * 0.5 -- Use half widths.
          end
          rdp.simplifyNodesWidthsVelVelLimits(nodes, widths, vels, velLimits, rdpTol)
          if spline.isLoop then
            nodes[#nodes + 1] = nodes[1]
            widths[#widths + 1] = widths[1]
            vels[#vels + 1] = vels[1]
            velLimits[#velLimits + 1] = velLimits[1]
          end
          local scriptParts = {}
          for i = spline.startingNode, #nodes do
            local n = nodes[i]
            table.insert(scriptParts, string.format(
              "{ x = %f, y = %f, z = %f, r = %f, v = %f, vl = %f }",
              n.x, n.y, n.z, widths[i], vels[i], velLimits[i]
            ))
          end
          local scriptStr = "{ " .. table.concat(scriptParts, ", ") .. " }"

          -- Create the command for vLua, then execute it.
          local command = string.format(
          [[
            ai.driveUsingPath{
              script = %s,
              routeSpeed = %f,
              routeSpeedMode = %q,
              avoidCars = %s,
              driveInLane = %s,
              aggression = %f,
              noOfLaps = %s }
          ]],
            scriptStr,
            routeSpeed,
            routeSpeedMode,
            tostring(avoidCars),
            tostring(driveInLane),
            aggression,
            noOfLaps and tostring(noOfLaps) or "nil")
            vehicle.veh:queueLuaCommand(command)
        else -- CASE: NAV GRAPH MODE.
          local wpTargetList, vels = spline.graphNodes, spline.vels
          local wpSpeeds = {}
          for i = spline.startingNode, #wpTargetList do
            wpSpeeds[wpTargetList[i]] = vels[i] -- Build the wpSpeeds table using waypoint names as keys.
          end

          -- Create the command for vlua, then execute it.
          local luaCmd = string.format(
          [[
            ai.driveUsingPath{
              wpTargetList = %s,
              wpSpeeds = %s,
              routeSpeed = %f,
              routeSpeedMode = %q,
              avoidCars = %s,
              driveInLane = %s,
              aggression = %f,
              noOfLaps = %s }
          ]],
            serialize(wpTargetList),
            serialize(wpSpeeds),
            routeSpeed,
            routeSpeedMode,
            tostring(avoidCars),
            tostring(driveInLane),
            aggression,
            noOfLaps and tostring(noOfLaps) or "nil")
            vehicle.veh:queueLuaCommand(luaCmd)
        end
        d.isStarted = true
      end
    end
  end

  -- Update the timers.
  local dt = timer:stopAndReset() * 0.001
  time = time + dt
  totalTime = totalTime + dt
end


-- Public interface.
M.getPlaybackTime =                                     getPlaybackTime

M.startPlayback =                                       startPlayback
M.stopPlayback =                                        stopPlayback
M.handlePlayback =                                      handlePlayback

return M