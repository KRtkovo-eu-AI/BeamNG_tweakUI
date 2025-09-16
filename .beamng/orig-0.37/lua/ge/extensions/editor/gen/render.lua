local Render = {}

local ffi = require "ffi"

local buf = ffi.new("float[?]", math.max(6*1000))

local function toLineBuf(u, v, pos)
	buf[pos + 0] = u.x
	buf[pos + 1] = u.y
	buf[pos + 2] = u.z
	buf[pos + 3] = v.x
	buf[pos + 4] = v.y
	buf[pos + 5] = v.z
end


local pathUp = function(buf, nStep, c, w)
	if w == nil then
		w = 2
	end
	if c == nil then
		c = color(0, 0, 0, 255)
	end
	ffi.C.BNG_DBG_DRAW_LineInstance_MinArgBatch(buf, nStep, w, c)
--    ffi.C.BNG_DBG_DRAW_Line(float x1, float y1, float z1, float x2, float y2, float z2, unsigned int packedCol, bool useZ);
end


Render.graph = function(apath, c, w)
	if not apath then return end
	local n = 0
	for _,pth in pairs(apath) do
		for i=1,#pth-1 do
			toLineBuf(pth[i],pth[i+1],n)
			n = n + 6
		end
	end
	local c = color(math.floor(c[1]*255),math.floor(c[2]*255),math.floor(c[3]*255))
	pathUp(buf, n/6, c, w)
end


Render.set = function(set, c, w)
	if not w then w = 0.02 end
	local campos = core_camera.getPosition()
	for _,pos in pairs(set) do
--			print('?? set:'..tostring(pos)..':'..tostring(campos)..':'..tostring(c))
		local r = w*math.sqrt((pos-campos):length())
		debugDrawer:drawSphere(pos, r, ColorF(c[1],c[2],c[3],c[4] or 1))
	end
end


Render.label = function(list, c, w)
	local c = ColorF(c[1],c[2],c[3],c[4] or 1)
	for _,s in pairs(list) do
--			print('?? label:'..tostring(s[2])..':'..tostring(s[1]))
		debugDrawer:drawText(s[2], String(tostring(s[1])), c)
	end
end


local circleGrid = 16

local function circle(center, r, c, w, dd)
--        print('?? circle:'..tostring(center))
	if not w then w = 1 end
	local v = center + vec3(r,0,0)
--    local v = vec3(center.x+r,center.y,0)

	for i = 1, circleGrid do
		--TODO: use heightmap
		local l = 2*r*math.sin(math.pi/circleGrid)
		local arg = math.pi/2 + (i - 1 + 1/2)*2*math.pi/circleGrid
		local dv = l*vec3(
			math.cos(arg),
			math.sin(arg),
			0)
		toLineBuf(v, v + dv, (i-1)*6)
		if dd then
			debugDrawer:drawLine(v, v+dv, ColorF(1,1,1,1), w)
		end
--        print('?? for_i:'..tostring(i)..tostring(center)..'::'..tostring(r)..' dv='..tostring(dv)..' v='..tostring(v)..tostring(v+dv))
		v = v + dv
	end
	if not dd then pathUp(buf, circleGrid, c, w) end
end


Render.sphere = function(pos, r, c)
	r = r*math.sqrt((pos-core_camera.getPosition()):length())
	debugDrawer:drawSphere(pos, r, ColorF(c[1],c[2],c[3],c[4])) -- ColorF(1,1,0,0.4))
end


local function path(apoint, c, w, dd)
	if not apoint then return end
	if not w then w = 1 end
	for i = 1,#apoint-1 do
		toLineBuf(apoint[i], apoint[i+1], (i-1)*6)
		if dd then
			debugDrawer:drawLine(apoint[i], apoint[i+1], ColorF(1,1,1,1), w)
		end
	end
	if not dd then pathUp(buf, #apoint-1, c, w) end
end


Render.circle = circle
Render.path = path

return Render