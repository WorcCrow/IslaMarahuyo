-- StarterPlayer/StarterPlayerScripts/BinocularController.lua
-- The binocular view. It is driven by the Binoculars tool in StarterPack: equipping the
-- tool sets the local BinocularsOn attribute (StarterPack.Binoculars.LookThrough), and this
-- follows it. B on a keyboard equips/unequips the tool; the old floating touch button is
-- gone -- on a phone the hotbar slot is the button.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local TOOL_NAME = "Binoculars"

-- Binocular Settings
local isUsingBinoculars = false
local defaultFOV = 70
local currentFOV = 15
local minFOV = 5    -- Max Zoom In
local maxFOV = 35   -- Max Zoom Out

-- Mouse / Touch Look Angles
local rotX = 0
local rotY = 0
local sensitivity = 0.25

local testCamPart = nil
local activeTags = {}
local binocularGui = nil

-- Visibility Check Timer
local lastVisibilityCheck = 0
local VISIBILITY_INTERVAL = 0.1

-- Forward declaration for function references
local toggleBinoculars

-- Create Fullscreen Binocular UI Mask
local function createBinocularOverlay()
	if binocularGui then binocularGui:Destroy() end

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	binocularGui = Instance.new("ScreenGui")
	binocularGui.Name = "BinocularOverlay"
	binocularGui.ResetOnSpawn = false
	binocularGui.IgnoreGuiInset = true
	binocularGui.DisplayOrder = 100

	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = binocularGui

	-- Center Circle Aperture (Scales to 90% of screen height)
	local circleFrame = Instance.new("Frame")
	circleFrame.Name = "BinocularLens"
	circleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	circleFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	circleFrame.Size = UDim2.new(1.5, 0, 1.5, 0)
	circleFrame.BackgroundTransparency = 1
	circleFrame.Parent = mainFrame

	local aspectConstraint = Instance.new("UIAspectRatioConstraint")
	aspectConstraint.AspectRatio = 1
	aspectConstraint.AspectType = Enum.AspectType.FitWithinMaxSize
	aspectConstraint.DominantAxis = Enum.DominantAxis.Height
	aspectConstraint.Parent = circleFrame

	-- Large Circular Outer Ring Mask
	local lensRing = Instance.new("Frame")
	lensRing.Size = UDim2.new(1, 0, 1, 0)
	lensRing.BackgroundTransparency = 1
	lensRing.Parent = circleFrame

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = lensRing

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(0, 0, 0)
	ringStroke.Thickness = 600
	ringStroke.Parent = lensRing

	-- Reticle Crosshairs
	local reticleH = Instance.new("Frame")
	reticleH.Size = UDim2.new(0, 60, 0, 2)
	reticleH.AnchorPoint = Vector2.new(0.5, 0.5)
	reticleH.Position = UDim2.new(0.5, 0, 0.5, 0)
	reticleH.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	reticleH.BorderSizePixel = 0
	reticleH.ZIndex = 5
	reticleH.Parent = circleFrame

	local reticleV = Instance.new("Frame")
	reticleV.Size = UDim2.new(0, 2, 0, 60)
	reticleV.AnchorPoint = Vector2.new(0.5, 0.5)
	reticleV.Position = UDim2.new(0.5, 0, 0.5, 0)
	reticleV.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	reticleV.BorderSizePixel = 0
	reticleV.ZIndex = 5
	reticleV.Parent = circleFrame

	-- On-Screen Mobile Exit Button
	if UserInputService.TouchEnabled then
		local closeButton = Instance.new("TextButton")
		closeButton.Name = "MobileExitBtn"
		closeButton.Size = UDim2.new(0, 50, 0, 50)
		closeButton.Position = UDim2.new(1, -70, 0, 20)
		closeButton.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
		closeButton.Text = "X"
		closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		closeButton.TextSize = 24
		closeButton.Font = Enum.Font.SourceSansBold
		closeButton.ZIndex = 10
		closeButton.Parent = mainFrame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = closeButton

		closeButton.Activated:Connect(function()
			-- putting the tool away is what turns the view off
			local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools()
			end
			toggleBinoculars(false)
		end)
	end

	binocularGui.Parent = playerGui
end

local function removeBinocularOverlay()
	if binocularGui then
		binocularGui:Destroy()
		binocularGui = nil
	end
end

-- Name Tag Management
local function createNameTag(targetPlayer)
	if activeTags[targetPlayer] then return activeTags[targetPlayer] end

	local char = targetPlayer.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return nil end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BinocularTag"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = targetPlayer.DisplayName .. "\n(@" .. targetPlayer.Name .. ")"
	textLabel.TextColor3 = Color3.fromRGB(255, 230, 0)
	textLabel.TextStrokeTransparency = 0
	textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.Parent = billboard

	billboard.Parent = head
	activeTags[targetPlayer] = billboard
	return billboard
end

local function removeNameTag(targetPlayer)
	if activeTags[targetPlayer] then
		activeTags[targetPlayer]:Destroy()
		activeTags[targetPlayer] = nil
	end
end

local function clearAllTags()
	for player, tag in pairs(activeTags) do
		if tag then tag:Destroy() end
	end
	table.clear(activeTags)
end

-- Line-of-Sight Visibility Check
local function checkPlayerVisibility()
	if not isUsingBinoculars or not testCamPart then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = {testCamPart}
	if localPlayer.Character then table.insert(ignoreList, localPlayer.Character) end
	rayParams.FilterDescendantsInstances = ignoreList

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= localPlayer and targetPlayer.Character then
			local char = targetPlayer.Character
			local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
			local humanoid = char:FindFirstChildOfClass("Humanoid")

			if head and humanoid and humanoid.Health > 0 then
				local origin = testCamPart.Position
				local destination = head.Position
				local direction = destination - origin

				local result = Workspace:Raycast(origin, direction, rayParams)

				if result and result.Instance and result.Instance:IsDescendantOf(char) then
					createNameTag(targetPlayer)
				else
					removeNameTag(targetPlayer)
				end
			else
				removeNameTag(targetPlayer)
			end
		else
			removeNameTag(targetPlayer)
		end
	end
end

-- Toggle Binoculars On/Off
toggleBinoculars = function(forceState)
	if forceState ~= nil then
		isUsingBinoculars = forceState
	else
		isUsingBinoculars = not isUsingBinoculars
	end

	if isUsingBinoculars then
		local char = localPlayer.Character
		local head = char and char:FindFirstChild("Head")
		if not head then 
			isUsingBinoculars = false
			return 
		end

		local pitch, yaw, _ = camera.CFrame:ToOrientation()
		rotX = math.deg(yaw)
		rotY = math.deg(pitch)

		testCamPart = Instance.new("Part")
		testCamPart.Name = "TestBinocularPart"
		testCamPart.Transparency = 1
		testCamPart.CanCollide = false
		testCamPart.Anchored = true
		testCamPart.CFrame = head.CFrame * CFrame.new(0, 20, 0)
		testCamPart.Parent = Workspace

		currentFOV = 15
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = currentFOV

		if not UserInputService.TouchEnabled then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end

		createBinocularOverlay()
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = defaultFOV

		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		removeBinocularOverlay()

		if testCamPart then
			testCamPart:Destroy()
			testCamPart = nil
		end

		clearAllTags()
	end
end

-- Touch Drag Panning & PC Mouse Look
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not isUsingBinoculars or not testCamPart then return end

	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		rotX = rotX - input.Delta.X * sensitivity
		rotY = math.clamp(rotY - input.Delta.Y * sensitivity, -80, 80)

		local pos = testCamPart.Position
		testCamPart.CFrame = CFrame.new(pos) 
			* CFrame.Angles(0, math.rad(rotX), 0) 
			* CFrame.Angles(math.rad(rotY), 0, 0)
	end

	-- PC Scroll Wheel Zoom
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		currentFOV = math.clamp(currentFOV - (input.Position.Z * 2), minFOV, maxFOV)
		camera.FieldOfView = currentFOV
	end
end)

-- Mobile Pinch-To-Zoom Handler
UserInputService.TouchPinch:Connect(function(touchPositions, totalScale, velocity, state, gameProcessed)
	if not isUsingBinoculars then return end

	if state == Enum.UserInputState.Change then
		-- Adjust FOV based on pinch gesture scale delta
		local zoomDelta = (1 - totalScale) * 3
		currentFOV = math.clamp(currentFOV + zoomDelta, minFOV, maxFOV)
		camera.FieldOfView = currentFOV
	end
end)

-- The tool is the switch: its LocalScript sets BinocularsOn while it is held.
localPlayer:GetAttributeChangedSignal("BinocularsOn"):Connect(function()
	toggleBinoculars(localPlayer:GetAttribute("BinocularsOn") == true)
end)

-- B on a keyboard reaches for the tool, or puts it away
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.B then
		return
	end
	local char = localPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if char:FindFirstChild(TOOL_NAME) then
		humanoid:UnequipTools()
	else
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		local tool = backpack and backpack:FindFirstChild(TOOL_NAME)
		if tool then
			humanoid:EquipTool(tool)
		end
	end
end)

Players.PlayerRemoving:Connect(removeNameTag)

local function onCharacterAdded(char)
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			if isUsingBinoculars then toggleBinoculars(false) end
		end)
	end
end

if localPlayer.Character then onCharacterAdded(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

RunService.RenderStepped:Connect(function(dt)
	if isUsingBinoculars and testCamPart then
		camera.CFrame = testCamPart.CFrame

		lastVisibilityCheck = lastVisibilityCheck + dt
		if lastVisibilityCheck >= VISIBILITY_INTERVAL then
			lastVisibilityCheck = 0
			checkPlayerVisibility()
		end
	end
end)