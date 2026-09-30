-- ChamberDressingService (Palamuti ng Silid)
--
-- Twelve air pockets, twelve rooms that have to be worth the swim. Finding one is
-- the reward, so the room has to pay that off the moment a diver's head breaks the
-- surface: a name to learn, a colour that is only this room's, shells on the floor
-- that say the sea has been here longer than you, and somewhere to stand for the
-- photo you are going to post.
--
-- Everything here is decoration and is built fresh at server start. Nothing is
-- saved into the place file, nothing is collectible, and nothing here is load
-- bearing -- if this script never ran the cave would still be fully playable, just
-- bare. That is deliberate: it keeps the generator and the dressing separable.
--
-- Two hard rules, because the chamber has exactly one way in and out:
--   * nothing is placed within SHAFT_CLEAR of the entry hole, so surfacing is never
--     blocked and the way down is always visible;
--   * every prop is anchored, CanCollide false and CanQuery false except the floor
--     dais, so no prop can trap a diver against the ceiling or eat a raycast.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaveGen = require(ServerStorage:WaitForChild("CaveGen"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local photoModeToggle = remotes:WaitForChild("PhotoModeToggle")

local FOLDER_NAME = "ChamberDecor"
local SHAFT_CLEAR = 11

-- One signature colour per chamber. A diver who has been to Bato-Kristal should be
-- able to tell a screenshot of it from a screenshot of Hatinggabi at a glance, and
-- colour does that faster than shape does.
local ACCENT = {
	Hub = Color3.fromRGB(255, 186, 92),        -- lamp amber
	RestB = Color3.fromRGB(126, 214, 130),     -- root green
	RestA = Color3.fromRGB(150, 226, 232),     -- foam
	RestC = Color3.fromRGB(140, 186, 255),     -- ice
	RestD = Color3.fromRGB(255, 140, 104),     -- last-breath coral
	RestE = Color3.fromRGB(186, 146, 255),     -- violet
	RestF = Color3.fromRGB(104, 126, 232),     -- midnight
	RestG = Color3.fromRGB(240, 118, 214),     -- crystal magenta
	RestH = Color3.fromRGB(96, 226, 206),      -- sanctuary turquoise
	RestI = Color3.fromRGB(255, 150, 178),     -- rose
	RestJ = Color3.fromRGB(150, 245, 190),     -- quiet mint
	Treasure = Color3.fromRGB(255, 226, 150),  -- pearl
}

local SHELL_COLOURS = {
	Color3.fromRGB(242, 232, 214),
	Color3.fromRGB(226, 198, 182),
	Color3.fromRGB(214, 186, 196),
	Color3.fromRGB(236, 214, 178),
	Color3.fromRGB(198, 206, 202),
}

local ROCK = Color3.fromRGB(78, 74, 70)

local rng = Random.new(20260917)

local ceilingParams = RaycastParams.new()
ceilingParams.FilterType = Enum.RaycastFilterType.Include
ceilingParams.FilterDescendantsInstances = { workspace.Terrain }
ceilingParams.IgnoreWater = true

local function newPart(parent, size, cf, colour, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.Slate
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(parent, d, cf, colour, material)
	local p = newPart(parent, Vector3.new(d, d, d), cf, colour, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cylinder(parent, size, cf, colour, material)
	local p = newPart(parent, size, cf, colour, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- ---------------------------------------------------------------- the shells
-- Three kinds, so a floor does not read as one prop stamped twenty times. Each is
-- built from primitives rather than a mesh asset, so nothing here can 404 later.

local function clamShell(parent, cf, colour, scale)
	local s = scale
	for side = -1, 1, 2 do
		local half = newPart(parent, Vector3.new(s * 2.0, s * 0.55, s * 1.6),
			cf * CFrame.new(0, s * 0.18 * side, 0) * CFrame.Angles(0, 0, math.rad(9 * side)),
			colour, Enum.Material.Sand)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = half
	end
	-- the hinge ridge, so it reads as a clam and not a pebble
	newPart(parent, Vector3.new(s * 0.5, s * 0.22, s * 1.5),
		cf * CFrame.new(-s * 0.85, 0, 0), colour:Lerp(Color3.new(0, 0, 0), 0.25),
		Enum.Material.Sand)
end

local function conchShell(parent, cf, colour, scale)
	local s = scale
	local n = 6
	for i = 1, n do
		local t = (i - 1) / (n - 1)
		local d = s * (1.5 - t * 1.15)
		local a = t * math.pi * 2.2
		ball(parent, d, cf * CFrame.new(math.cos(a) * s * 0.55 * t,
			s * 0.25 + t * s * 1.1, math.sin(a) * s * 0.55 * t), colour, Enum.Material.Sand)
	end
end

local function scallopShell(parent, cf, colour, scale)
	local s = scale
	local body = cylinder(parent, Vector3.new(s * 0.35, s * 1.9, s * 1.9),
		cf * CFrame.new(0, s * 0.18, 0) * CFrame.Angles(0, 0, math.rad(90)),
		colour, Enum.Material.Sand)
	body.Name = "Scallop"
	for i = 1, 5 do
		local a = math.rad(-52 + i * 26)
		newPart(parent, Vector3.new(s * 0.22, s * 0.42, s * 1.7),
			cf * CFrame.new(0, s * 0.30, 0) * CFrame.Angles(0, a, 0),
			colour:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Sand)
	end
end

local function starfish(parent, cf, colour, scale)
	local s = scale
	ball(parent, s * 0.9, cf * CFrame.new(0, s * 0.2, 0), colour, Enum.Material.Sand)
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		newPart(parent, Vector3.new(s * 0.45, s * 0.35, s * 1.5),
			cf * CFrame.new(0, s * 0.2, 0) * CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -s * 0.85), colour, Enum.Material.Sand)
	end
end

local SHELL_KINDS = { clamShell, conchShell, scallopShell, starfish }

-- --------------------------------------------------------------- the crystals
-- The only light down here. Neon reads as glowing but washes its own colour out,
-- so the crystal itself is glass in the chamber's accent and the PointLight beside
-- it does the actual glowing.
local function crystalCluster(parent, pos, accent, scale)
	local count = rng:NextInteger(3, 5)
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local lean = rng:NextNumber(0.05, 0.38)
		local h = scale * rng:NextNumber(1.6, 3.4)
		local w = scale * rng:NextNumber(0.28, 0.55)
		local off = CFrame.new(pos + Vector3.new(math.cos(a) * scale * 0.7, 0,
			math.sin(a) * scale * 0.7))
			* CFrame.Angles(math.cos(a) * lean, a, math.sin(a) * lean)
		local shard = newPart(parent, Vector3.new(w, h, w),
			off * CFrame.new(0, h * 0.45, 0), accent, Enum.Material.Glass)
		shard.Transparency = 0.25
		shard.Reflectance = 0.2
	end
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = 2.2
	light.Range = 26
	light.Parent = ball(parent, 0.6, CFrame.new(pos + Vector3.new(0, scale * 1.4, 0)),
		accent, Enum.Material.Neon)
end

local function stalactite(parent, top, length, colour)
	local seg = 3
	for i = 1, seg do
		local t = (i - 1) / seg
		local d = (1 - t) * 1.9 + 0.35
		local h = length / seg
		cylinder(parent, Vector3.new(h, d, d),
			CFrame.new(top - Vector3.new(0, h * (i - 0.5), 0)) * CFrame.Angles(0, 0, math.rad(90)),
			colour, Enum.Material.Slate)
	end
end

-- ------------------------------------------------------------------ the sign
local function plinthAndPlaque(parent, key, node, spots, accent)
	local base = spots.sign
	local look = CFrame.lookAt(base + Vector3.new(0, 1.6, 0), spots.signLook)

	local _, yaw = look:ToEulerAnglesYXZ()
	newPart(parent, Vector3.new(4.2, 1.0, 2.6), CFrame.new(base + Vector3.new(0, 0.5, 0))
		* CFrame.Angles(0, yaw, 0), ROCK, Enum.Material.Rock)
	newPart(parent, Vector3.new(3.4, 0.5, 2.0), CFrame.new(base + Vector3.new(0, 1.2, 0))
		* CFrame.Angles(0, yaw, 0), ROCK, Enum.Material.Rock)

	local slab = newPart(parent, Vector3.new(0.35, 3.0, 4.6),
		look * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(90), math.rad(-8)),
		Color3.fromRGB(32, 38, 44), Enum.Material.Slate)
	slab.Name = "Plaque_" .. key

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(460, 300)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
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
	stroke.Color = accent
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
		return l
	end

	line(1, string.format("SILID %02d", node.number or 0), 30, accent, Enum.Font.GothamBold)
	line(2, node.label, 46, Color3.fromRGB(238, 244, 248), Enum.Font.GothamBold)
	line(3, node.flavor or "", 24, Color3.fromRGB(150, 168, 182), Enum.Font.Gotham)
	line(4, string.format("%d studs below the waterline", math.floor(-node.y)),
		22, accent:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Font.GothamMedium)

	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = 1.4
	light.Range = 18
	light.Parent = slab
end

-- ------------------------------------------------------------- the photo spot
local function photoPad(parent, key, node, spots, accent)
	local pos = spots.photo + Vector3.new(0, 0.12, 0)
	local pad = newPart(parent, Vector3.new(6, 0.24, 6), CFrame.new(pos),
		Color3.fromRGB(46, 52, 58), Enum.Material.Slate)
	pad.Name = "PhotoPad_" .. key
	pad.CanQuery = true
	pad:SetAttribute("SpotName", node.label)
	pad:SetAttribute("Blurb", node.flavor or "")
	pad:SetAttribute("Facing", (spots.centre - pos).Unit)

	local ring = newPart(parent, Vector3.new(6.6, 0.1, 6.6), CFrame.new(pos - Vector3.new(0, 0.08, 0)),
		accent, Enum.Material.Neon)
	ring.Transparency = 0.45

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take a photo"
	prompt.ObjectText = node.label
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - pad.Position).Magnitude > 20 then
			return
		end
		photoModeToggle:FireClient(player, "enter", {
			spotName = pad:GetAttribute("SpotName"),
			blurb = pad:GetAttribute("Blurb"),
			facing = pad:GetAttribute("Facing"),
			position = pad.Position,
		})
	end)
end

-- ---------------------------------------------------------- the hole, marked
-- The way out is a hole in a dark floor and a panicking diver will not find it by
-- looking. A ring of low lamps round the mouth is the one piece of dressing here
-- that is really a safety feature.
local function markTheShaft(parent, node, spots, accent)
	local r = (node.entryR or 3.5) + 3.2
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local p = spots.centre + Vector3.new(math.cos(a) * r, 0.25, math.sin(a) * r)
		local stone = newPart(parent, Vector3.new(1.3, 0.5, 1.3), CFrame.new(p)
			* CFrame.Angles(0, a, 0), accent, Enum.Material.Neon)
		stone.Transparency = 0.25
	end
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = 1.8
	light.Range = 30
	light.Parent = ball(parent, 0.8, CFrame.new(spots.centre + Vector3.new(0, 2.4, 0)),
		accent, Enum.Material.Neon)
end

-- ------------------------------------------------------------------ assembly
local function dressChamber(root, key)
	local node = CaveGen.Nodes[key]
	local spots = CaveGen.ChamberSpots(key)
	local accent = ACCENT[key] or Color3.fromRGB(200, 210, 220)

	local model = Instance.new("Model")
	model.Name = "Silid_" .. key
	model.Parent = root

	local centre2D = Vector2.new(spots.centre.X, spots.centre.Z)
	local usable = {}
	for _, p in ipairs(spots.spots) do
		if (Vector2.new(p.X, p.Z) - centre2D).Magnitude > SHAFT_CLEAR then
			usable[#usable + 1] = p
		end
	end

	markTheShaft(model, node, spots, accent)
	plinthAndPlaque(model, key, node, spots, accent)
	photoPad(model, key, node, spots, accent)

	-- shells: scattered, never in rows, never the same kind twice in a row
	local lastKind = 0
	local shellCount = 0
	for i, p in ipairs(usable) do
		if i % 2 == 1 and shellCount < 16 then
			local k = rng:NextInteger(1, #SHELL_KINDS)
			if k == lastKind then k = (k % #SHELL_KINDS) + 1 end
			lastKind = k
			local cf = CFrame.new(p + Vector3.new(0, 0.35, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			SHELL_KINDS[k](model, cf, SHELL_COLOURS[rng:NextInteger(1, #SHELL_COLOURS)],
				rng:NextNumber(0.75, 1.35))
			shellCount += 1
		end
	end

	-- crystals: a handful of clusters, biased to the far side from the plaque
	local clusters = 0
	for i, p in ipairs(usable) do
		if i % 5 == 2 and clusters < 5 then
			crystalCluster(model, p, accent, rng:NextNumber(0.8, 1.5))
			clusters += 1
		end
	end

	-- stalactites: hung from the real ceiling, found by ray rather than assumed
	local hung = 0
	for i, p in ipairs(usable) do
		if i % 3 == 0 and hung < 7 then
			local hit = workspace:Raycast(p + Vector3.new(0, 1, 0),
				Vector3.new(0, node.r * 2.6 + 20, 0), ceilingParams)
			if hit and (hit.Position.Y - p.Y) > 7 then
				stalactite(model, hit.Position - Vector3.new(0, 0.2, 0),
					math.min(4.5, (hit.Position.Y - p.Y) * 0.32), ROCK)
				hung += 1
			end
		end
	end

	return model, shellCount, clusters, hung
end

local function build()
	local activities = workspace:WaitForChild("IslaMarahuyo"):WaitForChild("Activities")
	local caveFolder = activities:WaitForChild("CaveSystem")
	local old = caveFolder:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = FOLDER_NAME
	root.Parent = caveFolder

	local rooms, shells, crystals, hangs = 0, 0, 0, 0
	for key, node in pairs(CaveGen.Nodes) do
		if CaveGen.AirKinds[node.kind] then
			local _, s, c, h = dressChamber(root, key)
			rooms += 1
			shells += s
			crystals += c
			hangs += h
		end
	end
	print(string.format(
		"[ChamberDressingService] %d chambers dressed: %d shells, %d crystal clusters, %d stalactites",
		rooms, shells, crystals, hangs))
	return root
end

build()

return { Build = build }
