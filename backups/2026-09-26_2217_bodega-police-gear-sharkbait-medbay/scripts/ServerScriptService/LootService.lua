-- LootService
-- The one way a find gets into a diver's sack. Everything the sea and the cave give out
-- goes through here.
--
-- Finds are deliberately NOT bag items: there is no cap and gathering never fails, so a
-- diver is never stood over a kristal they cannot pick up. The bag stays for equipment.
-- The cost of a big haul is the swim home, not the inventory screen.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local refreshSignal = ServerStorage:WaitForChild("InventoryRefresh")

local LootService = {}

-- Always succeeds: there is no limit on how many finds a diver can carry.
-- Returns how many were added, so callers can still report the haul.
function LootService.Give(player, key, count)
	local loot = ItemConfig.Loot[key]
	local profile = PlayerProfileService.Get(player.UserId)
	if not loot or not profile then
		return 0
	end

	local n = math.max(1, count or 1)
	profile.Finds = profile.Finds or {}
	profile.Finds[key] = (profile.Finds[key] or 0) + n
	refreshSignal:Fire(player)
	return n
end

-- Everything the diver is carrying, for the scatter when they drown.
function LootService.TakeAll(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return {}
	end
	local haul = {}
	for key, count in pairs(profile.Finds or {}) do
		if ItemConfig.Loot[key] and count > 0 then
			haul[key] = count
		end
	end
	profile.Finds = {}
	refreshSignal:Fire(player)
	return haul
end

-- Cashes in the whole sack. Equipment is untouched -- you only ever sell what you found.
-- Returns money earned, pieces sold, and an itemised breakdown of what changed hands.
-- The breakdown is what lets the Palengke actually SHOW where a diver's shells went
-- instead of silently deleting them.
function LootService.SellAll(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return 0, 0, {}
	end

	local total, pieces = ItemConfig.LootValue(profile.Finds)
	if pieces <= 0 then
		return 0, 0, {}
	end

	local sold = {}
	for key, count in pairs(profile.Finds) do
		if ItemConfig.Loot[key] and count > 0 then
			sold[key] = count
		end
	end

	profile.Finds = {}
	refreshSignal:Fire(player)
	return total, pieces, sold
end

return LootService
