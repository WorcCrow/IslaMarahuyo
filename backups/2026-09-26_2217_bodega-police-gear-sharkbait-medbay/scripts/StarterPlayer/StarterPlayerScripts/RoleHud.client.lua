-- RoleHud
-- The work-board panel: what jobs exist, who is on them, and the button to take one.
-- Opened by the ProximityPrompt at the Barangay plaza, never from a hotkey -- taking a
-- job is something you walk up and do, which is also what keeps the board a real place.
--
-- IgnoreGuiInset is ON. With it off, AbsolutePosition and input hit-testing disagree by
-- the 36-58px topbar inset and every tap lands a row low on phones.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openBoard = remotes:WaitForChild("OpenRoleBoard")
local roleUpdated = remotes:WaitForChild("RoleUpdated")
local roleFeedback = remotes:WaitForChild("RoleFeedback")
local requestRole = remotes:WaitForChild("RequestRole")
local shiftStatus = remotes:WaitForChild("ShiftStatus")

local TOUCH = UserInputService.TouchEnabled
local GROUND = Color3.fromRGB(28, 28, 34)
local SUNK = Color3.fromRGB(40, 40, 48)
local GOLD = Color3.fromRGB(255, 210, 90)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 156, 168)

local PANEL_W = TOUCH and 330 or 306
local ROW_H = TOUCH and 76 or 62
local BTN_W = TOUCH and 74 or 62
local BTN_H = TOUCH and 40 or 32

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function round(inst, r)
	new("UICorner", {CornerRadius = UDim.new(0, r)}, inst)
end

-- Both events, because a TextButton fires Activated on touch and MouseButton1Click on a
-- mouse, and the debounce stops the pair double-firing where both land.
local function onPress(button, fn)
	local last = 0
	local function go()
		if os.clock() - last < 0.2 then
			return
		end
		last = os.clock()
		fn()
	end
	button.Activated:Connect(go)
	button.MouseButton1Click:Connect(go)
end

local gui = new("ScreenGui", {
	Name = "RoleGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local panel = new("Frame", {
	Name = "Panel", Size = UDim2.fromOffset(PANEL_W, 420),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = GROUND, BorderSizePixel = 0, Visible = false,
}, gui)
round(panel, 12)
new("UIStroke", {Color = GOLD, Thickness = 1.5, Transparency = 0.35}, panel)

new("TextLabel", {
	Name = "Title", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 22),
	Font = Enum.Font.GothamBold, TextSize = TOUCH and 15 or 13,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD,
	Text = "TRABAHO SA BARANGAY",
}, panel)

local subtitle = new("TextLabel", {
	Name = "Sub", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 16),
	Font = Enum.Font.Gotham, TextSize = TOUCH and 12 or 10.5,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM,
	Text = "Take a job, or hand one back.",
}, panel)

local close = new("TextButton", {
	Name = "Close", Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.new(1, -28, 0, BTN_H), BackgroundColor3 = SUNK, BorderSizePixel = 0,
	AutoButtonColor = true, Font = Enum.Font.GothamMedium,
	TextSize = TOUCH and 13 or 11, TextColor3 = DIM, Text = "Close",
}, panel)
round(close, 6)

local list = new("ScrollingFrame", {
	Name = "Roles", BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 56), Size = UDim2.new(1, -28, 1, -(56 + BTN_H + 24)),
	ScrollBarThickness = 4, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)

-- ===== toast =====
local toast = new("TextLabel", {
	Name = "Toast", BackgroundColor3 = GROUND, BackgroundTransparency = 0.08,
	BorderSizePixel = 0, Size = UDim2.fromOffset(PANEL_W + 40, 40),
	Position = UDim2.new(0.5, 0, 0.22, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	Font = Enum.Font.GothamMedium, TextSize = TOUCH and 13 or 11.5,
	TextColor3 = INK, Text = "", Visible = false, TextWrapped = true,
}, gui)
round(toast, 8)
local toastStroke = new("UIStroke", {Color = GOLD, Thickness = 1.2, Transparency = 0.4}, toast)

local toastToken = 0
local function showToast(message, ok)
	toastToken += 1
	local mine = toastToken
	toast.Text = message
	toastStroke.Color = ok and GOLD or Color3.fromRGB(236, 118, 118)
	toast.Visible = true
	task.delay(3.2, function()
		if toastToken == mine then
			toast.Visible = false
		end
	end)
end

-- ===== rows =====
local rows = {}
local myRole = nil

local function ensureRow(row)
	local entry = rows[row.key]
	if entry then
		return entry
	end

	local frame = new("Frame", {
		Name = row.key, BackgroundColor3 = SUNK, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = row.order,
	}, list)
	round(frame, 8)

	local pip = new("Frame", {
		Name = "Pip", BackgroundColor3 = row.tint, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 10), Size = UDim2.fromOffset(4, ROW_H - 20),
	}, frame)
	round(pip, 2)

	local textW = -(BTN_W + 26)
	local name = new("TextLabel", {
		Name = "Name", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, textW, 0, 17),
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 14 or 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = INK,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = row.label,
	}, frame)

	local blurb = new("TextLabel", {
		Name = "Blurb", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, textW, 0, 30),
		Font = Enum.Font.Gotham, TextSize = TOUCH and 11.5 or 10,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = DIM, TextWrapped = true, Text = row.blurb,
	}, frame)

	local who = new("TextLabel", {
		Name = "Who", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, ROW_H - 22), Size = UDim2.new(1, textW, 0, 15),
		Font = Enum.Font.GothamMedium, TextSize = TOUCH and 11 or 9.5,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
	}, frame)

	local act = new("TextButton", {
		Name = "Act", Size = UDim2.fromOffset(BTN_W, BTN_H),
		Position = UDim2.new(1, -(BTN_W + 10), 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = row.tint, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 12 or 10.5,
		TextColor3 = Color3.fromRGB(20, 20, 24), Text = "TAKE",
	}, frame)
	round(act, 6)
	onPress(act, function()
		if myRole == row.key then
			requestRole:FireServer("none")
		else
			requestRole:FireServer(row.key)
		end
	end)

	entry = {frame = frame, name = name, blurb = blurb, who = who, act = act, tint = row.tint}
	rows[row.key] = entry
	return entry
end

-- Panels must never grow past the screen on a phone, so the panel is sized from the rows
-- it actually has and then clamped to the viewport; the list scrolls if it had to shrink.
local function clamp()
	local n = 0
	for _ in pairs(rows) do
		n += 1
	end
	n = math.max(n, 1)
	local wanted = 56 + (ROW_H + 8) * n + BTN_H + 24
	local limit = math.floor(workspace.CurrentCamera.ViewportSize.Y * 0.86)
	panel.Size = UDim2.fromOffset(PANEL_W, math.min(wanted, limit))
end

local function repaint(snapshot, mine)
	myRole = mine
	local myLabel = nil
	for _, row in ipairs(snapshot) do
		if row.key == mine then
			myLabel = row.label
		end
	end
	for _, row in ipairs(snapshot) do
		local entry = ensureRow(row)
		entry.name.Text = string.format("%s  (%s)", row.label, row.english)

		local held = #row.holders
		if held > 0 then
			entry.who.Text = string.format("%d/%d on duty: %s", held, row.cap, table.concat(row.holders, ", "))
			entry.who.TextColor3 = row.tint
		elseif not row.open then
			entry.who.Text = string.format("Shift closed - %s is covering", row.bot)
			entry.who.TextColor3 = DIM
		else
			entry.who.Text = string.format("Nobody on duty - %s is covering", row.bot)
			entry.who.TextColor3 = DIM
		end

		local isMine = myRole == row.key
		local full = held >= row.cap
		entry.act.Text = isMine and "LEAVE" or (full and "FULL" or "TAKE")
		entry.act.BackgroundColor3 = isMine and Color3.fromRGB(58, 46, 42)
			or (full and SUNK or row.tint)
		entry.act.TextColor3 = (isMine or full) and DIM or Color3.fromRGB(20, 20, 24)
		-- a full role still shows the button so the count is legible; it just does nothing
		entry.act.AutoButtonColor = isMine or not full
		entry.frame.BackgroundTransparency = isMine and 0.02 or 0.15
	end

	subtitle.Text = myLabel
		and string.format("You are the %s. Press LEAVE to hand it back.", myLabel)
		or "Take a job, or hand one back. One at a time."
	clamp()
end

clamp()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(clamp)

onPress(close, function()
	panel.Visible = false
end)

openBoard.OnClientEvent:Connect(function(snapshot, mine)
	repaint(snapshot, mine)
	clamp()
	panel.Visible = true
end)

roleUpdated.OnClientEvent:Connect(function(snapshot, mine)
	repaint(snapshot, mine)
end)

roleFeedback.OnClientEvent:Connect(showToast)

-- ===== the tindero's shift meter =====
-- A market shift only pays if it is actually worked, so the one thing a tindero must be
-- able to see at all times is how much of it they have banked. Finding out at closing
-- time that you were 4% short would be a miserable way to learn the rule.
local meter = new("Frame", {
	Name = "Shift", Size = UDim2.fromOffset(TOUCH and 184 or 166, TOUCH and 46 or 40),
	Position = UDim2.new(0, 14, 1, TOUCH and -120 or -96), AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = GROUND, BackgroundTransparency = 0.1,
	BorderSizePixel = 0, Visible = false,
}, gui)
round(meter, 8)
new("UIStroke", {Color = Color3.fromRGB(240, 168, 96), Thickness = 1.2, Transparency = 0.4}, meter)

local meterText = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 5),
	Size = UDim2.new(1, -20, 0, 15), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 12 or 10.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = INK, Text = "SHIFT",
}, meter)

local barBack = new("Frame", {
	BackgroundColor3 = SUNK, BorderSizePixel = 0,
	Position = UDim2.fromOffset(10, TOUCH and 26 or 23),
	Size = UDim2.new(1, -20, 0, 7),
}, meter)
round(barBack, 3)
local barFill = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(240, 168, 96), BorderSizePixel = 0,
	Size = UDim2.new(0, 0, 1, 0),
}, barBack)
round(barFill, 3)
-- the pay line, drawn on the bar so the target is visible rather than remembered
local barMark = new("Frame", {
	BackgroundColor3 = INK, BorderSizePixel = 0, BackgroundTransparency = 0.3,
	Position = UDim2.new(0.7, 0, 0, -2), Size = UDim2.fromOffset(2, 11),
}, barBack)

local function refreshMeter()
	local coverage = player:GetAttribute("ShiftCoverage")
	if coverage == nil then
		meter.Visible = false
		return
	end
	local need = workspace:GetAttribute("ShiftRequiredCoverage") or 0.7
	barMark.Position = UDim2.new(need, 0, 0, -2)
	meter.Visible = true
	barFill.Size = UDim2.new(math.clamp(coverage, 0, 1), 0, 1, 0)
	barFill.BackgroundColor3 = coverage >= need
		and Color3.fromRGB(110, 206, 170)
		or Color3.fromRGB(240, 168, 96)
	meterText.Text = string.format("SHIFT %d%%  -  %d crates",
		math.floor(coverage * 100), player:GetAttribute("ShiftCrates") or 0)
end

player:GetAttributeChangedSignal("ShiftCoverage"):Connect(refreshMeter)
player:GetAttributeChangedSignal("ShiftCrates"):Connect(refreshMeter)
refreshMeter()

shiftStatus.OnClientEvent:Connect(function(kind, message, value)
	if kind == "toast" then
		showToast(message, value == 1)
	elseif kind == "warn" then
		showToast(message, true)
	elseif kind == "paid" then
		showToast(message, true)
	elseif kind == "unpaid" then
		showToast(message, false)
	end
	refreshMeter()
end)
