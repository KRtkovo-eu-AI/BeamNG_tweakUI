-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local function applyFilter(checkResult, key)
  if checkResult then
    input.setAllowedInputSource(key, 'adas', true)
    input.setAllowedInputSource(key, 'local', false)
  else
    input.setAllowedInputSource(key, 'local', true)
    input.setAllowedInputSource(key, 'adas', false)
  end
  return checkResult
end

local function filterAdasInput(val, key)
  if key == 'throttle' then
    return applyFilter((val < (input.lastInputs["local"][key] or 1)), key)
  elseif key == 'brake' then
    return applyFilter((val > (input.lastInputs["local"][key] or 0)), key)
  else
    return true
  end
end

local function applyAdasInput(val, key)
  if filterAdasInput(val, key) then
    if key == 'steering' then
      hydros.setExternalForce(val)
    else
      input.event(key, val, 1, nil, nil, nil, 'adas')
    end
  end
end

-- Public interfacce
M.applyAdasInput = applyAdasInput

return M