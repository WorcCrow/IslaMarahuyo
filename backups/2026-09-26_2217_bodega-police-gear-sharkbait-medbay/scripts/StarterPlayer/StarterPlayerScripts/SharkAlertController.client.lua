-- SharkAlertController (StarterPlayerScripts)
-- The danger banner and the camera sting. The shark COUNT lives in StatusHud's right-hand
-- column now, alongside air and torch, so this no longer draws a counter of its own.
-- Shows the warning banner ONLY when near or in water while the count is dangerous.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local SCARE_SOUND_ID = "rbxassetid://72251468781587"
local SHAKE_DURATION = 2
local SHAKE_MAGNITUDE = 1
local DANGER_SHARK_THRESHOLD = 100
local WATER_NEARBY_DISTANCE = 30 -- Max distance to water on land to trigger warning

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local sharkAlertUpdated = remotes:WaitForChild("SharkAlertUpdated")
local sharkScare = remotes:WaitForChild("SharkScare")

-- Sound Effect Setup
local scareSound = Instance.new("Sound")
scareSound.Name = "SharkScareSound"
scareSound.SoundId = SCARE_SOUND_ID
scareSound.Volume = 0.65
scareSound.Parent = SoundService

-- Raycast parameters for water detection
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = false

-- Automatic GUI Builder
local function buildCompactUI()
	local screenGui = playerGui:FindFirstChild("SharkAlertGui")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "SharkAlertGui"
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 10
		screenGui.Parent = playerGui
	end

	-- a counter left over from an older build of this script
	local oldCounter = screenGui:FindFirstChild("Counter")
	if oldCounter then
		oldCounter:Destroy()
	end

	-- Small Mobile-Friendly Top Warning Banner
	local warningFrame = screenGui:FindFirstChild("Warning")
	if not warningFrame then
		warningFrame = Instance.new("Frame")
		warningFrame.Name = "Warning"
		warningFrame.Size = UDim2.new(0, 180, 0, 22)
		-- sits below the Shells chip, which now occupies the top centre
		warningFrame.Position = UDim2.new(0.5, -90, 0, 44)
		warningFrame.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
		warningFrame.BackgroundTransparency = 0.2
		warningFrame.BorderSizePixel = 0
		warningFrame.Visible = false
		warningFrame.ZIndex = 5
		warningFrame.Parent = screenGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = warningFrame

		local label = Instance.new("TextLabel")
		label.Name = "WarningText"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextSize = 10
		label.Font = Enum.Font.GothamBlack
		label.ZIndex = 6
		label.Text = "\226\154\160 WARNING: DO NOT SWIM!"
		label.Parent = warningFrame
	end

	return screenGui, warningFrame
end

local gui, warningFrame = buildCompactUI()
local currentActiveSharks = 0

-- Function to check if player is swimming or standing near water
local function isNearOrInWater()
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return false end

	-- 1. Swimming or submerged
	if hum:GetState() == Enum.HumanoidStateType.Swimming or hrp.Position.Y < 1 then
		return true
	end

	-- 2. Check down and surrounding directions for nearby water
	local checkDirections = {
		Vector3.new(0, -15, 0),
		Vector3.new(WATER_NEARBY_DISTANCE, -10, 0),
		Vector3.new(-WATER_NEARBY_DISTANCE, -10, 0),
		Vector3.new(0, -10, WATER_NEARBY_DISTANCE),
		Vector3.new(0, -10, -WATER_NEARBY_DISTANCE),
	}

	for _, dir in ipairs(checkDirections) do
		local hit = workspace:Raycast(hrp.Position, dir, terrainParams)
		if hit and hit.Material == Enum.Material.Water then
			return true
		end
	end

	return false
end

-- Update UI state live every frame
RunService.RenderStepped:Connect(function()
	if not gui or not gui.Parent then
		gui, warningFrame = buildCompactUI()
	end

	-- Only show warning banner if player is actually near/in water
	warningFrame.Visible = currentActiveSharks > DANGER_SHARK_THRESHOLD and isNearOrInWater()
end)

-- Receive Shark Data from Server
sharkAlertUpdated.OnClientEvent:Connect(function(count, isWarning, totalSharks)
	currentActiveSharks = totalSharks or count or 0
end)

-- Camera Shake Effect
local shakeToken = 0
local function doShake()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	shakeToken = shakeToken + 1
	local myToken = shakeToken
	local startTime = os.clock()

	task.spawn(function()
		while os.clock() - startTime < SHAKE_DURATION and myToken == shakeToken do
			local elapsed = os.clock() - startTime
			local remaining = math.max(0, 1 - (elapsed / SHAKE_DURATION))
			local mag = SHAKE_MAGNITUDE * remaining
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * mag,
				(math.random() - 0.5) * 2 * mag,
				(math.random() - 0.5) * 2 * mag
			)
			RunService.RenderStepped:Wait()
		end
		if myToken == shakeToken then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

sharkScare.OnClientEvent:Connect(function()
	if scareSound.IsPlaying then
		scareSound:Stop()
	end
	scareSound.TimePosition = 0
	scareSound:Play()
	doShake()
end)