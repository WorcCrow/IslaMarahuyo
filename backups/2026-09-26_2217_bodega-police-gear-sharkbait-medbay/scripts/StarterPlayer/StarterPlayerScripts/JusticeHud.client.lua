-- JusticeHud
-- The jail toast, the community-service choice, and the community-vote card. The running
-- sentence itself (cell icon, minutes, jobs left) lives in StatusHud's column.
--
-- The vote card is deliberately plain and slow-looking: it names who called it and who it
-- is about, and it shows the running tally. A vote that anybody can call on anybody needs
-- to feel like a public act, not a button.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local jailStatus = remotes:WaitForChild("JailStatus")
local voteUpdated = remotes:WaitForChild("VoteUpdated")
local requestVote = remotes:WaitForChild("RequestVote")
local requestJailAction = remotes:WaitForChild("RequestJailAction")

local TOUCH = UserInputService.TouchEnabled
local GROUND = Color3.fromRGB(28, 28, 34)
local SUNK = Color3.fromRGB(40, 40, 48)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 156, 168)
local BLUE = Color3.fromRGB(96, 150, 240)
local RED = Color3.fromRGB(236, 118, 118)
local GREEN = Color3.fromRGB(110, 206, 170)

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
	Name = "JusticeGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- ===== jail toast =====
-- Speaks when something changes, then gets out of the way. It used to stay parked over the
-- top of the screen for the whole sentence, which made the game unplayable while serving.
local TOAST_SECONDS = 5
local banner = new("Frame", {
	Name = "Jail", Size = UDim2.fromOffset(TOUCH and 320 or 300, TOUCH and 74 or 64),
	Position = UDim2.new(0.5, 0, 0, TOUCH and 76 or 64), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = GROUND, BackgroundTransparency = 0.06,
	BorderSizePixel = 0, Visible = false,
}, gui)
round(banner, 10)
local bannerStroke = new("UIStroke", {Color = RED, Thickness = 1.5, Transparency = 0.3}, banner)

local bannerTitle = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 9),
	Size = UDim2.new(1, -28, 0, 18), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 14 or 12.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = RED, Text = "IN THE CELL",
}, banner)
local bannerBody = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 29),
	Size = UDim2.new(1, -28, 0, 34), Font = Enum.Font.Gotham,
	TextSize = TOUCH and 11.5 or 10.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = DIM,
	TextWrapped = true, Text = "",
}, banner)

local toastToken = 0
local function toast(title, colour, message)
	bannerStroke.Color = colour
	bannerTitle.TextColor3 = colour
	bannerTitle.Text = title
	bannerBody.Text = message
	banner.Visible = true
	toastToken += 1
	local mine = toastToken
	task.delay(TOAST_SECONDS, function()
		if toastToken == mine then
			banner.Visible = false
		end
	end)
end

-- ===== choosing community service =====
-- Opened from the duty desk. Where you serve is also where you stay until it is done, so
-- the card says up front how much work each place will take.
local chooser = new("Frame", {
	Name = "ServiceChoice", Size = UDim2.fromOffset(TOUCH and 320 or 300, TOUCH and 176 or 160),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = GROUND, BackgroundTransparency = 0.04,
	BorderSizePixel = 0, Visible = false,
}, gui)
round(chooser, 10)
new("UIStroke", {Color = GREEN, Thickness = 1.5, Transparency = 0.3}, chooser)
new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 10),
	Size = UDim2.new(1, -28, 0, 18), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 14 or 12.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = GREEN, Text = "COMMUNITY SERVICE",
}, chooser)
local chooserBody = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 30),
	Size = UDim2.new(1, -28, 0, 30), Font = Enum.Font.Gotham,
	TextSize = TOUCH and 11.5 or 10.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = DIM,
	TextWrapped = true, Text = "",
}, chooser)

local function trackButton(key, xScale)
	local b = new("TextButton", {
		Name = key, Size = UDim2.new(0.5, -20, 0, TOUCH and 56 or 50),
		Position = UDim2.new(xScale, xScale == 0 and 14 or 6, 0, 66),
		BackgroundColor3 = SUNK, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 12 or 11,
		TextColor3 = INK, TextWrapped = true, Text = "",
	}, chooser)
	round(b, 6)
	onPress(b, function()
		chooser.Visible = false
		requestJailAction:FireServer("service", key)
	end)
	return b
end
local trackButtons = {vendor = trackButton("vendor", 0), nurse = trackButton("nurse", 0.5)}

local stayBtn = new("TextButton", {
	Size = UDim2.new(1, -28, 0, TOUCH and 28 or 24), Position = UDim2.new(0, 14, 1, -10),
	AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = TOUCH and 11.5 or 10.5,
	TextColor3 = DIM, Text = "Stay in the cell",
}, chooser)
onPress(stayBtn, function()
	chooser.Visible = false
end)

local function openChooser(message, options)
	chooserBody.Text = message
	for key, b in pairs(trackButtons) do
		local o = options and options[key]
		b.Visible = o ~= nil
		if o then
			local noun = o.jobs == 1 and (o.noun:gsub("s$", "")) or o.noun
			local place = (o.place:gsub("^the ", ""))
			b.Text = string.format("%s duty\n%d %s", place, o.jobs, noun)
		end
	end
	chooser.Visible = true
end

jailStatus.OnClientEvent:Connect(function(kind, message, _, options)
	if kind == "choose" then
		openChooser(message, options)
		return
	end
	if kind == "free" then
		chooser.Visible = false
		toast("FREE", GREEN, message)
	elseif kind == "paralysed" then
		toast("PUT DOWN", RED, message)
	elseif kind == "info" then
		toast("PULIS", BLUE, message)
	elseif kind == "service" then
		chooser.Visible = false
		toast("COMMUNITY SERVICE", GREEN, message)
	else
		toast("IN THE CELL", RED, message)
	end
end)

-- ===== vote card =====
local card = new("Frame", {
	Name = "Vote", Size = UDim2.fromOffset(TOUCH and 300 or 280, TOUCH and 128 or 112),
	Position = UDim2.new(1, -14, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = GROUND, BackgroundTransparency = 0.06,
	BorderSizePixel = 0, Visible = false,
}, gui)
round(card, 10)
new("UIStroke", {Color = BLUE, Thickness = 1.5, Transparency = 0.3}, card)

local voteTitle = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 10),
	Size = UDim2.new(1, -28, 0, 18), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 13 or 12, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = BLUE, Text = "BARANGAY VOTE",
}, card)
local voteBody = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 30),
	Size = UDim2.new(1, -28, 0, 32), Font = Enum.Font.Gotham,
	TextSize = TOUCH and 11.5 or 10.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = INK,
	TextWrapped = true, Text = "",
}, card)
local tally = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 64),
	Size = UDim2.new(1, -28, 0, 14), Font = Enum.Font.GothamMedium,
	TextSize = TOUCH and 11 or 10, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = DIM, Text = "",
}, card)

local function voteButton(text, colour, xScale)
	local b = new("TextButton", {
		Size = UDim2.new(0.5, -20, 0, TOUCH and 36 or 30),
		Position = UDim2.new(xScale, xScale == 0 and 14 or 6, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = colour, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 12 or 11,
		TextColor3 = Color3.fromRGB(18, 18, 22), Text = text,
	}, card)
	round(b, 6)
	return b
end
local yesBtn = voteButton("JAIL THEM", RED, 0)
local noBtn = voteButton("LET IT GO", SUNK, 0.5)
noBtn.TextColor3 = INK
onPress(yesBtn, function() requestVote:FireServer("yes") end)
onPress(noBtn, function() requestVote:FireServer("no") end)

voteUpdated.OnClientEvent:Connect(function(kind, message, seconds, yes, no)
	if kind == "open" then
		voteTitle.Text = "BARANGAY VOTE"
		voteBody.Text = message
		tally.Text = "No votes yet."
		card.Visible = true
	elseif kind == "tally" then
		tally.Text = string.format("%d for jail  -  %d against", yes or 0, no or 0)
	elseif kind == "closed" then
		voteTitle.Text = "VOTE CLOSED"
		voteBody.Text = message
		tally.Text = ""
		task.delay(6, function()
			if voteTitle.Text == "VOTE CLOSED" then card.Visible = false end
		end)
	elseif kind == "info" then
		voteTitle.Text = "BARANGAY"
		voteBody.Text = message
		card.Visible = true
		task.delay(4, function()
			if voteTitle.Text == "BARANGAY" then card.Visible = false end
		end)
	end
end)

