local D = {}

local bindingLegendActions = {
  {
    action = 'toggleBigMap',
    label = 'ui.dashboard.bigmap',
    onClick = "freeroam_bigMapMode.toggleBigMap()",
  },
  {
    action = 'toggleRadialMenuMulti',
    label = 'ui.menu.openRadialMenu.name',
    onClick = "core_quickAccess.toggle()",
  },
  {
    action = 'recover_vehicle',
    label = 'ui.inputActions.gameplay.recover_vehicle.title',
    onClick = "getPlayerVehicle(0):queueLuaCommand('recovery.startRecovering() recovery.stopRecovering()')",
  },
  {
    action = 'reset_physics',
    label = 'ui.common.resetVehicle',
    onClick = "resetGameplay(0)",
  },
  {
    action = 'activateStarterMotor',
    label = 'ui.common.ignition',
    onClick = "getPlayerVehicle(0):queueLuaCommand('electrics.toggleIgnitionLevelOnDown() electrics.toggleIgnitionLevelOnUp()')",
  },
}

local freeroamExperiences = {
  {
    type = "freeroam",
    id = "leisurelyDrive",
    name = "ui.experiences.leisurelyDrive.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
    description = "ui.experiences.leisurelyDrive.description",
    image = "/gameplay/discover/images/leisurelyDrive.jpg",
    trigger = function(M)
      -- enable trafficLoadForFreeroam
      freeroam_freeroam.setForceTrafficLoading({traffic = true, parkedVehicles = true})
      freeroam_freeroam.startFreeroamByName("italy", "spawn_town_east", nil, false)
      M.onPlayerCameraReady = function()
        local vehs = {
          { vec3(189.2717133,-375.0607605,194.2601013), quat(0,0,0.7038784663,0.710320424), "vivace", "vehicles/vivace/vivace_230S_DCT.pc" },
        }
        local setupVehs = {}
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          local v = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
        end
        extensions.load('util_stepHandler')
        local seq = {
          util_stepHandler.makeStepWait(1),
          util_stepHandler.makeStepReturnTrueFunction(function(step)
            step.timeout = math.huge
            gameplay_traffic.setActiveAmount(0)
            freeroam_bigMapMode.setNavFocus(vec3(310.2650452,1816.934692,207.3096924))
            return true
          end),
          util_stepHandler.makeStepWait(1),
          util_stepHandler.makeStepReturnTrueFunction(function(step)
            step.timeout = math.huge
            local playerPos = be:getPlayerVehicle(0):getPosition()
            if playerPos:squaredDistance(vehs[1][1]) > 5*5 then
              gameplay_traffic.setActiveAmount(100)
              return true
            end
            return false
          end),
        }
        util_stepHandler.startStepSequence(seq)
        M.basicControlsIntroPopup()
        M.onPlayerCameraReady = nil
      end
      extensions.hookUpdate('onPlayerCameraReady')
      return true
    end,
    tasks = function(M)
      guihooks.trigger('ClearTasklist')
      guihooks.trigger("SetTasklistHeader", {
        label = "ui.experiences.leisurelyDrive.title",
        subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.italy.info.title"}}
      })
      guihooks.trigger("SetTasklistTask", {
        label = "ui.experiences.general.explore",
        subtext = "ui.experiences.leisurelyDrive.task.subtext",
        type = "message",
      })
    end,
  },

  {
    type = "freeroam",
    id = "johnson_valley",
    name = "ui.experiences.johnsonValley.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5-10"}},
    description = "ui.experiences.johnsonValley.description",
    image = "/gameplay/discover/images/offroad.jpg",
    trigger = function(M)
      -- enable trafficLoadForFreeroam
      freeroam_freeroam.setForceTrafficLoading({traffic = false, parkedVehicles = false})
      freeroam_freeroam.startFreeroamByName("johnson_valley", "spawn_remote_pits", nil, false)
      M.onPlayerCameraReady = function()
        local vehs = {
          { vec3(-1270.672607,-79.58815765,121.6928101), quat(-0.02186222721,0.0009984752378,0.7260386731,0.6873055297), "pickup", "vehicles/pickup/deserttruck_crawler_A.pc" },
          { vec3(-1273.283325,-83.95053864,121.7670593), quat(0.01025221426,-0.02570453177,0.8734151899,0.4861893409), "racetruck", "vehicles/racetruck/tt2_spec.pc" },
          --{ vec3(-574.324,-404.611,132.277), quat(-0.004031204019,-0.03853915852,-0.4529694097,0.8906835558), "rockbouncer", "vehicles/rockbouncer/rock_crawler.pc" },
          --{ vec3(-574.530,-404.151,132.347), quat(-0.004031204019,-0.03853915852,-0.4529694097,0.8906835558), "roamer", "vehicles/roamer/adventure.pc" },
          { vec3(-1272.337158,-74.02603149,121.4899216), quat(-0.007339913527,0.003215354856,0.4619465262,0.886871577), "utv", "vehicles/utv/plus.pc" },
        }
        local setupVehs = {}
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          local v = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
          if i <= 3 then
            setupVehs[v:getID()] = [[
              for _, v in ipairs(powertrain.getDevicesByType("differential")) do powertrain.toggleDeviceMode(v.name) end
              controller.getControllerSafe("frontLockControl").setDriveMode('locked')
              controller.getControllerSafe("rearLockControl").setDriveMode('locked')
              controller.getControllerSafe("transfercaseControl").setDriveMode('4lo')
              controller.getControllerSafe("transfercaseControl").setDriveMode('high')
              controller.getControllerSafe("rangeboxControl").setDriveMode('low')
            ]]
          end
        end
        extensions.load('util_stepHandler')
        local seq = {
          util_stepHandler.makeStepReturnTrueFunction(function()
            local dones = {}
            for vehId, setup in pairs(setupVehs) do
              local veh = getObjectByID(vehId)
              if veh and veh:isReady() then
                if not dones[vehId] then
                  dones[vehId] = true
                  veh:queueLuaCommand(setup)
                  log("I","discover","Setting up vehicle "..vehId.." with command: "..setup)
                end
              end
            end
            for id, _ in pairs(dones) do
              setupVehs[id] = nil
            end
            if not next(setupVehs) then
              return true
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
  },

  {
    type = "freeroam",
    id = "trackday",
    name = "ui.experiences.trackday.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5-15"}},
    description = "ui.experiences.trackday.description",
    image = "/gameplay/discover/images/trackday.jpg",
    trigger = function(M)
      -- enable trafficLoadForFreeroam
      freeroam_freeroam.setForceTrafficLoading({traffic = false, parkedVehicles = false})
      freeroam_freeroam.startFreeroamByName("hirochi_raceway", "spawn_pitlane", nil, false)
      M.onPlayerCameraReady = function()
        local vehChoices = {
          { "sunburst2", "vehicles/sunburst2/sport_RS_DCT.pc" },
          { "etkc", "vehicles/etkc/kc6x_trackday_A.pc" },
          { "scintilla", "vehicles/scintilla/gtx.pc" },
          { "etk800", "vehicles/etk800/856_ttsport_DCT.pc" },
          { "vivace", "vehicles/vivace/vivace_S_410q_M.pc" },
        }
        local vehs = {
          { vec3(-455.5000305,374.7161865,25.23128128), quat(6.270791814e-05,0.0005269290997,0.9929929419,-0.1181724831), vehChoices[1][1], vehChoices[1][2] },
          { vec3(-446.6066589,361.14505,25.16402245), quat(3.034665428e-05,0.0002429556407,0.9922893041,-0.123943039), vehChoices[2][1], vehChoices[2][2] },
          { vec3(-438.1695862,346.2776184,25.1306839), quat(-0.0001477062226,-0.001071917166,0.9906386067,-0.1365063375), vehChoices[3][1], vehChoices[3][2] },
          { vec3(-429.155426,333.7767334,25.10681915), quat(-8.45975059e-05,-0.0007574605165,0.9938206113,-0.1109955479), vehChoices[4][1], vehChoices[4][2] },
          { vec3(-420.4411316,319.9455872,25.14068985), quat(0,-0,0.9944942508,-0.10479115), vehChoices[5][1], vehChoices[5][2] },
        }
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
        end
        M.basicControlsIntroPopup()
        M.onPlayerCameraReady = nil
        extensions.hookUpdate('onPlayerCameraReady')
      end
      extensions.hookUpdate('onPlayerCameraReady')

      M.onClientPostStartMission = function()
        core_environment.setTimeOfDay({time=0.79000})
        core_environment.setFogDensity(0.001540986122)
        M.onClientPostStartMission = nil
        extensions.hookUpdate('onClientPostStartMission')
      end
      extensions.hookUpdate('onClientPostStartMission')
      return true
    end,
    tasks = function(M)
      guihooks.trigger('ClearTasklist')
      guihooks.trigger("SetTasklistHeader", {
        label = "ui.experiences.trackday.title",
        subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.hirochi_raceway.info.title"}}
      })
      guihooks.trigger("SetTasklistTask", {
        label = "ui.experiences.trackday.task1.label",
        subtext = "ui.experiences.trackday.task1.subtext",
        type = "message",
      })
      guihooks.trigger("SetTasklistTask", {
        label = "ui.experiences.general.explore",
        subtext = "ui.experiences.trackday.task2.subtext",
        type = "message",
      })
    end,
  },

  {
    type = "freeroam",
    id = "propDestruction",
    name = "ui.experiences.propDestruction.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
    description = "ui.experiences.propDestruction.description",
    image = "/gameplay/discover/images/propDestruction.jpg",
    trigger = function(M)
      -- enable trafficLoadForFreeroam
      freeroam_freeroam.setForceTrafficLoading({traffic = false, parkedVehicles = false})
      freeroam_freeroam.startFreeroamByName("Industrial", "spawn_factory", nil, false)
      M.onPlayerCameraReady = function()
        local vehs = {
          { vec3(-143.3728027,83.48352814,35.11228561), quat(-0.004508387994,0.0001588892785,0.03522081038,0.999369373), "van", "vehicles/van/h25_worker.pc" },
          { vec3(-171.8866425,127.8188705,34.96841812), quat(0.02066615241,-0.008679200679,0.387113079,0.9217597548), "cannon", "vehicles/cannon/cannon.pc" },
          { vec3(-158.3771362,143.2392883,35.22563553), quat(-0.001331452813,-0.001542004732,-0.7568890667,0.6535401978), "caravan", "vehicles/caravan/default.pc" },
          { vec3(-144.6221008,157.9118805,35.99853516), quat(-1.780725942e-06,-5.771057474e-06,0.9555452647,-0.2948444456), "fridge", "vehicles/fridge/standard.pc" },
          { vec3(-150.1018219,158.1330872,36.21847534), quat(1.766898486e-06,-1.028953559e-05,0.985574711,0.1692409196), "porta_potty", "vehicles/porta_potty/default.pc" },
          { vec3(-146.2707825,159.0570221,36.05832672), quat(0.0001382667643,1.267887785e-06,-0.009169481016,0.9999579499), "piano", "vehicles/piano/standard.pc" },
          { vec3(-138.2297058,102.0587769,34.79919434), quat(-0.0001324840225,0.0001432935834,0.7342591574,0.6788692449), "tv", "vehicles/tv/25inch.pc" },
          { vec3(-136.6850739,104.0551834,34.89838409), quat(-1.370823688e-06,-2.668151342e-06,0.8894732678,-0.4569872053), "couch", "vehicles/couch/couch_free.pc" },
          { vec3(-135.8791656,101.8557205,34.79919052), quat(0.0002344426654,0.0001473668705,-0.5321790558,0.8466317829), "couch", "vehicles/couch/armchair_free.pc" },
          { vec3(-135.1573334,102.8125229,34.79919434), quat(4.743933507e-05,1.696156212e-05,-0.3366698313,0.94162276), "barrels", "vehicles/barrels/empty.pc" },
          { vec3(-131.6051788,157.0005493,36.81754684), quat(0.0001472245881,0.01930025774,0.9997846345,-0.007626472298), "steel_coil", "vehicles/steel_coil/20ton.pc" },
          { vec3(-131.9969635,153.5990143,35.00673676), quat(-2.599318111e-05,-0.003242814254,0.9999626183,-0.008015324778), "pigeon", "vehicles/pigeon/base.pc" }
        }
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          local veh = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
          --veh.playerUsable = i <= 2
        end
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
        label = "ui.experiences.propDestruction.title",
        subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.industrial.info.title"}}
      })
      guihooks.trigger("SetTasklistTask", {
        label = "ui.experiences.propDestruction.task.label",
        subtext = "ui.experiences.propDestruction.task.subtext",
        type = "message",
      })
    end,
  },

  {
    type = "freeroam",
    id = "ramplow",
    name = "ui.experiences.ramplow.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
    description = "ui.experiences.ramplow.description",
    image = "/gameplay/discover/images/ramplow.jpg",
    trigger = function(M)
      freeroam_freeroam.setForceTrafficLoading({traffic = true, parkedVehicles = false})
      freeroam_freeroam.startFreeroamByName("west_coast_usa", "spawn_highway", nil, false)
      M.onPlayerCameraReady = function()
        local vehs = {
          { vec3(-926.2694092,-530.4829712,105.0409012), quat(0.02295934544,0.03978534072,0.5222144473,0.8515762245), "us_semi", "vehicles/us_semi/t82_ramplow.pc" },
        }
        local setupVehs = {}
        for i, veh in ipairs(vehs) do
          local spawningOptions = sanitizeVehicleSpawnOptions(veh[3], {config = veh[4]})
          spawningOptions.pos = veh[1]
          spawningOptions.rot = veh[2]
          spawningOptions.autoEnterVehicle = i == 1
          local v = core_vehicles.spawnNewVehicle(spawningOptions.model, spawningOptions)
        end
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
        label = "ui.experiences.ramplow.title",
        subtext = {txt = "ui.experiences.general.freeroamLevel", context = {level = "levels.west_coast_usa.info.title"}}
      })
      guihooks.trigger("SetTasklistTask", {
        label = "ui.experiences.ramplow.task.label",
        subtext = "ui.experiences.ramplow.task.subtext",
        type = "message",
      })
    end,
  },
}
local missions = {
  {
    type = "mission",
    id = "small_island_pursuit",
    missionId = "small_island/chase/001-Small",
    description = "ui.experiences.missions.smallIslandPursuit.description",
    icon = "wigwags",
    image = "/gameplay/discover/images/small_island_pursuit.jpg",
    name = "ui.experiences.missions.smallIslandPursuit.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
  {
    type = "mission",
    id = "get_down",
    missionId = "cliff/arrive/001-Get",
    description = "ui.experiences.missions.getDown.description",
    icon = "wigwags",
    image = "/gameplay/discover/images/get_down.jpg",
    name = "ui.experiences.missions.getDown.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "2"}},
  },
  {
    type = "mission",
    id = "garage_to_garage",
    missionId = "italy/garageToGarage/002-GlobalGeneric",
    description = "ui.experiences.missions.garageToGarage.description",
    icon = "toGarage",
    image = "/gameplay/discover/images/garage_to_garage.jpg",
    name = "ui.experiences.missions.garageToGarage.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5-30"}},
  },
  {
    type = "mission",
    id = "tasticola_restock",
    missionId = "italy/delivery/003-tastiCola",
    description = "ui.experiences.missions.tasticolaRestock.description",
    icon = "deliveryTruckArrows",
    image = "/gameplay/discover/images/tasticola_restock.jpg",
    name = "ui.experiences.missions.tasticolaRestock.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
  {
    type = "mission",
    id = "orchard_hill",
    missionId = "italy/rallyStage/003-ssorchardhill",
    description = "ui.experiences.missions.orchardHill.description",
    icon = "raceFlag",
    image = "/gameplay/discover/images/orchard_hill.jpg",
    name = "ui.experiences.missions.orchardHill.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
  {
    type = "mission",
    id = "ring_road",
    missionId = "small_island/aiRace/001-ring",
    description = "ui.experiences.missions.ringRoad.description",
    icon = "AIRace",
    image = "/gameplay/discover/images/ring_road.jpg",
    name = "ui.experiences.missions.ringRoad.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
  {
    type = "mission",
    id = "slithery_drift_short",
    missionId = "italy/drift/002-mountainShort",
    description = "ui.experiences.missions.slitheryDriftShort.description",
    icon = "drift01",
    image = "/gameplay/discover/images/slithery_drift_short.jpg",
    name = "ui.experiences.missions.slitheryDriftShort.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
  {
    type = "mission",
    id = "ridgeway_rider",
    missionId = "johnson_valley/crawl/003-Ridgeway",
    description = "ui.experiences.missions.ridgewayRider.description",
    icon = "rockCrawling01",
    image = "/gameplay/discover/images/ridgeway_rider.jpg",
    name = "ui.experiences.missions.ridgewayRider.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "5"}},
  },
  {
    type = "mission",
    id = "barrel_knocker",
    missionId = "industrial/knockAway/001-barrels",
    description = "ui.experiences.missions.barrelKnocker.description",
    icon = "barrelKnocker01",
    image = "/gameplay/discover/images/barrel_knocker.jpg",
    name = "ui.experiences.missions.barrelKnocker.title",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "2"}},
  },
  {
    type = "mission",
    id = "drag_strip_race",
    missionId = "hirochi_raceway/dragStripRace/001-hirochiDrag_500",
    description = "ui.experiences.missions.dragStripRace.description",
    icon = "stopwatchSectionOutlinedEnd",
    name = "ui.experiences.missions.dragStripRace.title",
    image = "/gameplay/discover/images/drag_strip_race.jpg",
    tag = {txt = "ui.experiences.general.timeTag", context = {time = "1-5"}},
    model = "covet",
    config = "vehicles/covet/15gtz_turbo2_M.pc"
  }
}

D.pageInfo = {
  title = "New Player Experience",
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
  }
}

for _, discover in pairs(freeroamExperiences) do
  table.insert(D.pageInfo.sections[1].discoverIds, discover.id)
end
for _, mission in pairs(missions) do
  table.insert(D.pageInfo.sections[2].discoverIds, mission.id)
end
D.experiences = arrayConcat(freeroamExperiences, missions)
return D