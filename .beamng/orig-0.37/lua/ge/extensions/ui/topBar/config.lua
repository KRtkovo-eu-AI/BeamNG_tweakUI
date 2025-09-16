-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
local M = {}

-- substates are a hack and should be removed after lua router is added in game

local TopBarEntryType = {
  MAIN = "main"
}

local TopBarEntryFlags = {
  IN_GAME_ONLY = "inGameOnly",
  CAREER_ONLY = "careerOnly",
  GARAGE_ONLY = "garageOnly",
  MISSION_ONLY = "missionOnly",
  SCENARIO_ONLY = "scenarioOnly",
  CAREER_GARAGE_ONLY = "careerGarageOnly",
  NO_CAREER = "noCareer",
  NO_GARAGE = "noGarage",
  NO_CAREER_GARAGE = "noCareerGarage",
  NO_MISSION = "noMission",
  NO_SCENARIO = "noScenario"
}

local TopBarEntries = {
  -- back = {
  --   id = "back",
  --   label = 'ui.inputActions.menu.menu_item_back.title',
  --   icon = 'arrowLeftOutline',
  --   section = "left",
  --   type = TopBarEntryType.MAIN,
  --   action = function()
  --     extensions.hook('MenuToggle')
  --   end,
  --   shouldSkipNavigation = function()
  --     return true
  --   end
  -- },
  mainmenu = {
    id = "mainmenu",
    label = 'ui.dashboard.menu',
    icon = 'catalog02',
    targetState = 'menu.mainmenu',
    flags = {TopBarEntryFlags.IN_GAME_ONLY},
    order = 1
  },
  career = {
    id = "career",
    label = 'ui.playmodes.career',
    icon = 'catalog02',
    targetState = 'menu.careerPause',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.CAREER_ONLY},
    order = 2
  },
  bigmap = {
    id = "bigmap",
    label = 'ui.dashboard.bigmap',
    icon = 'mapWithEmitter',
    targetState = 'menu.bigmap',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_SCENARIO, TopBarEntryFlags.NO_MISSION,
             TopBarEntryFlags.NO_GARAGE},
    order = 3
  },
  -- TODO: This seems to be always hidden?
  -- careerMission = {
  --   id = "careerMission",
  --   label = 'ui.dashboard.gameContext',
  --   icon = 'flag',
  --   targetState = 'menu.careermission',
  --   blackListStates = {'scenario', 'garage'},
  --   isHidden = function()
  --     return extensions.mission_missions and not extensions.mission_missions.isMissionEnabled()
  --   end,
  --   order = 4
  -- },
  mods = {
    id = "mods",
    label = 'ui.dashboard.mods',
    icon = 'puzzleModule',
    targetState = 'menu.mods.local',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_SCENARIO, TopBarEntryFlags.NO_MISSION,
             TopBarEntryFlags.NO_GARAGE},
    substate = 'menu.mods',
    order = 5
  },
  vehicles = {
    id = "vehicles",
    label = 'ui.dashboard.vehicles',
    icon = 'car',
    targetState = 'menu.vehiclesnew',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_SCENARIO, TopBarEntryFlags.NO_MISSION,
             TopBarEntryFlags.NO_GARAGE, TopBarEntryFlags.NO_CAREER},
    substate = 'vehicle-selector',
    order = 6
  },
  vehicleconfig = {
    id = "vehicleconfig",
    label = 'ui.dashboard.vehicleconfig',
    icon = 'engine',
    targetState = 'menu.vehicleconfig.parts',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_SCENARIO, TopBarEntryFlags.NO_MISSION,
             TopBarEntryFlags.NO_GARAGE, TopBarEntryFlags.NO_CAREER},
    substate = 'vehicle-config',
    order = 7
  },
  environment = {
    id = "environment",
    label = 'ui.dashboard.environment',
    icon = 'weather',
    targetState = 'menu.environment',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_SCENARIO, TopBarEntryFlags.NO_MISSION,
             TopBarEntryFlags.NO_GARAGE, TopBarEntryFlags.NO_CAREER},
    order = 8
  },
  photomode = {
    id = "photomode",
    label = 'ui.dashboard.photomode',
    icon = 'photo',
    targetState = 'menu.photomode',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_GARAGE},
    order = 9
  },
  appedit = {
    id = "appedit",
    label = 'ui.dashboard.appedit',
    icon = 'HUD',
    targetState = 'menu.appedit',
    flags = {TopBarEntryFlags.IN_GAME_ONLY, TopBarEntryFlags.NO_SCENARIO},
    order = 10
  },
  options = {
    id = "options",
    label = 'ui.dashboard.options',
    icon = 'adjust',
    targetState = 'menu.options.graphics',
    flags = {TopBarEntryFlags.IN_GAME_ONLY},
    substate = 'menu.options',
    order = 11
  }
}

M.TopBarEntryType = TopBarEntryType
M.TopBarEntries = TopBarEntries

return M
