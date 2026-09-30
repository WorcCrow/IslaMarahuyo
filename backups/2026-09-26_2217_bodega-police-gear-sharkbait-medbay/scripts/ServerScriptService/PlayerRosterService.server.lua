-- PlayerRosterService
-- Feeds the "who's on this server" panel: one row per player with Shells, level, revives,
-- Shells donated and their cave expertise title. Everything here is read from the server's
-- own profiles and pushed down -- the client never reports its own numbers, so the panel
-- can't be used to fake a balance or a badge.
--
-- Pushed on a slow timer plus immediately on join/leave, rather than on every Shells change:
-- this is a glanceable roster, not a live ticker, and a per-transaction push would be a lot
-- of traffic for a panel that is closed most of the time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function ensureRemote(name, className)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local rosterUpdated = ensureRemote("RosterUpdated", "RemoteEvent")
local requestRoster = ensureRemote("RequestRoster", "RemoteFunction")

local PUSH_SECONDS = 4

local function buildRoster()
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = PlayerProfileService.Get(player.UserId)
		table.insert(rows, {
			userId = player.UserId,
			name = player.DisplayName,
			shells = profile and (profile.Shells or 0) or 0,
			level = player:GetAttribute("Level") or 1,
			revives = profile and (profile.Revives or 0) or 0,
			donated = profile and (profile.Donated or 0) or 0,
			-- cave expertise, set by CaveExplorationService as milestones are earned
			title = player:GetAttribute("CaveTitle") or "",
			explored = player:GetAttribute("CaveExploredPct") or 0,
		})
	end

	table.sort(rows, function(a, b)
		if a.shells ~= b.shells then
			return a.shells > b.shells
		end
		return a.name < b.name
	end)

	return rows
end

local function push()
	local rows = buildRoster()
	rosterUpdated:FireAllClients(rows)
end

requestRoster.OnServerInvoke = function()
	return buildRoster()
end

Players.PlayerAdded:Connect(function()
	task.delay(2, push) -- give the profile a moment to land
end)
Players.PlayerRemoving:Connect(function()
	task.defer(push)
end)

task.spawn(function()
	while true do
		local ok, err = pcall(push)
		if not ok then
			warn("[PlayerRosterService] push failed:", err)
		end
		task.wait(PUSH_SECONDS)
	end
end)

print("[PlayerRosterService] server roster online")
