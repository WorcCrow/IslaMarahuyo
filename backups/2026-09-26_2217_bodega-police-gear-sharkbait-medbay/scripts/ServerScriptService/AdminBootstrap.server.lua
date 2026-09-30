-- AdminBootstrap
-- Every admin action is re-validated against the whitelist here, server-side, on every
-- single call -- the client only ever sees the dashboard GUI if it's already admin, but
-- that's a convenience, not the security boundary. Never trust the client's own claim.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(script.Parent.AdminConfig)
local AdminService = require(script.Parent.AdminService)
local CaveAudit = require(game:GetService("ServerStorage"):WaitForChild("CaveAudit"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local adminAction = remotes:WaitForChild("AdminAction")
local adminFeedback = remotes:WaitForChild("AdminFeedback")
local adminStatus = remotes:WaitForChild("AdminStatus")

local adminRoster = remotes:FindFirstChild("AdminRoster")
if not adminRoster then
	adminRoster = Instance.new("RemoteEvent")
	adminRoster.Name = "AdminRoster"
	adminRoster.Parent = remotes
end

local HANDLERS = {
	GrantShells = function(player, payload)
		return AdminService.GrantShells(player, payload.amount)
	end,
	SetTestVIP = function(player, payload)
		return AdminService.SetTestVIP(player, payload.enabled)
	end,
	SetTestPass = function(player, payload)
		return AdminService.SetTestPass(player, payload.passKey, payload.enabled)
	end,
	GetRoster = function(player, payload)
		local rows = AdminService.GetRoster()
		adminRoster:FireClient(player, rows)
		return true, string.format("%d player(s) on this server.", #rows)
	end,
	KickPlayer = function(player, payload)
		local target = Players:FindFirstChild(tostring(payload.targetName or ""))
		if not target then
			return false, "No player here by that name."
		end
		if target == player then
			return false, "You can't kick yourself."
		end
		if AdminConfig.IsAdmin(target.UserId) then
			return false, "That player is also an admin."
		end
		return AdminService.KickPlayer(target, payload.reason)
	end,
	ForceFiestaOn = function(player, payload)
		return AdminService.ForceFiesta(true)
	end,
	ForceFiestaOff = function(player, payload)
		return AdminService.ForceFiesta(false)
	end,
	ForceFiestaClear = function(player, payload)
		return AdminService.ForceFiesta(nil)
	end,
	TeleportToZone = function(player, payload)
		return AdminService.TeleportToZone(player, payload.zoneName)
	end,
	RespawnTreasure = function(player, payload)
		return AdminService.RespawnTreasure()
	end,
	-- Re-measures every passage in the cave against the finished terrain. The full
	-- breakdown goes to the server log because it is 20-odd lines; the toast gets the
	-- verdict, and F8 puts the same answer on the cave itself.
	AuditCave = function(player, payload)
		local audit = CaveAudit.Audit(true)
		print(CaveAudit.Report(audit))
		if audit.healthy then
			return true, string.format(
				"Cave is playable -- %d/%d passages open, every air pocket reachable.%s",
				audit.total - audit.blocked, audit.total,
				(audit.sealedToday and audit.sealedToday ~= "")
					and (" Today's cave-in: " .. audit.sealedToday .. ".") or "")
		end
		return false, string.format(
			"Cave needs attention -- %d carve fault(s), %d air pocket(s) cut off. Full report in the server log; press F8 to see where.",
			audit.carveFaults, #audit.unreachableAir)
	end,
}

adminAction.OnServerEvent:Connect(function(player, actionName, payload)
	if not AdminConfig.IsAdmin(player.UserId) then
		warn("[AdminBootstrap] Non-admin", player.Name, "attempted action:", tostring(actionName))
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end

	local handler = HANDLERS[actionName]
	if not handler then
		adminFeedback:FireClient(player, "Unknown admin action.", false)
		return
	end

	local ok, success, message = pcall(handler, player, payload)
	if not ok then
		warn("[AdminBootstrap] Action errored:", actionName, success)
		adminFeedback:FireClient(player, "That action failed -- check server logs.", false)
		return
	end

	adminFeedback:FireClient(player, tostring(message), success)
end)

Players.PlayerAdded:Connect(function(player)
	if AdminConfig.IsAdmin(player.UserId) then
		adminStatus:FireClient(player, true)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if AdminConfig.IsAdmin(player.UserId) then
		adminStatus:FireClient(player, true)
	end
end

print("[AdminBootstrap] Admin dashboard backend ready")
