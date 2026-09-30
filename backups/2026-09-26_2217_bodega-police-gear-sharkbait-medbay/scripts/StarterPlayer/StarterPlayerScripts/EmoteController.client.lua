-- EmoteController
-- The emote bar for the Sayawan Emote Pack. Opens with G on a keyboard, or the Dance icon
-- in the top bar (TopBarController) on every device -- the old floating dancer button on
-- touch screens is gone.
--
-- The bar is built for everyone and shown locked to non-owners, so the pass is
-- discoverable in play rather than only on the store page. The server ignores the request
-- either way; nothing here is trusted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local playEmote = remotes:WaitForChild("PlayEmote")
local emoteList = ReplicatedStorage:WaitForChild("EmoteList")

local gui = Instance.new("ScreenGui")
gui.Name = "EmoteGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 35
gui.Parent = playerGui

-- the bar sits low-centre, clear of the top strip and of the mobile thumbstick/jump button
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -118)
bar.Size = UDim2.new(0, 320, 0, 40)
bar.BackgroundColor3 = Color3.fromRGB(24, 30, 40)
bar.BackgroundTransparency = 0.08
bar.BorderSizePixel = 0
bar.Visible = false
bar.Parent = gui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 10)
barCorner.Parent = bar

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(70, 86, 108)
barStroke.Parent = bar

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local locked = Instance.new("TextLabel")
locked.Name = "Locked"
locked.AnchorPoint = Vector2.new(0.5, 1)
locked.Position = UDim2.new(0.5, 0, 1, -162)
locked.Size = UDim2.new(0, 320, 0, 20)
locked.BackgroundTransparency = 1
locked.Font = Enum.Font.Gotham
locked.TextSize = 12
locked.TextColor3 = Color3.fromRGB(226, 176, 110)
locked.Text = "Sayawan Emote Pack needed -- the plaza stage dance is free"
locked.Visible = false
locked.Parent = gui

local function owns()
	return player:GetAttribute("DanceEmotePack") == true
end

local buttons = {}
local entries = emoteList:GetChildren()
table.sort(entries, function(a, b)
	return a.Name < b.Name
end)

for index, cfg in ipairs(entries) do
	local key = cfg:GetAttribute("Key")
	local label = cfg:GetAttribute("Label")

	local b = Instance.new("TextButton")
	b.Name = key
	b.Size = UDim2.new(0, 50, 0, 32)
	b.BackgroundColor3 = Color3.fromRGB(38, 46, 58)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 11
	b.TextColor3 = Color3.fromRGB(232, 238, 246)
	b.Text = label
	b.LayoutOrder = index
	b.Parent = bar

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 7)
	c.Parent = b

	b.Activated:Connect(function()
		if not owns() then
			return
		end
		playEmote:FireServer(key)
	end)

	buttons[#buttons + 1] = b
end

local function refreshLockState()
	local unlocked = owns()
	for _, b in ipairs(buttons) do
		b.BackgroundColor3 = unlocked and Color3.fromRGB(38, 46, 58) or Color3.fromRGB(44, 42, 40)
		b.TextColor3 = unlocked and Color3.fromRGB(232, 238, 246) or Color3.fromRGB(140, 136, 130)
		b.AutoButtonColor = unlocked
	end
	locked.Visible = bar.Visible and not unlocked
end

local function setOpen(open)
	bar.Visible = open
	refreshLockState()
end

PanelUtil.Register("dance", {
	open = function() setOpen(true) end,
	close = function() setOpen(false) end,
	isOpen = function() return bar.Visible end,
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		PanelUtil.Toggle("dance")
	end
end)

player:GetAttributeChangedSignal("DanceEmotePack"):Connect(refreshLockState)
refreshLockState()
