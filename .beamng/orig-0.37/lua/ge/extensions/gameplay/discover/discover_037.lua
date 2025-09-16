local D = {}



local freeroamExperiences = {
  {
    type = "freeroam",
    id = "037_limousine",
    name = "ui.experiences.discover_037.limousine.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5-15"}},
    description = "ui.experiences.discover_037.limousine.description",
    image = "/gameplay/discover/images/limousineTestdrive.jpg",
    trigger = function(M)
      -- enable trafficLoadForFreeroam
      local trafficAmountFromSettings = settings.getValue('trafficAmount')
      if trafficAmountFromSettings == 0 then
        trafficAmountFromSettings = getMaxVehicleAmount(10)
      end
      local parkedVehiclesAmountFromSettings = settings.getValue('trafficParkedAmount')
      log("I", "037_limousine", string.format('Halving traffic and parked vehicles from settings: %d -> %d, %d -> %d', trafficAmountFromSettings, math.ceil(trafficAmountFromSettings / 2), parkedVehiclesAmountFromSettings, math.ceil(parkedVehiclesAmountFromSettings / 2)))
      -- half traffic for this experience
      trafficAmountFromSettings = math.ceil(trafficAmountFromSettings / 2)
      parkedVehiclesAmountFromSettings = math.ceil(parkedVehiclesAmountFromSettings / 2)
      freeroam_freeroam.setForceTrafficLoading({traffic = trafficAmountFromSettings, parkedVehicles = parkedVehiclesAmountFromSettings})
      freeroam_freeroam.startFreeroamByName("west_coast_usa", "spawns_industrial", nil, false)
      local walkId, limoId = nil, nil
      M.onPlayerCameraReady = function()
        local vehs = {
          { vec3(-821.7966309,903.6448364,75.53855133), quat(3.139752468e-06,-1.053478079e-05,0.4958757203,0.8683934995), "unicycle", "vehicles/unicycle/with_mesh.pc" },
          { vec3(-810.0274048,909.8909912,75.03192139), quat(-0.001089688493,-0.003704504967,0.9999047143,-0.01325336309), "fullsize", "vehicles/fullsize/limo_official.pc" },
        }
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          local v = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
          if i == 1 then
            walkId = v:getID()
          else
            limoId = v:getID()
            core_vehicleBridge.executeAction(v,'setIgnitionLevel', 0)
            core_vehicleBridge.registerValueChangeNotification(v, "ignitionLevel")
          end
        end
        M.basicControlsIntroPopup()
        M.onPlayerCameraReady = nil
        M.onVehicleSwitched = function(oldId, newId, player)
          if newId == limoId then
            guihooks.trigger("SetTasklistTask", {
              id = "037_limousine_walkingMode",
              clear = true
            })
            guihooks.trigger("SetTasklistTask", {
              label = "Ignition",
              subtext = "You can turn on the ignition by holding [action=activateStarterMotor], using the Radial Menu [action=toggleRadialMenuMulti] or clicking the 'Engine Start Stop' button in the bottom right corner.",
              type = "message",
              id = "037_limousine_ignition",
            })
            extensions.load('util_stepHandler')
            util_stepHandler.startStepSequence({
              util_stepHandler.makeStepReturnTrueFunction(function(step)
                step.timeout = math.huge
                step.complete = false
                --print(core_vehicleBridge.getCachedVehicleData(limoId, "ignitionLevel"))
                if core_vehicleBridge.getCachedVehicleData(limoId, "ignitionLevel") == 2 then
                  step.complete = true
                  guihooks.trigger("SetTasklistTask", {
                    id = "037_limousine_ignition",
                    clear = true
                  })
                  guihooks.trigger("SetTasklistTask", {
                    label = "ui.experiences.general.explore",
                    subtext = "ui.experiences.leisurelyDrive.task.subtext",
                    type = "message",
                  })
                  return true
                end
                if not scenetree.findObjectById(limoId) then
                  step.complete = true
                  return true
                end
                return false
              end),
            })
            freeroam_bigMapMode.setNavFocus(vec3(835.908,-522.544,165.363))
          end
          M.onVehicleSwitched = nil
          extensions.hookUpdate('onVehicleSwitched')
        end
        extensions.hookUpdate('onVehicleSwitched')
      end
      extensions.hookUpdate('onPlayerCameraReady')

      return true
    end,
    tasks = function(M)
      guihooks.trigger('ClearTasklist')
      guihooks.trigger("SetTasklistHeader", {
        label = "Limousine Test Drive",
        subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.west_coast_usa.info.title"}}
      })
      guihooks.trigger("SetTasklistTask", {
        label = "Walking Mode",
        subtext = "You can enter or exit vehicles using [action=toggleWalkingMode] or the Radial Menu [action=toggleRadialMenuMulti].",
        type = "message",
        id = "037_limousine_walkingMode",
      })
    end,
  },
  {
    type = "freeroam",
    id = "037_destructionProps",
    name = "ui.experiences.discover_037.destructiveProps.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5-10"}},
    description = "ui.experiences.discover_037.destructiveProps.description",
    image = "/gameplay/discover/images/destructive_props.jpg",
    trigger = function(M)
      -- enable trafficLoadForFreeroam
      freeroam_freeroam.setForceTrafficLoading({traffic = false, parkedVehicles = false})
      freeroam_freeroam.startFreeroamByName("gridmap_v2", "spawn_middle", nil, false)
      M.onPlayerCameraReady = function()

        local vehs = {

          { vec3(-393.538208,85.07393646,100.4414902), quat(0.003996261011,0.001331355885,-0.8466762199,0.5320917552), "hopper", "vehicles/hopper/sport_A.pc" },
          { vec3(-392.4162598,79.27086639,100.084465), quat(-0.0007308341831,-0.004185617448,0.9826823809,-0.1852492502), "fullsize", "vehicles/fullsize/lowrider.pc" },

          { vec3(-460.0043945,110.3837967,99.99999237), quat(0,-0,1,-0), "large_cannon", "vehicles/large_cannon/standard.pc" },
          { vec3(-471.0322876,111.5633316,99.99999237), quat(5.743762875e-07,-5.464591496e-06,1.715435881e-07,1), "large_roller", "vehicles/large_roller/standard.pc" },
          { vec3(-439,-15.95985031,100), quat(1.525190219e-07,-1.723923542e-07,-0.7071049957,0.7071085666), "large_hamster_wheel", "vehicles/large_hamster_wheel/standard.pc" },

          { vec3(-448,43.99998856,99.99998474), quat(-2.854423109e-06,-1.182347615e-06,0.9238819276,-0.38267765), "large_spinner", "vehicles/large_spinner/flail.pc" },

          { vec3(-460,32,100), quat(-0,0,0.9238795164,-0.3826834713), "large_spinner", "vehicles/large_spinner/base.pc", true },
          { vec3(-470,12.08457279,110.9995651), quat(0.5001355236,0.5010345638,0.4986913531,0.5001357399), "large_spinner", "vehicles/large_spinner/base.pc", true },

          { vec3(-439,68,100), quat(1.950982245e-06,1.950980785e-06,0.7071070457,0.7071065166), "spikestrip", "vehicles/spikestrip/flexr_dual.pc" },
          { vec3(-439,79,100), quat(1.950982245e-06,1.950980785e-06,0.7071070457,0.7071065166), "spikestrip", "vehicles/spikestrip/flexr_dual.pc" },

          { vec3(-422.999939,73.00011444,99.99913025), quat(-5.571546525e-05,-6.816663433e-05,0.9999999956,3.381670454e-05), "trampoline", "vehicles/trampoline/anchor.pc" },

          { vec3(-432,88.00015259,105.9998169), quat(0.4999864969,-0.5000118257,0.4999867948,0.5000148819), "large_spinner", "vehicles/large_spinner/small_dual.pc", true },


        }
        local setupVehs = {}
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          if veh[5] then
            spawningOptions.safeSpawn = false
          end
          local v = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
          if veh[3] == "large_spinner" then
            local speed = (0.8+math.random()*0.1) * -sign(i%2-0.5)
            if veh[4] == "vehicles/large_spinner/small_dual.pc" then
              speed = speed * 0.5
            end
            if veh[4] == "vehicles/large_spinner/base.pc" then
              speed = speed * 0.75
            end
            core_vehicleBridge.executeAction(v, "controllerGameplayEvent", "controller:spinner", "setTargetRPMRatio", speed)
          end
          if veh[3] == "large_hamster_wheel" then
            core_vehicleBridge.executeAction(v, "controllerGameplayEvent", "controller:hamster_wheel", "setTargetRPMRatio", 0.15)
          end
        end
        M.basicControlsIntroPopup()
        M.onPlayerCameraReady = nil
        extensions.hookUpdate('onPlayerCameraReady')
      end
      extensions.hookUpdate('onPlayerCameraReady')
      M.onClientPostStartMission = function()
        core_environment.setTimeOfDay({
          azimuthOverride = 4.5,
          dayLength = 1800,
          dayScale = 1,
          nightScale = 2,
          startTime = 0.10000000149012,
          time = 0.16200000047684
        })
        M.onClientPostStartMission = nil
        extensions.hookUpdate('onClientPostStartMission')
      end
      extensions.hookUpdate('onClientPostStartMission')
      return true
    end,
    tasks = function(M)
      guihooks.trigger('ClearTasklist')
      guihooks.trigger("SetTasklistHeader", {
        label = "ui.experiences.discover_037.destructiveProps.title",
        subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.gridmap.info.title"}}
      })
      guihooks.trigger("SetTasklistTask", {
        label = "ui.experiences.discover_037.destructiveProps.task.label",
        subtext = "ui.experiences.discover_037.destructiveProps.task.subtext",
        type = "message",
      })
    end,
  },

}
local missions = {
  {
    type = "mission",
    id = "037_villaVip",
    missionId = "italy/arrive/005-villaVip",
    description = "missions.arrive.italy.villaVIP.description",
    image = "/gameplay/discover/images/villa_vip.jpg",
    name = "missions.arrive.italy.villaVIP.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "10"}},
  },
  {
    type = "mission",
    id = "037_limoParking",
    missionId = "west_coast_usa/precisionParking/005-limoparking",
    description = "missions.west_coast_usa.precisionParking.limoparking.description",
    image = "/gameplay/discover/images/very_important_parking.jpg",
    name = "missions.west_coast_usa.precisionParking.limoparking.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "3"}},
  },
  {
    type = "mission",
    id = "037_Platform Jump",
    missionId = "industrial/arrive/001-Platform",
    description = "missions.industrial.arrive.Platform.description",
    image = "/gameplay/discover/images/platform_jump.jpg",
    name = "missions.industrial.arrive.Platform.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "3"}},
  },
  {
    type = "mission",
    id = "037_The Blender Bowl",
    missionId = "gridmap_v2/collection/002-blenderbowl",
    description = "missions.gridmap_v2.collection.blenderbowl.description",
    image = "/gameplay/discover/images/the_blender_bowl.jpg",
    name = "missions.gridmap_v2.collection.blenderbowl.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "2"}},
  },
  {
    type = "mission",
    id = "037_Grinder Grand Prix",
    missionId = "gridmap_v2/aiRace/001-grindergrandprix",
    description = "missions.aiRace.gridmap_v2.001-grindergrandprix.description",
    image = "/gameplay/discover/images/grinder_grand_prix.jpg",
    name = "missions.aiRace.gridmap_v2.001-grindergrandprix.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "3"}},
  },
  {
    type = "mission",
    id = "037_obstaclecourse",
    missionId = "gridmap_v2/delivery/004-obstaclecourse",
    description = "missions.gridmap_v2.delivery.obstaclecourse.description",
    image = "/gameplay/discover/images/turnstile_trial.jpg",
    name = "missions.gridmap_v2.delivery.obstaclecourse.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
}


local pressure_ball_demo =  {
  type = "freeroam",
  id = "pressure_ball_demo",
  name = "Pressue Ball Demo",
  tag = {txt = "ui.experiences.general.timeTag", context = {time = "999"}},
  description = "ui.experiences.johnsonValley.description",
  image = "/gameplay/discover/images/offroad.jpg",
  trigger = function(M)
    -- enable trafficLoadForFreeroam
    freeroam_freeroam.setForceTrafficLoading({traffic = false, parkedVehicles = false})
    freeroam_freeroam.startFreeroamByName("johnson_valley", "spawn_remote_pits", nil, false)
    M.onPlayerCameraReady = function()
      local vehs = {
        {vec3(1082.018188,427.2434998,114.7162094), quat(-0.02628606277,-0.04700933289,-0.007957618196,0.998516821), "pickup", "vehicles/pickup/deserttruck_crawler_A.pc" },

        {vec3(1100,584,160), quat(0,0,0,1), "pressure_ball", "vehicles/pressule_ball/helium.pc.pc" },
        {vec3(1100,584,160), quat(0,0,0,1), "pigeon", "vehicles/pigeon/base.pc.pc" },
      }
      local setupVehs = {}
      local random = math.random
      for i, veh in ipairs(vehs) do
        local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
        spawningOptions.pos = veh[1]
        spawningOptions.rot = veh[2]
        spawningOptions.autoEnterVehicle = i == 1
        if i > 1 then
          spawningOptions.safeSpawn = false
        end
        local v = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
        if i > 1 then
          table.insert(setupVehs, v)
        end
        local windVec = vec3(25+random()*10,0,0)
        v:queueLuaCommand('obj:setWind('..string.format('%6f, %6f, %6f', windVec.x, windVec.y, windVec.z)..')')
      end
      local balls = {}
      local len = 400
      local height = 200
      local vehicles = {{"pressure_ball", "vehicles/pressure_ball/standard.pc"}, {"pressure_ball", "vehicles/pressure_ball/standard.pc"},{"pressure_ball", "vehicles/pressure_ball/standard.pc"},{"pressure_ball", "vehicles/pressure_ball/standard.pc"}, {"pressure_ball", "vehicles/pressule_ball/helium.pc"}, {"pressure_ball", "vehicles/pressure_ball/big.pc"}, {"pressure_ball", "vehicles/ball/hydrogen.pc"}, {"ball", "vehicles/ball/ball.pc"}}
      local startX = 900
      local randomPos = function()
        return vec3(startX - random()*len/2,520 + random()*height,130 + random()*100)
      end
      for i = 1, 70 do

        local pos = randomPos()

        local set = vehicles[i%#vehicles+1]
        local model, config = set[1], set[2]
        local options = {pos = pos, rot = quat(0,0,0,1), model = model, config = config}
        if i > 1 then
          options.safeSpawn = false
        end
        local veh  = core_vehicles.spawnNewVehicle(model, options)
        local windVec = vec3(25+random()*10,0,0)
        veh:queueLuaCommand('obj:setWind('..string.format('%6f, %6f, %6f', windVec.x, windVec.y, windVec.z)..')')
        balls[i] = veh
      end
      extensions.load('util_stepHandler')
      local seq = {
        util_stepHandler.makeStepReturnTrueFunction(function(step)
          step.complete = false
          step.timeout = math.huge
          for _, veh in ipairs(balls) do
            local pos = veh:getPosition()
            if pos.x > startX+len then
              local randomPos = randomPos()
              veh:setClusterPosRelRot(veh:getRefNodeId(), randomPos.x, randomPos.y, randomPos.z,0,0,0,1)
              local windVec = vec3(25+random()*10,0,0)
              veh:queueLuaCommand('obj:setWind('..string.format('%6f, %6f, %6f', windVec.x, windVec.y, windVec.z)..')')
            end
          end
          local pigeonOOB = false
          for _, veh in ipairs(setupVehs) do
            local pos = veh:getPosition()
            if pos.x > startX+len then
              pigeonOOB = true
            end
          end
          if pigeonOOB then
            local randomPos = randomPos()
            for _, veh in ipairs(setupVehs) do
              --spawn.safeTeleport(veh, vec3(randomPos), quat(0,0,0,1), nil, nil, nil, nil, false)
              --veh:setClusterPosRelRot(veh:getRefNodeId(), randomPos.x, randomPos.y, randomPos.z,0,0,0,1)
              veh:setPosRot(randomPos.x, randomPos.y, randomPos.z, 0,0,0,1)
              veh:resetBrokenFlexMesh()
              local windVec = vec3(25+random()*10,0,0)
              veh:queueLuaCommand('obj:setWind('..string.format('%6f, %6f, %6f', windVec.x, windVec.y, windVec.z)..')')
            end
          end
          return false
        end),
      }
      util_stepHandler.startStepSequence(seq)
      M.basicControlsIntroPopup()
      M.onPlayerCameraReady = nil
      extensions.hookUpdate('onPlayerCameraReady')
    end
    extensions.hookUpdate('onPlayerCameraReady')
    return true
  end,
  tasks = function(M)
    guihooks.trigger('ClearTasklist')
    guihooks.trigger("SetTasklistHeader", {
      label = "ui.experiences.johnsonValley.title",
      subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.johnson_valley.info.title"}}
    })
    guihooks.trigger("SetTasklistTask", {
      label = "ui.experiences.general.explore",
      subtext = "ui.experiences.johnsonValley.task.subtext",
      type = "message",
    })
  end,
}

if false then
  table.insert(freeroamExperiences, pressure_ball_demo)
end

D.pageInfo = {
  title = "0.37 Highlights",
  sections = {
    {
      title = "Freeroam Experiences",
      type = "freeroam",
      discoverIds = {},
    },
    {
      title = "Missions",
      type = "mission",
      discoverIds = {},
    }
  },
  description = {
    title = "Destruction & Luxury",
    description = "Experience the thrill of remastered destructive props like spinners and large cannons, along with the elegance of the new Grand Marshal Limousine in the 2025 Fall Update.",
    image = "/gameplay/discover/images/small_island_pursuit.jpg",
  }
}

for _, discover in pairs(freeroamExperiences) do
  table.insert(D.pageInfo.sections[1].discoverIds, discover.id)
end
table.insert(D.pageInfo.sections[1].discoverIds, "johnson_valley")
for _, mission in pairs(missions) do
  table.insert(D.pageInfo.sections[2].discoverIds, mission.id)
end
D.experiences = arrayConcat(freeroamExperiences, missions)
return D