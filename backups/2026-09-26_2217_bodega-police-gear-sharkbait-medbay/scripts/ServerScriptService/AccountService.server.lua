-- AccountService
-- The player's own book: every Peso in and out, and why.
--
-- This is what is left of the old MarketService. The Palengke stall board -- where players
-- listed goods for other players at their own prices -- has been removed entirely. The
-- Palengke is now NPC-only: it sells gear at fixed prices and buys finds at fixed rates.
--
-- All player-to-player trade moved to the black market tolda. That is a deliberate
-- economic choice, not just a relocation: if the only way to name your own price is to
-- pitch an illegal stall, then every player marketplace is a crime scene, and the pulis
-- have something real to police. It also means the stall fee that used to justify the
-- black market is gone -- the edge is now simply that no legal alternative exists.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestLedger = remotes:FindFirstChild("RequestLedger")
if not requestLedger then
	requestLedger = Instance.new("RemoteFunction")
	requestLedger.Name = "RequestLedger"
	requestLedger.Parent = remotes
end

local SHOWN = 40 -- newest first; a book, not an archive

requestLedger.OnServerInvoke = function(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return { balance = 0, entries = {} }
	end

	local entries = {}
	local ledger = profile.Ledger or {}
	-- the ledger is appended to, so the tail is the newest
	for i = #ledger, math.max(1, #ledger - SHOWN + 1), -1 do
		local e = ledger[i]
		if e then
			-- CurrencyService writes {at, amount, label, balance}; it resolves the source
			-- label at write time, so there is nothing to translate here
			table.insert(entries, {
				amount = e.amount, label = e.label, balance = e.balance, at = e.at,
			})
		end
	end

	return {
		balance = CurrencyService.GetShells(player.UserId) or 0,
		entries = entries,
	}
end

print("[AccountService] account book online -- the Palengke no longer takes player listings")
