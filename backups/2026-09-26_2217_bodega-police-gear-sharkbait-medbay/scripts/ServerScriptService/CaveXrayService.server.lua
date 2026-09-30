-- CaveXrayService -- the server half of the admin-only cave X-ray.
--
-- Confirming a flooded tunnel is passable by swimming it is slow, and confirming
-- it by looking at it is impossible -- it is buried in rock. So the server does the
-- measuring (ServerStorage.CaveAudit) and hands an admin the result; the client
-- draws it through the walls.
--
-- SECURITY: admin status is re-checked here on every single call. The client's own
-- belief that it is an admin is a convenience for hiding UI, never the boundary --
-- same rule AdminBootstrap follows. The X-ray leaks the whole cave layout, so a
-- non-admin must never get a reply, not even an empty one that confirms the remote
-- exists in a useful way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AdminConfig = require(script.Parent:WaitForChild("AdminConfig"))
local CaveAudit = require(ServerStorage:WaitForChild("CaveAudit"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local caveXray = remotes:FindFirstChild("CaveXray")
if not caveXray then
	caveXray = Instance.new("RemoteFunction")
	caveXray.Name = "CaveXray"
	caveXray.Parent = remotes
end

-- One audit is ~5000 raycasts and ~900 voxel reads. That is fast (well under a
-- tenth of a second measured in Studio) but it is not free, so a rapid clicker
-- cannot make the server chew through it over and over.
local COOLDOWN = 2
local lastRun = {}

local function audit()
	return CaveAudit.Audit(true) -- yielding: never stall a live server's heartbeat
end

caveXray.OnServerInvoke = function(player, action, payload)
	if not AdminConfig.IsAdmin(player.UserId) then
		warn("[CaveXrayService] Non-admin", player.Name, "asked for", tostring(action))
		return nil
	end
	payload = type(payload) == "table" and payload or {}

	if action == "whoami" then
		return true
	end

	if action == "audit" then
		local now = os.clock()
		if lastRun[player.UserId] and now - lastRun[player.UserId] < COOLDOWN then
			return nil
		end
		lastRun[player.UserId] = now
		local ok, snap = pcall(function()
			return CaveAudit.Snapshot(audit())
		end)
		if not ok then
			warn("[CaveXrayService] audit failed:", snap)
			return nil
		end
		return snap
	end

	if action == "goto" then
		local pos = payload.pos
		if typeof(pos) ~= "Vector3" then
			return false
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return false
		end
		hrp.CFrame = CFrame.new(pos)
		return true
	end

	return nil
end

Players.PlayerRemoving:Connect(function(player)
	lastRun[player.UserId] = nil
end)

-- One audit at startup, written to the server log. The daily cave-in seals a
-- passage on a deferred task, so this waits for that to land first -- otherwise the
-- log would describe a cave that no longer exists a frame later.
task.delay(4, function()
	local ok, report = pcall(function()
		return CaveAudit.Report(audit())
	end)
	if ok then
		print(report)
	else
		warn("[CaveXrayService] startup audit failed:", report)
	end
end)

print("[CaveXrayService] cave X-ray ready -- admins press F8 in game")
