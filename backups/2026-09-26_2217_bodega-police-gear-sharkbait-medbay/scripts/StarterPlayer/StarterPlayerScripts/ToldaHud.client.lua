-- ToldaHud
-- Stocking your own black-market stall, and browsing somebody else's.
--
-- This is now the ONLY place a player can sell to another player. The Palengke board was
-- removed: the Palengke buys finds at a fixed rate and sells gear, and that is all it
-- does. If you want to name your own price, you pitch a tent and take the risk -- which
-- is what gives the pulis something to actually police.
--
-- Pitching and packing moved to the Tolda hotbar tool (ServerStorage.ItemAssets.ToldaTool),
-- so there is no floating button here any more. The stall panel closes itself when you
-- walk away from the tent.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestTolda = remotes:WaitForChild("RequestTolda")
local toldaUpdated = remotes:WaitForChild("ToldaUpdated")
local toldaStatus = remotes:WaitForChild("ToldaStatus")
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local TOUCH = UserInputService.TouchEnabled
local GROUND = Color3.fromRGB(28, 28, 34)
local SUNK = Color3.fromRGB(40, 40, 48)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 156, 168)
local VIOLET = Color3.fromRGB(196, 118, 236)
local RED = Color3.fromRGB(236, 118, 118)

local PANEL_W = TOUCH and 330 or 306
local ROW_H = TOUCH and 58 or 48
local BTN_H = TOUCH and 40 or 32
local SELL_H = TOUCH and 122 or 106

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end
local function round(inst, r)
	new("UICorner", {CornerRadius = UDim.new(0, r)}, inst)
end
-- Activated fires on touch, MouseButton1Click on a mouse; the debounce covers both landing.
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
	Name = "ToldaGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local carried = {} -- the latest inventory snapshot
local viewingMine = false
local sellIndex, sellCount = 1, 1

-- ===== the stall panel =====
local panel = new("Frame", {
	Name = "Stall", Size = UDim2.fromOffset(PANEL_W, 340),
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = GROUND, BorderSizePixel = 0, Visible = false,
}, gui)
round(panel, 12)
new("UIStroke", {Color = VIOLET, Thickness = 1.5, Transparency = 0.35}, panel)

local title = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 12),
	Size = UDim2.new(1, -28, 0, 20), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 14 or 12.5, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = VIOLET, Text = "TOLDA",
}, panel)
local subtitle = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 32),
	Size = UDim2.new(1, -28, 0, 15), Font = Enum.Font.Gotham,
	TextSize = TOUCH and 11 or 10, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = DIM, Text = "No receipts. No stall fee. No questions.",
}, panel)

local list = new("ScrollingFrame", {
	Name = "Rack", BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -28, 1, -(54 + BTN_H + 24)),
	ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, list)

local close = new("TextButton", {
	Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.new(1, -28, 0, BTN_H), BackgroundColor3 = SUNK, BorderSizePixel = 0,
	AutoButtonColor = true, Font = Enum.Font.GothamMedium,
	TextSize = TOUCH and 13 or 11, TextColor3 = DIM, Text = "Close",
}, panel)
round(close, 6)
PanelUtil.Register("tolda", {
	open = function() panel.Visible = true end,
	close = function() panel.Visible = false end,
	isOpen = function() return panel.Visible end,
})
onPress(close, function() PanelUtil.Close("tolda") end)

-- ===== stocking your own rack =====
-- Pinned above the footer rather than at a fixed Y, so it follows the panel when it clamps
-- on a short screen.
local sellBox = new("Frame", {
	Name = "Stock", Position = UDim2.new(0, 14, 1, -(SELL_H + BTN_H + 20)),
	AnchorPoint = Vector2.new(0, 0), Size = UDim2.new(1, -28, 0, SELL_H),
	BackgroundColor3 = SUNK, BackgroundTransparency = 0.35, BorderSizePixel = 0,
	Visible = false,
}, panel)
round(sellBox, 6)

local sellTitle = new("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 8),
	Size = UDim2.new(1, -20, 0, 16), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 12.5 or 11, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = INK, Text = "Put something out",
}, sellBox)

local pickBtn = new("TextButton", {
	Position = UDim2.fromOffset(10, TOUCH and 32 or 28), Size = UDim2.new(0.52, -6, 0, BTN_H),
	BackgroundColor3 = Color3.fromRGB(52, 38, 62), BorderSizePixel = 0, AutoButtonColor = true,
	Font = Enum.Font.GothamMedium, TextSize = TOUCH and 12 or 10.5,
	TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd, Text = "nothing to sell",
}, sellBox)
round(pickBtn, 5)

local countBtn = new("TextButton", {
	Position = UDim2.new(0.52, 6, 0, TOUCH and 32 or 28), Size = UDim2.new(0.2, -6, 0, BTN_H),
	BackgroundColor3 = Color3.fromRGB(52, 38, 62), BorderSizePixel = 0, AutoButtonColor = true,
	Font = Enum.Font.GothamBold, TextSize = TOUCH and 12 or 10.5, TextColor3 = INK, Text = "x1",
}, sellBox)
round(countBtn, 5)

local priceBox = new("TextBox", {
	Position = UDim2.new(0.72, 6, 0, TOUCH and 32 or 28), Size = UDim2.new(0.28, -6, 0, BTN_H),
	BackgroundColor3 = Color3.fromRGB(26, 18, 32), BorderSizePixel = 0,
	Font = Enum.Font.GothamBold, TextSize = TOUCH and 12 or 10.5, TextColor3 = VIOLET,
	PlaceholderText = "price", PlaceholderColor3 = DIM, Text = "", ClearTextOnFocus = false,
}, sellBox)
round(priceBox, 5)

local listBtn = new("TextButton", {
	Position = UDim2.fromOffset(10, TOUCH and 78 or 68), Size = UDim2.new(1, -20, 0, BTN_H),
	BackgroundColor3 = VIOLET, BorderSizePixel = 0, AutoButtonColor = true,
	Font = Enum.Font.GothamBold, TextSize = TOUCH and 13 or 11,
	TextColor3 = Color3.fromRGB(26, 16, 30), Text = "PUT IT ON THE RACK",
}, sellBox)
round(listBtn, 5)

-- Everything you could put out: finds first, because selling finds at your own price
-- instead of the Palengke's fixed rate is the whole reason to run a tolda.
local function sellable()
	local out = {}
	for _, loot in ipairs(ItemConfig.SortedLoot()) do
		local n = (carried.finds or {})[loot.key] or 0
		if n > 0 then
			table.insert(out, {key = loot.key, item = loot, have = n, loot = true})
		end
	end
	for _, item in ipairs(ItemConfig.SortedItems()) do
		-- gear can be sold from either the bodega or the bag
		local n = ((carried.bodega or {})[item.key] or 0) + ((carried.items or {})[item.key] or 0)
		if n > 0 then
			table.insert(out, {key = item.key, item = item, have = n, loot = false})
		end
	end
	return out
end

local function refreshSell()
	local options = sellable()
	if #options == 0 then
		sellIndex = 1
		pickBtn.Text = "nothing to sell"
		countBtn.Text = "x0"
		listBtn.Visible = false
		sellTitle.Text = "Put something out -- you are carrying nothing"
		return
	end
	sellIndex = ((sellIndex - 1) % #options) + 1
	local choice = options[sellIndex]
	sellCount = math.clamp(sellCount, 1, choice.have)
	pickBtn.Text = string.format("%s  (have %d)", choice.item.short, choice.have)
	countBtn.Text = "x" .. sellCount
	listBtn.Visible = true
	if choice.loot then
		sellTitle.Text = string.format("Put something out -- Palengke pays %d each", choice.item.sell or 0)
	else
		sellTitle.Text = "Put something out -- name your own price"
	end
end

onPress(pickBtn, function()
	sellIndex += 1
	sellCount = 1
	refreshSell()
end)
onPress(countBtn, function()
	local options = sellable()
	local choice = options[sellIndex]
	if not choice then return end
	-- wraps rather than clamping, so getting back to 1 is one more tap, not a long hold
	sellCount = (sellCount % choice.have) + 1
	refreshSell()
end)
onPress(listBtn, function()
	local options = sellable()
	local choice = options[sellIndex]
	if not choice then return end
	local price = math.floor(tonumber(priceBox.Text) or 0)
	if price < 1 then
		priceBox.PlaceholderText = "set a price"
		return
	end
	requestTolda:FireServer("list", choice.key, sellCount, price)
	priceBox.Text = ""
	sellCount = 1
end)

-- ===== rendering the rack =====
local function clampPanel(rowCount, mine)
	local body = math.max(rowCount, 1) * (ROW_H + 6)
	local wanted = 54 + body + (mine and (SELL_H + 8) or 0) + BTN_H + 24
	-- clamp and centre between the top bar and the hotbar (CoreGui, drawn above us), so
	-- neither the header nor the Close button ends up covered
	local inset = game:GetService("GuiService"):GetGuiInset().Y
	local band = workspace.CurrentCamera.ViewportSize.Y - inset - 80
	panel.Size = UDim2.fromOffset(PANEL_W, math.min(wanted, math.floor(band - 12)))
	panel.Position = UDim2.new(0.5, 0, 0, inset + band / 2)
	-- the rack list gives up whatever room the stock box needs
	list.Size = UDim2.new(1, -28, 1, -(54 + BTN_H + 24 + (mine and (SELL_H + 8) or 0)))
end

-- matches BlackMarketService's toldaUpdated:FireClient(who, id, ownerName, ownerId, rows, mine)
local function render(tentId, ownerName, _ownerId, rows, mine)
	if typeof(rows) ~= "table" then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	viewingMine = mine
	title.Text = mine and "YOUR TOLDA" or (string.upper(ownerName) .. "'S TOLDA")
	subtitle.Text = mine
		and "Whatever sells, you keep in full. Keep an eye out for pulis."
		or "No receipts. No stall fee. No questions."

	for i, row in ipairs(rows) do
		local def = ItemConfig.Find(row.key)
		local frame = new("Frame", {
			Name = "row" .. i, BackgroundColor3 = SUNK, BackgroundTransparency = 0.15,
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = i,
		}, list)
		round(frame, 6)
		new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(11, 7),
			Size = UDim2.new(1, -96, 0, 16), Font = Enum.Font.GothamBold,
			TextSize = TOUCH and 13 or 11.5, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = string.format("%s x%d", def and def.short or row.key, row.count),
		}, frame)
		new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(11, 25),
			Size = UDim2.new(1, -96, 0, 15), Font = Enum.Font.Gotham,
			TextSize = TOUCH and 11 or 10, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = DIM,
			Text = mine and string.format("asking %d Peso", row.price)
				or (row.loot and "a find, straight for Peso" or "gear"),
		}, frame)
		local btn = new("TextButton", {
			Size = UDim2.fromOffset(80, TOUCH and 36 or 30),
			Position = UDim2.new(1, -90, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = mine and SUNK or VIOLET, BorderSizePixel = 0,
			AutoButtonColor = true, Font = Enum.Font.GothamBold,
			TextSize = TOUCH and 11.5 or 10.5,
			TextColor3 = mine and INK or Color3.fromRGB(26, 16, 30),
			Text = mine and "TAKE BACK" or string.format("%d", row.price),
		}, frame)
		round(btn, 6)
		onPress(btn, function()
			if mine then
				requestTolda:FireServer("unlist", row.id)
			else
				requestTolda:FireServer("buy", tentId, row.id)
			end
		end)
	end

	if #rows == 0 then
		local frame = new("Frame", {
			Name = "empty", BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = 1,
		}, list)
		new("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.Gotham, TextSize = TOUCH and 12 or 10.5,
			TextColor3 = DIM, TextWrapped = true,
			Text = mine and "Nothing out yet. Pick something below and name a price."
				or "Nothing on the rack.",
		}, frame)
	end

	sellBox.Visible = mine
	if mine then
		refreshSell()
	end
	clampPanel(#rows, mine)
	-- the panel is always opened standing at the tent (its Browse prompt, or just after
	-- pitching), so where the player stands now is where it belongs
	PanelUtil.Open("tolda", {anchor = "here", radius = 22})
end

toldaUpdated.OnClientEvent:Connect(render)

-- ===== toast =====
local toast = new("TextLabel", {
	BackgroundColor3 = GROUND, BackgroundTransparency = 0.08, BorderSizePixel = 0,
	Size = UDim2.fromOffset(PANEL_W + 40, 40),
	Position = UDim2.new(0.5, 0, 0.22, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	Font = Enum.Font.GothamMedium, TextSize = TOUCH and 13 or 11.5,
	TextColor3 = INK, Text = "", Visible = false, TextWrapped = true,
}, gui)
round(toast, 8)
local toastStroke = new("UIStroke", {Color = VIOLET, Thickness = 1.2, Transparency = 0.4}, toast)

local token = 0
toldaStatus.OnClientEvent:Connect(function(message, ok)
	token += 1
	local mine = token
	toast.Text = message
	toastStroke.Color = ok and VIOLET or RED
	toast.Visible = true
	task.delay(3.6, function()
		if token == mine then toast.Visible = false end
	end)

	if message:find("Packed up") or message:find("seized") then
		PanelUtil.Close("tolda")
	end
end)

inventoryUpdated.OnClientEvent:Connect(function(snapshot)
	carried = snapshot or {}
	if panel.Visible and viewingMine then
		refreshSell()
	end
end)

-- ===== hiding Confiscate from everyone but a pulis =====
-- The Seize prompt sits on every tolda for any player standing nearby, same as every
-- other role-gated prompt in this game -- only the trigger is permission-checked. That
-- reads as broken here specifically because "Confiscate" looks like a real option to
-- someone who is not a pulis. Enabled is a local-only override: it never replicates back
-- to the server or to other clients, so this only changes what THIS player can see.
local ProximityPromptService = game:GetService("ProximityPromptService")
local isla = workspace:WaitForChild("IslaMarahuyo")
local toldas = isla:WaitForChild("Toldas")

local function filterSeize(prompt)
	if prompt.Name == "Report" then
		-- nobody reports their own stall
		prompt.Enabled = prompt:GetAttribute("OwnerId") ~= player.UserId
		return
	end
	if prompt.Name ~= "Seize" then
		return
	end
	prompt.Enabled = player:GetAttribute("Role") == "pulis"
end

local function rescanSeizePrompts()
	for _, tent in ipairs(toldas:GetChildren()) do
		local floor = tent:FindFirstChild("Floor")
		local seize = floor and floor:FindFirstChild("Seize")
		if seize then
			filterSeize(seize)
		end
		local report = floor and floor:FindFirstChild("Report")
		if report then
			filterSeize(report)
		end
	end
end

rescanSeizePrompts()
toldas.DescendantAdded:Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		filterSeize(inst)
	end
end)
player:GetAttributeChangedSignal("Role"):Connect(rescanSeizePrompts)
