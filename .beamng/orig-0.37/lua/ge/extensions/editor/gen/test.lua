local M = {}

local U = require('/lua/ge/extensions/editor/gen/utils')
local E,W,UI,UU

local lo = U.lo


M.clear = function(forestName)
        lo('?? Tst.clear:')
    -- clean bat
    local groupBat = scenetree.findObject('bat')
    if groupBat then
        local list = groupBat:getObjects()
        for _,o in pairs(list) do
            local om = scenetree.findObjectById(tonumber(o))
                lo('?? if_DEL:'..tostring(o)..':'..tostring(om))
            if om then
                om:delete()
            end
        end
        groupBat:deleteAllObjects()
    end
    -- forest
--    scenetree.findObject(forestName):delete()
--    local forest = worldEditorCppApi.createObject("Forest")
--    forest:registerObject(forestName)
--[[
    if false then
        local fdata = core_forest.getForestObject():getData()
        local list = fdata:getItems()
        for _,f in pairs(list) do
            editor.removeForestItem(fdata, f)
        end
    end
]]
--        if true then return end
	-- clean folders
	--- DAE
	local pth = U.path2disk({editor.getLevelPath(), 'bat', 'test'})
	local list = FS:findFiles(pth, '*.dae', -1, true, false)
--		lo('??^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ onVal_gen_unique:'..tostring(pth)..':'..tableSize(amesh))
	for i,s in pairs(list) do
--			lo('?? for_file:'..i..':'..s)
		FS:removeFile(s)
	end
	-- JSON
	list = FS:findFiles(pth, '*.json', -1, true, false)
	for i,s in pairs(list) do
		FS:removeFile(s)
	end
	--- forest
	pth = U.path2disk({editor.getLevelPath(), 'forest'})
	list = FS:findFiles(pth, '*.json', -1, true, false)
--		lo('?? onVal_gen_unique:'..tostring(pth)..':'..tableSize(amesh))
	for i,s in pairs(list) do
--			lo('?? for_file:'..i..':'..s)
		FS:removeFile(s)
	end
    FS:removeFile(editor.getLevelPath()..'/main/MissionGroup/bat/items.level.json')
    -- forest object
--    local forest =
    scenetree.findObject(forestName):delete()
    local forest = worldEditorCppApi.createObject("Forest")
--    forest = scenetree.findObject('theForest')
    forest:registerObject(forestName)

    return forest
end


local function test()
    local groupBat = scenetree.findObject('bat')
        lo('?? test.test:'..tostring(groupBat))
        if true then return end
	if groupBat then
		-- refresh
		local list = groupBat:getObjects()
		-- refresh static mmeshes
		for _,o in pairs(list) do
			local om = scenetree.findObjectById(tonumber(o))
			if om then
				local astep = U.split(om.obj.shapeName, '/', true)
				local dirname = editor.getLevelPath()..'bat/test/'
				local file = io.open(dirname..astep[#astep], "r")
				if file then
					local data = file:read('*all')
					file:close()
					local outputFile = io.open(dirname..astep[#astep], "w")
					if outputFile then
						outputFile:write(data)
						outputFile:close()
					end
				end
			else
--					lo('?? for_module:'..tostring(scenetree.findObject(o)))
				scenetree.findObject(o):delete()
			end
		end
	end
end


M.inject = function(olist)
    if not olist then olist = {} end
        print('?? Tst.inject:'..tableSize(olist))
    E = olist.E
    W = olist.W
    UI = olist.UI
    UU = olist.UU

    M.onUp()
end


M.onUp = function(arg)
        print('?? Tst.onUp:'..tostring(arg)..':'..tostring(E))
--        if true then return end
	editor.clearObjectSelection()
	editor.selectEditMode(editor.editModes.cityEditMode)
--        if true then return end
	E.reload('conf')
	W.reload('conf')
	editor.showWindow('LAT')
	editor.showWindow('TEST')
	UU._MODE = 'conf'
	UU.out._MODE = 'conf'
--	UI.inject({U = UU, W = W})
	UI.hint(editor.editModes.cityEditMode)
--	W.up(D, nil, true, 'conf')

--    test()
end
--M.onUp()


return M