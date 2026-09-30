-- MobileUIController
-- Every panel in this game (shop, boat hire, admin dashboard, quest log, the breath meter...)
-- was sized in fixed desktop pixels -- a 480px admin panel or a 400px boat hire card simply
-- doesn't fit inside a ~700px phone viewport once the on-screen thumbstick/jump buttons are
-- accounted for, so on mobile those panels ran off the visible screen with no way to reach
-- the Close button. This scales each one down to fit whatever screen it's actually shown on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ScaleMath = require(ReplicatedStorage:WaitForChild("MobileScaleMath"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- [ScreenGui name] = { panel Frame names inside it to manage }
local TARGETS = {
	ShopUI = { "Panel", "OddsPanel" },
	TutorialGui = { "Panel" },
	BoatGui = { "HirePanel" },
	AdminDashboardGui = { "Panel" },
	AVisitorList = { "VisitorPanel" },
	CaveXrayGui = { "Panel" },
	QuestGui = { "Panel" },
	RaceGui = { "Panel" },
	ZoneInfoGui = { "Panel" },
	ReviveGui = { "Card" },
	MusicHUD = { "Panel" },
	PhotoGui = { "Controls" },
}

local scales = {}

local function scaleFor(frame)
	local s = scales[frame]
	if not s then
		s = frame:FindFirstChildOfClass("UIScale")
		if not s then
			s = Instance.new("UIScale")
			s.Name = "MobileFit"
			s.Parent = frame
		end
		scales[frame] = s
	end
	return s
end

local function nativeSize(frame)
	local s = scaleFor(frame)
	local abs = frame.AbsoluteSize
	if s.Scale > 0 then
		return Vector2.new(abs.X / s.Scale, abs.Y / s.Scale)
	end
	return abs
end

local function rescaleFrame(frame)
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local native = nativeSize(frame)
	scaleFor(frame).Scale = ScaleMath.fit(viewport, native, touch)
end

local function rescaleAll()
	for guiName, panelNames in pairs(TARGETS) do
		local screenGui = playerGui:FindFirstChild(guiName)
		if screenGui then
			for _, panelName in ipairs(panelNames) do
				local frame = screenGui:FindFirstChild(panelName)
				if frame then
					rescaleFrame(frame)
				end
			end
		end
	end
end

if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleAll)
end
UserInputService.LastInputTypeChanged:Connect(function()
	task.defer(rescaleAll)
end)

-- ScreenGuis/panels stream in slightly staggered at spawn, and AutomaticSize / ScrollingFrame
-- content can settle a frame late, so re-check for a few seconds after join rather than
-- trusting a single pass.
task.spawn(function()
	for _ = 1, 14 do
		rescaleAll()
		task.wait(0.5)
	end
end)