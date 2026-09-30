-- CaveBootstrap
-- Starts BreathService and wires the cave system's two interactables: Lung Coral
-- pickups (permanent breath upgrades) and the Perlas Hollow treasure (one-time Shells).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BreathService = require(script.Parent.BreathService)
local LootService = require(script.Parent.LootService)
local ItemConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemConfig"))
local PlayerProfileService = require(script.Parent.PlayerProfileService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

BreathService.Init()

local caveFolder = workspace.IslaMarahuyo.Activities:WaitForChild("CaveSystem")

local function getPlayerFromPart(part)
	local character = part and part:FindFirstAncestorWhichIsA("Model")
	return character and Players:GetPlayerFromCharacter(character)
end

for _, model in ipairs(caveFolder:GetChildren()) do
	if model.Name:match("^LungCoral_") then
		local prompt = model:FindFirstChild("CollectPrompt", true)
		if prompt then
			prompt.Triggered:Connect(function(player)
				local ok, resultOrReason = BreathService.AddUpgrade(player)
				if ok then
					prompt.Enabled = false
					model:Destroy()
					diveFeedback:FireClient(player, "upgrade", string.format("Lung Coral collected! Max breath is now %ds (%d/%d found).", BreathService.BASE_BREATH + resultOrReason * BreathService.UPGRADE_BONUS, resultOrReason, BreathService.MAX_UPGRADES), 0)
				elseif resultOrReason == "max" then
					diveFeedback:FireClient(player, "upgrade", "Your lungs are already at full capacity from the other Lung Corals.", 0)
				end
			end)
		end
	end
end

local treasure = caveFolder:FindFirstChild("PerlasHollowTreasure")
if treasure then
	local prompt = treasure:FindFirstChild("OpenPrompt", true)
	if prompt then
		prompt.Triggered:Connect(function(player)
			local profile = PlayerProfileService.Get(player.UserId)
			if not profile then
				return
			end
			if profile.CaveTreasureFound then
				diveFeedback:FireClient(player, "treasure", "Perlas Hollow is empty now -- you already claimed its pearl.", 0)
				return
			end
			profile.CaveTreasureFound = true
			-- The pearl is an object like any other find: claiming it is only half the job,
			-- because it still has to be carried back out of the deepest room in the cave.
			LootService.Give(player, "perlas", 1)
			diveFeedback:FireClient(player, "treasure", string.format(
				"You found the Perlas Hollow pearl -- worth %d Peso if you can carry it out.",
				ItemConfig.Loot.perlas.sell), 0)
		end)
	end
end

print("[CaveBootstrap] Breath service + cave interactables online")
