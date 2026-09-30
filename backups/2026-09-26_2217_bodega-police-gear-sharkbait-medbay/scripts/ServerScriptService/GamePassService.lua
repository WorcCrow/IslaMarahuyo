-- GamePassService
-- Cached ownership checks + the perks each pass grants. Passes still at id = 0 (not yet
-- created on the Creator Dashboard) are treated as "not owned" without calling the API.

local MarketplaceService = game:GetService("MarketplaceService")
local MonetizationConfig = require(script.Parent.MonetizationConfig)

local GamePassService = {}

local ownershipCache = {} -- [userId] = { [passKey] = boolean }
local warnedUnconfigured = {}

-- Lets the admin dashboard force a pass "owned" for a session, purely for QA/demo --
-- so perks can be proven out end-to-end before a real Game Pass ID exists.
local debugOverrides = {} -- [userId] = { [passKey] = boolean }

function GamePassService.SetDebugOverride(userId, passKey, value)
	debugOverrides[userId] = debugOverrides[userId] or {}
	debugOverrides[userId][passKey] = value
end

local function checkOwnership(userId, passKey)
	local override = debugOverrides[userId] and debugOverrides[userId][passKey]
	if override ~= nil then
		return override
	end

	local pass = MonetizationConfig.GamePasses[passKey]
	if not pass or pass.id == 0 then
		if not warnedUnconfigured[passKey] then
			warnedUnconfigured[passKey] = true
			warn("[GamePassService] '" .. passKey .. "' has no real id yet -- treating as not owned")
		end
		return false
	end

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, pass.id)
	end)
	return ok and owns or false
end

-- Populates the ownership cache for a player. Call once on join.
function GamePassService.LoadForPlayer(player)
	local cache = {}
	for passKey in pairs(MonetizationConfig.GamePasses) do
		cache[passKey] = checkOwnership(player.UserId, passKey)
	end
	ownershipCache[player.UserId] = cache
	GamePassService.ApplyPerks(player)
end

function GamePassService.Owns(player, passKey)
	local cache = ownershipCache[player.UserId]
	return cache and cache[passKey] or false
end

-- Re-checks one pass (e.g. right after a purchase finishes) and re-applies perks.
function GamePassService.Recheck(player, passKey)
	local cache = ownershipCache[player.UserId]
	if not cache then
		return
	end
	cache[passKey] = checkOwnership(player.UserId, passKey)
	GamePassService.ApplyPerks(player)
end

-- Translates ownership into concrete gameplay effects.
--   KasamaVIP           -> 2x Shells on everything earned
--   BangkeroSpeed       -> boat speed boost (read by the bangka controller)
--   ExtraCabinPlot      -> a second simultaneous bodega slot (BodegaService reads Owns())
--   KalangitanIsleAccess-> the ferry to the offshore isle (FerryService reads Owns())
--   ZiplinePass         -> zipline legs cost nothing (ZiplineService reads the attribute)
--   BrightBeam          -> brighter, wider flashlight cone (FlashlightClient reads the attribute)
--   CabinBuilder        -> the Stone Bodega tier for free (BodegaService)
--   BangkaCustom        -> boat paint/sail/name-plate options
--   NameTitle           -> player-chosen title above the name
--   IslandLegend        -> gold nameplate + Island Legend title
--   DanceEmotes         -> the extra emote set
--   BroadcastLicense    -> your track plays out loud to nearby players
--   AudioCustomizer     -> personal playlist ordering
--   PhotoFX             -> cinematic filters at photo spots
--
-- Everything here is looks, time or reach. None of it touches breath, sharks, the maze
-- or the revive -- see the rule at the top of MonetizationConfig before adding to this.
--
-- Perks that are cheap to check are mirrored onto attributes so the client can render
-- the right UI without asking the server; the ones queried at the point of use
-- (cabin plot, ferry) stay as Owns() calls so a mid-session purchase just works.
function GamePassService.ApplyPerks(player)
	if GamePassService.Owns(player, "KasamaVIP") then
		player:SetAttribute("ShellsMultiplier", 2)
	else
		player:SetAttribute("ShellsMultiplier", nil)
	end

	player:SetAttribute("BoatSpeedBoost", GamePassService.Owns(player, "BangkeroSpeed") or nil)
	player:SetAttribute("CabinPlotLimit", GamePassService.Owns(player, "ExtraCabinPlot") and 2 or 1)
	player:SetAttribute("IsleAccess", GamePassService.Owns(player, "KalangitanIsleAccess") or nil)

	-- convenience
	player:SetAttribute("FreeZipline", GamePassService.Owns(player, "ZiplinePass") or nil)
	-- FlashlightClient reads this to widen and brighten the beam. Flagged in
	-- MonetizationConfig: it makes the cave easier to read, which is close to the line.
	player:SetAttribute("BrightBeam", GamePassService.Owns(player, "BrightBeam") or nil)

	-- building / decor
	player:SetAttribute("CabinBuilder", GamePassService.Owns(player, "CabinBuilder") or nil)
	player:SetAttribute("BangkaCustom", GamePassService.Owns(player, "BangkaCustom") or nil)

	-- expression
	player:SetAttribute("CanSetTitle", GamePassService.Owns(player, "NameTitle") or nil)
	player:SetAttribute("DanceEmotePack", GamePassService.Owns(player, "DanceEmotes") or nil)
	player:SetAttribute("BroadcastLicense", GamePassService.Owns(player, "BroadcastLicense") or nil)
	player:SetAttribute("AudioCustomizer", GamePassService.Owns(player, "AudioCustomizer") or nil)
	player:SetAttribute("PhotoFX", GamePassService.Owns(player, "PhotoFX") or nil)

	-- Prestige. Only the flag is set here: TitleTagService is the single owner of
	-- DisplayTitle, because it is the one place that knows the custom/prestige/earned
	-- precedence. Two services writing the same attribute is how it ends up flickering.
	player:SetAttribute("IslandLegend", GamePassService.Owns(player, "IslandLegend") or nil)
end

function GamePassService.Cleanup(player)
	ownershipCache[player.UserId] = nil
end

return GamePassService
