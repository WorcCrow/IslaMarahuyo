-- AdminService
-- Implements every action the admin dashboard can trigger. AdminBootstrap checks the
-- whitelist before calling any of these -- this module assumes the caller is already
-- authorized, so it must never be required or reachable from a client-trusted path.

local CurrencyService = require(script.Parent.CurrencyService)
local GamePassService = require(script.Parent.GamePassService)
local FiestaEventService = require(script.Parent.FiestaEventService)
local PlayerProfileService = require(script.Parent.PlayerProfileService)
local QuestService = require(script.Parent.QuestService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fiestaStatusUpdated = remotes:WaitForChild("FiestaStatusUpdated")

local AdminService = {}

function AdminService.GrantShells(targetPlayer, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount == 0 then
		return false, "Enter a non-zero amount."
	end
	local newBalance = CurrencyService.AddShells(targetPlayer, amount, false, "AdminGrant")
	return true, string.format("%s now has %d Shells.", targetPlayer.Name, newBalance)
end

function AdminService.SetTestVIP(targetPlayer, enabled)
	return AdminService.SetTestPass(targetPlayer, "KasamaVIP", enabled)
end

-- Any pass can be forced on for QA, not just VIP -- the ferry and the second cabin
-- plot are gated the same way and need the same proving-out before real IDs exist.
local PASS_LABELS = {
	KasamaVIP = "2x Shells multiplier",
	BangkeroSpeed = "boat speed boost",
	ExtraCabinPlot = "second cabin plot",
	KalangitanIsleAccess = "Kalangitan Isle ferry",
}

function AdminService.SetTestPass(targetPlayer, passKey, enabled)
	if not PASS_LABELS[passKey] then
		return false, "Unknown pass: " .. tostring(passKey)
	end
	GamePassService.SetDebugOverride(targetPlayer.UserId, passKey, enabled or nil)
	GamePassService.Recheck(targetPlayer, passKey)
	return true, string.format(
		"%s %s for %s (%s).",
		passKey,
		enabled and "ON" or "OFF",
		targetPlayer.Name,
		PASS_LABELS[passKey]
	)
end

function AdminService.ForceFiesta(state)
	-- state: true = force on, false = force off, nil = clear override (use real schedule)
	FiestaEventService.DebugForceActive = state
	local isActive = FiestaEventService.IsActive()

	local plazaStage = workspace.IslaMarahuyo.Activities:FindFirstChild("PlazaStage")
	local fiestaLights = plazaStage and plazaStage:FindFirstChild("FiestaLights")
	if fiestaLights then
		for _, lantern in ipairs(fiestaLights:GetChildren()) do
			if lantern:IsA("BasePart") then
				lantern.Material = isActive and Enum.Material.Neon or Enum.Material.SmoothPlastic
				local light = lantern:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = isActive
				end
			end
		end
	end

	fiestaStatusUpdated:FireAllClients(FiestaEventService.GetStatusText(), isActive)
	return true, FiestaEventService.GetStatusText()
end

function AdminService.TeleportToZone(targetPlayer, zoneName)
	local zone = workspace.IslaMarahuyo.Zones:FindFirstChild(zoneName)
	if not zone then
		return false, "Unknown zone: " .. tostring(zoneName)
	end
	local character = targetPlayer.Character
	if not character then
		return false, "No character to teleport."
	end
	character:PivotTo(CFrame.new(zone.Position + Vector3.new(0, 6, 6)))
	return true, "Teleported to " .. zoneName .. "."
end

function AdminService.RespawnTreasure()
	local digFolder = workspace.IslaMarahuyo.Activities:FindFirstChild("TreasureDigs")
	if not digFolder then
		return false, "TreasureDigs folder not found."
	end
	for _, spot in ipairs(digFolder:GetChildren()) do
		local prompt = spot:FindFirstChildOfClass("ProximityPrompt")
		local marker = spot:FindFirstChild("XMarker")
		if prompt then
			prompt.Enabled = true
		end
		if marker then
			marker.Transparency = 0
		end
	end
	return true, "All treasure dig spots reset."
end

function AdminService.GetStats(targetPlayer)
	local profile = PlayerProfileService.Get(targetPlayer.UserId)
	return {
		Shells = CurrencyService.GetShells(targetPlayer.UserId),
		UserId = targetPlayer.UserId,
		VIP = GamePassService.Owns(targetPlayer, "KasamaVIP"),
		BoatSpeed = GamePassService.Owns(targetPlayer, "BangkeroSpeed"),
		ExtraPlot = GamePassService.Owns(targetPlayer, "ExtraCabinPlot"),
		IsleAccess = GamePassService.Owns(targetPlayer, "KalangitanIsleAccess"),
	}
end

-- Live roster for the dashboard: who is on, what they have, and how far through
-- today's tasks they are. Read-only.
function AdminService.GetRoster()
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = PlayerProfileService.Get(player.UserId)
		local tasksDone, tasksTotal = 0, 0
		local state = QuestService.GetState(player)
		if state then
			tasksTotal = #state.tasks
			for _, entry in ipairs(state.tasks) do
				if entry.done then
					tasksDone += 1
				end
			end
		end
		rows[#rows + 1] = {
			Name = player.Name,
			DisplayName = player.DisplayName,
			UserId = player.UserId,
			Shells = profile and profile.Shells or 0,
			VIP = GamePassService.Owns(player, "KasamaVIP"),
			Tasks = string.format("%d/%d", tasksDone, tasksTotal),
			Saved = profile ~= nil,
		}
	end
	table.sort(rows, function(a, b)
		return a.Shells > b.Shells
	end)
	return rows
end

-- Removes a player from this server. Deliberately the only moderation action here:
-- a mute would need a chat-filter hook and a persisted record to be meaningful, and a
-- half-built one is worse than none.
function AdminService.KickPlayer(targetPlayer, reason)
	if type(reason) ~= "string" or reason == "" then
		reason = "Removed by an island admin."
	end
	targetPlayer:Kick(string.sub(reason, 1, 200))
	return true, string.format("Kicked %s.", targetPlayer.Name)
end

return AdminService
