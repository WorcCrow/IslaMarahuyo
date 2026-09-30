-- TreasureDigService
-- Baybayon Beach dig spots: hold the prompt to unearth a small Shells reward,
-- then the spot goes on cooldown until a fresh glint of treasure resets it.

local CurrencyService = require(script.Parent.CurrencyService)
local QuestService = require(script.Parent.QuestService)

local COOLDOWN_SECONDS = 45
local MIN_REWARD, MAX_REWARD = 8, 15

local digFolder = workspace.IslaMarahuyo.Activities:WaitForChild("TreasureDigs")
local rng = Random.new()

local function setSpotState(spot, buried)
	local prompt = spot:FindFirstChildOfClass("ProximityPrompt")
	local marker = spot:FindFirstChild("XMarker")
	if prompt then
		prompt.Enabled = buried
	end
	if marker then
		marker.Transparency = buried and 0 or 1
	end
end

local function onDug(player, spot)
	local prompt = spot:FindFirstChildOfClass("ProximityPrompt")
	if not prompt or not prompt.Enabled then return end

	setSpotState(spot, false)

	local reward = rng:NextInteger(MIN_REWARD, MAX_REWARD)
	CurrencyService.AddShells(player, reward, true, "TreasureDig")
	QuestService.Report(player, "TreasureDig", 1)

	task.delay(COOLDOWN_SECONDS, function()
		if spot and spot.Parent then
			setSpotState(spot, true)
		end
	end)
end

for _, spot in ipairs(digFolder:GetChildren()) do
	local prompt = spot:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			onDug(player, spot)
		end)
	end
end

print("[TreasureDigService] " .. #digFolder:GetChildren() .. " dig spots ready on Baybayon Beach")
