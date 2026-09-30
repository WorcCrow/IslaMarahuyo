-- CaveExplorationService
-- Tracks which cave chambers each diver has actually stood in, and hands out the four
-- exploration milestones on the way to mapping the whole system. Visiting is detected
-- server-side by proximity -- there is no prompt to press and nothing the client reports,
-- so the badges can't be claimed from the surface.
--
-- Real Roblox badges need IDs created on the Creator Dashboard, which can't be done from
-- Studio (same blocker as the Game Passes). So each milestone is awarded in-game and
-- persisted in the profile either way, and BADGE_IDS below is the one place to paste real
-- IDs later -- fill one in and that milestone also grants the platform badge, no other
-- change needed.

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CaveGen = require(game.ServerStorage.CaveGen)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

local POLL_SECONDS = 0.6

-- Every non-entrance chamber counts. The entrance sinks are deliberately excluded --
-- you can touch all three from open water without ever committing to the cave.
local CHAMBERS = {}
for name, n in pairs(CaveGen.Nodes) do
	if n.kind ~= "entrance" then
		table.insert(CHAMBERS, {
			name = name,
			label = n.label or name,
			x = n.x,
			y = n.y,
			z = n.z,
			-- a little wider than the room itself, so brushing through a junction counts
			radius = n.r + 6,
		})
	end
end
table.sort(CHAMBERS, function(a, b)
	return a.name < b.name
end)

local TOTAL = #CHAMBERS

local MILESTONES = {
	{ key = "q1", frac = 0.25, title = "Bagong Maninisid (Novice Diver)" },
	{ key = "q2", frac = 0.50, title = "Manlalakbay ng Yungib (Cave Wanderer)" },
	{ key = "q3", frac = 0.75, title = "Batikang Maninisid (Seasoned Diver)" },
	{ key = "q4", frac = 1.00, title = "Scuba Diving Professional" },
}

-- Paste Creator Dashboard badge IDs here to also grant real platform badges. 0 = in-game only.
local BADGE_IDS = { q1 = 0, q2 = 0, q3 = 0, q4 = 0 }

local function visitedCount(profile)
	local visited = profile.CaveVisited or {}
	local count = 0
	for _, c in ipairs(CHAMBERS) do
		if visited[c.name] then
			count += 1
		end
	end
	return count
end

local function publish(player, profile)
	local count = visitedCount(profile)
	local pct = TOTAL > 0 and (count / TOTAL) or 0
	player:SetAttribute("CaveExplored", count)
	player:SetAttribute("CaveChambersTotal", TOTAL)
	player:SetAttribute("CaveExploredPct", math.floor(pct * 100 + 0.5))

	local title = nil
	profile.CaveBadges = profile.CaveBadges or {}
	for _, m in ipairs(MILESTONES) do
		if profile.CaveBadges[m.key] then
			title = m.title
		end
	end
	player:SetAttribute("CaveTitle", title or "")
	return count, pct
end

local function checkMilestones(player, profile)
	local count, pct = publish(player, profile)
	profile.CaveBadges = profile.CaveBadges or {}

	for _, m in ipairs(MILESTONES) do
		-- the epsilon matters: 3/11 chambers is 0.2727..., and floating point should never
		-- be the reason a milestone the player has genuinely earned fails to fire
		if not profile.CaveBadges[m.key] and (pct + 1e-6) >= m.frac then
			profile.CaveBadges[m.key] = true

			local isFinal = (m.frac >= 1)
			diveFeedback:FireClient(player, "badge", string.format(
				"%s Badge earned: %s (%d of %d chambers).",
				isFinal and "The whole cave is mapped --" or "Cave explored",
				m.title, count, TOTAL), 0)

			local badgeId = BADGE_IDS[m.key]
			if badgeId and badgeId > 0 then
				task.spawn(function()
					local ok, err = pcall(function()
						BadgeService:AwardBadge(player.UserId, badgeId)
					end)
					if not ok then
						warn("[CaveExplorationService] AwardBadge failed for", m.key, err)
					end
				end)
			end
		end
	end

	publish(player, profile)
end

local function scanPlayer(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	profile.CaveVisited = profile.CaveVisited or {}
	local pos = hrp.Position
	local found = false

	for _, c in ipairs(CHAMBERS) do
		if not profile.CaveVisited[c.name] then
			local dx, dy, dz = pos.X - c.x, pos.Y - c.y, pos.Z - c.z
			if (dx * dx + dy * dy + dz * dz) <= (c.radius * c.radius) then
				profile.CaveVisited[c.name] = true
				found = true
				diveFeedback:FireClient(player, "explore", string.format(
					"New chamber found -- %s.", c.label), 0)
			end
		end
	end

	if found then
		checkMilestones(player, profile)
	end
end

local function initPlayer(player)
	task.spawn(function()
		-- the profile lands a moment after the player does
		for _ = 1, 30 do
			local profile = PlayerProfileService.Get(player.UserId)
			if profile then
				profile.CaveVisited = profile.CaveVisited or {}
				profile.CaveBadges = profile.CaveBadges or {}
				publish(player, profile)
				return
			end
			task.wait(0.5)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end
Players.PlayerAdded:Connect(initPlayer)

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(scanPlayer, player)
			if not ok then
				warn("[CaveExplorationService] scan failed:", err)
			end
		end
		task.wait(POLL_SECONDS)
	end
end)

print(string.format("[CaveExplorationService] tracking %d cave chambers, 4 milestone badges", TOTAL))
