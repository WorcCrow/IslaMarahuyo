-- HUDController
-- Owns the Roster and Settings panels, and the name-tag / island-sign controllers behind
-- them. Both panels open from the TopbarPlus menu (TopBarController) through PanelUtil;
-- the balance chip and the row of icon buttons that used to sit up here are gone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local player = Players.LocalPlayer
local hud = script.Parent

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rosterUpdated = remotes:WaitForChild("RosterUpdated")
local requestRoster = remotes:WaitForChild("RequestRoster")

-- Shells are money now, and the shell glyph belongs to the things you fish out of the sea,
-- so the balance reads as a money bag instead.
local SHELL = "\240\159\146\176"

local NameTagController = require(ReplicatedStorage:WaitForChild("NameTagController"))
NameTagController.Init()

-- Island/location name billboards (zone signs + zipline tower markers) -- off by default,
-- since they're visible from anywhere on the map (MaxDistance = inf) and get noisy fast.
local IslandNameController = require(ReplicatedStorage:WaitForChild("IslandNameController"))
IslandNameController.Init()

--------------------------------------------------------------------------------
-- shared panel chrome
--------------------------------------------------------------------------------

local function buildPanel(name, title, heightScale)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 48)
	panel.Size = UDim2.new(0.5, 0, heightScale, 0)
	panel.BackgroundColor3 = Color3.fromRGB(24, 30, 40)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = hud

	local clamp = Instance.new("UISizeConstraint")
	clamp.MinSize = Vector2.new(280, 190)
	clamp.MaxSize = Vector2.new(430, 400)
	clamp.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 86, 108)
	stroke.Thickness = 1
	stroke.Parent = panel

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, -46, 0, 30)
	heading.Position = UDim2.new(0, 12, 0, 8)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 16
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = Color3.fromRGB(245, 205, 130)
	heading.Text = title
	heading.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.new(0, 28, 0, 28)
	close.Position = UDim2.new(1, -34, 0, 9)
	close.BackgroundColor3 = Color3.fromRGB(52, 40, 36)
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.TextSize = 15
	close.TextColor3 = Color3.fromRGB(236, 210, 190)
	close.Text = "X"
	close.Parent = panel

	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 6)
	cc.Parent = close

	close.Activated:Connect(function()
		panel.Visible = false
		PanelUtil.Refresh()
	end)

	return panel
end

--------------------------------------------------------------------------------
-- settings: the two name toggles live here now
--------------------------------------------------------------------------------

local settingsPanel = buildPanel("SettingsPanel", "Settings", 0.56)

local function buildToggleRow(parent, y, labelText, getter, setter)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 38)
	row.Position = UDim2.new(0, 12, 0, y)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -78, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 14
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.fromRGB(228, 234, 242)
	text.Text = labelText
	text.Parent = row

	local btn = Instance.new("TextButton")
	btn.Name = "Toggle"
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, 0, 0.5, 0)
	btn.Size = UDim2.new(0, 66, 0, 28)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.Parent = row

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	local function refresh()
		local on = getter()
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Color3.fromRGB(46, 122, 96) or Color3.fromRGB(64, 58, 54)
		btn.TextColor3 = on and Color3.fromRGB(226, 248, 238) or Color3.fromRGB(198, 190, 182)
	end

	btn.Activated:Connect(function()
		setter(not getter())
		refresh()
	end)
	refresh()
end

buildToggleRow(settingsPanel, 48, "Player names",
	NameTagController.IsVisible, NameTagController.SetVisible)
buildToggleRow(settingsPanel, 90, "Island name signs",
	IslandNameController.IsVisible, IslandNameController.SetVisible)

--------------------------------------------------------------------------------
-- Custom Title -- the Custom Title pass's only way in. The server owns the gate and
-- the filtering (TitleTagService); this is just the field. Non-owners see why it's
-- locked rather than an input that silently fails, and everyone keeps whatever title
-- they EARNED in the cave for free -- clearing the box falls back to it.
--------------------------------------------------------------------------------

local setTitleRemote = remotes:WaitForChild("SetPlayerTitle")
local titleFeedback = remotes:WaitForChild("TitleFeedback")

local titleRow = Instance.new("Frame")
titleRow.Name = "TitleRow"
titleRow.Size = UDim2.new(1, -24, 0, 62)
titleRow.Position = UDim2.new(0, 12, 0, 128)
titleRow.BackgroundTransparency = 1
titleRow.Parent = settingsPanel

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 18)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamMedium
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.fromRGB(228, 234, 242)
titleLabel.Text = "Your title"
titleLabel.Parent = titleRow

local titleBox = Instance.new("TextBox")
titleBox.Name = "TitleBox"
titleBox.Size = UDim2.new(1, -74, 0, 30)
titleBox.Position = UDim2.new(0, 0, 0, 22)
titleBox.BackgroundColor3 = Color3.fromRGB(18, 24, 32)
titleBox.BorderSizePixel = 0
titleBox.ClearTextOnFocus = false
titleBox.Font = Enum.Font.GothamMedium
titleBox.TextSize = 14
titleBox.TextColor3 = Color3.fromRGB(240, 232, 216)
titleBox.PlaceholderColor3 = Color3.fromRGB(126, 138, 150)
titleBox.Text = ""
titleBox.Parent = titleRow

local tbCorner = Instance.new("UICorner")
tbCorner.CornerRadius = UDim.new(0, 6)
tbCorner.Parent = titleBox

local tbPad = Instance.new("UIPadding")
tbPad.PaddingLeft = UDim.new(0, 8)
tbPad.PaddingRight = UDim.new(0, 8)
tbPad.Parent = titleBox

local titleApply = Instance.new("TextButton")
titleApply.Name = "Apply"
titleApply.AnchorPoint = Vector2.new(1, 0)
titleApply.Position = UDim2.new(1, 0, 0, 22)
titleApply.Size = UDim2.new(0, 66, 0, 30)
titleApply.BackgroundColor3 = Color3.fromRGB(46, 122, 96)
titleApply.BorderSizePixel = 0
titleApply.Font = Enum.Font.GothamBold
titleApply.TextSize = 13
titleApply.TextColor3 = Color3.fromRGB(226, 248, 238)
titleApply.Text = "Set"
titleApply.Parent = titleRow

local taCorner = Instance.new("UICorner")
taCorner.CornerRadius = UDim.new(0, 6)
taCorner.Parent = titleApply

local function refreshTitleRow()
	local owns = player:GetAttribute("CanSetTitle") == true
	titleBox.TextEditable = owns
	titleBox.PlaceholderText = owns and "e.g. Bangkero ng Timog" or "Needs the Custom Title pass"
	titleApply.BackgroundColor3 = owns and Color3.fromRGB(46, 122, 96) or Color3.fromRGB(58, 66, 74)
	titleApply.TextColor3 = owns and Color3.fromRGB(226, 248, 238) or Color3.fromRGB(150, 160, 170)
	titleApply.AutoButtonColor = owns

	local shown = player:GetAttribute("DisplayTitle")
	if owns then
		titleLabel.Text = "Your title"
	elseif shown and shown ~= "" then
		titleLabel.Text = string.format("Your title -- %s (earned)", shown)
	else
		titleLabel.Text = "Your title -- earn one in the cave, or buy the pass"
	end
end

local function submitTitle()
	if player:GetAttribute("CanSetTitle") ~= true then
		return
	end
	setTitleRemote:FireServer(titleBox.Text)
end

titleApply.Activated:Connect(submitTitle)
titleBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitTitle()
	end
end)

titleFeedback.OnClientEvent:Connect(function(ok, message)
	titleLabel.Text = message or (ok and "Title updated." or "Couldn't set that title.")
	titleLabel.TextColor3 = ok and Color3.fromRGB(140, 220, 185) or Color3.fromRGB(232, 150, 130)
	task.delay(4, function()
		titleLabel.TextColor3 = Color3.fromRGB(228, 234, 242)
		refreshTitleRow()
	end)
end)

player:GetAttributeChangedSignal("CanSetTitle"):Connect(refreshTitleRow)
player:GetAttributeChangedSignal("DisplayTitle"):Connect(refreshTitleRow)
refreshTitleRow()

--------------------------------------------------------------------------------
-- Bangka paint -- the Bangka Customs pass. Cycles through the schemes the server
-- publishes, so the button can never offer one the server would reject.
--------------------------------------------------------------------------------

local setPaintRemote = remotes:WaitForChild("SetBangkaPaint")
local paintFolder = ReplicatedStorage:WaitForChild("BangkaPaints")

local paintEntries = paintFolder:GetChildren()
table.sort(paintEntries, function(a, b)
	return a.Name < b.Name
end)

local paintIndex = 1

local paintRow = Instance.new("Frame")
paintRow.Name = "PaintRow"
paintRow.Size = UDim2.new(1, -24, 0, 38)
paintRow.Position = UDim2.new(0, 12, 0, 196)
paintRow.BackgroundTransparency = 1
paintRow.Parent = settingsPanel

local paintLabel = Instance.new("TextLabel")
paintLabel.Size = UDim2.new(1, -110, 1, 0)
paintLabel.BackgroundTransparency = 1
paintLabel.Font = Enum.Font.GothamMedium
paintLabel.TextSize = 14
paintLabel.TextXAlignment = Enum.TextXAlignment.Left
paintLabel.TextColor3 = Color3.fromRGB(228, 234, 242)
paintLabel.Text = "Bangka paint"
paintLabel.Parent = paintRow

local paintButton = Instance.new("TextButton")
paintButton.Name = "Paint"
paintButton.AnchorPoint = Vector2.new(1, 0.5)
paintButton.Position = UDim2.new(1, 0, 0.5, 0)
paintButton.Size = UDim2.new(0, 104, 0, 28)
paintButton.BorderSizePixel = 0
paintButton.Font = Enum.Font.GothamBold
paintButton.TextSize = 12
paintButton.Text = "Standard"
paintButton.Parent = paintRow

local pbCorner = Instance.new("UICorner")
pbCorner.CornerRadius = UDim.new(0, 6)
pbCorner.Parent = paintButton

local function refreshPaintRow()
	local owns = player:GetAttribute("BangkaCustom") == true
	local entry = paintEntries[paintIndex]
	paintButton.Text = owns and (entry and entry:GetAttribute("Label") or "Standard") or "Locked"
	paintButton.BackgroundColor3 = owns and Color3.fromRGB(46, 78, 122) or Color3.fromRGB(58, 66, 74)
	paintButton.TextColor3 = owns and Color3.fromRGB(226, 238, 252) or Color3.fromRGB(150, 160, 170)
	paintButton.AutoButtonColor = owns
	paintLabel.Text = owns and "Bangka paint" or "Bangka paint -- needs Bangka Customs"
end

paintButton.Activated:Connect(function()
	if player:GetAttribute("BangkaCustom") ~= true then
		return
	end
	paintIndex = (paintIndex % #paintEntries) + 1
	local entry = paintEntries[paintIndex]
	if entry then
		setPaintRemote:FireServer(entry:GetAttribute("Key"))
	end
	refreshPaintRow()
end)

player:GetAttributeChangedSignal("BangkaCustom"):Connect(refreshPaintRow)
refreshPaintRow()

local settingsNote = Instance.new("TextLabel")
settingsNote.Size = UDim2.new(1, -24, 0, 34)
settingsNote.Position = UDim2.new(0, 12, 0, 240)
settingsNote.BackgroundTransparency = 1
settingsNote.Font = Enum.Font.Gotham
settingsNote.TextSize = 12
settingsNote.TextWrapped = true
settingsNote.TextXAlignment = Enum.TextXAlignment.Left
settingsNote.TextYAlignment = Enum.TextYAlignment.Top
settingsNote.TextColor3 = Color3.fromRGB(150, 162, 176)
settingsNote.Text = "These only change what you see. Nobody else's screen is affected."
settingsNote.Parent = settingsPanel

--------------------------------------------------------------------------------
-- roster: who is on this server
--------------------------------------------------------------------------------

local rosterPanel = buildPanel("RosterPanel", "On this server", 0.52)

local rosterCount = Instance.new("TextLabel")
rosterCount.Size = UDim2.new(1, -24, 0, 16)
rosterCount.Position = UDim2.new(0, 12, 0, 36)
rosterCount.BackgroundTransparency = 1
rosterCount.Font = Enum.Font.Gotham
rosterCount.TextSize = 12
rosterCount.TextXAlignment = Enum.TextXAlignment.Left
rosterCount.TextColor3 = Color3.fromRGB(150, 162, 176)
rosterCount.Text = ""
rosterCount.Parent = rosterPanel

local rosterList = Instance.new("ScrollingFrame")
rosterList.Name = "List"
rosterList.Position = UDim2.new(0, 8, 0, 56)
rosterList.Size = UDim2.new(1, -16, 1, -64)
rosterList.BackgroundTransparency = 1
rosterList.BorderSizePixel = 0
rosterList.ScrollBarThickness = 4
rosterList.CanvasSize = UDim2.new(0, 0, 0, 0)
rosterList.AutomaticCanvasSize = Enum.AutomaticSize.Y
rosterList.Parent = rosterPanel

local rosterLayout = Instance.new("UIListLayout")
rosterLayout.Padding = UDim.new(0, 4)
rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
rosterLayout.Parent = rosterList

local function renderRoster(rows)
	if typeof(rows) ~= "table" then
		return
	end

	for _, child in ipairs(rosterList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	rosterCount.Text = string.format("%d %s here", #rows, #rows == 1 and "diver" or "divers")

	for i, entry in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -4, 0, 42)
		row.BackgroundColor3 = Color3.fromRGB(34, 42, 54)
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = rosterList

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = row

		local isYou = entry.userId == player.UserId

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -16, 0, 18)
		nameLabel.Position = UDim2.new(0, 8, 0, 3)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextColor3 = isYou and Color3.fromRGB(250, 214, 140) or Color3.fromRGB(232, 238, 246)
		nameLabel.Text = entry.name .. (isYou and "  (you)" or "")
		nameLabel.Parent = row

		-- expertise sits on its own line only when they've actually earned one
		local stats = Instance.new("TextLabel")
		stats.Size = UDim2.new(1, -16, 0, 16)
		stats.Position = UDim2.new(0, 8, 0, 21)
		stats.BackgroundTransparency = 1
		stats.Font = Enum.Font.Gotham
		stats.TextSize = 12
		stats.TextXAlignment = Enum.TextXAlignment.Left
		stats.TextTruncate = Enum.TextTruncate.AtEnd
		stats.TextColor3 = Color3.fromRGB(166, 180, 196)
		local title = entry.title
		if title == nil or title == "" then
			title = string.format("cave %d%%", entry.explored or 0)
		end
		stats.Text = string.format("%s %d   Lv %d   \226\153\187 %d   \240\159\142\129 %d   %s",
			SHELL, entry.shells or 0, entry.level or 1,
			entry.revives or 0, entry.donated or 0, title)
		stats.Parent = row
	end
end

rosterUpdated.OnClientEvent:Connect(renderRoster)

--------------------------------------------------------------------------------
-- opened from the top bar -- opening one panel closes the other, so they never stack
--------------------------------------------------------------------------------

PanelUtil.Register("roster", {
	open = function()
		settingsPanel.Visible = false
		rosterPanel.Visible = true
		task.spawn(function()
			local ok, rows = pcall(function()
				return requestRoster:InvokeServer()
			end)
			if ok then
				renderRoster(rows)
			end
		end)
	end,
	close = function() rosterPanel.Visible = false end,
	isOpen = function() return rosterPanel.Visible end,
})

PanelUtil.Register("settings", {
	open = function()
		rosterPanel.Visible = false
		settingsPanel.Visible = true
	end,
	close = function() settingsPanel.Visible = false end,
	isOpen = function() return settingsPanel.Visible end,
})
