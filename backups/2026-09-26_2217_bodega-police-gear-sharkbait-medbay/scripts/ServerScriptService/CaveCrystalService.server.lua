-- CaveCrystalService (Kristal ng Kailaliman)
-- One crystal at a time, hidden in a randomly-chosen DEEP chamber -- never in the hub or
-- the shallow grottoes, so finding it is a question of knowing the deep half of the maze
-- and having the air to get back out. When it's taken it goes quiet for a while, then
-- re-lights somewhere else in the deep and the whole server is told it's back -- but never
-- told where, because that's the entire task.
--
-- The payout is one Shell per stud of depth, so the spots that cost the most air are
-- also the ones worth the trip: 62 at the Cold Chamber, 118 down in Perlas Hollow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local QuestService = require(script.Parent.QuestService)
local LootService = require(script.Parent.LootService)
local ItemConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemConfig"))
local CaveGen = require(game.ServerStorage.CaveGen)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

-- Only chambers at this depth or below are eligible. Everything shallower is on the
-- casual route through the cave and would make this a walk-up collectible.
local MIN_DEPTH = -60
local RESPAWN_SECONDS = 150

local caveFolder = workspace.IslaMarahuyo.Activities:WaitForChild("CaveSystem")
local rng = Random.new(os.time() + 7331)

local DEEP_SPOTS = {}
for name, n in pairs(CaveGen.Nodes) do
	if n.kind ~= "entrance" and n.y <= MIN_DEPTH then
		table.insert(DEEP_SPOTS, { name = name, label = n.label or name, x = n.x, y = n.y, z = n.z, r = n.r })
	end
end
table.sort(DEEP_SPOTS, function(a, b)
	return a.name < b.name
end)

local current = nil -- { model =, spot =, reward = }
local lastSpotName = nil

local function clearCrystal()
	if current and current.model then
		current.model:Destroy()
	end
	current = nil
end

local function buildCrystal(spot, reward)
	local model = Instance.new("Model")
	model.Name = "KristalNgKailaliman"

	-- sit it a little off the chamber's dead centre so it isn't always in the same place
	-- relative to the tunnel mouth you arrive from
	local offset = Vector3.new(
		rng:NextNumber(-1, 1),
		rng:NextNumber(-0.5, 0.3),
		rng:NextNumber(-1, 1)
	).Unit * (spot.r * 0.35)
	local pos = Vector3.new(spot.x, spot.y, spot.z) + offset

	local shard = Instance.new("Part")
	shard.Name = "Shard"
	shard.Size = Vector3.new(1.8, 3.4, 1.8)
	shard.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(20), rng:NextNumber(0, math.pi * 2), math.rad(15))
	shard.Anchored = true
	shard.CanCollide = false
	shard.Material = Enum.Material.Neon
	shard.Color = Color3.fromRGB(120, 240, 255)
	shard.Transparency = 0.15
	shard.Parent = model
	model.PrimaryPart = shard

	local glow = Instance.new("PointLight")
	glow.Brightness = 3
	glow.Range = 22
	glow.Color = Color3.fromRGB(140, 235, 255)
	glow.Parent = shard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakePrompt"
	prompt.ActionText = "Take the Kristal"
	prompt.ObjectText = string.format("Kristal ng Kailaliman (sells %d)", ItemConfig.Loot.kristal.sell)
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = shard

	model.Parent = caveFolder
	return model, prompt
end

local function announceAll(text)
	for _, player in ipairs(Players:GetPlayers()) do
		diveFeedback:FireClient(player, "crystal", text, 0)
	end
end

local spawnCrystal -- forward declaration

local function onCollected(player)
	if not current then
		return
	end
	local spot = current.spot

	LootService.Give(player, "kristal", 1)
	clearCrystal()

	local profile = PlayerProfileService.Get(player.UserId)
	if profile then
		profile.CrystalsFound = (profile.CrystalsFound or 0) + 1
		player:SetAttribute("CrystalsFound", profile.CrystalsFound)
	end

	-- The kristal is a bulky object, not a payout: it fills a whole slot and is only
	-- worth anything once it is carried up to the Palengke.
	local loot = ItemConfig.Loot.kristal
	pcall(function()
		QuestService.Report(player, "CaveCrystal", 1)
	end)

	diveFeedback:FireClient(player, "crystal", string.format(
		"You pried the Kristal out of %s -- worth %d Peso topside. Now get back to air.",
		spot.label, loot.sell), 0)

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			diveFeedback:FireClient(other, "crystal", string.format(
				"%s brought up the Kristal ng Kailaliman. Another one will form in the deep soon.",
				player.DisplayName), 0)
		end
	end

	task.delay(RESPAWN_SECONDS, spawnCrystal)
end

function spawnCrystal()
	if #DEEP_SPOTS == 0 then
		warn("[CaveCrystalService] no chambers deep enough to hold a crystal")
		return
	end
	clearCrystal()

	-- never twice in a row in the same chamber, so nobody can just camp one room
	local spot
	for _ = 1, 12 do
		spot = DEEP_SPOTS[rng:NextInteger(1, #DEEP_SPOTS)]
		if #DEEP_SPOTS == 1 or spot.name ~= lastSpotName then
			break
		end
	end
	lastSpotName = spot.name

	local reward = math.floor(math.abs(spot.y))
	local model, prompt = buildCrystal(spot, reward)
	current = { model = model, spot = spot, reward = reward }

	prompt.Triggered:Connect(function(player)
		if current and current.model == model then
			onCollected(player)
		end
	end)

	announceAll("A Kristal ng Kailaliman is glowing somewhere in the deep cave. Only the divers who know the far chambers will reach it.")
end

local function initPlayer(player)
	task.spawn(function()
		for _ = 1, 30 do
			local profile = PlayerProfileService.Get(player.UserId)
			if profile then
				player:SetAttribute("CrystalsFound", profile.CrystalsFound or 0)
				return
			end
			task.wait(0.5)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end
Players.PlayerAdded:Connect(initPlayer)

spawnCrystal()

print(string.format("[CaveCrystalService] kristal live -- %d deep chambers in rotation (%d studs or deeper)", #DEEP_SPOTS, math.abs(MIN_DEPTH)))
