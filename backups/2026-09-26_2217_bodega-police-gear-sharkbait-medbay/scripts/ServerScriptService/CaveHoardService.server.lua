-- CaveHoardService
-- Puts the biggest payouts in the game at the ends of the fourteen dead-end crawls -- the
-- places with no air, no through route and nothing else worth the swim.
--
-- The point is to make the dangerous half of the cave worth entering. A dead end is where
-- divers suffocate: you commit air to get in, and you need the same again to get back out,
-- with no pocket at the far end to save you. So the hoards scale with depth, and the
-- deepest ones pay more than anything else on the island.
--
-- They rotate. Only a few are live at a time, so nobody farms one known crawl -- you have
-- to go looking, which means swimming past air pockets you might need on the way home.

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LootService = require(ServerScriptService.LootService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local CaveGen = require(ServerStorage:WaitForChild("CaveGen"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

local LIVE_AT_ONCE = 4
local RESPAWN_SECONDS = 210
-- A hoard is a pile of Yaman, scaled by how deep the crawl runs.
local STUDS_PER_PIECE = 55 -- a -220 crawl yields 4 pieces, a -74 one yields 1
local MIN_PIECES, MAX_PIECES = 1, 6
local REACH = 14

local rng = Random.new()

local folder = workspace:FindFirstChild("CaveHoards")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CaveHoards"
	folder.Parent = workspace
end
folder:ClearAllChildren()

local deadEnds = {}
for name, node in pairs(CaveGen.Nodes) do
	if node.kind == "deadend" then
		table.insert(deadEnds, {name = name, node = node})
	end
end
table.sort(deadEnds, function(a, b) return a.name < b.name end)

local live = {} -- [deadEndName] = model

local function piecesFor(node)
	return math.clamp(math.floor(math.abs(node.y) / STUDS_PER_PIECE + 0.5), MIN_PIECES, MAX_PIECES)
end

local function buildHoard(entry, pieces)
	local node = entry.node
	local model = Instance.new("Model")
	model.Name = "Hoard_" .. entry.name

	local pile = Instance.new("Part")
	pile.Name = "Pile"
	pile.Shape = Enum.PartType.Ball
	pile.Size = Vector3.new(3.4, 2.2, 3.4)
	pile.Material = Enum.Material.Foil
	pile.Color = Color3.fromRGB(226, 182, 92)
	pile.Anchored = true
	pile.CanCollide = false
	pile.CanQuery = false
	pile.CanTouch = false
	pile.CFrame = CFrame.new(node.x, node.y - node.r + 3, node.z)
	pile.Parent = model

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 206, 120)
	glow.Brightness = 2.6
	glow.Range = 24
	glow.Shadows = false
	glow.Parent = pile

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = node.label or entry.name
	prompt.ActionText = string.format("Take the hoard (%d Yaman)", pieces)
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = REACH
	prompt.RequiresLineOfSight = false
	prompt.Parent = pile

	model.PrimaryPart = pile
	model.Parent = folder
	return model, prompt
end

local placeOne

local function claim(entry, model, prompt, pieces, player)
	if not model.Parent then
		return
	end

	local taken = LootService.Give(player, "yaman", pieces)
	local worth = taken * ItemConfig.Loot.yaman.sell

	prompt.Enabled = false
	live[entry.name] = nil
	model:Destroy()

	diveFeedback:FireClient(player, "hoard", string.format(
		"You emptied the hoard in %s -- %d Yaman, worth %d at the Palengke. Now get out.",
		entry.node.label or entry.name, taken, worth), 0)

	task.delay(RESPAWN_SECONDS, placeOne)
end

function placeOne()
	local candidates = {}
	for _, entry in ipairs(deadEnds) do
		if not live[entry.name] then
			table.insert(candidates, entry)
		end
	end
	if #candidates == 0 then
		return
	end

	local entry = candidates[rng:NextInteger(1, #candidates)]
	local pieces = piecesFor(entry.node)
	local model, prompt = buildHoard(entry, pieces)
	model:SetAttribute("Pieces", pieces)
	live[entry.name] = model

	prompt.Triggered:Connect(function(player)
		claim(entry, model, prompt, model:GetAttribute("Pieces") or pieces, player)
	end)
end

for _ = 1, LIVE_AT_ONCE do
	placeOne()
end

local least, most = math.huge, -math.huge
for _, entry in ipairs(deadEnds) do
	local p = piecesFor(entry.node)
	least = math.min(least, p)
	most = math.max(most, p)
end

print(string.format("[CaveHoardService] %d dead-end hoards in rotation, %d live -- %d to %d Yaman (%d each)",
	#deadEnds, LIVE_AT_ONCE, least, most, ItemConfig.Loot.yaman.sell))
