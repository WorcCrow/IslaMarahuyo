-- ReviveController (StarterPlayerScripts)
-- Handles multi-angle camera transitions, EKG audio acceleration, blur pulse, 
-- typewriter logs, and interactive pulse-stabilization.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ReviveGui")
local vignette = gui:WaitForChild("Vignette")
local title = gui:WaitForChild("Title")
local card = gui:WaitForChild("Card")
local status = card:WaitForChild("Status")
local countdown = card:WaitForChild("Countdown")
local barBg = card:WaitForChild("BarBg")
local barFill = barBg.BarFill
local hint = card:WaitForChild("Hint")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reviveStatus = remotes:WaitForChild("ReviveStatus")

local camera = workspace.CurrentCamera
local active = false
local total = 20
local startedAt = 0
local cameraConn

local ekgSound = Instance.new("Sound")
ekgSound.Name = "ReviveEKGSound"
ekgSound.SoundId = "rbxassetid://9114233513"
ekgSound.Volume = 0.45
ekgSound.Looped = true
ekgSound.Parent = SoundService

local pulseSuccessSound = Instance.new("Sound")
pulseSuccessSound.Name = "RevivePulseSuccess"
pulseSuccessSound.SoundId = "rbxassetid://9114223178"
pulseSuccessSound.Volume = 0.6
pulseSuccessSound.Parent = SoundService

local blurEffect = Lighting:FindFirstChild("ReviveBlur") or Instance.new("BlurEffect")
blurEffect.Name = "ReviveBlur"
blurEffect.Size = 0
blurEffect.Enabled = false
blurEffect.Parent = Lighting

local pulseButton = nil
local nextPulseAt = 0
local miniGameInputConn = nil

local function typeWrite(textLabel, fullText)
	textLabel.Text = ""
	for i = 1, #fullText do
		textLabel.Text = string.sub(fullText, 1, i)
		task.wait(0.02)
	end
end

local function setupPulseUI()
	if pulseButton then return end
	pulseButton = Instance.new("TextButton")
	pulseButton.Name = "PulseGameButton"
	pulseButton.Size = UDim2.new(0, 200, 0, 36)
	pulseButton.Position = UDim2.new(0.5, -100, 1, 15)
	pulseButton.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
	pulseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	pulseButton.TextSize = 12
	pulseButton.Font = Enum.Font.GothamBold
	pulseButton.Text = "TAP [SPACE] TO STABILIZE!"
	pulseButton.Visible = false
	pulseButton.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = pulseButton
end
setupPulseUI()

local function triggerPulseMiniGame()
	if not active then return end
	pulseButton.Visible = true
	pulseButton.BackgroundColor3 = Color3.fromRGB(0, 180, 120)

	local clicked = false
	local function handleInput()
		if clicked then return end
		clicked = true
		pulseSuccessSound:Play()
		pulseButton.BackgroundColor3 = Color3.fromRGB(50, 255, 150)
		pulseButton.Text = "PULSE STABILIZED!"

		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(20, 60, 40) }):Play()
		task.delay(0.2, function()
			TweenService:Create(card, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(15, 20, 28) }):Play()
			pulseButton.Visible = false
		end)
	end

	local btnConn
	btnConn = pulseButton.MouseButton1Click:Connect(function()
		btnConn:Disconnect()
		handleInput()
	end)

	miniGameInputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			if miniGameInputConn then miniGameInputConn:Disconnect() end
			if btnConn then btnConn:Disconnect() end
			handleInput()
		end
	end)

	task.delay(1.8, function()
		if not clicked then
			if miniGameInputConn then miniGameInputConn:Disconnect() end
			if btnConn then btnConn:Disconnect() end
			pulseButton.Visible = false
		end
	end)
end

local function fadeIn()
	gui.Enabled = true
	blurEffect.Enabled = true
	blurEffect.Size = 12

	if not ekgSound.IsPlaying then
		ekgSound.TimePosition = 0
		ekgSound.PlaybackSpeed = 0.85
		ekgSound:Play()
	end

	local t = TweenInfo.new(0.7)
	TweenService:Create(vignette, t, { BackgroundTransparency = 0.32 }):Play()
	TweenService:Create(title, t, { TextTransparency = 0 }):Play()
	TweenService:Create(card, t, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(status, t, { TextTransparency = 0 }):Play()
	TweenService:Create(countdown, t, { TextTransparency = 0 }):Play()
	TweenService:Create(hint, t, { TextTransparency = 0.15 }):Play()
	TweenService:Create(barBg, t, { BackgroundTransparency = 0.25 }):Play()
	TweenService:Create(barFill, t, { BackgroundTransparency = 0 }):Play()
end

local function fadeOut()
	local t = TweenInfo.new(0.55)
	TweenService:Create(vignette, t, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, t, { TextTransparency = 1 }):Play()
	TweenService:Create(card, t, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(status, t, { TextTransparency = 1 }):Play()
	TweenService:Create(countdown, t, { TextTransparency = 1 }):Play()
	TweenService:Create(hint, t, { TextTransparency = 1 }):Play()
	TweenService:Create(barBg, t, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barFill, t, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(blurEffect, t, { Size = 0 }):Play()

	if ekgSound.IsPlaying then ekgSound:Stop() end
	if miniGameInputConn then miniGameInputConn:Disconnect() end
	pulseButton.Visible = false

	task.delay(0.6, function()
		if not active then
			gui.Enabled = false
			blurEffect.Enabled = false
		end
	end)
end

local function takeCamera()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	camera.CameraType = Enum.CameraType.Scriptable
	cameraConn = RunService.RenderStepped:Connect(function()
		if not (hrp and hrp.Parent) then return end
		local nowTime = os.clock()
		local elapsed = nowTime - startedAt
		local progress = math.clamp(elapsed / total, 0, 1)

		local focus = hrp.Position + Vector3.new(0, 1.2, 0)
		local offset

		if progress < 0.35 then
			offset = Vector3.new(6, 2, 5)
		elseif progress < 0.70 then
			-- straight on through the open front of the scanner arch
			offset = hrp.CFrame.LookVector * 7 + Vector3.new(0, 1, 0)
		else
			local orbit = CFrame.Angles(0, math.sin(nowTime * 0.25) * 0.2, 0)
			offset = orbit:VectorToWorldSpace(Vector3.new(-3, 3, 4))
		end

		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(focus + offset, focus), 0.05)
		blurEffect.Size = 8 + math.sin(nowTime * 2.5) * 4
		ekgSound.PlaybackSpeed = 0.85 + (progress * 0.35)
	end)
end

local function releaseCamera()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

reviveStatus.OnClientEvent:Connect(function(kind, text, secondsLeft)
	if kind == "begin" then
		active = true
		total = secondsLeft or 20
		startedAt = os.clock()
		nextPulseAt = os.clock() + 4
		title.Text = "UNCONSCIOUS"
		barFill.Size = UDim2.new(0, 0, 1, 0)
		task.spawn(function() typeWrite(status, text or "") end)
		fadeIn()
		takeCamera()
	elseif kind == "stage" then
		title.Text = "REVIVING"
		task.spawn(function() typeWrite(status, text or "") end)
	elseif kind == "done" then
		active = false
		title.Text = "STABILIZED"
		status.Text = text or "You're alright."
		countdown.Text = ""
		barFill.Size = UDim2.new(1, 0, 1, 0)
		releaseCamera()
		fadeOut()
	end
end)

RunService.Heartbeat:Connect(function()
	if not active then return end
	local elapsed = os.clock() - startedAt
	local remaining = math.max(0, total - elapsed)
	local progress = math.clamp(elapsed / total, 0, 1)

	countdown.Text = string.format("%ds", math.ceil(remaining))
	barFill.Size = UDim2.new(progress, 0, 1, 0)

	if os.clock() >= nextPulseAt and progress < 0.85 then
		nextPulseAt = os.clock() + 6
		triggerPulseMiniGame()
	end
end)

player.CharacterAdded:Connect(function()
	if active then
		active = false
		releaseCamera()
		fadeOut()
	end
end)