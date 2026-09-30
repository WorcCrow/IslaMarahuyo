-- PoliceService (Pulis)
-- Arrest, jail, the community vote, and community service.
--
-- WHY A SEPARATE DATASTORE KEY: a sentence has to be written the instant it lands, even
-- if the player rage-quits in the same second. PlayerProfileService sits behind a session
-- lock and writes the whole profile on a schedule, which makes that race unsafe -- and on
-- a stale-lock edge case a sentence could be read from a stale version. The jail key is
-- its own, written with UpdateAsync the moment a sentence lands and read fresh on every
-- join, so it sidesteps the lock entirely.
--
-- WHY DAYS REMAINING, NOT A RELEASE DAY: workspace.IslandDay is PER-SERVER -- every server
-- counts up from 1 independently -- so "release on day 45" means nothing anywhere else.
-- The sentence is a countdown, and whichever server is hosting the player burns it down.
--
-- THE ONE ANTI-GRIEF RULE: the taser only fires at a player who is Wanted, and PoliceUnit
-- sets that from exactly two server-verified facts -- you just landed an axe swing on
-- somebody else's bodega, or another player reported you standing at your own open
-- illegal stall. Nobody, officer or NPC, can aim at anybody else. If that guard is ever
-- relaxed, this whole feature becomes a harassment tool.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoleService = require(script.Parent.RoleService)
local AdminConfig = require(script.Parent.AdminConfig)
local ReviveService = require(script.Parent.ReviveService)

local serviceCredit = ServerStorage:WaitForChild("ServiceCredit")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRemote(name)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local jailStatus = ensureRemote("JailStatus")
local voteUpdated = ensureRemote("VoteUpdated")
local requestVote = ensureRemote("RequestVote")
local requestJailAction = ensureRemote("RequestJailAction")
-- after JailStatus exists: PoliceUnit waits on it at load
local PoliceUnit = require(script.Parent.PoliceUnit)
local policeAssets = ServerStorage:WaitForChild("PoliceAssets")

local isla = workspace:WaitForChild("IslaMarahuyo")
local station = isla:WaitForChild("PoliceStation")
local holdingSpot = station:WaitForChild("HoldingSpot")
local deskPart = station:WaitForChild("Desk")

-- ===== tuning =====
local SENTENCE_CAUGHT = 2 -- island days for being caught at your own stall
local SENTENCE_VOTED = 2 -- island days the community can hand down
local CELL_RADIUS = 9
local PARALYSE_SECONDS = 8
local TRANQ_RANGE = 60

-- Vote thresholds. Any player may call a vote on any player -- that is the mechanic as
-- asked for -- so every scrap of protection has to live in these numbers.
local VOTE_SECONDS = 45
local QUORUM_ABSOLUTE = 5
local THRESHOLD = 0.66
local THRESHOLD_REPEAT = 0.75 -- a second jailing of the same player inside one island day
local VOTE_COOLDOWN_SERVER = 300
local VOTE_COOLDOWN_TARGET = 600

-- Community service is served in one place, doing one job, and the player is held there
-- until it is done. Each job pays off a fixed slice of the sentence, so the work scales
-- with it: a 2-day sentence is 20 Palengke restocks or 2 revives at the Health Post.
local SERVICE_TRACKS = {
	vendor = {
		-- QUICK-TEST VALUE: 0.4 clears a 2-day sentence in 5 restocks. Restore to 0.1 for the
		-- tuned 20-restock balance described above.
		credit = 0.4, job = "restock", jobs = "restocks", place = "the Palengke",
		area = isla:WaitForChild("PalengkeMarketDeck"),
		arriveOffset = Vector3.new(0, 0, -20), -- just in front of the restock crates
	},
	nurse = {
		credit = 1.0, job = "revive", jobs = "revives", place = "the Health Post",
		area = isla:WaitForChild("Activities"):WaitForChild("MedicalDock"):WaitForChild("Platform"),
		arriveOffset = Vector3.new(0, 0, -9), -- the walkway in front of the cots
	},
}
local SERVICE_AREA_MARGIN = 4
local CONFINE_WARN_EVERY = 4

-- Time now burns continuously in real time, whether the player is sitting in the cell or
-- working a service job -- the old mechanic only ever subtracted a flat whole day at each
-- island-day rollover, which never worked once community-service credit could leave a
-- fractional day behind (1.7 days left needed two full 24-minute waits to clear, not one).
local DAY_REAL_SECONDS = 24 * 60 -- matches DayNightCycle's CYCLE_MINUTES
local PASSIVE_PERSIST_EVERY = 10 -- seconds between DataStore writes of passive decay alone

-- A prisoner's clothes swap to solid orange while any sentence is active, and back on
-- release. This is a body-colour swap rather than a Shirt/Pants texture: a texture asset
-- can silently fail to load (tried first, and it did -- the torso rendered bare), while
-- setting colour directly on the character's own parts always renders, on any avatar, with
-- no dependency on an external asset. The one gap is a player wearing full layered-clothing
-- (accessory) pants or a coat -- those sit on top of the body and hide the colour under them,
-- same as they would hide a real Shirt/Pants too.
local JUMPSUIT_COLOR = Color3.fromRGB(235, 110, 20)
local SKIP_COLORING = {Head = true, HumanoidRootPart = true}

local jailStore = DataStoreService:GetDataStore("IslaMarahuyo_Jail_v1")
local sentences = {}
local paralysed = {}
local custody = {} -- [userId] = true while an NPC officer is dragging them in
local arrestPrompts = {}
local lastVoteAt = 0
local lastVoteOn = {}
local jailedToday = {}
local confineWarnedAt = {}
local lastPersistAt = {}
local originalOutfit = {} -- [userId] = {shirt = clone-or-false, pants = clone-or-false, colors = {[partName] = Color3}}
local activeVote = nil

local function jailKey(userId)
	return "Jail_" .. tostring(userId)
end

local function loadSentence(userId)
	local ok, data = pcall(function()
		return jailStore:GetAsync(jailKey(userId))
	end)
	if ok then
		return data
	end
	warn("[PoliceService] could not read the jail record for", userId, "-- treating as free")
	return nil
end

-- Fired the moment a sentence lands, before the target is even told, so a rage-quit in the
-- same second cannot outrun it. If it fails after retries the sentence is lost -- a rare
-- miss is the right trade against blocking gameplay on a DataStore round trip.
local function writeSentence(userId, record)
	task.spawn(function()
		for attempt = 1, 3 do
			local ok = pcall(function()
				if record == nil then
					-- an UpdateAsync that returns nil cancels rather than clears, which left every
					-- served sentence on file to re-jail the player on their next join
					jailStore:RemoveAsync(jailKey(userId))
				else
					jailStore:UpdateAsync(jailKey(userId), function()
						return record
					end)
				end
			end)
			if ok then
				return
			end
			task.wait(attempt * 1.5)
		end
		warn("[PoliceService] failed to persist a sentence for", userId, "-- it will not follow them")
	end)
end

-- ===== sentence state =====

local function jobsLeftFor(days, track)
	return math.max(1, math.ceil(days / track.credit - 1e-6))
end

local function clearAttributes(player)
	for _, name in ipairs({"Jailed", "OnService", "ServiceTrack", "ServiceJobsLeft", "JailDays"}) do
		player:SetAttribute(name, nil)
	end
end

-- Attributes only, no toast -- this is what the passive per-tick decay calls every 0.3s, so
-- the HUD's minutes genuinely count down in real time without spamming a message that often.
local function updateAttributes(player, s)
	if not s or s.days <= 0 then
		clearAttributes(player)
		return
	end
	local track = s.service and SERVICE_TRACKS[s.track]
	player:SetAttribute("Jailed", true)
	player:SetAttribute("OnService", track and true or nil)
	player:SetAttribute("ServiceTrack", track and s.track or nil)
	player:SetAttribute("ServiceJobsLeft", track and jobsLeftFor(s.days, track) or nil)
	player:SetAttribute("JailDays", s.days)
end

-- Swaps a sentenced player into the jumpsuit (idempotent -- safe to call on every publish
-- and every respawn) and back out again once free. Classic Shirt/Pants are removed (cached
-- as clones first) so they cannot paint over the body colour underneath.
local function dressAsPrisoner(player)
	local character = player.Character
	if not character then
		return
	end
	if not originalOutfit[player.UserId] then
		local shirt = character:FindFirstChildOfClass("Shirt")
		local pants = character:FindFirstChildOfClass("Pants")
		local colors = {}
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") and not SKIP_COLORING[part.Name] then
				colors[part.Name] = part.Color
			end
		end
		originalOutfit[player.UserId] = {
			shirt = shirt and shirt:Clone() or false,
			pants = pants and pants:Clone() or false,
			colors = colors,
		}
		if shirt then
			shirt:Destroy()
		end
		if pants then
			pants:Destroy()
		end
	end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and not SKIP_COLORING[part.Name] then
			part.Color = JUMPSUIT_COLOR
		end
	end
end

local function undressPrisoner(player)
	local saved = originalOutfit[player.UserId]
	originalOutfit[player.UserId] = nil
	local character = player.Character
	if not saved or not character then
		return
	end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and saved.colors[part.Name] then
			part.Color = saved.colors[part.Name]
		end
	end
	if saved.shirt then
		local clone = saved.shirt:Clone()
		clone.Parent = character
	end
	if saved.pants then
		local clone = saved.pants:Clone()
		clone.Parent = character
	end
end

local function publish(player, message)
	local s = sentences[player.UserId]
	updateAttributes(player, s)
	if not s or s.days <= 0 then
		jailStatus:FireClient(player, "free", "You are free to go.", 0)
		return
	end
	dressAsPrisoner(player)
	local track = s.service and SERVICE_TRACKS[s.track]
	jailStatus:FireClient(player, track and "service" or "jailed",
		message or s.reason or "Sentenced by the barangay.", s.days)
end

local function persist(userId)
	local s = sentences[userId]
	if not s or s.days <= 0 then
		sentences[userId] = nil
		writeSentence(userId, nil)
		return
	end
	writeSentence(userId, {
		days = s.days, service = s.service, track = s.track, reason = s.reason,
	})
end

local function toCell(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(holdingSpot.Position + Vector3.new(0, 3, 0))
	end
end

local function toServiceArea(player, track)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local area = track.area
		root.CFrame = CFrame.new(area.Position + track.arriveOffset + Vector3.new(0, area.Size.Y / 2 + 3, 0))
	end
end

local function inServiceArea(track, position)
	local p = track.area.CFrame:PointToObjectSpace(position)
	local half = track.area.Size / 2
	return math.abs(p.X) <= half.X + SERVICE_AREA_MARGIN
		and math.abs(p.Z) <= half.Z + SERVICE_AREA_MARGIN
		and p.Y > -8 and p.Y < 30
end

-- wherever the sentence says this player should be standing right now
local function toPlace(player)
	local s = sentences[player.UserId]
	if not s or s.days <= 0 then
		return
	end
	local track = s.service and SERVICE_TRACKS[s.track]
	if track then
		toServiceArea(player, track)
	else
		toCell(player)
	end
end

local function sentencePlayer(player, days, reason)
	PoliceUnit.ClearWanted(player)
	local existing = sentences[player.UserId]
	sentences[player.UserId] = {
		days = (existing and existing.days or 0) + days,
		service = false,
		reason = reason,
	}
	-- written BEFORE they are told, so quitting on the notification changes nothing
	persist(player.UserId)
	jailedToday[player.UserId] = workspace:GetAttribute("IslandDay") or 1
	toCell(player)
	publish(player)
end

local function release(player, why)
	sentences[player.UserId] = nil
	persist(player.UserId)
	clearAttributes(player)
	undressPrisoner(player)
	jailStatus:FireClient(player, "free", why or "Time served. You are free to go.", 0)
end

-- ===== joining =====
local function onPlayerAdded(player)
	local record = loadSentence(player.UserId)
	if not record or (record.days or 0) <= 0 then
		return
	end
	-- a record from before service had a place and a job goes back to the cell to choose one
	local onTrack = record.service and SERVICE_TRACKS[record.track] ~= nil
	sentences[player.UserId] = {
		days = record.days, service = onTrack, track = onTrack and record.track or nil,
		reason = record.reason,
	}
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		task.wait(0.6)
		if character then
			toPlace(player)
		end
		publish(player)
	end)
end

-- ===== the tranquiliser =====
-- Paralysis is shared by the player pulis's taser and the NPC officers (via PoliceUnit).
local function paralyse(target, seconds)
	paralysed[target.UserId] = os.clock() + seconds
	jailStatus:FireClient(target, "paralysed", "A pulis put you down. You cannot move.", seconds)
end

PoliceUnit.PARALYSE_SECONDS = PARALYSE_SECONDS
PoliceUnit.OnParalyse = paralyse
PoliceUnit.IsParalysed = function(target)
	local liftsAt = paralysed[target.UserId]
	return liftsAt ~= nil and os.clock() < liftsAt
end
-- an NPC officer reached a downed suspect: book them the same way a player pulis would
PoliceUnit.OnCapture = function(target, reason)
	custody[target.UserId] = nil
	if paralysed[target.UserId] then
		paralysed[target.UserId] = os.clock() -- lifts on the next tick, now that they are in custody
	end
	sentencePlayer(target, SENTENCE_CAUGHT, reason .. " Booked by a barangay officer.")
end
-- Cuffed: held still for however long the walk to the station takes, not just the
-- tranq window, and nobody else gets an arrest prompt on someone already in custody.
PoliceUnit.OnCuffed = function(target)
	custody[target.UserId] = true
	paralysed[target.UserId] = math.huge
	local prompt = arrestPrompts[target.UserId]
	if prompt then
		prompt:Destroy()
		arrestPrompts[target.UserId] = nil
	end
end
PoliceUnit.OnReleased = function(target)
	custody[target.UserId] = nil
	if paralysed[target.UserId] then
		paralysed[target.UserId] = os.clock()
	end
end

local function removeTranq(player)
	for _, where in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		local tool = where and where:FindFirstChild("Baril Pampatulog")
		if tool then
			tool:Destroy()
		end
	end
end

local function giveTranq(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	if backpack:FindFirstChild("Baril Pampatulog")
		or (player.Character and player.Character:FindFirstChild("Baril Pampatulog")) then
		return
	end

	-- the same taser the NPC officers carry, from the store model in PoliceAssets
	local tool = policeAssets.Taser:Clone()
	tool.Name = "Baril Pampatulog"
	tool.CanBeDropped = false
	tool.ToolTip = "Non-lethal. Only works on someone wanted for a crime."
	tool.Parent = backpack

	local lastShot = 0
	tool.Activated:Connect(function()
		if not RoleService.Has(player, "pulis") then
			jailStatus:FireClient(player, "info", "You are not on duty.", 0)
			return
		end
		if os.clock() - lastShot < 1.5 then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local best, bestDist
		for _, other in ipairs(Players:GetPlayers()) do
			-- the ONLY condition: PoliceUnit has them Wanted for a crime it saw happen
			if other ~= player and PoliceUnit.IsWanted(other) then
				local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if r then
					local d = (r.Position - root.Position).Magnitude
					if d <= TRANQ_RANGE and (not bestDist or d < bestDist) then
						best, bestDist = other, d
					end
				end
			end
		end
		if not best then
			jailStatus:FireClient(player, "info",
				"Nothing to shoot at. It only works on someone wanted for a crime.", 0)
			return
		end
		lastShot = os.clock()
		local target = best
		local muzzle = tool:FindFirstChild("Barrel") or tool.Handle
		PoliceUnit.FireProbe(muzzle, target.Character.HumanoidRootPart, true, function()
			if not PoliceUnit.IsWanted(target) then
				return
			end
			paralyse(target, PARALYSE_SECONDS)
			jailStatus:FireClient(player, "info",
				string.format("%s is down for %d seconds. Walk them in.", target.DisplayName, PARALYSE_SECONDS), 0)
		end)
	end)
end

local function watchRole(player)
	local function sync()
		if RoleService.Has(player, "pulis") then
			giveTranq(player)
		else
			removeTranq(player)
		end
	end
	player:GetAttributeChangedSignal("Role"):Connect(sync)
	player.CharacterAdded:Connect(function()
		task.wait(0.8)
		sync()
	end)
	task.spawn(function()
		-- the Backpack is not there the instant the player object is
		player:WaitForChild("Backpack", 10)
		sync()
	end)
end

-- ===== the arrest =====
-- A prompt that appears on a paralysed suspect. Caught in the act only: the suspect must
-- still be Wanted, i.e. inside the window since their last offence.
local function ensureArrestPrompt(target)
	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local prompt = arrestPrompts[target.UserId]
	if prompt and prompt.Parent ~= root then
		prompt:Destroy()
		prompt = nil
	end
	if prompt then
		return prompt
	end
	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Arrest"
	prompt.ObjectText = target.DisplayName
	prompt.ActionText = "Bring them in"
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(officer)
		if not RoleService.Has(officer, "pulis") then
			return
		end
		if not PoliceUnit.IsWanted(target) then
			jailStatus:FireClient(officer, "info",
				"They are not wanted any more. You can only jail somebody caught in the act.", 0)
			return
		end
		sentencePlayer(target, SENTENCE_CAUGHT,
			string.format("%s Booked by %s.", PoliceUnit.WantedReason(target), officer.DisplayName))
		jailStatus:FireClient(officer, "info",
			string.format("%s booked -- %d days.", target.DisplayName, SENTENCE_CAUGHT), 0)
	end)
	arrestPrompts[target.UserId] = prompt
	return prompt
end

-- ===== choosing your sentence =====
local deskPrompt = Instance.new("ProximityPrompt")
deskPrompt.Name = "ServiceDesk"
deskPrompt.ObjectText = "Duty desk"
deskPrompt.ActionText = "Sign up for community service"
deskPrompt.HoldDuration = 0.6
deskPrompt.MaxActivationDistance = 12
deskPrompt.RequiresLineOfSight = false
deskPrompt.Parent = deskPart

-- The desk only offers the choice; the pick comes back through RequestJailAction.
deskPrompt.Triggered:Connect(function(player)
	local s = sentences[player.UserId]
	if not s or s.days <= 0 then
		jailStatus:FireClient(player, "free", "You have nothing to work off.", 0)
		return
	end
	if s.service then
		jailStatus:FireClient(player, "service", "You are already on service. Go and be useful.", s.days)
		return
	end
	local options = {}
	for key, track in pairs(SERVICE_TRACKS) do
		options[key] = {jobs = jobsLeftFor(s.days, track), noun = track.jobs, place = track.place}
	end
	jailStatus:FireClient(player, "choose", "Pick where you work it off. You stay there until it is done.",
		s.days, options)
end)

requestJailAction.OnServerEvent:Connect(function(player, action, arg)
	local s = sentences[player.UserId]
	if not s or s.days <= 0 then
		return
	end

	if action == "service" then
		local track = SERVICE_TRACKS[arg]
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not track or s.service or not root
			or (root.Position - deskPart.Position).Magnitude > deskPrompt.MaxActivationDistance + 8 then
			return
		end
		s.service = true
		s.track = arg
		persist(player.UserId)
		toServiceArea(player, track)
		local left = jobsLeftFor(s.days, track)
		publish(player, string.format("Out you go -- unpaid. %d %s at %s and you are free.",
			left, left == 1 and track.job or track.jobs, track.place))
		return
	end

	if action == "backToCell" and s.service then
		-- service is a choice you can hand back; the cell ticks on its own clock
		s.service = false
		s.track = nil
		persist(player.UserId)
		toCell(player)
		publish(player, "Back in the cell. Time still counts down -- or take service again at the desk.")
	end
end)

-- ===== community service =====
-- The alternative to sitting: unpaid work for the other roles. It has to be meaningfully
-- faster than waiting, or players will simply log off and not come back.
-- `job` is what was just done ("restock" or "revive"); it only counts on the matching track.
serviceCredit.Event:Connect(function(player, job)
	local s = sentences[player.UserId]
	local track = s and s.service and SERVICE_TRACKS[s.track]
	if not track or track.job ~= job then
		return
	end
	-- rounded, or twenty tenths of a day leave a sliver of float behind and a 21st job
	s.days = math.max(0, math.floor((s.days - track.credit) * 1000 + 0.5) / 1000)
	persist(player.UserId)
	if s.days <= 0 then
		release(player, "Your debt to the barangay is paid. Keep your nose clean.")
		return
	end
	local left = jobsLeftFor(s.days, track)
	publish(player, string.format("%s logged -- unpaid. %d more %s to go.",
		track.job:sub(1, 1):upper() .. track.job:sub(2), left, left == 1 and track.job or track.jobs))
end)

-- ===== the community vote =====
local function finishVote()
	local vote = activeVote
	activeVote = nil
	if not vote then
		return
	end

	local yes, no = 0, 0
	for _, choice in pairs(vote.ballots) do
		if choice then yes += 1 else no += 1 end
	end
	local cast = yes + no
	local present = #Players:GetPlayers()
	local quorum = math.min(QUORUM_ABSOLUTE, math.max(1, math.ceil(present * 0.5)))

	-- a repeat jailing inside one island day needs a bigger majority, so a clique has to
	-- keep growing to keep targeting the same person
	local today = workspace:GetAttribute("IslandDay") or 1
	local needed = (jailedToday[vote.targetId] == today) and THRESHOLD_REPEAT or THRESHOLD

	local target = Players:GetPlayerByUserId(vote.targetId)
	local summary
	if not target then
		summary = "They left before the vote closed."
	elseif cast < quorum then
		summary = string.format("Not enough voted (%d of %d needed). No action.", cast, quorum)
	elseif yes / math.max(1, cast) >= needed then
		sentencePlayer(target, SENTENCE_VOTED, string.format("Voted in by the barangay (%d-%d).", yes, no))
		summary = string.format("%s is jailed -- %d to %d.", target.DisplayName, yes, no)
	else
		summary = string.format("The vote failed -- %d to %d, %d%% needed.", yes, no, math.floor(needed * 100))
	end

	for _, player in ipairs(Players:GetPlayers()) do
		voteUpdated:FireClient(player, "closed", summary, 0, 0, 0)
	end
end

requestVote.OnServerEvent:Connect(function(player, action, arg)
	if action == "call" then
		if activeVote then
			voteUpdated:FireClient(player, "info", "A vote is already running.", 0, 0, 0)
			return
		end
		if os.clock() - lastVoteAt < VOTE_COOLDOWN_SERVER then
			voteUpdated:FireClient(player, "info", string.format(
				"The barangay is still arguing about the last one. %d seconds.",
				math.ceil(VOTE_COOLDOWN_SERVER - (os.clock() - lastVoteAt))), 0, 0, 0)
			return
		end
		local target = Players:GetPlayerByUserId(tonumber(arg) or -1)
		if not target or target == player then
			return
		end
		if AdminConfig.IsAdmin(target.UserId) then
			voteUpdated:FireClient(player, "info", "You cannot vote on a barangay official.", 0, 0, 0)
			return
		end
		if os.clock() - (lastVoteOn[target.UserId] or 0) < VOTE_COOLDOWN_TARGET then
			voteUpdated:FireClient(player, "info", "That one was just voted on. Leave it.", 0, 0, 0)
			return
		end

		lastVoteAt = os.clock()
		lastVoteOn[target.UserId] = os.clock()
		activeVote = {
			targetId = target.UserId, targetName = target.DisplayName,
			calledBy = player.DisplayName, ballots = {}, endsAt = os.clock() + VOTE_SECONDS,
		}
		for _, other in ipairs(Players:GetPlayers()) do
			voteUpdated:FireClient(other, "open",
				string.format("%s wants %s jailed.", player.DisplayName, target.DisplayName),
				VOTE_SECONDS, 0, 0)
		end
		task.delay(VOTE_SECONDS, finishVote)
		return
	end

	if action == "yes" or action == "no" then
		if not activeVote or activeVote.targetId == player.UserId then
			return -- you do not get a say in your own trial
		end
		activeVote.ballots[player.UserId] = (action == "yes")
		local yes, no = 0, 0
		for _, choice in pairs(activeVote.ballots) do
			if choice then yes += 1 else no += 1 end
		end
		for _, other in ipairs(Players:GetPlayers()) do
			voteUpdated:FireClient(other, "tally", "", 0, yes, no)
		end
	end
end)

-- ===== lifecycle =====
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
	watchRole(player)
end
-- a respawn lands at the spawn point; put a sentenced player straight back, quietly
local function watchRespawn(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.6)
		toPlace(player)
		-- a fresh spawn loads the player's normal avatar, wiping any jumpsuit swap made on
		-- the previous body
		if sentences[player.UserId] and sentences[player.UserId].days > 0 then
			dressAsPrisoner(player)
		end
	end)
end
for _, player in ipairs(Players:GetPlayers()) do
	watchRespawn(player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
	watchRole(player)
	watchRespawn(player)
end)
Players.PlayerRemoving:Connect(function(player)
	persist(player.UserId)
	sentences[player.UserId] = nil
	paralysed[player.UserId] = nil
	custody[player.UserId] = nil
	arrestPrompts[player.UserId] = nil
	confineWarnedAt[player.UserId] = nil
	lastPersistAt[player.UserId] = nil
	originalOutfit[player.UserId] = nil
end)

-- ===== the tick =====
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.3 then
		return
	end
	local elapsed = accumulated
	accumulated = 0
	local now = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		local liftsAt = paralysed[player.UserId]
		if liftsAt then
			if now >= liftsAt then
				paralysed[player.UserId] = nil
				if humanoid then
					humanoid.WalkSpeed = 16
					humanoid.PlatformStand = false
				end
				local prompt = arrestPrompts[player.UserId]
				if prompt then
					prompt:Destroy()
					arrestPrompts[player.UserId] = nil
				end
			else
				if humanoid then
					humanoid.WalkSpeed = 0
					humanoid.PlatformStand = true
				end
				if not custody[player.UserId] then
					ensureArrestPrompt(player)
				end
			end
		end

		-- The cell, or the service area, holds you: wander off and you are put straight back.
		-- Not while drowned, though -- the Health Post owns the body until the revive is done.
		local s = sentences[player.UserId]
		if s and s.days > 0 then
			-- Time burns continuously in real time, in the cell or on service alike, on top of
			-- whatever job credit service earns -- see the comment by DAY_REAL_SECONDS.
			s.days = math.max(0, s.days - elapsed / DAY_REAL_SECONDS)
			if s.days <= 0 then
				release(player, s.service
					and "Your debt to the barangay is paid. Keep your nose clean."
					or "Time served. Out you go.")
			else
				updateAttributes(player, s)
				if now - (lastPersistAt[player.UserId] or 0) > PASSIVE_PERSIST_EVERY then
					lastPersistAt[player.UserId] = now
					persist(player.UserId)
				end

				if root and not ReviveService.IsReviving(player) then
					local track = s.service and SERVICE_TRACKS[s.track]
					local escaped, message
					if track then
						escaped = not inServiceArea(track, root.Position)
						local left = jobsLeftFor(s.days, track)
						message = string.format("You cannot leave %s until your service is done -- %d %s to go.",
							track.place, left, left == 1 and track.job or track.jobs)
					else
						escaped = (root.Position - holdingSpot.Position).Magnitude > CELL_RADIUS
						message = "You are not going anywhere. Sit it out, or take community service at the desk."
					end
					if escaped then
						toPlace(player)
						if now - (confineWarnedAt[player.UserId] or 0) > CONFINE_WARN_EVERY then
							confineWarnedAt[player.UserId] = now
							jailStatus:FireClient(player, track and "service" or "jailed", message, s.days)
						end
					end
				end
			end
		end
	end
end)

print(string.format(
	"[PoliceService] station open -- %d-day sentences, %ds paralysis, vote needs %d%% of at least %d voters",
	SENTENCE_CAUGHT, PARALYSE_SECONDS, math.floor(THRESHOLD * 100), QUORUM_ABSOLUTE))
