-- MonetizationBootstrap
-- Wires the shop remotes to MarketplaceService, handles Developer Product receipts
-- idempotently, and loads/applies Game Pass perks on join.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(script.Parent.MonetizationConfig)
local GamePassService = require(script.Parent.GamePassService)
local CurrencyService = require(script.Parent.CurrencyService)
local PlayerProfileService = require(script.Parent.PlayerProfileService)
local QuestService = require(script.Parent.QuestService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestProduct = remotes:WaitForChild("RequestProductPurchase")
local requestPass = remotes:WaitForChild("RequestGamePassPurchase")

local function ensureRemote(name)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local bilaoBoxOpened = ensureRemote("BilaoBoxOpened")
local taskRerolled = ensureRemote("TaskRerolled")

-- Weighted roll over MonetizationConfig.BilaoBoxOdds -- the same table the shop UI
-- turns into published percentages.
local function rollBilaoBox()
	local odds = MonetizationConfig.BilaoBoxOdds
	local total = 0
	for _, entry in ipairs(odds) do
		total += entry.weight
	end
	local roll = math.random() * total
	local acc = 0
	for _, entry in ipairs(odds) do
		acc += entry.weight
		if roll <= acc then
			return entry
		end
	end
	return odds[1]
end

-- ===== Purchase requests from the shop UI =====

requestProduct.OnServerEvent:Connect(function(player, productKey)
	local product = MonetizationConfig.DeveloperProducts[productKey]
	if not product or product.id == 0 then
		warn("[MonetizationBootstrap] Product '" .. tostring(productKey) .. "' has no real id yet -- ignoring purchase request")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end)

requestPass.OnServerEvent:Connect(function(player, passKey)
	local pass = MonetizationConfig.GamePasses[passKey]
	if not pass or pass.id == 0 then
		warn("[MonetizationBootstrap] Pass '" .. tostring(passKey) .. "' has no real id yet -- ignoring purchase request")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.id)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then
		return
	end
	for passKey, pass in pairs(MonetizationConfig.GamePasses) do
		if pass.id == gamePassId then
			GamePassService.Recheck(player, passKey)
			break
		end
	end
end)

-- ===== Developer Product receipts (idempotent) =====

local function findProductKey(productId)
	for key, product in pairs(MonetizationConfig.DeveloperProducts) do
		if product.id == productId then
			return key, product
		end
	end
	return nil
end

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- player isn't in this server (yet, or left) -- Roblox will retry the receipt later
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	profile.ProcessedPurchases = profile.ProcessedPurchases or {}
	if profile.ProcessedPurchases[receiptInfo.PurchaseId] then
		-- already granted (e.g. the server saved-and-restarted between granting and confirming)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey, product = findProductKey(receiptInfo.ProductId)
	if not productKey then
		warn("[MonetizationBootstrap] Receipt for unknown product id", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if product.shells then
		CurrencyService.AddShells(player, product.shells, false, productKey) -- no VIP multiplier on purchased Shells
	elseif productKey == "InstantRestock" then
		player:SetAttribute("InstantRestockCharges", (player:GetAttribute("InstantRestockCharges") or 0) + 1)
	elseif productKey == "TaskReroll" then
		-- Granted only if it actually rerolled something. Returning NotProcessedYet on a
		-- no-op (every task already done) means Roblox retries rather than charging for
		-- nothing -- the client also blocks the button, this is the server-side guarantee.
		local ok, titleOrReason = QuestService.RerollTask(player)
		if not ok then
			warn("[MonetizationBootstrap] TaskReroll no-op for", player.Name, "--", titleOrReason)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		taskRerolled:FireClient(player, titleOrReason)
	elseif productKey == "StreakSaver" then
		profile.StreakSavers = (profile.StreakSavers or 0) + 1
		player:SetAttribute("StreakSavers", profile.StreakSavers)
	elseif productKey == "BilaoBox" then
		-- Rolls the same table the shop publishes odds from, so what players are shown and
		-- what the server actually grants can never disagree.
		local drop = rollBilaoBox()
		profile.Cosmetics = profile.Cosmetics or {}
		profile.Cosmetics[drop.key] = (profile.Cosmetics[drop.key] or 0) + 1
		CurrencyService.AddShells(player, drop.shells, false, "BilaoBox")
		bilaoBoxOpened:FireClient(player, drop.name, drop.rarity, drop.shells)
	else
		warn("[MonetizationBootstrap] Product '" .. productKey .. "' has no grant logic wired up yet")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	profile.ProcessedPurchases[receiptInfo.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt

-- ===== Game Pass ownership on join =====

Players.PlayerAdded:Connect(function(player)
	task.spawn(GamePassService.LoadForPlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	GamePassService.Cleanup(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(GamePassService.LoadForPlayer, player)
end

-- ===== Publish Bilao Box odds to the client =====
-- Replicated from the same table the server rolls on, so the disclosed percentages
-- cannot drift away from the real drop rates.
do
	local existing = ReplicatedStorage:FindFirstChild("BilaoBoxOdds")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "BilaoBoxOdds"

	local total = 0
	for _, entry in ipairs(MonetizationConfig.BilaoBoxOdds) do
		total += entry.weight
	end

	for index, entry in ipairs(MonetizationConfig.BilaoBoxOdds) do
		local item = Instance.new("Configuration")
		item.Name = string.format("%02d_%s", index, entry.key)
		item:SetAttribute("ItemName", entry.name)
		item:SetAttribute("Rarity", entry.rarity)
		item:SetAttribute("Percent", entry.weight / total * 100)
		item.Parent = folder
	end

	folder.Parent = ReplicatedStorage
end

print("[MonetizationBootstrap] Shop + receipt handling online")
