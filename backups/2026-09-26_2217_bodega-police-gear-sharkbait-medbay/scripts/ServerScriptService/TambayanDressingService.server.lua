-- TambayanDressingService (Tambayan sa Baybayon)
--
-- A place to put your feet in the sand between dives: a row of chairs facing
-- the water, a small kubo roof for shade, a fire that lights itself at dusk.
--
-- Unlike the cave's ChamberDressingService, this one has two lifecycles, not
-- one: the chairs/umbrellas/torches/string-lights are Creator Store models
-- that get inserted into Activities.Tambayan.Props exactly ONCE (a script
-- cannot regenerate a marketplace model from code), so build() only ever
-- REPOSITIONS them by name -- it never destroys Props. The pavilion, its
-- dais and its sign ARE regenerated from primitives every server start,
-- exactly like ChamberDressingService's cave dressing, in Activities.Tambayan.Decor.
-- Nothing here is load-bearing except the dais you can actually stand on.

local Lighting = game:GetService("Lighting")

local activities = workspace:WaitForChild("IslaMarahuyo"):WaitForChild("Activities")
local tambayan = activities:WaitForChild("Tambayan")
local props = tambayan:WaitForChild("Props")

local DECOR_FOLDER_NAME = "Decor"

-- The cove around the BaybayonBeach zone marker (0, 15.4, 267): probed
-- terrain shows clean sand roughly x=56..77, z=200..290 before it gives way
-- to rock or open water further east.
local SEA_DIR = Vector3.new(1, 0, 0)
local SHORE_DIR = Vector3.new(0, 0, 1)
local CLUSTER_X, CLUSTER_Z = 63, 257
local MARKER_POS = Vector3.new(0, 15.4, 267)

local BAMBOO = Color3.fromRGB(196, 180, 110)
local BAMBOO_NODE = Color3.fromRGB(120, 104, 60)
local THATCH = Color3.fromRGB(168, 150, 90)
local ACCENT = Color3.fromRGB(255, 196, 120) -- warm torchlight amber

local POST_SPACING = 3.5 -- half-width of the 7x7 pavilion footprint
local POST_HEIGHT = 8
local DIGSPOT_CLEAR_R = 14 -- studs; keeps scatter props off the dig prompts

-- Creator Store models sourced whole (chairs, umbrellas, torches, string
-- lights). HangoutUmbrella_1 and a second ChairUmbrella were dropped after
-- insertion: the umbrella's mesh scale was corrupted (extents ballooned to
-- millions of studs after any ScaleTo call), and the second chair set risked
-- overlapping the dig spots in an area whose shoreline we hadn't mapped.
local PROP_SCALE = {
	StringLights_1 = 0.6,
	StringLights_2 = 0.6,
}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }
groundParams.IgnoreWater = true

local function sandY(x, z, aboveY)
	local origin = Vector3.new(x, aboveY + 25, z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -60, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	warn(string.format("[TambayanDressingService] no terrain hit at (%d, %d), using fallback height", x, z))
	return aboveY - 0.5
end

local function newPart(parent, size, cf, colour, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.Wood
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(parent, size, cf, colour, material)
	local p = newPart(parent, size, cf, colour, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- ------------------------------------------------------------------ pavilion
-- Four bamboo-look posts (segmented cylinders with darker "node" rings, the
-- same segmented technique ChamberDressingService uses for stalactites), a
-- two-panel sloped thatch roof, and a dais you can actually stand on.

-- Roblox's Cylinder shape runs its length along local X with the circular
-- faces in the YZ-plane, so a cylinder() call needs Size.X = length and a
-- +90-degree Z rotation to stand that length up along world Y (exactly the
-- trick ChamberDressingService's stalactite() uses).
local function verticalCylinder(parent, length, diameter, cf, colour, material)
	return cylinder(parent, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)),
		colour, material)
end

local function pavilionPosts(parent, cx, cz, floorY)
	for _, side in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
		local px, pz = cx + side[1] * POST_SPACING, cz + side[2] * POST_SPACING
		for seg = 0, 3 do
			local segY = floorY + seg * 2 + 1
			verticalCylinder(parent, 2, 0.7, CFrame.new(px, segY, pz), BAMBOO, Enum.Material.Wood)
			if seg < 3 then
				verticalCylinder(parent, 0.15, 0.85, CFrame.new(px, segY + 1, pz), BAMBOO_NODE, Enum.Material.Wood)
			end
		end
	end
end

local function pavilionRoof(parent, cx, cz, floorY)
	local ridgeY = floorY + POST_HEIGHT + 2.2
	local eaveY = floorY + POST_HEIGHT + 0.6
	for _, side in ipairs({ -1, 1 }) do
		local midZ = cz + side * (POST_SPACING + 1.5) * 0.5
		newPart(parent, Vector3.new(10, 0.4, 5.7),
			CFrame.new(cx, (ridgeY + eaveY) / 2, midZ) * CFrame.Angles(math.rad(28) * side, 0, 0),
			THATCH, Enum.Material.Grass)
	end
	-- the ridge beam runs horizontally along world X, which is the cylinder's
	-- native length axis, so this one is left unrotated.
	cylinder(parent, Vector3.new(10, 0.5, 0.5), CFrame.new(cx, ridgeY, cz), BAMBOO_NODE, Enum.Material.Wood)
end

local function pavilionDais(parent, cx, cz, floorY)
	local dais = newPart(parent, Vector3.new(10, 0.3, 10),
		CFrame.new(cx, floorY + 0.15, cz), Color3.fromRGB(230, 214, 178), Enum.Material.Sand)
	dais.Name = "Dais"
	dais.CanCollide = true
end

-- ---------------------------------------------------------------------- sign
-- Same plinth + SurfaceGui + PointLight structure as ChamberDressingService's
-- plinthAndPlaque, just without the per-node data table (there is only one
-- of these).
local function signPlaque(parent, pos, lookAt)
	local look = CFrame.lookAt(pos + Vector3.new(0, 1.6, 0), lookAt)
	newPart(parent, Vector3.new(4.2, 1.0, 2.6), CFrame.new(pos + Vector3.new(0, 0.5, 0)), BAMBOO, Enum.Material.Wood)

	local slab = newPart(parent, Vector3.new(0.35, 3.0, 4.6), look * CFrame.new(0, 1.6, 0),
		Color3.fromRGB(32, 38, 44), Enum.Material.Slate)
	slab.Name = "Plaque_Tambayan"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(460, 300)
	gui.LightInfluence = 0
	gui.Parent = slab

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(18, 22, 27)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 22)
	pad.PaddingRight = UDim.new(0, 22)
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = ACCENT
	stroke.Parent = frame

	local function line(order, text, size, colour, font)
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.Size = UDim2.new(1, 0, 0, size)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextSize = size
		l.TextColor3 = colour
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextWrapped = true
		l.Text = text
		l.Parent = frame
	end

	line(1, "TAMBAYAN", 30, ACCENT, Enum.Font.GothamBold)
	line(2, "TAMBAYAN NG BAYBAYON", 46, Color3.fromRGB(238, 244, 248), Enum.Font.GothamBold)
	line(3, "Upuan, kubo, at ilaw sa gabi -- para sa sinumang dumaan.", 24,
		Color3.fromRGB(150, 168, 182), Enum.Font.Gotham)
	line(4, "Nagliliwanag paglubog ng araw.", 22, ACCENT:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Font.GothamMedium)

	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Brightness = 1.4
	light.Range = 18
	light.Parent = slab
end

-- ------------------------------------------------------------ prop lighting
-- The Tiki Torch models ship with Fire/Smoke ParticleEmitters but no actual
-- PointLight, and the String Lights models are just Neon bulb parts with no
-- Light instance either -- neither would visibly light the sand at night on
-- its own. We add one supplemental PointLight per fixture, tagged by name so
-- a later server start (Props is never destroyed/rebuilt) finds the light it
-- already added instead of stacking a second one on top.

local litInstances = {}

local function addNamedLight(part, colour, brightness, range)
	local l = Instance.new("PointLight")
	l.Name = "TambayanAutoLight"
	l.Color = colour
	l.Brightness = brightness
	l.Range = range
	l.Parent = part
	table.insert(litInstances, l)
end

local function ensureTorchLight(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "TambayanAutoLight" then
			table.insert(litInstances, d)
		elseif d:IsA("ParticleEmitter") or d:IsA("Fire") then
			table.insert(litInstances, d)
		end
	end
	if not model:FindFirstChild("TambayanAutoLight", true) then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Parent and d.Parent:IsA("BasePart") then
				addNamedLight(d.Parent, Color3.fromRGB(255, 150, 60), 3, 18)
				break
			end
		end
	end
end

local function ensureStringLight(model)
	local haveOwn = false
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "TambayanAutoLight" then
			table.insert(litInstances, d)
			haveOwn = true
		end
	end
	if haveOwn then
		return
	end
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			count += 1
			if count % 4 == 1 then
				addNamedLight(d, d.Color, 1.2, 14)
			end
		end
	end
end

local function isNight()
	local ct = Lighting.ClockTime
	return ct >= 19 or ct <= 5
end

-- ------------------------------------------------------------- prop placing
local function placeProp(name, pos, lookAt)
	local model = props:FindFirstChild(name)
	if not model then
		warn("[TambayanDressingService] missing prop: " .. name)
		return
	end
	local scale = PROP_SCALE[name]
	if scale then
		model:ScaleTo(scale)
	end
	model:PivotTo(lookAt and CFrame.lookAt(pos, lookAt) or CFrame.new(pos))
	if name:match("^TikiTorch") then
		ensureTorchLight(model)
	elseif name:match("^StringLights") then
		ensureStringLight(model)
	end
end

-- ---------------------------------------------------------------- assembly
local function buildMainCluster()
	local floorY = sandY(CLUSTER_X, CLUSTER_Z, MARKER_POS.Y)

	local old = tambayan:FindFirstChild(DECOR_FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local decor = Instance.new("Folder")
	decor.Name = DECOR_FOLDER_NAME
	decor.Parent = tambayan

	pavilionPosts(decor, CLUSTER_X, CLUSTER_Z, floorY)
	pavilionRoof(decor, CLUSTER_X, CLUSTER_Z, floorY)
	pavilionDais(decor, CLUSTER_X, CLUSTER_Z, floorY)

	local centre = Vector3.new(CLUSTER_X, floorY, CLUSTER_Z)
	signPlaque(decor, centre - SHORE_DIR * 9, MARKER_POS)

	-- ChairUmbrella_1 bundles 3 chairs + 3 umbrellas laid out along its OWN
	-- facing axis (a 33-stud deep row, not a side-by-side spread), so aiming
	-- it at the water would walk half the row out to sea. Aim it along the
	-- shore instead -- the long x=66 sand column we probed runs clean from
	-- z=200 to z=290, easily covering the row's spread.
	placeProp("ChairUmbrella_1", centre + SEA_DIR * 8, centre + SEA_DIR * 8 + SHORE_DIR * 30)
	placeProp("StringLights_1", centre - SHORE_DIR * 5.5, centre)
	placeProp("StringLights_2", centre + SHORE_DIR * 5.5, centre)

	local torchOffsets = {
		Vector3.new(9.2, 0, 9.2),
		Vector3.new(-9.2, 0, 9.2),
		Vector3.new(-9.2, 0, -9.2),
		Vector3.new(9.2, 0, -9.2),
	}
	for i, off in ipairs(torchOffsets) do
		placeProp("TikiTorch_Main_" .. i, centre + off, nil)
	end

	return decor
end

-- Scattered secondary decor toward the TreasureDigs cluster, kept clear of
-- every DigSpot's ProximityPrompt (read live, never hardcoded).
local function buildScatter()
	local treasureDigs = activities:FindFirstChild("TreasureDigs")
	local digPositions = {}
	if treasureDigs then
		for _, d in ipairs(treasureDigs:GetChildren()) do
			if d:IsA("BasePart") and d.Name:match("^DigSpot") then
				table.insert(digPositions, d.Position)
			end
		end
	end

	local function clearOfDigs(pos)
		for _, d in ipairs(digPositions) do
			local flat = Vector3.new(pos.X - d.X, 0, pos.Z - d.Z)
			if flat.Magnitude < DIGSPOT_CLEAR_R then
				local pushed = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(1, 0, 0)
				return d * Vector3.new(1, 0, 1) + pushed * (DIGSPOT_CLEAR_R + 2)
			end
		end
		return pos
	end

	local scatterSpecs = {
		{ name = "SunbedUmbrella_Scatter_1", x = 85, z = 435, faceDir = Vector3.new(0.4, 0, 1) },
		{ name = "SunbedUmbrella_Scatter_2", x = 95, z = 445, faceDir = Vector3.new(0.4, 0, 1) },
		{ name = "TikiTorch_Scatter_1", x = 90, z = 450 },
		{ name = "TikiTorch_Scatter_2", x = 78, z = 465 },
	}

	for _, spec in ipairs(scatterSpecs) do
		local y = sandY(spec.x, spec.z, 10)
		local pos = clearOfDigs(Vector3.new(spec.x, y, spec.z))
		pos = Vector3.new(pos.X, sandY(pos.X, pos.Z, 10), pos.Z)
		placeProp(spec.name, pos, spec.faceDir and (pos + spec.faceDir * 10) or nil)
	end
end

local function build()
	local decor = buildMainCluster()
	buildScatter()

	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
		local night = isNight()
		for _, inst in ipairs(litInstances) do
			inst.Enabled = night
		end
	end)
	local night = isNight()
	for _, inst in ipairs(litInstances) do
		inst.Enabled = night
	end

	print(string.format(
		"[TambayanDressingService] tambayan dressed: pavilion + sign, 4 seating/lighting props, %d lights wired for night",
		#litInstances))
	return decor
end

build()

return { Build = build }
