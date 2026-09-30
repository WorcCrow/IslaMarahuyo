-- DanceService (Sayawan)
-- Tap the same prompt in time at the plaza stage. Each session lasts SESSION_LENGTH
-- seconds; every player who joins in gets paid per move (debounced so holding/mashing
-- doesn't help), plus a group bonus if two or more people danced together.

local Workspace = game:GetService("Workspace")
local CurrencyService = require(script.Parent.CurrencyService)
local QuestService = require(script.Parent.QuestService)

local stage = Workspace.IslaMarahuyo.Activities.PlazaStage
local dancePrompt = stage:WaitForChild("DancePrompt")

local SESSION_LENGTH = 10
local MIN_MOVE_INTERVAL = 0.5
-- Rebalanced: at 4 Shells x 8 moves per 13s cycle this was the best earner in the game by
-- a wide margin (~2.5/sec), which is why nobody needed to fish or dive. Sayawan is a social
-- activity, so it still pays well per minute, just no longer better than working the sea.
local SHELLS_PER_MOVE = 2
local MAX_PAID_MOVES = 6
local GROUP_BONUS = 8
local COOLDOWN_AFTER_SESSION = 3

-- The prompt was wired correctly all along -- what was missing is that nothing ever made
-- the character actually dance, so pressing E looked like it did nothing at all. Each tap
-- now plays one of the default emote animations for a couple of beats.
local DANCE_ANIMATION_IDS = {
	"rbxassetid://507771019",
	"rbxassetid://507771955",
	"rbxassetid://507772104",
}
local MOVE_HOLD = 2.6 -- how long one move plays before it eases off

local animations = {}
for i, id in ipairs(DANCE_ANIMATION_IDS) do
	local anim = Instance.new("Animation")
	anim.Name = "Sayawan" .. i
	anim.AnimationId = id
	anim.Parent = script
	animations[i] = anim
end

local activeTrack = {} -- [player] = AnimationTrack

local function playDanceMove(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local previous = activeTrack[player]
	if previous then
		pcall(function()
			previous:Stop(0.2)
		end)
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(animations[math.random(1, #animations)])
	end)
	if not ok or not track then
		warn("[DanceService] Could not load a dance animation:", track)
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.15)
	activeTrack[player] = track

	task.delay(MOVE_HOLD, function()
		if activeTrack[player] == track then
			pcall(function()
				track:Stop(0.3)
			end)
			activeTrack[player] = nil
		end
	end)
end

local sessionActive = false
local acceptingMoves = false
local participants = {} -- [player] = { moves = n, lastMoveAt = t }

local function endSession()
	acceptingMoves = false
	local count = 0
	for _ in pairs(participants) do
		count += 1
	end

	for player, data in pairs(participants) do
		if player.Parent then
			local moves = math.min(data.moves, MAX_PAID_MOVES)
			local reward = moves * SHELLS_PER_MOVE
			if count >= 2 then
				reward += GROUP_BONUS
			end
			if reward > 0 then
				CurrencyService.AddShells(player, reward, true, "Dance")
				QuestService.Report(player, "Dance", 1)
			end
		end
	end

	participants = {}
	task.delay(COOLDOWN_AFTER_SESSION, function()
		sessionActive = false
	end)
end

dancePrompt.Triggered:Connect(function(player)
	if not sessionActive then
		sessionActive = true
		acceptingMoves = true
		participants = {}
		task.delay(SESSION_LENGTH, endSession)
	end

	if not acceptingMoves then
		return
	end

	local now = os.clock()
	local data = participants[player]
	if not data then
		data = { moves = 0, lastMoveAt = 0 }
		participants[player] = data
	end

	if now - data.lastMoveAt >= MIN_MOVE_INTERVAL then
		data.moves += 1
		data.lastMoveAt = now
		playDanceMove(player)
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	activeTrack[player] = nil
end)

print("[DanceService] Sayawan ready at Barangay Plaza stage")
