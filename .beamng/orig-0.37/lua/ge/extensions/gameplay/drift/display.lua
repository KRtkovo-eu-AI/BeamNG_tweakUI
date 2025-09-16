-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt
local M = {}

M.dependencies = {"gameplay_drift_general", "gameplay_drift_drift", "gameplay_drift_scoring", "ui_apps_genericMissionData"}
local im = ui_imgui
local driftDebugInfo = {
  default = false,
  canBeChanged = true
}

local flashTime = 1.5
local msgData = {}
local score

local wrongWayFlag = false
local outOfBoundsFlag = false
local creepSmoother = newTemporalSmoothingNonLinear(50,10, 0)

local driftDebugUILayout = false

local guiData = {}


local function rtMessage(msg)
  msgData.msg = msg
  msgData.context = "drift"
  guihooks.trigger('ScenarioRealtimeDisplay', msgData)
end

local function clearRt()
  table.clear(msgData)
  msgData.msg = ""
  guihooks.trigger('ScenarioRealtimeDisplay', msgData)
end

local function flashMessage(msg, duration)
  duration = duration or flashTime

  local messageData = {{msg, flashTime, 0, false}}

  -- Original direct UI trigger for backward compatibility
  guihooks.trigger('DriftFlashMessage', messageData)

  -- Also hook into gameplayAppContainers for intelligent routing
  extensions.hook('onGameplayFlashMessage', {
    source = 'drift',
    data = messageData
  })
end

local function onDriftCompletedScored(data)
  --guihooks.trigger("setDriftRemainingComboTime", 0)
  guiData.realtimeRemainingComboTime = 0
  --guihooks.trigger("setDriftRealtimeCreep", 0)
  guiData.realtimeCreep = 0
  creepSmoother:set(0)

  flashMessage(string.format("+ %i points", data.addedScore))
  guihooks.trigger("setDriftPersistentDriftScored", data.addedScore, data.combo)

  clearRt()
end

local function onDriftCrash()
  guihooks.trigger("setDriftRealtimeFail", "Crashed!")
  -- Ensure UI resets remaining time and creep immediately on crash
  --guihooks.trigger("setDriftRemainingComboTime", 0)
  --guihooks.trigger("setDriftRealtimeCreep", 0)
  guiData.realtimeRemainingComboTime = 0
  guiData.realtimeCreep = 0
  guihooks.queueStream("drift", guiData)

  creepSmoother:set(0)
  clearRt()
end

local function onDriftSpinout()
  guihooks.trigger("setDriftRealtimeFail", "Spinout!")
  -- Ensure UI resets remaining time and creep immediately on spinout
  --guihooks.trigger("setDriftRemainingComboTime", 0)
  --guihooks.trigger("setDriftRealtimeCreep", 0)
  guiData.realtimeRemainingComboTime = 0
  guiData.realtimeCreep = 0
  guihooks.queueStream("drift", guiData)


  creepSmoother:set(0)
  clearRt()
end

local function onDonutDriftScored(score)
  flashMessage(string.format("Donut! + %i points", score))
  guihooks.trigger("stuntZoneScored",{type = "donut", score = score})
end

local function onNearPoleScored(score)
  flashMessage(string.format("Near pole drift! + %i points", score))
  guihooks.trigger("stuntZoneScored",{type = "nearPole", score = score})
end

local function onTightDriftScored(score)
  flashMessage(string.format("Drift through! + %i points", score))
  guihooks.trigger("stuntZoneScored",{type = "tightDrift", score = score})
end

local function onHitPoleScored(score)
  flashMessage(string.format("Pole hit! + %i points", score))
  guihooks.trigger("stuntZoneScored",{type = "hitPole", score = score})
end

local function updateApps(dtReal)
  if not gameplay_drift_general.getIsThereAnyDriftUIAppDisplayed() then return end

  score = gameplay_drift_scoring.getScore()
  local scoreOptions = gameplay_drift_scoring.getScoreOptions()

  --guihooks.trigger("setDriftPermanentAndPotentialScore", score.score, score.potentialScore)
  guiData.permanentScore = score.score
  guiData.potentialScore = score.potentialScore

  if score.cachedScore > 0 then
    --guihooks.trigger("setDriftRealtimeScore", math.floor(score.cachedScore), score.combo)
    guiData.realtimeCachedScoreFloored = math.floor(score.cachedScore)
    guiData.realtimeCombo = score.combo
    --guihooks.trigger("setDriftRemainingComboTime", gameplay_drift_drift.getCurrDriftCompletedTime())
    guiData.realtimeRemainingComboTime = gameplay_drift_drift.getCurrDriftCompletedTime()
    local creepPercent = score.comboCreepup / 100
    if score.combo >= scoreOptions.comboOptions.comboSoftCap then
      creepPercent = 1
    end

    --guihooks.trigger("setDriftRealtimeCreep", creepSmoother:get(creepPercent, dtReal))
    guiData.realtimeCreep = creepSmoother:get(creepPercent, dtReal)
  end
  --guihooks.trigger("setDriftPerformanceFactor", gameplay_drift_scoring.getSteppedDriftPerformanceFactor())
  guiData.realtimePerformanceFactor = gameplay_drift_scoring.getSteppedDriftPerformanceFactor()

  local airspeed =  gameplay_drift_drift.getAirSpeed() or 0
  local angle = gameplay_drift_drift.getCurrDegAngleSigned() or 0
  local isDrifting = gameplay_drift_drift.getIsDrifting()


  if math.abs(angle) < gameplay_drift_drift.getDriftOptions().maxAngle and gameplay_drift_drift.getIsOverSteering() and gameplay_drift_drift.getIsOverMinSpeedForDrift() and not gameplay_drift_drift.getIsInTheAir() and not gameplay_walk.isWalking() then
    --guihooks.trigger("setDriftRealtimeAngle", angle )
    guiData.realtimeAngle = round(angle)
  else
    --guihooks.trigger("setDriftRealtimeAngle", 0)
    guiData.realtimeAngle = 0
  end

  if isDrifting then
    if angle == math.huge or angle == -math.huge or airspeed < 2 then angle = 0 end
    --guihooks.trigger("setDriftRealtimeAirSpeed",airspeed)
    guiData.realtimeAirSpeed = airspeed
  else
    --guihooks.trigger("setDriftRealtimeAirSpeed", 0)
    guiData.realtimeAirSpeed = 0
  end
  guihooks.queueStream("drift", guiData)
end

local function displayRemainingDist()
  if gameplay_drift_destination and not gameplay_drift_destination.getDisableWrongWayAndDist() then
    local remainingDist = gameplay_drift_destination.getRemainingDist() or 0
    local data = {
      title = "missions.missions.general.distRemaining",
      txt = string.format("%d m", remainingDist),
      meters = remainingDist,
      category = "drift",
      style = "text",
      order = 10,
    }

    ui_apps_genericMissionData.setData(data)
  end
end

local function displayWrongWay()
  if not gameplay_drift_destination then return end

  if gameplay_drift_freeroam_driftSpots and gameplay_drift_freeroam_driftSpots.getIsInFreeroamChallenge() then
    return
  end

  if gameplay_drift_destination.getGoingWrongWay() and not outOfBoundsFlag then
    rtMessage(translateLanguage("missions.drift.general.wrongWayFirst", "missions.drift.general.wrongWayFirst"))
    wrongWayFlag = true
  elseif wrongWayFlag then
    clearRt()
    wrongWayFlag = false
  end
end

-- "Out of bounds" message has higher priority than the "Wrong way" message
local function displayOutOfBounds()
  if not gameplay_drift_bounds then return end

  local isInConcludingPhase = gameplay_drift_freeroam_driftSpots and gameplay_drift_freeroam_driftSpots.getIsInTheConcludingPhase()

  if gameplay_drift_bounds.getIsOutOfBounds() and not isInConcludingPhase then
    rtMessage(translateLanguage("missions.crawl.general.outOfBounds", "missions.crawl.general.outOfBounds"))
    outOfBoundsFlag = true
  elseif outOfBoundsFlag then
    clearRt()
    outOfBoundsFlag = false
  end
end

local function setDriftUILayout(value, onlyDriftAngle)
  if onlyDriftAngle == nil then onlyDriftAngle = false end

  if not onlyDriftAngle then
    core_gamestate.setGameState('freeroam', ((value and 'driftMission') or 'freeroam'), 'freeroam')
  end

  if value then
    ui_gameplayAppContainers.showApp('gameplayApps', 'drift')
  else
    ui_gameplayAppContainers.hideApp('gameplayApps', 'drift')
  end

  driftDebugUILayout = value
end

local function imguiDebug()
  if gameplay_drift_general.getExtensionDebug("gameplay_drift_display") then
    if im.Begin("Drift display") then
      if im.Button("Toggle drift ui layout") then
        setDriftUILayout(not driftDebugUILayout)
      end
    end
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  imguiDebug()
  updateApps(dtReal)
  --[[
    im.Begin("Drift display")
    im.Text("Drift display")
    im.TextWrapped(dumps(guiData))
    im.End()
  ]]

  score = gameplay_drift_scoring.getScore()

  displayWrongWay()
  displayOutOfBounds()
  displayRemainingDist()
end

local function onFreeroamChallengeCompleted(data)
  core_jobsystem.create(function(job)
    rtMessage(string.format(data.newRecord and "New record! Score: %i" or "Drift zone finished! Score: %i", data.score))
    job.sleep(data.duration)
    clearRt()
  end
  )
end

local function onDriftQuickMessageDisplay(data)
  guihooks.trigger('displayDriftScoreModifier', data.msg )
end

local function onDriftPlVehReset()
  --guihooks.trigger("setDriftRealtimeScore", 0, 0)
  --guihooks.trigger("setDriftRemainingComboTime", 0)
  --guihooks.trigger("setDriftRealtimeCreep", 0)
  guiData.realtimeCachedScoreFloored = 0
  guiData.realtimeCombo = 0
  guiData.realtimeRemainingComboTime = 0
  guiData.realtimeCreep = 0
  guihooks.queueStream("drift", guiData)
  clearRt()
end

local function onDriftCachedScoreReset()
  --guihooks.trigger("setDriftRealtimeScore", 0, 0)
  guiData.realtimeCachedScoreFloored = 0
  guiData.realtimeCombo = 0
  guihooks.queueStream("drift", guiData)
  clearRt()
end

local function onExtensionUnloaded()
  clearRt()
end

local function onFreeroamDriftZoneNewHighscore()
  flashMessage("New Highscore!")
end

local function onFreeroamChallengeTerminated(reason, msgDisplayTime)
  core_jobsystem.create(function(job)
    rtMessage(reason.msg)
    job.sleep(msgDisplayTime)
    clearRt()
    end
  )
end

local function onDriftScoreWrappedUp(score)
  flashMessage(string.format("+ %i points for current drift", math.floor(score)))
end

local function onNewDriftTierReached(tierData)
  flashMessage(string.format("%s", tierData.name))
end


local function onSerialize()
  setDriftUILayout(false)

  return {
    driftDebugUILayout = driftDebugUILayout
  }
end

local function onDeserialized(data)
  driftDebugUILayout = data.driftDebugUILayout
end

local function onDriftDebugChanged(value)
  if not value then
    setDriftUILayout(false)
  end
end

local function onDriftContextChanged(context)
  if context == "inFreeroamChallenge" or context == "inChallenge" then
    setDriftUILayout(true)
  elseif context == "inFreeroam" then
    setDriftUILayout(false)
  end
end

local function reset()
  ui_apps_genericMissionData.clearData()
end

local function getDriftDebugInfo()
  return driftDebugInfo
end

local function onDriftCruisingToggled(value)
  setDriftUILayout(value, true)
end

M.reset = reset

M.onUpdate = onUpdate
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.onDriftDebugChanged = onDriftDebugChanged

M.onDriftPlVehReset = onDriftPlVehReset
M.onDriftCompletedScored = onDriftCompletedScored
M.onDriftCrash = onDriftCrash
M.onDriftSpinout = onDriftSpinout
M.onDriftQuickMessageDisplay = onDriftQuickMessageDisplay
M.onFreeroamChallengeCompleted = onFreeroamChallengeCompleted
M.onDriftScoreWrappedUp = onDriftScoreWrappedUp
M.onNewDriftTierReached = onNewDriftTierReached

M.onDonutDriftScored = onDonutDriftScored
M.onTightDriftScored = onTightDriftScored
M.onHitPoleScored = onHitPoleScored
M.onNearPoleScored = onNearPoleScored

M.onDriftContextChanged = onDriftContextChanged

M.onDriftCachedScoreReset = onDriftCachedScoreReset
M.onExtensionUnloaded = onExtensionUnloaded
M.onFreeroamDriftZoneNewHighscore = onFreeroamDriftZoneNewHighscore
M.onFreeroamChallengeTerminated = onFreeroamChallengeTerminated

M.getDriftDebugInfo = getDriftDebugInfo
M.getIsThereAnyDriftUIAppDisplayed = getIsThereAnyDriftUIAppDisplayed
M.onDriftCruisingToggled = onDriftCruisingToggled

return M