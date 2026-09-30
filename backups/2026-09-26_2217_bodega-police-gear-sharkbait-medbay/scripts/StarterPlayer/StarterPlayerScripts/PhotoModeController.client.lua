-- PhotoModeController
-- Photo mode at the Isla Ningning brag spots: a framed orbit camera around your own
-- character, a postcard border with the spot name and your name on it, and a clean
-- three-second window with every bit of UI hidden so the screenshot is the shareable
-- artifact. Roblox can't write an image file from a script, so the honest version of
-- "take a photo" is to compose the shot properly and get out of the way of the capture.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("PhotoGui")
local frame = gui:WaitForChild("Frame")
local caption = frame:WaitForChild("Bottom")
local controls = gui:WaitForChild("Controls")
local hint = gui:WaitForChild("Hint")
local flash = gui:WaitForChild("Flash")
local countdown = gui:WaitForChild("Countdown")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local photoModeToggle = remotes:WaitForChild("PhotoModeToggle")

local Lighting = game:GetService("Lighting")

local camera = workspace.CurrentCamera
local active = false
local capturing = false

--------------------------------------------------------------------------------
-- Photo FX -- the Photo FX pass.
-- Local-only grading: the effects live in Lighting on THIS client and are torn down on
-- exit, so one player's filter never recolours the island for anyone else. "Natural" is
-- always available and is what everybody without the pass gets, so the pass adds looks
-- rather than taking the plain shot away.
--------------------------------------------------------------------------------

local GRADES = {
	{ name = "Natural", free = true },
	{ name = "Cinematic Dusk", tint = Color3.fromRGB(255, 198, 150), contrast = 0.18, saturation = -0.08, brightness = -0.02, bloom = 0.9 },
	{ name = "Deep Blue", tint = Color3.fromRGB(168, 205, 255), contrast = 0.12, saturation = 0.05, brightness = -0.03, bloom = 0.5 },
	{ name = "Fiesta", tint = Color3.fromRGB(255, 226, 190), contrast = 0.10, saturation = 0.30, brightness = 0.02, bloom = 1.3 },
	{ name = "Silver Tide", tint = Color3.fromRGB(226, 232, 238), contrast = 0.24, saturation = -0.85, brightness = 0, bloom = 0.4 },
}

local gradeIndex = 1
local fxColour, fxBloom
local refreshGradeButton -- defined with the control below, called from enter()

local function clearGrade()
	if fxColour then fxColour:Destroy(); fxColour = nil end
	if fxBloom then fxBloom:Destroy(); fxBloom = nil end
end

local function applyGrade()
	clearGrade()
	local grade = GRADES[gradeIndex]
	if not grade or grade.free then
		return -- Natural: no effects at all
	end

	fxColour = Instance.new("ColorCorrectionEffect")
	fxColour.Name = "PhotoFXGrade"
	fxColour.TintColor = grade.tint
	fxColour.Contrast = grade.contrast
	fxColour.Saturation = grade.saturation
	fxColour.Brightness = grade.brightness
	fxColour.Parent = Lighting

	fxBloom = Instance.new("BloomEffect")
	fxBloom.Name = "PhotoFXBloom"
	fxBloom.Intensity = grade.bloom
	fxBloom.Size = 24
	fxBloom.Threshold = 0.9
	fxBloom.Parent = Lighting
end
local orbitAngle = 0
local orbitDistance = 15
local orbitHeight = 4
local cameraConn
local dragging = false
local lastDragX = 0

-- HUD that gets hidden so the shot is clean
local OTHER_GUIS = { "ShellsHUD", "QuestGui", "MusicHUD", "BoatGui", "ZoneInfoGui", "AdminDashboardGui", "RaceGui",
	"StatusHud", "GearHud", "ToldaGui", "SharkAlertGui", "AVisitorList", "CaveXrayGui", "EmoteGui", "Hotbar" }
local hiddenState = {}
-- the top bar icons are TopbarPlus's own gui, which has its own switch
local TopbarIcon = require(game:GetService("ReplicatedStorage"):WaitForChild("TopbarPlus"):WaitForChild("Icon"))

local function setOtherGuis(visible)
	for _, name in ipairs(OTHER_GUIS) do
		local other = playerGui:FindFirstChild(name)
		if other and other:IsA("ScreenGui") then
			if visible then
				if hiddenState[name] ~= nil then
					other.Enabled = hiddenState[name]
				end
			else
				hiddenState[name] = other.Enabled
				other.Enabled = false
			end
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, visible)
		-- the custom Hotbar replaces the built-in backpack; "All" would bring it back
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	pcall(TopbarIcon.setTopbarEnabled, visible)
end

local function updateCamera()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local focus = hrp.Position + Vector3.new(0, 1.6, 0)
	local offset = Vector3.new(
		math.sin(orbitAngle) * orbitDistance,
		orbitHeight,
		math.cos(orbitAngle) * orbitDistance
	)
	camera.CFrame = CFrame.lookAt(focus + offset, focus)
end

local function enter(info)
	if active then
		return
	end
	active = true

	frame.Bottom.SpotName.Text = info.spotName or "Isla Ningning"
	frame.Bottom.Blurb.Text = (info.blurb or "") .. "   -   Isla Ningning"
	frame.Bottom.Stamp.Text = string.format("ISLA MARAHUYO\n%s", player.DisplayName)

	orbitAngle = math.rad((info.facing or 0) + 180)
	orbitDistance = 15
	orbitHeight = 4

	setOtherGuis(false)
	gui.Enabled = true
	controls.Visible = true
	hint.Visible = true
	UserInputService.ModalEnabled = true

	gradeIndex = 1
	applyGrade()
	refreshGradeButton()

	camera.CameraType = Enum.CameraType.Scriptable
	cameraConn = RunService.RenderStepped:Connect(updateCamera)
end

local function exit()
	if not active then
		return
	end
	active = false
	capturing = false
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	gui.Enabled = false
	UserInputService.ModalEnabled = false
	setOtherGuis(true)
	clearGrade() -- never leave the island tinted after the shot
end

local function capture()
	if capturing or not active then
		return
	end
	capturing = true
	controls.Visible = false
	hint.Visible = false

	for n = 3, 1, -1 do
		countdown.Text = tostring(n)
		countdown.TextTransparency = 0
		TweenService:Create(countdown, TweenInfo.new(0.75), { TextTransparency = 1 }):Play()
		task.wait(0.85)
	end

	-- shutter flash
	flash.BackgroundTransparency = 0.15
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()

	-- clean frame: nothing on screen but the postcard border and the view
	task.wait(3)

	if active then
		controls.Visible = true
		hint.Visible = true
	end
	capturing = false
end

-- ===== Photo FX control =====
-- Added here rather than in the static GUI so the button ships with the feature.
local gradeButton = controls:FindFirstChild("Grade")
if not gradeButton then
	gradeButton = Instance.new("TextButton")
	gradeButton.Name = "Grade"
	gradeButton.Size = controls.Snap.Size
	gradeButton.BackgroundColor3 = Color3.fromRGB(46, 52, 66)
	gradeButton.BorderSizePixel = 0
	gradeButton.Font = Enum.Font.GothamBold
	gradeButton.TextSize = 13
	gradeButton.TextColor3 = Color3.fromRGB(236, 232, 224)
	gradeButton.LayoutOrder = 10
	gradeButton.Text = "Natural"
	gradeButton.Parent = controls
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 7)
	c.Parent = gradeButton
end

refreshGradeButton = function()
	local owns = player:GetAttribute("PhotoFX") == true
	gradeButton.Text = GRADES[gradeIndex].name
	gradeButton.BackgroundColor3 = owns and Color3.fromRGB(46, 52, 66) or Color3.fromRGB(58, 56, 52)
	gradeButton.TextColor3 = owns and Color3.fromRGB(236, 232, 224) or Color3.fromRGB(150, 146, 140)
end

gradeButton.Activated:Connect(function()
	if player:GetAttribute("PhotoFX") ~= true then
		gradeButton.Text = "Photo FX pass"
		task.delay(1.6, refreshGradeButton)
		return
	end
	gradeIndex = (gradeIndex % #GRADES) + 1
	applyGrade()
	refreshGradeButton()
end)

player:GetAttributeChangedSignal("PhotoFX"):Connect(refreshGradeButton)
refreshGradeButton()

-- ===== controls =====
controls.RotL.Activated:Connect(function() orbitAngle -= math.rad(22) end)
controls.RotR.Activated:Connect(function() orbitAngle += math.rad(22) end)
controls.ZoomIn.Activated:Connect(function() orbitDistance = math.max(7, orbitDistance - 3) end)
controls.ZoomOut.Activated:Connect(function() orbitDistance = math.min(38, orbitDistance + 3) end)
controls.Snap.Activated:Connect(function() task.spawn(capture) end)
controls.Exit.Activated:Connect(exit)

-- drag to orbit
UserInputService.InputBegan:Connect(function(input, processed)
	if not active or processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		lastDragX = input.Position.X
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if not (active and dragging) then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		orbitAngle += (input.Position.X - lastDragX) * 0.006
		lastDragX = input.Position.X
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

photoModeToggle.OnClientEvent:Connect(function(kind, info)
	if kind == "enter" then
		enter(info or {})
	elseif kind == "exit" then
		exit()
	end
end)

-- never leave the camera or HUD stuck
player.CharacterAdded:Connect(exit)
