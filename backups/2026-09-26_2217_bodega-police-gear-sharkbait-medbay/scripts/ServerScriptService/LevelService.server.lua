-- LevelService
-- One level per minute played, carried across sessions in the player's profile.
--
-- Note for tuning later: this counts wall-clock time in the server, so an idle player
-- levels at exactly the same rate as someone working the abyss. If levels should mean
-- "has actually played" rather than "has been connected", flip COUNT_ONLY_ACTIVE to true --
-- that only banks time for players who have moved recently.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local levelUpdated = remotes:FindFirstChild("LevelUpdated")
if not levelUpdated then
	levelUpdated = Instance.new("RemoteEvent")
	levelUpdated.Name = "LevelUpdated"
	levelUpdated.Parent = remotes
end

local SECONDS_PER_LEVEL = 60
local TICK = 5
local COUNT_ONLY_ACTIVE = false
local IDLE_DISTANCE = 4 -- studs moved per tick to count as active

local lastPos = {} -- [userId] = Vector3

local function levelFor(seconds)
	return math.max(1, math.floor(seconds / SECONDS_PER_LEVEL) + 1)
end

local function push(player, profile)
	local seconds = profile.PlaytimeSeconds or 0
	local level = levelFor(seconds)
	local intoLevel = seconds % SECONDS_PER_LEVEL
	player:SetAttribute("Level", level)
	player:SetAttribute("PlaytimeSeconds", seconds)
	levelUpdated:FireClient(player, level, intoLevel / SECONDS_PER_LEVEL)
end

local function waitForProfile(player, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local p = PlayerProfileService.Get(player.UserId)
		if p then
			return p
		end
		task.wait(0.5)
	end
	return PlayerProfileService.Get(player.UserId)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local profile = waitForProfile(player, 15)
		if profile then
			push(player, profile)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastPos[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(TICK)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = PlayerProfileService.Get(player.UserId)
			if profile then
				local counts = true
				if COUNT_ONLY_ACTIVE then
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local previous = lastPos[player.UserId]
						counts = previous == nil or (hrp.Position - previous).Magnitude >= IDLE_DISTANCE
						lastPos[player.UserId] = hrp.Position
					else
						counts = false
					end
				end

				if counts then
					local before = levelFor(profile.PlaytimeSeconds or 0)
					profile.PlaytimeSeconds = (profile.PlaytimeSeconds or 0) + TICK
					local after = levelFor(profile.PlaytimeSeconds)
					push(player, profile)
					if after > before then
						levelUpdated:FireClient(player, after, 0, true)
					end
				end
			end
		end
	end
end)

print("[LevelService] 1 level per minute played")
