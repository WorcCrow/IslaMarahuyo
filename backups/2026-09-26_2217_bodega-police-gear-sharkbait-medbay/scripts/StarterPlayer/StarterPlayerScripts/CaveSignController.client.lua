-- CaveSignController
-- The writing panel for the cave slates. Opens when the server says the player triggered
-- a sign prompt, sends one line back, and closes.
--
-- Mouse lock is freed while the panel is open for the same reason the shop needed it:
-- with shift lock on the cursor is pinned to the middle of the screen, so the text box and
-- the buttons are visible but literally unclickable.
--
-- It is done through UserInputService.MouseBehavior, NOT Player.DevEnableMouseLock. The
-- latter cannot be assigned from a LocalScript at all -- it throws "lacking capability
-- RobloxScript" -- and because that assignment sat one line above `gui.Enabled = true`,
-- it killed openPanel every single time and the writing panel never appeared. That is what
-- "you can't write on the signs" actually was. Every mouse-lock call here is wrapped so a
-- future platform change can never take the panel down with it again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local signPrompt = remotes:WaitForChild("CaveSignPrompt")
local signWrite = remotes:WaitForChild("CaveSignWrite")

local MAX_LENGTH = 70

local openNode = nil

local function setMouseFree(free)
	pcall(function()
		UserInputService.MouseBehavior = free
			and Enum.MouseBehavior.Default
			or Enum.MouseBehavior.LockCenter
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "CaveSignGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.45)
panel.Size = UDim2.fromScale(0.46, 0.34)
panel.BackgroundColor3 = Color3.fromRGB(38, 28, 19)
panel.BorderSizePixel = 0
panel.Parent = gui

local sizeClamp = Instance.new("UISizeConstraint")
sizeClamp.MinSize = Vector2.new(300, 200)
sizeClamp.MaxSize = Vector2.new(470, 290)
sizeClamp.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 92, 58)
stroke.Thickness = 2
stroke.Parent = panel

local heading = Instance.new("TextLabel")
heading.Name = "Heading"
heading.Size = UDim2.new(1, -24, 0, 30)
heading.Position = UDim2.new(0, 12, 0, 12)
heading.BackgroundTransparency = 1
heading.Font = Enum.Font.GothamBold
heading.TextSize = 19
heading.TextXAlignment = Enum.TextXAlignment.Left
heading.TextColor3 = Color3.fromRGB(240, 190, 120)
heading.TextTruncate = Enum.TextTruncate.AtEnd
heading.Text = "Write on the slate"
heading.Parent = panel

local blurb = Instance.new("TextLabel")
blurb.Name = "Blurb"
blurb.Size = UDim2.new(1, -24, 0, 32)
blurb.Position = UDim2.new(0, 12, 0, 42)
blurb.BackgroundTransparency = 1
blurb.Font = Enum.Font.Gotham
blurb.TextSize = 14
blurb.TextWrapped = true
blurb.TextXAlignment = Enum.TextXAlignment.Left
blurb.TextYAlignment = Enum.TextYAlignment.Top
blurb.TextColor3 = Color3.fromRGB(196, 178, 152)
blurb.Text = "Every diver who comes through reads this, and your name goes under it."
blurb.Parent = panel

local box = Instance.new("TextBox")
box.Name = "Entry"
box.Size = UDim2.new(1, -24, 0, 58)
box.Position = UDim2.new(0, 12, 0, 80)
box.BackgroundColor3 = Color3.fromRGB(26, 20, 14)
box.BorderSizePixel = 0
box.ClearTextOnFocus = false
-- single line, so Enter means "post" rather than inserting a newline
box.MultiLine = false
box.TextWrapped = true
box.Font = Enum.Font.GothamMedium
box.TextSize = 16
box.TextColor3 = Color3.fromRGB(240, 232, 216)
box.PlaceholderText = "e.g. left tunnel = air, right = dead end"
box.PlaceholderColor3 = Color3.fromRGB(126, 112, 94)
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextYAlignment = Enum.TextYAlignment.Top
box.Text = ""
box.Parent = panel

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 6)
boxCorner.Parent = box

local boxPad = Instance.new("UIPadding")
boxPad.PaddingLeft = UDim.new(0, 8)
boxPad.PaddingTop = UDim.new(0, 6)
boxPad.PaddingRight = UDim.new(0, 8)
boxPad.Parent = box

local counter = Instance.new("TextLabel")
counter.Name = "Counter"
counter.Size = UDim2.new(1, -24, 0, 18)
counter.Position = UDim2.new(0, 12, 0, 142)
counter.BackgroundTransparency = 1
counter.Font = Enum.Font.Gotham
counter.TextSize = 13
counter.TextXAlignment = Enum.TextXAlignment.Right
counter.TextColor3 = Color3.fromRGB(150, 134, 112)
counter.Text = "0/" .. MAX_LENGTH
counter.Parent = panel

local function makeButton(name, text, xScale, bg, fg)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(0.44, 0, 0, 38)
	b.Position = UDim2.new(xScale, 0, 1, -50)
	b.AnchorPoint = Vector2.new(xScale, 0)
	b.BackgroundColor3 = bg
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = fg
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = panel

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 7)
	c.Parent = b
	return b
end

-- 0.04 / 0.96 with matching anchor points keeps both buttons inside the padding at any width
local cancelButton = makeButton("Cancel", "Cancel", 0.04, Color3.fromRGB(62, 48, 34), Color3.fromRGB(220, 206, 186))
local postButton = makeButton("Post", "Post it", 0.96, Color3.fromRGB(190, 122, 54), Color3.fromRGB(28, 20, 12))

local function closePanel()
	openNode = nil
	gui.Enabled = false
	box.Text = ""
	-- hand the cursor back to the camera script, which re-applies shift lock if it was on
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
end

local function openPanel(nodeName, chamberLabel, currentText)
	openNode = nodeName
	heading.Text = chamberLabel or "Write on the slate"
	box.Text = ""
	counter.Text = "0/" .. MAX_LENGTH

	if type(currentText) == "string" and #currentText > 0 then
		blurb.Text = string.format("Currently reads: %s", currentText)
	else
		blurb.Text = "Every diver who comes through reads this, and your name goes under it."
	end

	setMouseFree(true)
	gui.Enabled = true

	-- Let the key that opened this panel come back up before grabbing the keyboard.
	-- Capturing focus on the same frame as the prompt's own keypress meant the box lost
	-- focus the instant the player let go of the prompt key, which closed the panel again
	-- the moment it appeared -- the panel looked like it simply never opened.
	task.delay(0.2, function()
		if gui.Enabled and openNode == nodeName then
			box:CaptureFocus()
		end
	end)
end

box:GetPropertyChangedSignal("Text"):Connect(function()
	if #box.Text > MAX_LENGTH then
		box.Text = box.Text:sub(1, MAX_LENGTH)
	end
	counter.Text = string.format("%d/%d", #box.Text, MAX_LENGTH)
end)

local function submit()
	if not openNode then
		return
	end
	local text = box.Text
	local node = openNode
	closePanel()
	if text:gsub("%s", "") ~= "" then
		signWrite:FireServer(node, text)
	end
end

postButton.Activated:Connect(submit)
cancelButton.Activated:Connect(closePanel)

box.FocusLost:Connect(function(enterPressed)
	-- Enter posts, but only when there is something to post. Losing focus for any other
	-- reason must never close the panel: tapping away on a phone, or releasing the prompt
	-- key, would otherwise throw the whole thing away mid-sentence.
	if enterPressed and box.Text:gsub("%s", "") ~= "" then
		submit()
	end
end)

signPrompt.OnClientEvent:Connect(openPanel)
