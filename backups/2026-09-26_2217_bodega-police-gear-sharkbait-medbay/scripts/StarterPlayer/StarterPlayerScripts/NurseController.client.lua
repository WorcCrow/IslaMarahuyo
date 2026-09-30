-- NurseController
-- What the NURSE sees while treating somebody. The patient's side is ReviveController;
-- this is the other half of the same twenty seconds.
--
-- The pulse ring is the whole point of the UI: it fires on the same beat the server is
-- scoring against, so a nurse who taps when the ring flashes is in the window. Without a
-- visible beat the rhythm step would be guesswork, and guessing is not a skill.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local nurseStatus = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("NurseStatus")

local TOUCH = UserInputService.TouchEnabled
local GROUND = Color3.fromRGB(28, 28, 34)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 156, 168)
local GOOD = Color3.fromRGB(110, 206, 170)
local BAD = Color3.fromRGB(236, 118, 118)
local ROSE = Color3.fromRGB(236, 118, 128)

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local gui = new("ScreenGui", {
	Name = "NurseGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- bottom centre, lifted clear of the bottom-left dive buttons and the jump button
local strip = new("Frame", {
	Name = "Strip", Size = UDim2.fromOffset(TOUCH and 300 or 268, TOUCH and 76 or 66),
	Position = UDim2.new(0.5, 0, 1, TOUCH and -186 or -150),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = GROUND, BackgroundTransparency = 0.08,
	BorderSizePixel = 0, Visible = false,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 10)}, strip)
local stroke = new("UIStroke", {Color = ROSE, Thickness = 1.5, Transparency = 0.35}, strip)

local ring = new("Frame", {
	Name = "Pulse", Size = UDim2.fromOffset(34, 34),
	Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = ROSE, BackgroundTransparency = 0.7, BorderSizePixel = 0,
}, strip)
new("UICorner", {CornerRadius = UDim.new(1, 0)}, ring)

local title = new("TextLabel", {
	Name = "Title", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(62, TOUCH and 14 or 11),
	Size = UDim2.new(1, -76, 0, 18),
	Font = Enum.Font.GothamBold, TextSize = TOUCH and 14 or 12.5,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = INK,
	TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
}, strip)

local sub = new("TextLabel", {
	Name = "Sub", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(62, TOUCH and 36 or 31),
	Size = UDim2.new(1, -76, 0, 30),
	Font = Enum.Font.Gotham, TextSize = TOUCH and 11.5 or 10.5,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = DIM, TextWrapped = true, Text = "",
}, strip)

local hideToken = 0
local function hideAfter(seconds)
	hideToken += 1
	local mine = hideToken
	task.delay(seconds, function()
		if hideToken == mine then
			strip.Visible = false
		end
	end)
end

local function flash(colour)
	ring.BackgroundColor3 = colour
	ring.BackgroundTransparency = 0.15
	ring.Size = UDim2.fromOffset(42, 42)
	TweenService:Create(ring, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 0.7,
	}):Play()
end

local PROMPT = TOUCH and "Tap the prompt" or "Press E"

nurseStatus.OnClientEvent:Connect(function(kind, message, value)
	strip.Visible = true
	hideToken += 1 -- cancel any pending hide

	if kind == "called" then
		stroke.Color = ROSE
		title.Text = "CALL OUT"
		sub.Text = message
		flash(ROSE)
	elseif kind == "beat" then
		stroke.Color = ROSE
		title.Text = string.format("PULSE %d", value or 0)
		sub.Text = PROMPT .. " when the ring flashes."
		flash(ROSE)
	elseif kind == "hit" then
		title.Text = "GOOD"
		sub.Text = string.format("%d clean pulse%s so far.", value or 0, (value or 0) == 1 and "" or "s")
		flash(GOOD)
	elseif kind == "miss" then
		title.Text = "OFF RHYTHM"
		sub.Text = "Wait for the ring. Rushing costs the fee."
		flash(BAD)
	elseif kind == "again" then
		stroke.Color = BAD
		title.Text = "LOSING THEM"
		sub.Text = message
		flash(BAD)
	elseif kind == "hold" or kind == "mask" then
		stroke.Color = ROSE
		title.Text = kind == "hold" and "CLEAR THE LUNGS" or "OXYGEN MASK"
		sub.Text = message
		flash(ROSE)
	elseif kind == "done" then
		stroke.Color = GOOD
		title.Text = "PATIENT STABLE"
		sub.Text = message
		flash(GOOD)
		hideAfter(5)
	elseif kind == "lost" then
		stroke.Color = BAD
		title.Text = "HANDED OVER"
		sub.Text = message
		flash(BAD)
		hideAfter(5)
	end
end)
