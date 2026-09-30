-- RoleService
-- Who is doing which job on this server right now, and who covers it when nobody is.
--
-- Roles are PER-SERVER and in-memory, exactly like MarketService listings. Leaving the
-- server drops the role. That is deliberate: a role is a shift you are working, not a
-- possession you own, and persisting it would mean an absent player could hold the only
-- nurse slot on a server they are not even in.
--
-- Every role has a bot. The bot never leaves -- it just stops taking jobs the moment a
-- real player claims the role, and its nametag says so. Making the NPC physically walk
-- off would look like a bug and would strand the clinic with nobody standing in it; what
-- matters is who the WORK is routed to, which is what BotIsCovering() answers.
--
-- The title above a player's head is NOT touched here. TitleTagService owns DisplayTitle
-- and documents a deliberate priority (custom pass > Island Legend > earned cave title).
-- A free role must never silently outrank a paid pass, so the role shows as its own chip
-- on the nametag instead.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

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

local requestRole = ensureRemote("RequestRole", "RemoteEvent")
local roleUpdated = ensureRemote("RoleUpdated", "RemoteEvent")
local roleFeedback = ensureRemote("RoleFeedback", "RemoteEvent")

-- ===== the roles =====
-- `cap` is how many players may hold it at once on one server. `shift` is when the job
-- actually pays: "any" is around the clock, "day" only between DAY_START and DAY_END.
M.Roles = {
	nurse = {
		key = "nurse", label = "Nars", english = "Nurse", cap = 2, shift = "any",
		bot = "NurseFely", botLine = "Nurse Fely", post = "Barangay Health Post",
		blurb = "Revive drowned divers at the Health Post. The diver pays you.",
		tint = Color3.fromRGB(236, 118, 128), order = 1,
	},
	pulis = {
		key = "pulis", label = "Pulis", english = "Police", cap = 3, shift = "any",
		bot = "PulisBoy", botLine = "Pulis Bayani", post = "Barangay Outpost",
		blurb = "Seize illegal stalls and bring thieves in. You keep a cut.",
		tint = Color3.fromRGB(96, 150, 240), order = 2,
	},
	tindero = {
		key = "tindero", label = "Tindero", english = "Market hand", cap = 2, shift = "day",
		bot = "AlingNena", botLine = "Aling Nena", post = "Palengke",
		blurb = "Work the Palengke floor from morning to night. Paid at closing.",
		tint = Color3.fromRGB(240, 168, 96), order = 3,
	},
	mangingisda = {
		key = "mangingisda", label = "Mangingisda", english = "Fisher", cap = 4, shift = "any",
		-- posted at the Bangkaan pier, not the Looban dock: the dock is buried under
		-- terrain, and the pier is where the bangka a far-water lambat needs are moored
		bot = "MangTasyo", botLine = "Mang Tasyo", post = "Bangkaan Pier",
		blurb = "Set lambat out at sea. Whatever the sharks shake loose is anyone's.",
		tint = Color3.fromRGB(110, 206, 170), order = 4,
	},
}

-- The market shift, in island hours. One island day is 24 real minutes, so this window is
-- about 13 real minutes of work.
M.DAY_START = 6
M.DAY_END = 19

-- Long enough that you cannot flip roles to dodge a duty you just took on, short enough
-- that an honest mistake is not a punishment.
local RECLAIM_COOLDOWN = 90

local holders = {} -- [roleKey] = { [userId] = player }
local lastLeft = {} -- [userId] = { [roleKey] = os.clock() when they resigned }
for key in pairs(M.Roles) do
	holders[key] = {}
end

-- ===== queries other services use =====

function M.Get(player)
	return player and player:GetAttribute("Role") or nil
end

function M.Has(player, roleKey)
	return M.Get(player) == roleKey
end

function M.Holders(roleKey)
	local list = {}
	for _, player in pairs(holders[roleKey] or {}) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function M.CountOf(roleKey)
	return #M.Holders(roleKey)
end

-- Is this role's shift open right now? A 24h role is always open; the market only counts
-- between dawn and dusk, which is what makes it a shift rather than a title.
function M.ShiftOpen(roleKey)
	local role = M.Roles[roleKey]
	if not role or role.shift == "any" then
		return true
	end
	local hour = Lighting.ClockTime
	return hour >= M.DAY_START and hour < M.DAY_END
end

-- The one question the rest of the game actually asks: is a real person doing this job, or
-- does the bot have to? Someone off-shift does not count as covering it.
function M.BotIsCovering(roleKey)
	if not M.ShiftOpen(roleKey) then
		return true
	end
	return M.CountOf(roleKey) == 0
end

-- Picks a player to hand a job to, nearest first when a position is given so the nurse who
-- is actually standing at the scanner gets the call rather than one across the island.
function M.PickHolder(roleKey, nearPosition)
	local list = M.Holders(roleKey)
	if #list == 0 or not M.ShiftOpen(roleKey) then
		return nil
	end
	if not nearPosition then
		return list[1]
	end
	local best, bestDist
	for _, player in ipairs(list) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - nearPosition).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = player, d
			end
		end
	end
	return best or list[1]
end

function M.Snapshot()
	local rows = {}
	for key, role in pairs(M.Roles) do
		local names = {}
		for _, player in ipairs(M.Holders(key)) do
			table.insert(names, player.DisplayName)
		end
		table.insert(rows, {
			key = key, label = role.label, english = role.english, blurb = role.blurb,
			cap = role.cap, order = role.order, shift = role.shift,
			tint = role.tint, bot = role.botLine, post = role.post,
			holders = names, open = M.ShiftOpen(key),
		})
	end
	table.sort(rows, function(a, b)
		return a.order < b.order
	end)
	return rows
end

-- ===== claiming and resigning =====

local function say(player, message, ok)
	roleFeedback:FireClient(player, message, ok and true or false)
end

-- Pushed to everyone, because the board and every player's panel show the same roster.
function M.Broadcast()
	local rows = M.Snapshot()
	for _, player in ipairs(Players:GetPlayers()) do
		roleUpdated:FireClient(player, rows, player:GetAttribute("Role"))
	end
	if M.OnRosterChanged then
		M.OnRosterChanged(rows)
	end
end

function M.Resign(player, quiet)
	local current = M.Get(player)
	if not current then
		return false
	end
	holders[current][player.UserId] = nil
	player:SetAttribute("Role", nil)
	lastLeft[player.UserId] = lastLeft[player.UserId] or {}
	lastLeft[player.UserId][current] = os.clock()
	if not quiet then
		say(player, string.format("You hand back the %s job.", M.Roles[current].label), true)
		M.Broadcast()
	end
	return true
end

function M.Claim(player, roleKey)
	local role = M.Roles[roleKey]
	if not role then
		return false
	end

	if M.Get(player) == roleKey then
		say(player, string.format("You are already the %s.", role.label), false)
		return false
	end

	-- you may only work one job at a time; taking a new one resigns the old
	local previous = M.Get(player)

	local cooled = lastLeft[player.UserId] and lastLeft[player.UserId][roleKey]
	if cooled and os.clock() - cooled < RECLAIM_COOLDOWN then
		say(player, string.format("Wait %d more seconds before taking the %s job again.",
			math.ceil(RECLAIM_COOLDOWN - (os.clock() - cooled)), role.label), false)
		return false
	end

	if M.CountOf(roleKey) >= role.cap then
		say(player, string.format("The %s posts are full (%d of %d).",
			role.label, M.CountOf(roleKey), role.cap), false)
		return false
	end

	if previous then
		M.Resign(player, true)
	end

	holders[roleKey][player.UserId] = player
	player:SetAttribute("Role", roleKey)

	if M.ShiftOpen(roleKey) then
		say(player, string.format("You are the %s. %s", role.label, role.blurb), true)
	else
		say(player, string.format("You are the %s, but the shift runs %02d:00 to %02d:00 -- come back at sunrise.",
			role.label, M.DAY_START, M.DAY_END), true)
	end
	M.Broadcast()
	return true
end

function M.Init()
	requestRole.OnServerEvent:Connect(function(player, roleKey)
		if roleKey == nil or roleKey == "none" then
			M.Resign(player)
			return
		end
		if type(roleKey) ~= "string" then
			return
		end
		M.Claim(player, roleKey)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local current = M.Get(player)
		if current then
			holders[current][player.UserId] = nil
		end
		lastLeft[player.UserId] = nil
		task.defer(M.Broadcast)
	end)

	Players.PlayerAdded:Connect(function()
		task.delay(2, M.Broadcast)
	end)

	-- The market shift opening or closing changes who is covering the job even though
	-- nobody claimed or resigned anything, so the roster has to be repushed on the clock.
	task.spawn(function()
		local wasOpen = M.ShiftOpen("tindero")
		while true do
			task.wait(2)
			local open = M.ShiftOpen("tindero")
			if open ~= wasOpen then
				wasOpen = open
				M.Broadcast()
			end
		end
	end)
end

return M
