-- Visitor list (admin only -- AVisitorListService enables this ScreenGui for admins alone).
-- Opens from the top bar's menu (TopBarController) through PanelUtil; the old on-screen
-- VISITOR button is gone.

local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local visitorGui = script.Parent
local panel = visitorGui:WaitForChild("VisitorPanel")
local scrollingFrame = panel:WaitForChild("ScrollingFrame")
local listLayout = scrollingFrame:WaitForChild("UIListLayout")
local emptyLabel = panel:WaitForChild("EmptyLabel")

local remoteEvent = ReplicatedStorage:WaitForChild("UpdateVisitorHistory")

-- shared with the admin dashboard's palette so the two panels read as one family
local GOLD = Color3.fromRGB(255, 210, 90)
local ROW_BG = Color3.fromRGB(40, 40, 48)
local MUTED = Color3.fromRGB(150, 156, 168)

scrollingFrame.Active = true
scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y

-- Auto-adjust CanvasSize based on content height
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

-- Render real visitors fetched from the server
local function renderVisitors(userIdList)
	-- rows are Frames now, not bare TextLabels
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	if #userIdList == 0 then
		emptyLabel.Text = "No visitors recorded yet."
		emptyLabel.Visible = true
		return
	end

	-- Convert User IDs to Display Names / Usernames
	local success, userInfoList = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(userIdList)
	end)

	-- A failed lookup used to leave the panel blank with no explanation.
	if not success or not userInfoList or #userInfoList == 0 then
		emptyLabel.Text = "Couldn't load the visitor list just now."
		emptyLabel.Visible = true
		return
	end

	emptyLabel.Visible = false
	for _, userInfo in ipairs(userInfoList) do
		-- Row styling follows the admin panel family: the toggle's own ground colour,
		-- a 6px corner, and the display name carrying the gold the headings use.
		local row = Instance.new("Frame")
		row.Name = userInfo.Username
		row.Size = UDim2.new(1, -6, 0, 40)
		row.BackgroundColor3 = ROW_BG
		row.BackgroundTransparency = 0.15
		row.BorderSizePixel = 0
		row.Parent = scrollingFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -20, 0, 18)
		name.Position = UDim2.fromOffset(10, 4)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = GOLD
		name.Text = userInfo.DisplayName
		name.Parent = row

		local handle = Instance.new("TextLabel")
		handle.Size = UDim2.new(1, -20, 0, 15)
		handle.Position = UDim2.fromOffset(10, 21)
		handle.BackgroundTransparency = 1
		handle.Font = Enum.Font.Gotham
		handle.TextSize = 12
		handle.TextXAlignment = Enum.TextXAlignment.Left
		handle.TextTruncate = Enum.TextTruncate.AtEnd
		handle.TextColor3 = MUTED
		handle.Text = "@" .. userInfo.Username
		handle.Parent = row
	end
end

-- Listen for visitor list sent from server
remoteEvent.OnClientEvent:Connect(renderVisitors)

panel.Visible = false
PanelUtil.Register("visitors", {
	open = function() panel.Visible = true end,
	close = function() panel.Visible = false end,
	isOpen = function() return visitorGui.Enabled and panel.Visible end,
})
PanelUtil.AddCloseButton(panel, "visitors")