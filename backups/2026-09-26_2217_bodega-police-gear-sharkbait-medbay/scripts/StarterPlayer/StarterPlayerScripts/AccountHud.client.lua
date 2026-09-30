-- AccountHud
-- The account book: every Peso in and out, newest first, on L -- or from the top bar's
-- menu (TopBarController), which replaced the touch-only ACCOUNT chip.
--
-- This is what is left of MarketHud. The Palengke stall board went with the ability to
-- list goods there -- all player-to-player trade is on the black market now -- but the
-- book stayed, because "why am I short?" is a question players ask constantly and the
-- ledger is the only thing that answers it.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestLedger = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestLedger")
local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local TOUCH = UserInputService.TouchEnabled
local KEY = Enum.KeyCode.L
local GROUND = Color3.fromRGB(28, 28, 34)
local SUNK = Color3.fromRGB(40, 40, 48)
local GOLD = Color3.fromRGB(255, 210, 90)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 156, 168)
local GREEN = Color3.fromRGB(110, 206, 170)
local RED = Color3.fromRGB(236, 118, 118)

local PANEL_W = TOUCH and 330 or 306
local ROW_H = TOUCH and 40 or 34
local BTN_H = TOUCH and 40 or 32

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end
local function round(inst, r)
	new("UICorner", {CornerRadius = UDim.new(0, r)}, inst)
end
local function onPress(button, fn)
	local last = 0
	local function go()
		if os.clock() - last < 0.25 then return end
		last = os.clock()
		fn()
	end
	button.Activated:Connect(go)
	button.MouseButton1Click:Connect(go)
end

local gui = new("ScreenGui", {
	Name = "AccountGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local panel = new("Frame", {
	Name = "Account", Size = UDim2.fromOffset(PANEL_W, 380),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = GROUND, BorderSizePixel = 0, Visible = false,
}, gui)
round(panel, 12)
new("UIStroke", {Color = GOLD, Thickness = 1.5, Transparency = 0.35}, panel)

new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 12),
	Size = UDim2.new(1, -28, 0, 20), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 14 or 12.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = GOLD, Text = "ACCOUNT",
}, panel)
local balance = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 32),
	Size = UDim2.new(1, -28, 0, 16), Font = Enum.Font.GothamMedium,
	TextSize = TOUCH and 12 or 11, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = INK, Text = "",
}, panel)

local entries = new("ScrollingFrame", {
	Name = "Entries", BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -28, 1, -(54 + BTN_H + 24)),
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, entries)

local close = new("TextButton", {
	Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.new(1, -28, 0, BTN_H), BackgroundColor3 = SUNK, BorderSizePixel = 0,
	AutoButtonColor = true, Font = Enum.Font.GothamMedium,
	TextSize = TOUCH and 13 or 11, TextColor3 = DIM, Text = "Close",
}, panel)
round(close, 6)
onPress(close, function() PanelUtil.Close("account") end)

local function clamp()
	-- clamp and centre between the top bar and the hotbar (CoreGui, drawn above us), so
	-- neither the header nor the Close button ends up covered
	local inset = game:GetService("GuiService"):GetGuiInset().Y
	local band = workspace.CurrentCamera.ViewportSize.Y - inset - 80
	panel.Size = UDim2.fromOffset(PANEL_W, math.min(380, math.floor(band - 12)))
	panel.Position = UDim2.new(0.5, 0, 0, inset + band / 2)
end
clamp()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(clamp)

local function refresh()
	local ok, book = pcall(function()
		return requestLedger:InvokeServer()
	end)
	if not ok or type(book) ~= "table" then
		balance.Text = "The book is closed right now."
		return
	end
	balance.Text = string.format("%d Peso on hand", book.balance or 0)

	for _, child in ipairs(entries:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for i, e in ipairs(book.entries or {}) do
		local row = new("Frame", {
			Name = "e" .. i, BackgroundColor3 = SUNK, BackgroundTransparency = 0.3,
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = i,
		}, entries)
		round(row, 5)
		new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -96, 1, 0), Font = Enum.Font.Gotham,
			TextSize = TOUCH and 12 or 10.5, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = e.label or "Unknown",
		}, row)
		local amount = e.amount or 0
		new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.new(1, -90, 0, 0),
			Size = UDim2.fromOffset(80, ROW_H), Font = Enum.Font.GothamBold,
			TextSize = TOUCH and 12 or 10.5, TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = amount >= 0 and GREEN or RED,
			Text = string.format("%s%d", amount >= 0 and "+" or "", amount),
		}, row)
	end

	if #(book.entries or {}) == 0 then
		local row = new("Frame", {
			Name = "empty", BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, ROW_H * 2), LayoutOrder = 1,
		}, entries)
		new("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.Gotham, TextSize = TOUCH and 12 or 10.5,
			TextColor3 = DIM, TextWrapped = true,
			Text = "Nothing in the book yet. Earn or spend something.",
		}, row)
	end
end

PanelUtil.Register("account", {
	open = function()
		panel.Visible = true
		refresh()
	end,
	close = function() panel.Visible = false end,
	isOpen = function() return panel.Visible end,
})

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == KEY then
		PanelUtil.Toggle("account")
	end
end)
