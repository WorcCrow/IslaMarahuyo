-- TerrainGen -- organic island generator for Isla Marahuyo
-- Replaces the old "fused circles on a flat tabletop" island with a noise-shaped
-- landmass: domain-warped coastline, rolling interior, a real ridge in the north,
-- and a sandy shelf under the water. Every existing prop gets a guaranteed patch
-- of land under it via the PADS list, so nothing is stranded in the sea.

local M = {}
local T = workspace.Terrain

local X0, X1 = -880, 880
local Z0, Z1 = -600, 700
local Y_BOT = -36
local CHUNK = 160
local RES = 4
local LAND_T = 0.5

M.X0, M.X1, M.Z0, M.Z1 = X0, X1, Z0, Z1
local nx = math.ceil((X1 - X0) / CHUNK)
local nz = math.ceil((Z1 - Z0) / CHUNK)
M.ChunkCount = nx * nz
M.NX, M.NZ = nx, nz

local function n2(x, z, seed)
	return math.noise(x, z, seed) * 2
end

local function fbm(x, z, seed, oct, freq, gain, lac)
	local amp, f, sum, norm = 1, freq, 0, 0
	for i = 1, oct do
		sum += amp * n2(x * f, z * f, seed + i * 17.3)
		norm += amp
		amp *= gain
		f *= lac
	end
	return sum / norm
end

-- cx, cz, rx, rz, rotation, amplitude
local BLOBS = {
	{-450,   10, 215, 175,  0.30, 1.00}, -- west lobe (Terminal Cove)
	{-245,  -75, 225, 185, -0.28, 1.00}, -- plaza plain
	{  75,  -15, 230, 190,  0.18, 1.00}, -- central
	{ 380,  -55, 205, 165,  0.22, 1.00}, -- Looban east
	{  95, -240, 210, 165,  0.25, 0.95}, -- north headland / ridge
	{ -60,  255, 165, 215,  0.35, 0.95}, -- south peninsula (runs SW)
	{ -25,  440, 155, 115,  0.25, 0.85}, -- treasure beach tip
	{-275,  165, 140, 120,  0.20, 0.80}, -- market shore
	{-520,  175,  90,  70,  0.50, 0.80}, -- south-west tail
	{ 545, -175,  95,  70, -0.55, 0.85}, -- north-east headland
	{ 560,  165, 140, 125, -0.15, 0.92}, -- Kalangitan islet
	{-660,  205,  52,  42,  0.40, 0.80}, -- offshore rocks
	{ 235,  325,  46,  38,  0.10, 0.78},
	{-575, -205,  48,  40,  0.20, 0.78},
	{ 690,  -40,  44,  38,  0.30, 0.76},
	{ 330,  455,  38,  30,  0.15, 0.74},
}

-- x, z, radius, amplitude -- guarantees land under existing props
local PADS = {
	{-495,    0,  95, 0.85}, {-225,  -67,  95, 0.85}, {-270,  180,  80, 0.70},
	{   0,  267,  90, 0.80}, { 120, -225, 100, 0.85}, { 397,  -60,  95, 0.85},
	{ 562,  165, 100, 0.85},
	{-360,  -34,  60, 0.75}, { -98, -104,  60, 0.75}, { 120, -140,  60, 0.75},
	{ 304, -100,  60, 0.75},
	{  98, -155,  55, 0.75}, { 113, -183,  55, 0.75}, { 120, -204,  55, 0.75},
	{ 105, -219,  55, 0.75},
	{-495,   20,  60, 0.75}, { 430,  -40,  70, 0.75}, {-225,  -95,  70, 0.80},
	{-270,  150,  55, 0.70}, {-220,  150,  55, 0.70},
	{ -70,  452,  60, 0.80}, { -25,  458,  60, 0.80}, {  25,  456,  60, 0.80},
	{  70,  450,  60, 0.80},
	{-470,   40,  50, 0.70}, {-560,   70,  50, 0.70}, {-430,  -90,  50, 0.70},
	{-300, -170,  50, 0.70}, {-100, -180,  50, 0.70}, {-140,  400,  50, 0.70},
	{ -40,  440,  50, 0.70}, {  70,  430,  50, 0.70}, { 160,  390,  50, 0.70},
	{ 500, -140,  50, 0.70}, { 480,   30,  50, 0.70}, { 600,   90,  50, 0.70},
	{ 630,  210,  50, 0.70}, { 500,  200,  50, 0.70},
	{ 358,  -28,  60, 0.80}, { 415,  -95,  60, 0.80}, {-463,   48,  60, 0.80},
	{  35,  245,  60, 0.80}, {-270,  205,  55, 0.70}, {-220,  205,  55, 0.70},
}

-- x, z, radius, amplitude -- guarantees open water (boat course, stilt market, bays)
local CUTS = {
	{-320,  205,  48, 0.95}, {-320,  150,  45, 0.90}, {-330,  175,  60, 0.80},
	{-580,  -50,  75, 0.90},
	{  60,  500,  90, 1.05},
	{  80,  560,  85, 1.00}, { 350,  580,  85, 1.00}, { 600,  480,  85, 1.00},
	{ 540,  280,  85, 1.00}, { 280,  380,  85, 1.00},
	{ 468,  182,  40, 0.90}, {-345,  120,  40, 0.90}, {-308,  150,  40, 0.90},
	{ 375,  199,  40, 0.90}, { 281,  216,  40, 0.90},
}

-- x, z, radius -- flattened building pads
local FLATS = {
	{-463,   48, 34}, { 358,  -28, 34}, { 415,  -95, 34}, {  35,  245, 34},
	{-225,  -95, 44}, { 120, -225, 42}, {-270,  192, 42}, { 430,  -40, 34},
	{-495,   20, 36}, {-270,  150, 26}, {-220,  150, 26}, {-270,  205, 26},
	{-220,  205, 26}, {   0,  452, 92}, { 562,  165, 40},
}

-- Two fields are computed. `shape` (blobs + water cuts) drives ELEVATION, so the
-- island's height follows its natural landmass form. `mask` adds the prop pads on
-- top and only decides land-vs-water, so guaranteeing ground under a prop creates a
-- low sandy shore rather than an artificial hill.
local function fieldsAt(x, z)
	local wx = x + 58 * fbm(x, z, 11.3, 3, 1 / 430, 0.5, 2.0) + 15 * fbm(x, z, 71.1, 2, 1 / 130, 0.5, 2.0)
	local wz = z + 58 * fbm(x, z, 47.9, 3, 1 / 430, 0.5, 2.0) + 15 * fbm(x, z, 91.7, 2, 1 / 130, 0.5, 2.0)
	local shape = 0
	for i = 1, #BLOBS do
		local b = BLOBS[i]
		local dx, dz = wx - b[1], wz - b[2]
		local c, s = math.cos(b[5]), math.sin(b[5])
		local rx = dx * c + dz * s
		local rz = -dx * s + dz * c
		local q = (rx / b[3]) ^ 2 + (rz / b[4]) ^ 2
		if q < 1 then
			shape += b[6] * (1 - q)
		end
	end
	for i = 1, #CUTS do
		local c = CUTS[i]
		local dx, dz = x - c[1], z - c[2]
		local q = (dx * dx + dz * dz) / (c[3] * c[3])
		if q < 1 then
			shape -= c[4] * (1 - q)
		end
	end
	local mask = shape
	for i = 1, #PADS do
		local p = PADS[i]
		local dx, dz = x - p[1], z - p[2]
		local q = (dx * dx + dz * dz) / (p[3] * p[3])
		if q < 1 then
			mask += p[4] * (1 - q)
		end
	end
	return shape, mask
end
M.FieldsAt = fieldsAt

local function rawHeight(x, z)
	local shape, mask = fieldsAt(x, z)
	local aShape = shape - LAND_T
	local h
	if mask - LAND_T > 0 then
		-- land: elevation follows the landmass form, floored just above the waterline
		local a = math.max(aShape, 0.06)
		h = 1.5 + 24 * a
		local hills = 13 * fbm(x, z, 5.7, 4, 1 / 260, 0.5, 2.0)
		local fine = 4.5 * fbm(x, z, 23.4, 3, 1 / 85, 0.5, 2.0)
		h += (hills + fine) * math.min(1, a * 1.8)
	else
		h = -1.2 - 30 * (1 - math.exp(aShape * 1.1))
	end
	-- Tanaw Ridge
	local rq = ((x - 115) / 185) ^ 2 + ((z + 230) / 168) ^ 2
	h += 74 * math.exp(-rq * 1.5)
	-- secondary rises so the interior is not a tabletop
	local hq = ((x + 355) / 150) ^ 2 + ((z + 120) / 130) ^ 2
	h += 20 * math.exp(-hq * 1.6)
	local iq = ((x - 430) / 140) ^ 2 + ((z - 20) / 120) ^ 2
	h += 15 * math.exp(-iq * 1.6)
	return h
end

local flatCache = {}
function M.HeightAt(x, z)
	local h = rawHeight(x, z)
	for i = 1, #FLATS do
		local f = FLATS[i]
		local dx, dz = x - f[1], z - f[2]
		local d2 = dx * dx + dz * dz
		local r = f[3]
		if d2 < r * r then
			local t = 1 - math.sqrt(d2) / r
			t = t * t * (3 - 2 * t)
			local base = flatCache[i]
			if not base then
				base = math.max(rawHeight(f[1], f[2]), 6)
				flatCache[i] = base
			end
			h = h * (1 - t) + base * t
		end
	end
	return h
end

function M.MaterialFor(h, slope, x, z)
	if h < 1.6 then
		return Enum.Material.Sand
	end
	if slope > 0.95 then
		return Enum.Material.Rock
	end
	if h > 66 then
		if slope > 0.5 then
			return Enum.Material.Rock
		end
		return Enum.Material.Slate
	end
	if h > 46 and slope > 0.72 then
		return Enum.Material.Rock
	end
	if h < 4.5 and slope < 0.25 then
		return Enum.Material.Sand
	end
	local p = fbm(x, z, 88.2, 2, 1 / 150, 0.5, 2.0)
	if p > 0.12 then
		return Enum.Material.LeafyGrass
	end
	if p < -0.32 then
		return Enum.Material.Ground
	end
	return Enum.Material.Grass
end

function M.ClearRegion()
	local n = 0
	local step = 440
	for x = X0, X1 - 1, step do
		for z = Z0, Z1 - 1, step do
			local x2 = math.min(X1, x + step)
			local z2 = math.min(Z1, z + step)
			T:FillBlock(
				CFrame.new((x + x2) / 2, 50, (z + z2) / 2),
				Vector3.new(x2 - x, 190, z2 - z),
				Enum.Material.Air
			)
			n += 1
		end
	end
	return n
end

function M.WriteChunks(fromIdx, toIdx)
	local t0 = os.clock()
	local done = 0
	for idx = fromIdx, math.min(toIdx, M.ChunkCount) do
		local ci = idx - 1
		local cx = ci % nx
		local cz = math.floor(ci / nx)
		local x0 = X0 + cx * CHUNK
		local z0 = Z0 + cz * CHUNK
		local x1 = math.min(X1, x0 + CHUNK)
		local z1 = math.min(Z1, z0 + CHUNK)
		local ncx = (x1 - x0) / RES
		local ncz = (z1 - z0) / RES

		local H = {}
		local maxH = -1e9
		for ix = 0, ncx + 1 do
			local col = {}
			H[ix] = col
			local wx = x0 + (ix - 1) * RES + RES / 2
			for iz = 0, ncz + 1 do
				local wz = z0 + (iz - 1) * RES + RES / 2
				local h = M.HeightAt(wx, wz)
				col[iz] = h
				if h > maxH and ix >= 1 and ix <= ncx and iz >= 1 and iz <= ncz then
					maxH = h
				end
			end
		end

		local yTop = math.max(8, math.ceil((maxH + 8) / RES) * RES)
		local ncy = (yTop - Y_BOT) / RES

		local mats, occs = {}, {}
		for ix = 1, ncx do
			local mcol, ocol = {}, {}
			mats[ix] = mcol
			ocol = {}
			occs[ix] = ocol
			for iy = 1, ncy do
				mcol[iy] = {}
				ocol[iy] = {}
			end
			local wx = x0 + (ix - 1) * RES + RES / 2
			for iz = 1, ncz do
				local wz = z0 + (iz - 1) * RES + RES / 2
				local h = H[ix][iz]
				local dhx = (H[ix + 1][iz] - H[ix - 1][iz]) / (2 * RES)
				local dhz = (H[ix][iz + 1] - H[ix][iz - 1]) / (2 * RES)
				local slope = math.sqrt(dhx * dhx + dhz * dhz)
				local landMat = M.MaterialFor(h, slope, wx, wz)
				for iy = 1, ncy do
					local y0 = Y_BOT + (iy - 1) * RES
					local frac = (h - y0) / RES
					local mat, occ
					if frac >= 0.5 then
						mat = landMat
						occ = math.min(1, frac)
					elseif frac > 0 and h > 0.6 then
						mat = landMat
						occ = frac
					elseif y0 + RES <= 0.5 then
						mat = Enum.Material.Water
						occ = 1
					else
						mat = Enum.Material.Air
						occ = 0
					end
					mcol[iy][iz] = mat
					ocol[iy][iz] = occ
				end
			end
		end

		local region = Region3.new(Vector3.new(x0, Y_BOT, z0), Vector3.new(x1, yTop, z1))
		T:WriteVoxels(region, RES, mats, occs)
		done += 1
	end
	return string.format("wrote %d chunks (%d..%d) in %.1fs", done, fromIdx, math.min(toIdx, M.ChunkCount), os.clock() - t0)
end

function M.Probe(pts)
	local out = {}
	for _, p in ipairs(pts) do
		local shape, mask = fieldsAt(p[1], p[2])
		out[#out + 1] = string.format("(%d,%d) shape=%.2f mask=%.2f h=%.1f %s",
			p[1], p[2], shape, mask, M.HeightAt(p[1], p[2]),
			(mask - LAND_T > 0) and "LAND" or "water")
	end
	return table.concat(out, "\n")
end

function M.AsciiMap(step)
	step = step or 32
	local rows = {}
	for z = Z0, Z1, step do
		local row = {}
		for x = X0, X1, step do
			local h = M.HeightAt(x, z)
			local ch
			if h < 0 then ch = "~"
			elseif h < 3 then ch = "."
			elseif h < 12 then ch = "1"
			elseif h < 22 then ch = "2"
			elseif h < 34 then ch = "3"
			elseif h < 48 then ch = "4"
			elseif h < 64 then ch = "5"
			elseif h < 82 then ch = "6"
			else ch = "7" end
			row[#row + 1] = ch
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, "\n")
end

return M
