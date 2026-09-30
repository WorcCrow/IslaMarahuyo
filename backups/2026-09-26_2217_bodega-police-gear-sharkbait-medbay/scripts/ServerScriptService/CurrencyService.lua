-- CurrencyService
-- Server-authoritative Shells (in-experience currency) operations.
-- All balance changes go through here so nothing ever trusts a client-sent amount.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local PlayerProfileService = require(script.Parent.PlayerProfileService)
local FiestaEventService = require(script.Parent.FiestaEventService)

local CurrencyService = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shellsUpdated = remotes:WaitForChild("ShellsUpdated")

-- Maps a `source` label (passed by callers) to the AnalyticsEconomyTransactionType
-- Roblox's economy charts group by. Anything not listed falls back to "Gameplay".
local TRANSACTION_TYPE_BY_SOURCE = {
	Quest = "Gameplay",
	Dance = "Gameplay",
	Vendor = "Gameplay",
	TreasureDig = "Gameplay",
	SeaHarvest = "Gameplay",
	CaveTreasure = "Gameplay",
	-- sinks: fees the player pays back into the economy
	Zipline = "Gameplay",
	BoatRental = "Gameplay",
	DrownFee = "Gameplay",
	DailyLogin = "TimedReward",
	GiftReceived = "ContextualPurchase",
	GiftBonus = "ContextualPurchase",
	GiftSent = "ContextualPurchase",
	ShellsSmall = "IAP",
	ShellsMedium = "IAP",
	ShellsLarge = "IAP",
	ShellsMega = "IAP",
	InstantRestock = "IAP",
	BilaoBox = "IAP",
}

-- Flat, non-IAP grants above this size are almost certainly a bug or an exploit --
-- nothing in the earning loop or gifting caps should ever produce one this large.
local SUSPICIOUS_AMOUNT_THRESHOLD = 500

-- Plain-language names for the account view. Anything not listed falls back to the raw
-- source label, which is still more use to a player than nothing.
local LEDGER_LABELS = {
	Quest = "Island task",
	Dance = "Sayawan",
	Vendor = "Palengke restock",
	TreasureDig = "Beach dig",
	-- roles and the black market
	LootSold = "Sold finds at the Palengke",
	NurseWork = "Nursing at the Health Post",
	NurseFee = "Paid the nurse",
	MarketShift = "A day on the Palengke floor",
	ToldaSale = "Sold from your tolda",
	ToldaBuy = "Bought from a tolda",
	Confiscation = "Cut of a seized stall",
	SeaHarvest = "Sea find",
	CaveTreasure = "Perlas Hollow",
	CaveCrystal = "Kristal",
	CaveHoard = "Dead-end hoard",
	LootSold = "Sold finds at the Palengke",
	Zipline = "Zipline fare",
	BoatRental = "Bangka hire",
	BoatExtension = "Bangka extension",
	DailyLogin = "Daily login",
	GiftReceived = "Gift received",
	GiftSent = "Gift sent",
	GiftBonus = "Gifting bonus",
	BagUpgrade = "Bigger bag",
	-- MarketSale/MarketBuy are gone with the Palengke stall board. Old saved ledgers may
	-- still contain them, but nothing writes them any more -- see ToldaSale/ToldaBuy.
}

local LEDGER_MAX = 60

-- Every movement of money in the game passes through here, so this is the one place that
-- can answer "where did it come from" and "why am I short" without each service having to
-- remember to report itself.
local function appendLedger(player, signedAmount, source, endingBalance)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return
	end
	profile.Ledger = profile.Ledger or {}

	local label = LEDGER_LABELS[source]
	if not label then
		-- Item_battery -> "Bought Battery", BagUpgrade_bayong -> "Bigger bag"
		local itemKey = string.match(source or "", "^Item_(%w+)")
		if itemKey then
			label = "Bought " .. itemKey
		elseif string.match(source or "", "^BagUpgrade_") then
			label = "Bigger bag"
		else
			label = source or "Unknown"
		end
	end

	table.insert(profile.Ledger, {
		at = os.time(),
		amount = signedAmount,
		label = label,
		balance = endingBalance,
	})
	while #profile.Ledger > LEDGER_MAX do
		table.remove(profile.Ledger, 1)
	end
end

local function logEconomyEvent(player, flowType, amount, endingBalance, source)
	source = source or "Unknown"
	local transactionType = TRANSACTION_TYPE_BY_SOURCE[source] or "Gameplay"

	appendLedger(player,
		flowType == Enum.AnalyticsEconomyFlowType.Sink and -amount or amount,
		source, endingBalance)

	if amount > SUSPICIOUS_AMOUNT_THRESHOLD and transactionType ~= "IAP" then
		warn("[CurrencyService] Suspiciously large Shells change:", amount, "for", player.Name, "source:", source)
	end

	local ok, err = pcall(function()
		AnalyticsService:LogEconomyEvent(player, flowType, "Shells", amount, endingBalance, transactionType, source)
	end)
	if not ok then
		warn("[CurrencyService] Analytics log failed:", err)
	end
end

function CurrencyService.GetShells(userId)
	local profile = PlayerProfileService.Get(userId)
	return profile and profile.Shells or 0
end

-- Adds (or subtracts, if amount is negative) Shells and pushes the new balance to the client.
-- applyMultiplier defaults to true; pass false for purchased Shells packs so the Kasama VIP
-- 2x perk applies to *earned* Shells only, not to Shells someone already paid Robux for.
function CurrencyService.AddShells(player, amount, applyMultiplier, source)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return 0
	end

	if applyMultiplier ~= false and amount > 0 then
		local multiplier = player:GetAttribute("ShellsMultiplier") or 1
		multiplier *= FiestaEventService.GetMultiplier()
		if multiplier ~= 1 then
			amount = math.floor(amount * multiplier)
		end
	end

	profile.Shells = math.max(0, profile.Shells + amount)
	shellsUpdated:FireClient(player, profile.Shells)

	if amount > 0 then
		logEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, amount, profile.Shells, source)
	elseif amount < 0 then
		logEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, -amount, profile.Shells, source)
	end

	return profile.Shells
end

-- Atomically checks-and-deducts. Returns false without changing anything if funds are insufficient.
function CurrencyService.TrySpend(player, amount, source)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile or profile.Shells < amount then
		return false
	end

	profile.Shells -= amount
	shellsUpdated:FireClient(player, profile.Shells)
	logEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, amount, profile.Shells, source)
	return true
end

return CurrencyService
