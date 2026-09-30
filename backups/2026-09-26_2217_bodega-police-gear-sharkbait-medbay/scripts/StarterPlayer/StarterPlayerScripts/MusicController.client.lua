-- MusicController
-- The island's music player. Runs entirely on the client (music is per-listener, and a
-- server-driven Sound would fight with everyone's volume), reading its whole playlist
-- from ReplicatedStorage.MusicConfig -- see that file for how to swap tracks.
--
-- Picks a playlist by context: day music on the island, night music after dark, and a
-- separate deep track inside the cave system. Full track list, skip, pause and mute are
-- in the music panel, which opens from the top bar's menu (TopBarController) -- built off
-- what's really playing rather than a static menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MusicConfig = require(ReplicatedStorage:WaitForChild("MusicConfig"))
local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MusicHUD")
local panel = gui:WaitForChild("Panel")
local nowPlayingLabel = panel:WaitForChild("NowPlaying")
local list = panel:WaitForChild("List")
local controls = panel:WaitForChild("Controls")
local playPauseBtn = controls:WaitForChild("PlayPause")
local skipBtn = controls:WaitForChild("Skip")
local muteBtn = controls:WaitForChild("Mute")

local NOTE = "\240\159\142\181"
-- declared up here because the track rows below fire it; declared after them it would be
-- a nil global inside their click handlers
local broadcastRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BroadcastTrack")

-- one Sound, reused for every track, parented to SoundService so it's 2D (not positional)
local sound = Instance.new("Sound")
sound.Name = "IslandMusic"
sound.Volume = MusicConfig.Volume
sound.Looped = false
sound.Parent = SoundService

local currentTrack = nil
local paused = false
local muted = false
local repeatOne = false -- Audio Customizer
local broadcasting = false -- Broadcast License
local queue = {}
local queueIndex = 0
local currentMood = nil
local rowByTitle = {}

local function moodNow()
	-- inside the cave system the player is below the seabed; NearWater alone isn't enough
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp.Position.Y < -8 then
		return "deep"
	end
	local ct = Lighting.ClockTime
	if ct >= 19 or ct <= 5 then
		return "night"
	end
	return "day"
end

local function buildQueue(mood)
	local tracks = MusicConfig.ByMood(mood)
	local copy = table.clone(tracks)
	if MusicConfig.Shuffle then
		for i = #copy, 2, -1 do
			local j = math.random(1, i)
			copy[i], copy[j] = copy[j], copy[i]
		end
	end
	queue = copy
	queueIndex = 0
	currentMood = mood
end

local function highlight(track)
	for title, row in pairs(rowByTitle) do
		local isCurrent = track ~= nil and title == track.title
		row.BackgroundTransparency = isCurrent and 0.15 or 1
		row.TextColor3 = isCurrent and Color3.fromRGB(235, 245, 235) or Color3.fromRGB(160, 180, 168)
	end
end

local function setNowPlaying(track)
	currentTrack = track
	if track then
		nowPlayingLabel.Text = string.format("%s  Now playing: %s\n%s", NOTE, track.title, track.artist)
	else
		nowPlayingLabel.Text = "Paused"
	end
	highlight(track)
end

local function playTrack(track)
	if not track then
		return
	end
	sound:Stop()
	sound.SoundId = track.id
	sound.TimePosition = 0
	sound.Volume = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(1.5), { Volume = muted and 0 or MusicConfig.Volume }):Play()
	setNowPlaying(track)
end

local function playNext()
	if paused then
		return
	end
	local mood = moodNow()
	if mood ~= currentMood or queueIndex >= #queue then
		buildQueue(mood)
	end
	queueIndex += 1
	if queueIndex > #queue then
		queueIndex = 1
	end
	playTrack(queue[queueIndex])
end

-- build the visible track list from the same config the player reads
for i, track in ipairs(MusicConfig.Tracks) do
	local row = Instance.new("TextButton")
	row.Name = "Track" .. i
	row.LayoutOrder = i
	row.Size = UDim2.new(1, -6, 0, 30)
	row.BackgroundColor3 = Color3.fromRGB(30, 46, 41)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Font = Enum.Font.Gotham
	row.TextSize = 11.5
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = Color3.fromRGB(160, 180, 168)
	row.Text = string.format("  %d. %s   (%s)", i, track.title, track.mood)
	row.Parent = list
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = row
	rowByTitle[track.title] = row

	row.Activated:Connect(function()
		paused = false
		playPauseBtn.Text = "Pause"
		playTrack(track)
		if broadcasting then
			broadcastRemote:FireServer(track.id)
		end
	end)
end

-- controls
panel.Visible = false
PanelUtil.Register("music", {
	open = function() panel.Visible = true end,
	close = function() panel.Visible = false end,
	isOpen = function() return panel.Visible end,
})
PanelUtil.AddCloseButton(panel, "music")

playPauseBtn.Activated:Connect(function()
	paused = not paused
	playPauseBtn.Text = paused and "Play" or "Pause"
	if paused then
		sound:Pause()
		setNowPlaying(nil)
	else
		if sound.SoundId ~= "" and sound.TimePosition > 0 then
			sound:Resume()
			setNowPlaying(queue[queueIndex])
		else
			playNext()
		end
	end
end)

skipBtn.Activated:Connect(function()
	paused = false
	playPauseBtn.Text = "Pause"
	playNext()
end)

muteBtn.Activated:Connect(function()
	muted = not muted
	muteBtn.Text = muted and "Unmute" or "Mute"
	sound.Volume = muted and 0 or MusicConfig.Volume
end)

--------------------------------------------------------------------------------
-- Audio Customizer and Broadcast License.
-- Picking a track is free for everyone; what Audio Customizer adds is KEEPING it --
-- without it the playlist moves on by context (day/night/cave) as soon as the track ends.
-- Broadcast License is the part a client genuinely cannot do alone, since island music is
-- per-listener: the server puts a positional speaker on your character so people nearby
-- hear what you're playing.
--------------------------------------------------------------------------------

local function styleExtra(button, on, owned)
	button.BackgroundColor3 = owned and (on and Color3.fromRGB(46, 122, 96) or Color3.fromRGB(38, 56, 50))
		or Color3.fromRGB(52, 50, 46)
	button.TextColor3 = owned and Color3.fromRGB(226, 244, 236) or Color3.fromRGB(146, 142, 136)
	button.AutoButtonColor = owned
end

local function makeExtraButton(name, order)
	local b = controls:FindFirstChild(name)
	if not b then
		b = Instance.new("TextButton")
		b.Name = name
		b.Size = muteBtn.Size
		b.BorderSizePixel = 0
		b.Font = muteBtn.Font
		b.TextSize = muteBtn.TextSize
		b.LayoutOrder = order
		b.Parent = controls
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = b
	end
	return b
end

local repeatBtn = makeExtraButton("Repeat", 10)
local broadcastBtn = makeExtraButton("Broadcast", 11)

local function refreshExtras()
	local ownsRepeat = player:GetAttribute("AudioCustomizer") == true
	local ownsCast = player:GetAttribute("BroadcastLicense") == true
	repeatBtn.Text = ownsRepeat and (repeatOne and "Repeat: on" or "Repeat") or "Repeat \226\128\162"
	broadcastBtn.Text = ownsCast and (broadcasting and "Stop cast" or "Broadcast") or "Broadcast \226\128\162"
	styleExtra(repeatBtn, repeatOne, ownsRepeat)
	styleExtra(broadcastBtn, broadcasting, ownsCast)
end

repeatBtn.Activated:Connect(function()
	if player:GetAttribute("AudioCustomizer") ~= true then
		return
	end
	repeatOne = not repeatOne
	refreshExtras()
end)

broadcastBtn.Activated:Connect(function()
	if player:GetAttribute("BroadcastLicense") ~= true then
		return
	end
	broadcasting = not broadcasting
	if broadcasting and currentTrack then
		broadcastRemote:FireServer(currentTrack.id)
	else
		broadcasting = false
		broadcastRemote:FireServer(nil)
	end
	refreshExtras()
end)

player:GetAttributeChangedSignal("AudioCustomizer"):Connect(refreshExtras)
player:GetAttributeChangedSignal("BroadcastLicense"):Connect(refreshExtras)
refreshExtras()

-- keep the speaker in step with whatever is actually playing
local function syncBroadcast()
	if broadcasting and currentTrack then
		broadcastRemote:FireServer(currentTrack.id)
	end
end

-- advance when a track finishes, after a short breath of quiet
sound.Ended:Connect(function()
	task.wait(MusicConfig.GapSeconds)
	if repeatOne and currentTrack and player:GetAttribute("AudioCustomizer") == true then
		playTrack(currentTrack)
	else
		playNext()
	end
	syncBroadcast()
end)

-- start, and re-check context periodically so day/night/cave changes take effect at the
-- next track boundary rather than cutting the current one off mid-phrase
task.spawn(function()
	task.wait(2)
	playNext()
	while true do
		task.wait(5)
		if not paused and not sound.IsPlaying and sound.TimePosition == 0 then
			playNext()
		end
	end
end)
