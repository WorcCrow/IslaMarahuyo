-- SeaHarvestService (Ani sa Dagat)
-- Gatherable finds across the seabed and down through the cave system. Payout scales with
-- how deep you had to go for it, so the sea is the game's main earner and air management is
-- the thing standing between you and the good money.
--
-- The deep tiers deliberately outrun a stock 45-second lungful: they can only be worked
-- properly once you've found Lung Corals, and the abyss sits below the single air dome in
-- Kailaliman, so it has to be planned as a route rather than swum at.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuestService = require(script.Parent.QuestService)
local LootService = require(script.Parent.LootService)
local ItemConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

local RESPAWN_SECONDS = 90
local MAX_REACH = 18
local rng = Random.new()

-- Payout curve. The surface tiers are open water anyone can reach in swim trunks; the two
-- cave tiers cost a flashlight battery, air and usually a tank to reach at all, so they pay
-- several times what the island does. Gear bought at the Palengke has to earn itself back
-- down here, or there is no reason to buy it.
--   island work for comparison: fishing 8/15/25, bangka lap 15-30, vendor cycle ~21-31
local TIERS = {
	{
		key = "shallow", label = "Kabibe", count = 12,
		minDepth = -17, maxDepth = -4,
		loot = "kabibe",
		color = Color3.fromRGB(240, 226, 190),
		names = { "Kabibe", "Sigay", "Talaba", "Bulalo Shell" },
		mode = "seabed",
	},
	{
		key = "reef", label = "Bahura", count = 10,
		minDepth = -31, maxDepth = -17,
		loot = "bahura",
		color = Color3.fromRGB(255, 150, 170),
		names = { "Bahura Coral", "Sea Urchin", "Tahong", "Starfish" },
		mode = "seabed",
	},
	{
		key = "cave", label = "Yungib", count = 6,
		loot = "yungib",
		color = Color3.fromRGB(170, 230, 255),
		names = { "Cave Pearl", "Glass Sponge", "Blind Shrimp" },
		mode = "volume",
		volumes = {
			{ centre = Vector3.new(-40, -26, 150), radius = 13 },
			{ centre = Vector3.new(-150, -20, 280), radius = 9 },
			{ centre = Vector3.new(150, -20, 50), radius = 9 },
			{ centre = Vector3.new(-100, -30, 240), radius = 9 },
		},
	},
	{
		key = "abyss", label = "Kailaliman", count = 5,
		loot = "kailaliman",
		color = Color3.fromRGB(200, 170, 255),
		names = { "Perlas ng Kailaliman", "Black Coral", "Abyss Nautilus" },
		mode = "volume",
		volumes = {
			{ centre = Vector3.new(-40, -64, 150), radius = 15 },
			{ centre = Vector3.new(-98, -60, 196), radius = 10 },
			{ centre = Vector3.new(14, -68, 112), radius = 10 },
		},
	},
}

local folder = workspace.IslaMarahuyo.Activities:FindFirstChild("SeaHarvest")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "SeaHarvest"
	folder.Parent = workspace.IslaMarahuyo.Activities
end
folder:ClearAllChildren()

local rayParams = RaycastParams.new()
rayParams.IgnoreWater = true
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { folder }

-- Is this point inside open water or an air pocket, rather than buried in rock?
local function isOpenSpace(pos)
	local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok or not materials then
		return false
	end
	local m = materials[1][1][1]
	return m == Enum.Material.Water or m == Enum.Material.Air
end

local function findSeabedSpot(tier)
	for _ = 1, 60 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(220, 760)
		local x, z = math.cos(angle) * dist, math.sin(angle) * dist
		local hit = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -180, 0), rayParams)
		if hit and hit.Position.Y >= tier.minDepth and hit.Position.Y <= tier.maxDepth then
			local spot = hit.Position + Vector3.new(0, 1.6, 0)
			if isOpenSpace(spot) then
				return spot
			end
		end
	end
	return nil
end

local function findVolumeSpot(tier)
	for _ = 1, 60 do
		local volume = tier.volumes[rng:NextInteger(1, #tier.volumes)]
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.7, 0.4), rng:NextNumber(-1, 1)).Unit
			* rng:NextNumber(2, volume.radius)
		local spot = volume.centre + offset
		if isOpenSpace(spot) then
			return spot
		end
	end
	return nil
end

local function findSpot(tier)
	if tier.mode == "seabed" then
		return findSeabedSpot(tier)
	end
	return findVolumeSpot(tier)
end

local nodes = {}

local function dressNode(model, tier, pos)
	local name = tier.names[rng:NextInteger(1, #tier.names)]
	model.Name = "Find_" .. tier.key

	local orb = model:FindFirstChild("Orb")
	if not orb then
		orb = Instance.new("Part")
		orb.Name = "Orb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(2.2, 2.2, 2.2)
		orb.Material = Enum.Material.Neon
		orb.Anchored = true
		orb.CanCollide = false
		orb.Parent = model
		model.PrimaryPart = orb

		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 1.8
		light.Parent = orb

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HarvestPrompt"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = orb
	end

	orb.Color = tier.color
	orb.Position = pos
	orb.PointLight.Color = tier.color
	orb.HarvestPrompt.ActionText = "Gather " .. name
	orb.HarvestPrompt.ObjectText = string.format("%s -- %.0fm down", tier.label, math.abs(pos.Y))
	orb.HarvestPrompt.Enabled = true
	model:SetAttribute("ItemName", name)
	model:SetAttribute("Depth", pos.Y)
end

local function relocate(model, tier)
	local pos = findSpot(tier)
	if not pos then
		task.delay(20, function()
			if model.Parent then
				relocate(model, tier)
			end
		end)
		return
	end
	dressNode(model, tier, pos)
end

local function onHarvest(model, tier, player)
	local orb = model.PrimaryPart
	local prompt = orb and orb:FindFirstChild("HarvestPrompt")
	if not prompt or not prompt.Enabled then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - orb.Position).Magnitude > MAX_REACH then
		return
	end

	-- A find is an object, not a payout: it joins the sack and is only worth anything once
	-- it is carried up to the Palengke alive.
	local depth = math.abs(model:GetAttribute("Depth") or 0)
	LootService.Give(player, tier.loot, 1)

	prompt.Enabled = false
	orb.Transparency = 1
	orb.PointLight.Enabled = false

	local loot = ItemConfig.Loot[tier.loot]
	QuestService.Report(player, "SeaHarvest", 1)
	diveFeedback:FireClient(player, "harvest", string.format(
		"%s gathered at %.0fm -- worth %d Peso at the Palengke.",
		model:GetAttribute("ItemName") or tier.label, depth, loot.sell), 0)

	task.delay(RESPAWN_SECONDS, function()
		if model.Parent then
			orb.Transparency = 0
			orb.PointLight.Enabled = true
			relocate(model, tier)
		end
	end)
end

local placed = 0
for _, tier in ipairs(TIERS) do
	for _ = 1, tier.count do
		local pos = findSpot(tier)
		if pos then
			local model = Instance.new("Model")
			model.Parent = folder
			dressNode(model, tier, pos)
			nodes[model] = tier
			placed += 1
			model.PrimaryPart.HarvestPrompt.Triggered:Connect(function(player)
				onHarvest(model, tier, player)
			end)
		end
	end
end

local summary = {}
for _, tier in ipairs(TIERS) do
	local loot = ItemConfig.Loot[tier.loot]
	summary[#summary + 1] = string.format("%s sells %d", tier.label, loot and loot.sell or 0)
end
print("[SeaHarvestService]", placed, "finds placed --", table.concat(summary, ", "))
