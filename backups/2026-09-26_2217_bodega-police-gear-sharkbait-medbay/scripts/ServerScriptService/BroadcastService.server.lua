-- BroadcastService (Broadcast License)
-- Island music is per-listener and client-side by design, so "everyone hears my track" is
-- the one thing a client cannot do for itself. This puts a positional Sound on the
-- broadcaster's own character: it falls off with distance, so it's a thing you hear when
-- you walk past someone rather than a track imposed on the whole server.
--
-- Only ids that exist in the shared MusicConfig are accepted. Without that check a client
-- could pass any asset id and play arbitrary audio to everyone around them, which is a
-- moderation problem rather than a feature.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePassService = require(script.Parent.GamePassService)
local MusicConfig = require(ReplicatedStorage:WaitForChild("MusicConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local broadcast = remotes:FindFirstChild("BroadcastTrack") or Instance.new("RemoteEvent", remotes)
broadcast.Name = "BroadcastTrack"

local RANGE_MIN = 12
local RANGE_MAX = 70
local VOLUME = 0.55

-- id -> title, from the same config the client plays from
local allowed = {}
for _, track in ipairs(MusicConfig.Tracks) do
	allowed[track.id] = track.title
end

local function speakerFor(player, create)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local existing = hrp:FindFirstChild("BroadcastSpeaker")
	if existing or not create then
		return existing
	end
	local s = Instance.new("Sound")
	s.Name = "BroadcastSpeaker"
	s.Volume = VOLUME
	s.Looped = true
	s.RollOffMinDistance = RANGE_MIN
	s.RollOffMaxDistance = RANGE_MAX
	s.Parent = hrp
	return s
end

local function stop(player)
	local s = speakerFor(player, false)
	if s then
		s:Destroy()
	end
	player:SetAttribute("Broadcasting", nil)
end

broadcast.OnServerEvent:Connect(function(player, soundId)
	if soundId == nil then
		stop(player)
		return
	end

	if not GamePassService.Owns(player, "BroadcastLicense") then
		return
	end
	if type(soundId) ~= "string" or not allowed[soundId] then
		return -- not one of the island's own tracks
	end

	local s = speakerFor(player, true)
	if not s then
		return
	end
	if s.SoundId ~= soundId then
		s.SoundId = soundId
		s.TimePosition = 0
	end
	if not s.IsPlaying then
		s:Play()
	end
	player:SetAttribute("Broadcasting", allowed[soundId])
end)

Players.PlayerAdded:Connect(function(player)
	-- a fresh character has no speaker; don't leave the attribute claiming otherwise
	player.CharacterAdded:Connect(function()
		player:SetAttribute("Broadcasting", nil)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("Broadcasting", nil)
end)

print(string.format("[BroadcastService] ready -- %d island tracks broadcastable", #MusicConfig.Tracks))
