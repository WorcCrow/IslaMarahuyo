-- LeaderboardService
-- Two boards on the plaza: most Shells right now, and the fastest bangka lap. Both
-- read straight off live profiles, so there is no separate score to keep in sync and
-- nothing a client can submit.
--
-- Scope is this server's players. A global board needs OrderedDataStore, which cannot
-- be exercised in Studio without API access; this is the useful half that works today
-- and the surface a global board would later plug into.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerProfileService = require(script.Parent.PlayerProfileService)

local REFRESH_SECONDS = 5
local ROWS = 8

local island = Workspace:WaitForChild("IslaMarahuyo")

local function findGround(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { island }
	params.IgnoreWater = true
	local result = Workspace:Raycast(Vector3.new(x, 700, z), Vector3.new(0, -1100, 0), params)
	return result and result.Position.Y or 14
end

local function buildBoard(name, title, x, z, rotation)
	local existing = island:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local y = findGround(x, z)

	local model = Instance.new("Model")
	model.Name = name
	model.Parent = island

	local base = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rotation), 0)

	for side = -1, 1, 2 do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Size = Vector3.new(0.6, 7, 0.6)
		post.CFrame = base * CFrame.new(side * 3.4, 3.5, 0)
		post.Anchored = true
		post.CanCollide = false
		post.CanTouch = false
		post.CanQuery = false
		post.Material = Enum.Material.Wood
		post.Color = Color3.fromRGB(112, 82, 54)
		post.Parent = model
	end

	local board = Instance.new("Part")
	board.Name = "Board"
	board.Size = Vector3.new(8, 6, 0.4)
	board.CFrame = base * CFrame.new(0, 6, 0)
	board.Anchored = true
	board.CanCollide = false
	board.CanTouch = false
	board.CanQuery = false
	board.Material = Enum.Material.WoodPlanks
	board.Color = Color3.fromRGB(196, 158, 108)
	board.Parent = model
	model.PrimaryPart = board

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Display"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(400, 300)
	surface.Adornee = board
	surface.Parent = board

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(46, 34, 24)
	bg.BorderSizePixel = 0
	bg.Parent = surface

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, -16, 0, 34)
	heading.Position = UDim2.new(0, 8, 0, 6)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 24
	heading.TextColor3 = Color3.fromRGB(240, 190, 120)
	heading.Text = title
	heading.Parent = bg

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.Size = UDim2.new(1, -16, 1, -48)
	list.Position = UDim2.new(0, 8, 0, 42)
	list.BackgroundTransparency = 1
	list.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i = 1, ROWS do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 19
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.fromRGB(238, 228, 210)
		row.LayoutOrder = i
		row.Text = ""
		row.Parent = list
	end

	return list
end

local plaza = island.Zones:FindFirstChild("BarangayPlaza")
local px = plaza and plaza.Position.X or -225
local pz = plaza and plaza.Position.Z or -67

-- Two boards. The Fastest Lap board went with the bangka race.
local shellsRows = buildBoard("LeaderboardShells", "Most Shells", px - 20, pz + 22, 0)
local drownRows = buildBoard("LeaderboardDrowns", "Most Drowned", px + 20, pz + 22, 0)

local function refresh()
	local byShells, byDrowns = {}, {}

	for _, player in ipairs(Players:GetPlayers()) do
		local profile = PlayerProfileService.Get(player.UserId)
		if profile then
			table.insert(byShells, { name = player.DisplayName, value = profile.Shells or 0 })
			table.insert(byDrowns, { name = player.DisplayName, value = profile.Drowns or 0 })
		end
	end

	table.sort(byShells, function(a, b)
		return a.value > b.value
	end)
	table.sort(byDrowns, function(a, b)
		return a.value > b.value
	end)

	for i = 1, ROWS do
		local row = shellsRows:FindFirstChild("Row" .. i)
		local entry = byShells[i]
		if row then
			row.Text = entry and string.format("%d. %s -- %d", i, entry.name, entry.value) or ""
		end

		local drownRow = drownRows:FindFirstChild("Row" .. i)
		local drownEntry = byDrowns[i]
		if drownRow then
			drownRow.Text = drownEntry
				and string.format("%d. %s -- %d", i, drownEntry.name, drownEntry.value)
				or ""
		end
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(refresh)
		if not ok then
			warn("[LeaderboardService] refresh failed:", err)
		end
		task.wait(REFRESH_SECONDS)
	end
end)

print("[LeaderboardService] plaza boards up")
