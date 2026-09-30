-- LambatController
-- The stake button. Only ever on screen when you are the mangingisda and actually carrying
-- a lambat, because a button you cannot press is worse than no button on a phone.
--
-- Bottom-left, above the glowstick/tank row that GearHud owns, and on H for desktop. Every
-- other letter this game binds is taken: N bag, F light, Q tank, L ledger, G emote,
-- B binoculars, F8 cave x-ray.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestLambat = remotes:WaitForChild("RequestLambat")
local lambatStatus = remotes:WaitForChild("LambatStatus")
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local TOUCH = UserInputService.TouchEnabled
local KEY = Enum.KeyCode.H
local GROUND = Color3.fromRGB(28, 28, 34)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 156, 168)
local SEA = Color3.fromRGB(110, 206, 170)

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local gui = new("ScreenGui", {
	Name = "LambatGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- sits above GearHud's dive-action row, which is anchored to the same corner
local button = new("TextButton", {
	Name = "Stake", Size = UDim2.fromOffset(TOUCH and 150 or 132, TOUCH and 46 or 38),
	Position = UDim2.new(0, 14, 1, TOUCH and -244 or -196),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = SEA, BorderSizePixel = 0, AutoButtonColor = true,
	Font = Enum.Font.GothamBold, TextSize = TOUCH and 13 or 11.5,
	TextColor3 = Color3.fromRGB(16, 30, 26), Text = "PLANT STAKE",
	Visible = false,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, button)

local counter = new("TextLabel", {
	Name = "Count", BackgroundColor3 = GROUND, BackgroundTransparency = 0.1,
	BorderSizePixel = 0, Size = UDim2.fromOffset(TOUCH and 150 or 132, 20),
	Position = UDim2.new(0, 14, 1, TOUCH and -292 or -238),
	AnchorPoint = Vector2.new(0, 1),
	Font = Enum.Font.Gotham, TextSize = TOUCH and 11.5 or 10,
	TextColor3 = DIM, Text = "", Visible = false,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 6)}, counter)

local toast = new("TextLabel", {
	Name = "Toast", BackgroundColor3 = GROUND, BackgroundTransparency = 0.08,
	BorderSizePixel = 0, Size = UDim2.fromOffset(TOUCH and 320 or 300, 40),
	Position = UDim2.new(0.5, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	Font = Enum.Font.GothamMedium, TextSize = TOUCH and 13 or 11.5,
	TextColor3 = INK, Text = "", Visible = false, TextWrapped = true,
}, gui)
new("UICorner", {CornerRadius = UDim.new(0, 8)}, toast)
local toastStroke = new("UIStroke", {Color = SEA, Thickness = 1.2, Transparency = 0.4}, toast)

local planted = 0
local carried = 0

local function refresh()
	local isFisher = player:GetAttribute("Role") == "mangingisda"
	local hasNet = carried > 0
	button.Visible = isFisher and hasNet
	counter.Visible = isFisher
	if not isFisher then
		return
	end
	if hasNet then
		button.Text = TOUCH and "PLANT STAKE" or string.format("PLANT STAKE  [%s]", KEY.Name)
		counter.TextColor3 = DIM
		counter.Text = string.format("Lambat  -  %d of %d stakes set", planted, ItemConfig.LambatStakes)
	else
		counter.TextColor3 = Color3.fromRGB(236, 118, 118)
		counter.Text = "No lambat in your bag - buy one at the Palengke market"
	end
end

local toastToken = 0
local function showToast(message, ok)
	toastToken += 1
	local mine = toastToken
	toast.Text = message
	toastStroke.Color = ok and SEA or Color3.fromRGB(236, 118, 118)
	toast.Visible = true
	task.delay(3.4, function()
		if toastToken == mine then
			toast.Visible = false
		end
	end)
end

local lastPress = 0
local function plant()
	if os.clock() - lastPress < 0.35 then
		return
	end
	lastPress = os.clock()
	requestLambat:FireServer("stake")
end

-- Activated fires on touch, MouseButton1Click on a mouse; the debounce above covers the
-- platforms where both land.
button.Activated:Connect(plant)
button.MouseButton1Click:Connect(plant)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= KEY then
		return
	end
	if button.Visible then
		plant()
	end
end)

inventoryUpdated.OnClientEvent:Connect(function(state)
	carried = (state.items or {}).lambat or 0
	refresh()
end)

player:GetAttributeChangedSignal("Role"):Connect(refresh)

lambatStatus.OnClientEvent:Connect(function(message, ok)
	showToast(message, ok)
	-- keep the stake counter honest without a second remote: the server's own wording is
	-- the source of truth for how many are in the water
	local n = string.match(message, "^Stake (%d+) of")
	if n then
		planted = tonumber(n)
	elseif message:find("Lambat set") or message:find("pulled back up") or message:find("hauled in") then
		planted = 0
	end
	refresh()
end)

refresh()
