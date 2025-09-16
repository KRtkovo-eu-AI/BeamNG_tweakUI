-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local appsDir = '/ui/modules/apps/'
local layoutPath = '/settings/ui_apps/layouts/'
local originalLayoutPath = '/settings/ui_apps/originalLayouts/'

local function getAvailableAppList()
  local jsonFiles = FS:findFiles(appsDir, 'app.json', -1, false, false)
  local res = {}
  for _, fn in ipairs(jsonFiles) do
    local appDir, dn, ext = path.split(fn)
    if appDir then
      local appData = jsonReadFile(fn)
      appData.official = isOfficialContentVPath(fn)
      appData.previews = {
        imageExistsDefault(appDir..'app.png'),
        fileExistsOrNil(appDir..'app2.png'),
        fileExistsOrNil(appDir..'app3.png'),
      }

      if not appData.types then
        appData.types = {'ui.apps.categories.unknown'}
      end

      appData["appName"] = appData["appName"] or appData["directive"]

      if appData["domElement"] and appData["directive"] and appData["appName"] then
        appData["jsSource"] = appDir..'app.js'
        res[appData.appName] = appData
      else
        log('E', 'apps', 'invalid app data:' .. tostring(fn) .. ': missing "domElement" or "directive" in app.json - IGNORING APP: ' .. dumps(appData))
      end
      --dump(appData)
    else
      log('E', 'apps', 'unable to read app from dir:' .. tostring(fn))
    end
  end
  return res
end

local function getAppIndexByName(layout, appName)
  if layout and layout.apps then
    for i, app in ipairs(layout.apps) do
      if app.appName == appName then
        return i
      end
    end
  end
  return nil
end

local function getAvailableLayouts()
  local res = {}
  for _, originalFilePath in ipairs(FS:findFiles(originalLayoutPath, '*.uilayout.json', -1, false, false)) do
    local userFilePath = originalFilePath:gsub(originalLayoutPath, layoutPath)
    local replace = false
    local origLayout = jsonReadFile(originalFilePath)
    if FS:fileExists(userFilePath) then
      local userLayout = jsonReadFile(userFilePath)
      local userLayoutChanged = false

      -- the legacy system of updating old user layouts which updates the whole layout at once
      -- copy over original if the user file version is older.
      if origLayout.version and (not userLayout.version or origLayout.version > userLayout.version) then
        userLayout = origLayout
        userLayoutChanged = true
      end

      -- go through the apps of the original layout one by one and update them in the user layout if they are newer
      if not userLayoutChanged then
        for _, originalApp in ipairs(origLayout.apps) do
          if originalApp.appVersion then
            local userAppIndex = getAppIndexByName(userLayout, originalApp.appName)
            if userAppIndex then
              local userApp = userLayout.apps[userAppIndex]
              if userApp.appVersion == nil or userApp.appVersion < originalApp.appVersion then
                userLayout.apps[userAppIndex] = originalApp
                userLayoutChanged = true
              end
            elseif not (userLayout.removedApps and userLayout.removedApps[originalApp.appName] and userLayout.removedApps[originalApp.appName] >= originalApp.appVersion) then
              -- add new app to user layout
              table.insert(userLayout.apps, originalApp)
              userLayoutChanged = true
            end
          end
        end
      end

      -- if the original layout has removed apps, remove them from the user layout
      if origLayout.removedApps then
        for appName, appVersion in pairs(origLayout.removedApps) do
          local userAppIndex = getAppIndexByName(userLayout, appName)
          if userAppIndex then
            local userApp = userLayout.apps[userAppIndex]
            if userApp.appVersion == nil or userApp.appVersion < appVersion then
              table.remove(userLayout.apps, userAppIndex)
              userLayoutChanged = true
            end
          end
        end
      end

      if userLayoutChanged then
        jsonWriteFile(userFilePath, userLayout, true)
        log("I","",string.format("User layout was updated. File: %s", userFilePath))
      end
    else
      -- if no user file is found, add this layout to the return list
      origLayout.filename = userFilePath
      if originalFilePath:find('default') then
        origLayout.default = true
      end
      table.insert(res, origLayout)
    end
  end
  -- now go over all files in the user-ui folder and add them too.
  local jsonFiles = FS:findFiles(layoutPath, '*.uilayout.json', -1, false, false)
  for _, fn in ipairs(jsonFiles) do
    local layout = jsonReadFile(fn)

    if fn:find('default') then
      layout.default = true
    end
    layout.filename = fn
    table.insert(res, layout)
  end
  return res
end
M.getAvailableLayouts = getAvailableLayouts

local function getUIAppsData()
  return {availableLayouts = getAvailableLayouts(), availableApps = getAvailableAppList()}
end

local function requestUIAppsData()
  guihooks.trigger('onUIAppsData', getUIAppsData())
end

local function updateData(data)
  local version = data.version
  -- otherwise find original layout and return that version.
  if data.filename then
    -- find original layout for this file
    local originalFilePath = data.filename:gsub(layoutPath, originalLayoutPath)
    if FS:fileExists(originalFilePath) then
      local originalLayout = jsonReadFile(originalFilePath)
      for _, app in ipairs(originalLayout.apps) do
        local appIndex = getAppIndexByName(data, app.appName)
        if appIndex then
          -- if the app is in the user layout, update the app version with the original layout version
          data.apps[appIndex].appVersion = app.appVersion
        else
          -- if the app is not in the user layout, add it to the removed apps
          data.removedApps = data.removedApps or {}
          data.removedApps[app.appName] = app.appVersion
        end
      end

      -- if the app doesnt have a version, check if it is in the removed apps of the original layout and set the version to the removed app version
      for _, app in ipairs(data.apps) do
        if not app.appVersion then
          app.appVersion = originalLayout.removedApps and originalLayout.removedApps[app.appName]
        end
      end

      if not version and originalLayout then
        version = originalLayout.version
      end
    end
  end
  data['version'] = version
end

local function saveLayout(data)
  if not data['filename'] then
    dump({'invalid layout save data. Filename missing: ', data})
    return
  end
  updateData(data)
  local filename = data['filename']
  data['filename'] = nil
  jsonWriteFile(filename, data, true)
  --dump({'saved layout: ' .. tostring(filename), data})
  requestUIAppsData()
end


local function deleteLayout(filenameToDelete)
  --dump({'deleteLayout', filenameToDelete})
  local layouts = getAvailableLayouts()
  for _, layout in ipairs(layouts) do
    --dump({'delete?', layout.filename, filenameToDelete})
    if layout.filename == filenameToDelete then
      if not isOfficialContentVPath(layout.filename) then
        log('I', '', 'deleting layout: ' .. tostring(layout.filename))
        FS:removeFile(layout.filename)
        requestUIAppsData()
      else
        log('I', '', 'will not delete file as it is part of the official content distribution: ' .. tostring(layout.filename))
        requestUIAppsData()
      end
      return
    end
  end
  log('E', '', 'unable to delete layout - file not found: ' .. tostring(filenameToDelete))
end

-- Update apps list whenever there is a filesystem change in the apps directory.
-- This way, UI will stay informed about the apps' list without having to
-- explicitly request for it every time it is needed (an initial request is still needed).
local function onFilesChanged(files)
  for _,v in pairs(files) do
    local filename = v.filename
    if string.startswith(filename, appsDir) or string.startswith(filename, '/mods/') then
      requestUIAppsData()
      return
    end
  end
end

local function isAppOnLayout (appDirective, layout)
  local layouts = getLayouts()
  if layouts[layout] == nil then
    log('D', '', 'layout not existing', layout)
    return
  end
  for k,v in pairs(layouts[layout]) do
    if v.directive == appDirective then
      return true
    end
  end
  return false
end

M.onFilesChanged = onFilesChanged

M.requestUIAppsData = requestUIAppsData
M.getUIAppsData = getUIAppsData
M.saveLayout = saveLayout
M.deleteLayout = deleteLayout
M.isAppOnLayout = isAppOnLayout

return M
