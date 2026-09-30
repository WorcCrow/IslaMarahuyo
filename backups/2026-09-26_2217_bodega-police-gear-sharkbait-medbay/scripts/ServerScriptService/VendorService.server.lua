-- VendorService (Palengke vendor)
-- Restock the three market crates in order (1, 2, 3) to complete a cycle. Steadier,
-- lower-variance Shells than fishing/dancing -- the job for players who'd rather not compete.
--
-- Payout was rebalanced: a full three-crate cycle used to pay a flat 6 Shells, against
-- 8-25 for a single fishing catch, so the "steady job" was strictly the worst way to earn
-- and nobody had a reason to work it. A cycle now pays 3 per crate plus a 12 bonus on
-- completion (21 total), which lands next to fishing per unit of time while keeping the
-- low variance that is the whole point of this activity. A short streak bonus rewards
-- staying on the job without making it the best earner on the island.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CurrencyService = require(script.Parent.CurrencyService)
local QuestService = require(script.Parent.QuestService)

-- A player serving a sentence on Palengke duty runs the same rounds for nothing: each full
-- 1-2-3 round is one restock off their sentence (PoliceService does the counting).
local serviceCredit = ServerStorage:WaitForChild("ServiceCredit")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local vendorFeedback = remotes:FindFirstChild("VendorFeedback")
if not vendorFeedback then
	vendorFeedback = Instance.new("RemoteEvent")
	vendorFeedback.Name = "VendorFeedback"
	vendorFeedback.Parent = remotes
end

local crateFolder = Workspace.IslaMarahuyo.Activities.VendorCrates

local PER_CRATE_REWARD = 3
local CYCLE_BONUS = 12
local STREAK_STEP = 2 -- extra Shells per consecutive clean cycle
local STREAK_MAX_BONUS = 10
local PER_CRATE_DEBOUNCE = 1

local expectedOrder = {} -- [player] = next crate order expected (1..3)
local lastCrateHitAt = {} -- [player] = { [order] = t }
local streak = {} -- [player] = consecutive completed cycles
local cycleStartBalance = {} -- [player] = Shells balance when this cycle began

for _, crate in ipairs(crateFolder:GetChildren()) do
	local prompt = crate:FindFirstChild("RestockPrompt")
	if prompt then
		local order = prompt:GetAttribute("Order")

		prompt.Triggered:Connect(function(player)
			local now = os.clock()
			lastCrateHitAt[player] = lastCrateHitAt[player] or {}
			if lastCrateHitAt[player][order] and now - lastCrateHitAt[player][order] < PER_CRATE_DEBOUNCE then
				return
			end
			lastCrateHitAt[player][order] = now

			local expected = expectedOrder[player] or 1
			local sentenced = player:GetAttribute("ServiceTrack") == "vendor"

			if order == expected then
				if order == 1 then
					cycleStartBalance[player] = CurrencyService.GetShells(player.UserId)
				end
				if not sentenced then
					CurrencyService.AddShells(player, PER_CRATE_REWARD, true, "Vendor")
				end

				if order == 3 and sentenced then
					expectedOrder[player] = 1
					cycleStartBalance[player] = nil
					serviceCredit:Fire(player, "restock")
				elseif order == 3 then
					local runs = (streak[player] or 0) + 1
					streak[player] = runs
					local bonus = CYCLE_BONUS + math.min((runs - 1) * STREAK_STEP, STREAK_MAX_BONUS)
					CurrencyService.AddShells(player, bonus, true, "Vendor")
					QuestService.Report(player, "VendorRestock", 1)
					expectedOrder[player] = 1

					-- Report what was actually credited across the whole cycle, so the
					-- number the player reads matches their balance once the fiesta and
					-- VIP multipliers have been applied.
					local earned = CurrencyService.GetShells(player.UserId) - (cycleStartBalance[player] or 0)
					cycleStartBalance[player] = nil
					vendorFeedback:FireClient(player, string.format(
						"Restock complete -- +%d Shells for the round%s",
						math.max(earned, 0),
						runs > 1 and string.format(" (%d in a row)", runs) or ""
					), true)
				else
					expectedOrder[player] = expected + 1
					vendorFeedback:FireClient(player, string.format(
						"Crate %d done -- next is crate %d",
						order,
						expected + 1
					), true)
				end
			else
				-- wrong crate -- restart the cycle from crate 1, no penalty beyond losing progress
				expectedOrder[player] = (order == 1) and 2 or 1
				streak[player] = 0
				cycleStartBalance[player] = nil
				vendorFeedback:FireClient(player, string.format(
					"Out of order -- crate %d was next. Starting again from crate %d.",
					expected,
					expectedOrder[player]
				), false)
			end
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	expectedOrder[player] = nil
	lastCrateHitAt[player] = nil
	streak[player] = nil
	cycleStartBalance[player] = nil
end)

print(string.format(
	"[VendorService] Palengke stall ready (crates 1 -> 2 -> 3, %d/crate + %d cycle bonus)",
	PER_CRATE_REWARD,
	CYCLE_BONUS
))
