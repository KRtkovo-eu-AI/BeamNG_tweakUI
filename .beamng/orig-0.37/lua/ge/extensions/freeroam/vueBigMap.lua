-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.dependencies = {'gameplay_missions_missions','freeroam_bigMapMode', 'gameplay_rawPois'}

--[[
    enterBigMap: () => {}, -- initializes lua backend, creates caches etc
    exitBigMap: () => {}, -- clears caches

    getPoiData: () => {}, -- gives the full poi data by id: name, preview, aggregates, available actions
    getFilters: () => {}, -- filter icons, sorted first by type, then by group id
    {
      {
        key = 'careerPois',
        icon = 'flag',
        label = 'Career POIs',
        groups = {
          { key = 'type_garage', label = 'Garages', icon = 'garage01', elementCount = 5, visible = true },
          { key = 'type_gasStation', label = 'Gas Stations', icon = 'fuelPump', elementCount = 3, visible = false }
        }
      },
      {
        ...
      }
    }


    getGroups: () => {}, -- groups for the poiList, sorted again by type
    {
      {
        key = 'careerPois',
        icon = 'flag',
        label = 'Career POIs',
        groups = {
          { key = 'type_garage', label = 'Garages', icon = 'garage01', elements = [...], visible = true }, -- elements is poi ids
          -- not including type_gasStation because its not visible
        }
      },
      {
        ...
      }
    }


    toggleFiltersByIds: (groupKey) => String, -- toggles a group by group key
    getGameStateInfo: () => {}, -- game state info for the poiList

    selectPoiFromList: (poiId) => String, -- selects a poi from the list, highlighting the poi bigmapmarker and triggering showPoiDetails
    hoverPoiFromList: (poiId, active) => [String, Boolean], -- hovers a poi from the list, highlighting the poi bigmapmarker
    executePoiAction: (poiId, action) => [String, String], -- executes an action on a poi

    -- calls from lua to vue:
    showPoiDetails: (poiIds) => List of PoiIds, (can also be empty or a single poi) (guihooks.trigger('showPoiDetails', {poiIds}))
--]]

-- Cache variables
local poiDataCache = {}
local groupStructureCache = {}
local filterStructureCache = {}
local gameStateInfoCache = {}
local cacheValid = false

-- Group visibility state storage
local filterVisibilityState = {}

-- Action management system (like detailsInteraction.lua)
M.actionIdCounter = 0
M.actionFunctions = {}


-- Function to invalidate cache
local function invalidateCache()
  poiDataCache = {}
  groupStructureCache = {}
  gameStateInfoCache = {}
  filterStructureCache = {}
  cacheValid = false
end


-- Function to toggle group visibility
local function toggleFiltersByIds(filterIds)
  for _, filterId in ipairs(filterIds) do
    filterVisibilityState[filterId] = not filterVisibilityState[filterId]
  end
  M.setVisibleIds()
end

local function toggleFilterSectionById(sectionId)
  for _, filterSection in ipairs(filterStructureCache) do
    if filterSection.key == sectionId then
      local onGroupCount, offGroupCount = 0, 0
      for _, group in ipairs(filterSection.groups) do
        if group.visible then
          onGroupCount = onGroupCount + 1
        else
          offGroupCount = offGroupCount + 1
        end
      end
      local allVisible = onGroupCount > offGroupCount
      if offGroupCount == 0 then
        allVisible = false
      end
      if onGroupCount == 0 then
        allVisible = true
      end
      for _, group in ipairs(filterSection.groups) do
        group.visible = allVisible
        filterVisibilityState[group.key] = allVisible
      end
    end
  end
  M.setVisibleIds()
end

-- Get a free action ID
local function getFreeActionId()
  M.actionIdCounter = M.actionIdCounter + 1
  return M.actionIdCounter
end

-- Clear all action functions
local function clearActionFunctions()
  M.actionFunctions = {}
end

-- Add an action with callback function
local function addAction(callback, meta)
  local actionId = getFreeActionId()
  M.actionFunctions[actionId] = callback

  meta = meta or {}
  meta.actionId = actionId
  return meta
end

-- Execute action callback by ID
local function executeAction(actionId)
  if M.actionFunctions[actionId] then
    M.actionFunctions[actionId]()
    return "success"
  else
    log("E", "", "Action function not found for ID: " .. tostring(actionId))
    return "error"
  end
end

-- POI type icons mapping
local poiTypeIcons = {
  spawnPoint = 'fastTravel',
  garage = 'garage01',
  gasStation = 'fuelPump',
  dealership = 'carDealer',
  logisticsParking = 'boxTruckFast',
  logisticsOffice = 'boxTruckFast',
  driftSpot = 'drift01',
  dragstrip = 'drag02',
  crawl = 'mission_rockcrawling01_triangle',
  playerVehicle = 'carStarred',
  other = 'info',
}

-- Format POI for bigmap
local function formatPoiForBigmap(poi)
  local bmi = poi.markerInfo.bigmapMarker
  local qtEnabled = ((not career_career.isActive()) or (career_modules_linearTutorial.getTutorialFlag('quickTravelEnabled'))) and bmi.quickTravelPosRotFunction
  local icon = bmi.cardIcon or poiTypeIcons[poi.data.type]
  local actions = {}
  table.insert(actions, addAction(
    function()
      freeroam_bigMapMode.navigateToMission(poi.id)
    end,
    {
      id = "setRoute",
      label = "Set Route",
      icon = "mapPoint",
    }
  ))

  if qtEnabled then
    table.insert(actions, addAction(
      function()
        freeroam_bigMapMode.teleportToPoi(poi.id)
      end,
      {
        id = "quickTravel",
        label = "Quick Travel",
        icon = "fastTravel",
      }
    ))
  end

  return {
    id = poi.id,
    icon = icon,
    name = bmi.name,
    description = bmi.description,
    thumbnailFile = bmi.thumbnail,
    previewFiles = bmi.previews,
    type = poi.data.type,
    label = '',
    aggregatePrimary = bmi.aggregatePrimary,
    aggregateSecondary = bmi.aggregateSecondary,
    actions = actions,
  }
end

-- Format mission for bigmap
local function formatMissionForBigmap(elemData)
  local mission = gameplay_missions_missions.getMissionById(elemData.missionId)
  local qtEnabled = (not career_career.isActive()) or (career_modules_linearTutorial.getTutorialFlag('quickTravelEnabled'))
  if mission then
    local ret = {
      id = elemData.missionId,
      icon = mission.iconFontIcon,
      idInCluster = elemData.idInCluster,
      name = mission.name,
      label = mission.missionTypeLabel or mission.missionType,
      description = mission.description,
      thumbnailFile = mission.thumbnailFile,
      previewFiles = {mission.previewFile},
      type = "mission",
      devMission = mission.devMission or false,
    }
    ret.formattedProgress = gameplay_missions_progress.formatSaveDataForUi(elemData.missionId)

    for key, val in pairs(gameplay_missions_progress.formatSaveDataForBigmap(mission.id) or {}) do
      ret[key] = val
    end

    local actions = {}

    table.insert(actions, addAction(
      function()
        freeroam_bigMapMode.navigateToMission(ret.id)
      end,
      {
        id = "setRoute",
        label = "Set Route",
        icon = "mapPoint",
      }
    ))

    if qtEnabled then
      table.insert(actions, addAction(
        function()
          freeroam_bigMapMode.teleportToPoi(ret.id)
        end,
        {
          id = "quickTravel",
          label = "Quick Travel",
          icon = "fastTravel",
        }
      ))
    end
    ret.actions = actions

    return ret
  end
  return nil
end


local noBranch = "branch_noBranch"
-- Helper function to build group data structure
local function buildGroupData()

  local groupData = {
    type_mission = {label = "Mission"},
    type_driftSpots = {label = "Drift Spots", icon = "drift01"},
    type_dragstrip = {label = "Dragstrips", icon = "drag02"},
    type_crawl = {label = "Crawl Trails", icon = "mission_rockcrawling01_triangle"},
    type_spawnPoint = {label = "Quicktravel Points", icon = "fastTravel"},
    type_garage = {label = "Garages", icon = "garage01"},
    type_gasStation = {label = "Gas Stations", icon = "fuelPump"},
    type_dealership = {label = "Dealerships", icon = "carDealer"},
    type_playerVehicle = {label = "Player Vehicles", icon = "carStarred"},
    type_other = {label = "Other"},

  }

  if career_career.isActive() then
    groupData.delivery_facility = {label = "Logistics: Delivery Facility"}
    groupData.delivery_dropoff = {label = "Logistics: Delivery Dropoff"}

    for _, branch in ipairs(career_branches.getSortedBranches()) do
      if branch and not branch.isDomain then
        local domain = career_branches.getBranchById(branch.parentDomain)
        groupData["branch_"..branch.id] = {label = {txt = "ui.career.domainSlashBranch", context={domain=domain.name, branch=branch.name}}}
      end
    end
    groupData[noBranch] = {label = "Branchless Missions"}
  end

  for groupKey, gr in pairs(groupData) do
    gr.elements = {}
  end

  return groupData
end

-- Helper function to process mission POI data
local function processMissionPoi(poi, groupData)
  local formatted = formatMissionForBigmap(poi.data)
  local filterData = {
    groupTags = {},
    sortingValues = {}
  }

  filterData.sortingValues['id'] = poi.id
  filterData.groupTags['type_mission'] = true

  local mission = gameplay_missions_missions.getMissionById(poi.data.missionId)
  -- general data
  filterData.groupTags['missionType_'..mission.missionTypeLabel] = true
  if not groupData['missionType_'..mission.missionTypeLabel] then
    groupData['missionType_'..mission.missionTypeLabel] = {label = mission.missionTypeLabel, elements = {}, icon = mission.iconFontIcon}
  end
  filterData.sortingValues['depth'] = mission.unlocks.depth

  if career_career.isActive() and mission.careerSetup.skill then
    local skill = career_branches.getBranchById(mission.careerSetup.skill)
    if skill then
      filterData.groupTags['branch_'..skill.id] = true
    end
  end

  filterData.sortingValues['maxBranchTier'] = mission.unlocks.maxBranchlevel
  filterData.groupTags['maxBranchTier_'..mission.unlocks.maxBranchlevel] = true
  groupData['maxBranchTier_'..mission.unlocks.maxBranchlevel] = {label = 'Tier ' .. mission.unlocks.maxBranchlevel, elements = {}}

  -- custom groups/tags
  if mission.grouping.id ~= "" then
    local gId = 'missionGroup_'..mission.grouping.id
    if not groupData[gId] then
      groupData[gId] = {elements = {}, icon = mission.iconFontIcon}
    end
    if mission.grouping.label ~= "" and groupData[gId].label == nil then
      groupData[gId].label = mission.grouping.label
    end
    filterData.groupTags[gId] = true
  end

  filterData.sortingValues['starCount'] = formatted.rating.totalStars
  filterData.sortingValues['defaultUnlockedStarCount'] = formatted.rating.defaultUnlockedStarCount
  filterData.sortingValues['totalUnlockedStarCount'] = formatted.rating.totalUnlockedStarCount

  return formatted, filterData
end

-- Helper function to process non-mission POI data
local function processNonMissionPoi(poi, groupData)
  local formatted = formatPoiForBigmap(poi)
  local filterData = {
    groupTags = {},
    sortingValues = {}
  }

  filterData.sortingValues['id'] = poi.id

  if poi.data.type == 'spawnPoint' then
    filterData.groupTags['type_spawnPoint'] = true
  elseif poi.data.type == 'garage' then
    filterData.groupTags['type_garage'] = true
  elseif poi.data.type == 'gasStation' then
    filterData.groupTags['type_gasStation'] = true
  elseif poi.data.type == 'dealership' then
    filterData.groupTags['type_dealership'] = true
  elseif poi.data.type == "logisticsParking" then
    filterData.groupTags['delivery_dropoff'] = true
  elseif poi.data.type == 'logisticsOffice' then
    filterData.groupTags['delivery_facility'] = true
  elseif poi.data.type == "driftSpot" then
    filterData.groupTags['type_driftSpots'] = true
  elseif poi.data.type == "dragstrip" then
    filterData.groupTags['type_dragstrip'] = true
  elseif poi.data.type == "crawl" then
    filterData.groupTags['type_crawl'] = true
  elseif poi.data.type == "playerVehicle" then
    filterData.groupTags['type_playerVehicle'] = true
  else -- other
    filterData.groupTags['type_other'] = true
  end

  return formatted, filterData
end

-- Helper function to build POI data cache
local function buildPoiDataCache(level)
  gameplay_rawPois.clear()
  local poiData = {}
  local groupData = buildGroupData()
  for _, poi in ipairs(gameplay_rawPois.getRawPoiListByLevel(level)) do
    if poi.markerInfo.bigmapMarker then
      local formatted, filterData

      if poi.data.type == 'mission' then
        formatted, filterData = processMissionPoi(poi, groupData)
      else
        formatted, filterData = processNonMissionPoi(poi, groupData)
      end

      formatted.spriteIcon = poi.markerInfo.bigmapMarker.icon

      poiData[poi.id] = formatted
      poiData[poi.id].filterData = filterData

      for tag, include in pairs(filterData.groupTags) do
        if include then
          if not groupData[tag] then
            log("W","","Unknown group tag: " .. dumps(tag) .. " for poi " .. dumps(poi.id))
            groupData[tag] = {label = tag, elements = {}}
          end
          table.insert(groupData[tag].elements, poi.id)
        end
      end
    end
  end

  -- Sort elements in each group
  for key, gr in pairs(groupData) do
    local elementsAsPois = {}
    for i, id in ipairs(gr.elements) do elementsAsPois[i] = poiData[id] end
    table.sort(elementsAsPois,gameplay_missions_unlocks.depthIdSort)
    for i, poi in ipairs(elementsAsPois) do gr.elements[i] = elementsAsPois[i].id end
    gr.key = key
  end


  return poiData, groupData
end

-- helper function to build group structure
local function buildGroupStructure(poisById, groupsById)
  local groupStructure = {}

  if not career_career.isActive() then
    table.insert(groupStructure, {
      key = 'freeroamPois',
      icon = 'mapPoint',
      title = 'bigMap.sideMenu.pois',
      groups = {
        groupsById['type_spawnPoint'],
        groupsById['type_gasStation'],
        groupsById['type_driftSpots'],
        groupsById['type_dragstrip'],
        groupsById['type_crawl'],
        groupsById['type_other'],
      }
    })
    table.insert(groupStructure, {
      key = 'missionsByType',
      icon = 'flag',
      title = 'Challenges',
      groups = {},
    })
    local sortedGroupIds = tableKeysSorted(groupsById)
    for _, groupId in ipairs(sortedGroupIds) do
      if string.startswith(groupId, 'missionType_') then
        table.insert(groupStructure[2].groups, groupsById[groupId])
      end
    end
  else
    table.insert(groupStructure, {
      key = 'freeroamPois',
      icon = 'mapPoint',
      title = 'bigMap.sideMenu.pois',
      groups = {
        groupsById['type_playerVehicle'],
        groupsById['type_dealership'],
        groupsById['type_garage'],
        groupsById['type_gasStation'],
        groupsById['type_dragstrip'],
        groupsById['type_crawl'],
        groupsById['type_other'],
      }
    })
    local branchOrdered = career_branches.orderBranchNamesKeysByBranchOrder()
    for _, domainId in ipairs(branchOrdered) do
      local domain = career_branches.getBranchById(domainId)
      if domain.isDomain then
        local hasContent = false
        local filter = {
          key = 'domain_'..domainId,
          icon = domain.icon,
          title = domain.name,
          groups = {}
        }
        if domain.id == "logistics" then
          table.insert(filter.groups, groupData['delivery_dropoff'])
          table.insert(filter.groups, groupData['delivery_facility'])
          hasContent = true
        end

        if domain.id == "apm" then
          poiData["apmChallengeInfo"] = {
            id = "apmChallengeInfo",
            type = "apmChallengeInfo",
            name = "APM Challenges",
            description = "APM Challenges and progress can be found in the Career Paths Menu.",
            thumbnailFile = domain.thumbnail,
            previewFiles = {domain.progressCover},
          }
          table.insert(filter.groups, {
            label = "APM Challenges",
            elements = { "apmChallengeInfo" }
          })
          hasContent = true
        end

        for _, branchId in ipairs(branchOrdered) do
          local branch = career_branches.getBranchById(branchId)
          if branch.parentDomain == domainId then
            if groupData['branch_'..branchId] and next(groupData['branch_'..branchId].elements) then
              table.insert(filter.groups, groupData['branch_'..branchId])
              hasContent = true
            end
            if branch.id == "bmra-drift" then
              table.insert(filter.groups, groupData['type_driftSpots'])
              hasContent = true
            end
            if branch.id == "bmra-crawl" then
              table.insert(filter.groups, groupData['type_crawl'])
              hasContent = true
            end
          end
        end
        if hasContent then
          table.insert(groupStructure, filter)
        end
      end
    end
    if next(groupData['delivery_dropoff'].elements) then
    table.insert(groupStructure, {
      key = 'delivery',
      icon = 'boxTruckFast',
      title = 'Delivery Tasks',
      groups = {
          groupData['delivery_dropoff']
        }
      })
    end
  end

  return groupStructure
end

local function buildFilters(groupStructure)
  local filters = {}
  for _, section in ipairs(groupStructure) do
    local filterSection = {
      key = section.key,
      icon = section.icon,
      title = section.title,
      groups = {}
    }
    for _, group in ipairs(section.groups) do
      if filterVisibilityState[group.key] == nil then
        filterVisibilityState[group.key] = true
      end
      local visible = filterVisibilityState[group.key]
      table.insert(filterSection.groups, {
        key = group.key,
        label = group.label,
        icon = group.icon,
        elementCount = #group.elements,
        visible = visible,
      })
    end
    table.insert(filters, filterSection)
  end
  return filters
end
-- Function to generate cache data
local function generateCacheData()
  log("I", "", "Generating cache data for bigmap...")
  local level = getCurrentLevelIdentifier()

  M.clearActionFunctions()

  -- Build POI data cache
  local poisById, groupsById = buildPoiDataCache(level)
  local groupStructure = buildGroupStructure(poisById, groupsById)
  local filters = buildFilters(groupStructure)

  poiDataCache = poisById
  groupStructureCache = groupStructure
  filterStructureCache = filters

  local gameStateInfoCache = {
    rules = {
      canSetRoute = true
    }
  }
  for _, lvl in ipairs(core_levels.getList()) do
    if string.lower(lvl.levelName) == getCurrentLevelIdentifier() then
      gameStateInfoCache.levelData = lvl
    end
  end
  gameStateInfoCache.gameMode = "freeroam"
  if career_career and career_career.isActive() then
    gameStateInfoCache.gameMode = "career"
    gameStateInfoCache.rules.canSetRoute = not career_modules_testDrive.isActive()
  end
  if gameplay_missions_missionManager.getForegroundMissionId() then
    gameStateInfoCache.gameMode = "mission"
  end

  cacheValid = true
end

-- Main functions
local function enterBigMap()
  -- Delegate to existing bigmap mode
  if freeroam_bigMapMode then
    freeroam_bigMapMode.enterBigMap({instant = true})
  end

  -- Generate cache data
  generateCacheData()


  M.setVisibleIds()

end

local function exitBigMap()
  -- Delegate to existing bigmap mode
  if freeroam_bigMapMode then
    freeroam_bigMapMode.exitBigMap(true)
  end

  -- Clear caches
  invalidateCache()

  -- Clear action functions
  clearActionFunctions()
end

local function getPoiData()
  if not cacheValid then
    generateCacheData()
  end
  return poiDataCache
end

local function getFilters()
  if not cacheValid then
    generateCacheData()
  end
  for _, section in ipairs(filterStructureCache) do
    for _, group in ipairs(section.groups) do
      group.visible = filterVisibilityState[group.key]
    end
  end
  return filterStructureCache
end

local function getGroups()
  if not cacheValid then
    generateCacheData()
  end
  local validIds = nil

  local groups = {}
  for _, section in ipairs(groupStructureCache) do
    local validSection = false
    local groupSection = {
      key = section.key,
      icon = section.icon,
      title = section.title,
      groups = {}
    }
    for _, group in ipairs(section.groups) do
      local visible = filterVisibilityState[group.key]
      if visible and group.elements and #group.elements > 0 then
        local validPoiIds = {}
        for _, poiId in ipairs(group.elements) do
          if validIds == nil or validIds[poiId] then
            table.insert(validPoiIds, poiId)
          end
        end
        if #validPoiIds > 0 then
          table.insert(groupSection.groups, {
            key = group.key,
            label = group.label,
            icon = group.icon,
            elementIds = validPoiIds,
            visible = true,
          })
          validSection = true
        end
      end
    end
    if validSection then
      table.insert(groups, groupSection)
    end
  end

  return groups
end

local function getGameStateInfo()
  if not cacheValid then
    generateCacheData()
  end
  return gameStateInfoCache
end

local function setVisibleIds()
  local visibleIds = {}
  for _, groupSection in ipairs(groupStructureCache) do
    for _, group in ipairs(groupSection.groups) do
      if filterVisibilityState[group.key] then
        for _, poiId in ipairs(group.elements) do
          visibleIds[poiId] = true
        end
      end
    end
  end
  if freeroam_bigMapMode then
    freeroam_bigMapMode.setOnlyIdsVisible(tableKeys(visibleIds))
  end
end

local function selectPoiFromList(poiId)
  if freeroam_bigMapMode then
    if poiId then
      freeroam_bigMapMode.selectPoi(poiId)
    else
      freeroam_bigMapMode.deselect()
    end
  end
  return "success"
end

local function onPoiSelectedFromBigmap(poiId)
  if poiId then
    local poiIds = freeroam_bigMapMarkers.getIdsFromHoveredPoiId(poiId)
    if not tableIsEmpty(poiIds) then
    guihooks.trigger("showPoiDetails", {poiIds = poiIds})
    else
      guihooks.trigger("showPoiDetails", {})
    end
  else
    guihooks.trigger("showPoiDetails", {})
  end
end
M.onPoiSelectedFromBigmap = onPoiSelectedFromBigmap

local function hoverPoiFromList(poiId, active)
  if freeroam_bigMapMode then
    freeroam_bigMapMode.poiHovered(poiId, active)
  end
  return "success", active
end

local function executePoiAction(actionId)
  executeAction(actionId)
end

-- Return module functions
M.enterBigMap = enterBigMap
M.exitBigMap = exitBigMap
M.getPoiData = getPoiData
M.getFilters = getFilters
M.getGroups = getGroups
M.toggleFiltersByIds = toggleFiltersByIds
M.toggleFilterSectionById = toggleFilterSectionById
M.getGameStateInfo = getGameStateInfo
M.selectPoiFromList = selectPoiFromList
M.hoverPoiFromList = hoverPoiFromList
M.executePoiAction = executePoiAction
M.setVisibleIds = setVisibleIds

-- Action management functions
M.getFreeActionId = getFreeActionId
M.clearActionFunctions = clearActionFunctions
M.addAction = addAction
M.executeAction = executeAction
return M