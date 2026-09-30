-- EmoteService (Sayawan Emote Pack)
-- The Sayawan stage dance is free and stays free -- this is the pass's addition: six
-- emotes you can play anywhere on the island rather than only on the plaza stage.
--
-- Played on the SERVER so everyone around you sees it, and gated here rather than on the
-- client, because a client-side gate on a paid feature is not a gate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePassService = require(script.Parent.GamePassService)

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

local playEmote = ensureRemote("PlayEmote", "RemoteEvent")

-- Published to the client so the wheel and the server can never disagree about the list.
local EMOTES = {
	{ key = "wave", label = "Wave", id = "rbxassetid://507770239", hold = 2.4 },
	{ key = "point", label = "Point", id = "rbxassetid://507770453", hold = 2.2 },
	{ key = "cheer", label = "Cheer", id = "rbxassetid://507770677", hold = 2.6 },
	{ key = "laugh", label = "Laugh", id = "rbxassetid://507770818", hold = 2.6 },
	{ key = "sayaw1", label = "Sayaw", id = "rbxassetid://507771955", hold = 3.4 },
	{ key = "sayaw2", label = "Sayaw II", id = "rbxassetid://507772104", hold = 3.4 },
}

do
	local existing = ReplicatedStorage:FindFirstChild("EmoteList")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "EmoteList"
	for index, emote in ipairs(EMOTES) do
		local cfg = Instance.new("Configuration")
		cfg.Name = string.format("%02d_%s", index, emote.key)
		cfg:SetAttribute("Key", emote.key)
		cfg:SetAttribute("Label", emote.label)
		cfg.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local byKey = {}
local animations = {}
for _, emote in ipairs(EMOTES) do
	byKey[emote.key] = emote
	local anim = Instance.new("Animation")
	anim.Name = emote.key
	anim.AnimationId = emote.id
	anim.Parent = script
	animations[emote.key] = anim
end

local COOLDOWN = 0.6
local lastAt = {}
local activeTrack = {}

local function stopFor(player)
	local track = activeTrack[player]
	if track then
		pcall(function()
			track:Stop(0.25)
		end)
		activeTrack[player] = nil
	end
end

playEmote.OnServerEvent:Connect(function(player, key)
	if type(key) ~= "string" then
		return
	end

	if not GamePassService.Owns(player, "DanceEmotes") then
		return -- the client shows it locked; this is the real gate
	end

	local emote = byKey[key]
	if not emote then
		return
	end

	local now = os.clock()
	if lastAt[player] and now - lastAt[player] < COOLDOWN then
		return
	end
	lastAt[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	-- don't fire an emote out of a dive or a revive; it reads as a bug rather than a flourish
	if humanoid:GetState() == Enum.HumanoidStateType.Swimming or player:GetAttribute("Reviving") then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	stopFor(player)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animations[key])
	end)
	if not ok or not track then
		warn("[EmoteService] could not load emote", key, track)
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.15)
	activeTrack[player] = track

	task.delay(emote.hold, function()
		if activeTrack[player] == track then
			stopFor(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastAt[player] = nil
	activeTrack[player] = nil
end)

print(string.format("[EmoteService] %d pass emotes ready (playable anywhere)", #EMOTES))
