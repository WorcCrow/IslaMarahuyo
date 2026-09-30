-- GearHud
-- Two separate jobs, deliberately kept apart:
--   the DIVE BAG is what you are carrying -- drop it for a teammate, pack or stow it at your
--   bodega; no prices, no shopping;
--   the PALENGKE is where money changes hands, and it only exists when you are stood there.
-- Mixing the two put a Buy button next to a Use button on a drowning player's screen.
--
-- Nothing here sits on screen until it is asked for. Gear you use in the field (tank,
-- glowstick, tolda, flashlight) lives in the hotbar as tools; the numbers live in StatusHud;
-- the bag opens from the top bar (TopBarController) and the Palengke from its counter prompt.
--
-- This screen decides nothing. It renders the server's last snapshot and sends intent back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))
local ItemIcon = require(ReplicatedStorage:WaitForChild("ItemIcon"))
local BODEGA = ItemConfig.Bodega

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local requestItemBuy = remotes:WaitForChild("RequestItemBuy")
local requestItemUse = remotes:WaitForChild("RequestItemUse")
local requestItemDrop = remotes:WaitForChild("RequestItemDrop")
local requestTransfer = remotes:WaitForChild("RequestTransfer")
local requestBagUpgrade = remotes:WaitForChild("RequestBagUpgrade")
local requestSellLoot = remotes:WaitForChild("RequestSellLoot")
local requestBodega = remotes:WaitForChild("RequestBodega")
local bodegaOpen = remotes:WaitForChild("BodegaOpen")
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
local itemFeedback = remotes:WaitForChild("ItemFeedback")
local flashlightFeedback = remotes:WaitForChild("FlashlightFeedback")
local requestPass = remotes:FindFirstChild("RequestGamePassPurchase")

local AMBER = Color3.fromRGB(232, 168, 64)
local LOW = Color3.fromRGB(214, 84, 54)
local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 172, 184)
local SUNK = Color3.fromRGB(24, 38, 47)
local GROUND = Color3.fromRGB(10, 18, 24)
local SEA = Color3.fromRGB(28, 96, 130)
local RUST = Color3.fromRGB(58, 46, 42)

local TOUCH = UserInputService.TouchEnabled

-- Checked against what the place already binds: B binoculars, G emote, J tolda panel,
-- L account, H lambat, F8 x-ray, Space revive. E is the ProximityPrompt key.
local KEY_BAG = Enum.KeyCode.N
local ROW_H = TOUCH and 62 or 48
local BTN_W = TOUCH and 68 or 56
local BTN_H = TOUCH and 44 or 34
local PANEL_W = TOUCH and 330 or 306

-- On a phone the bag and bodega are a grid of picture cards instead of a list of rows:
-- the rows were too thin to hit and a narrow list left most of a landscape screen empty.
-- The panel takes the width the phone has and fits as many cards to a row as it can.
-- The Palengke keeps its list.
local TILE = TOUCH
local PANEL_W_TILE = 640
local TILE_H = 136
local TILE_MIN_W = 100
local GAP = 8

-- These are equipped from the hotbar and used by clicking, so the bag offers no second USE
-- button for them -- only DROP, to hand one to a teammate.
local HOTBAR_TOOL = {oxygen = true, glowstick = true, tolda = true, sharkbait = true}

local state = {items = {}, used = 0, capacity = 4, tierLabel = "Sako", tierIndex = 1, passBag = false}

local function new(class, props, parent)
	local e = Instance.new(class)
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function round(inst, r)
	new("UICorner", {CornerRadius = UDim.new(0, r)}, inst)
end

-- Activated covers touch, MouseButton1Click covers mouse; listen for both and debounce so
-- one press never counts twice.
local function onPress(button, fn)
	local last = 0
	local function fire()
		local now = os.clock()
		if now - last < 0.2 then
			return
		end
		last = now
		fn()
	end
	button.Activated:Connect(fire)
	button.MouseButton1Click:Connect(fire)
end

-- IgnoreGuiInset: without it AbsolutePosition is measured below the topbar while input is
-- tested against the whole screen, so taps land low.
local gui = new("ScreenGui", {
	Name = "GearHud", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- Panels are sized to their content but must never exceed the screen -- the shop is taller
-- than a small phone. They clamp to the band between the top bar and the hotbar and centre
-- in it: the top bar would cover the header, and the hotbar is CoreGui, drawn above game UI,
-- so a Close button under it cannot be tapped at all. The row list scrolls.
local HOTBAR_RESERVE = 80
local panels = {}

local function clampPanels()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local inset = GuiService:GetGuiInset().Y
	local band = camera.ViewportSize.Y - inset - HOTBAR_RESERVE
	for _, entry in ipairs(panels) do
		local width, wanted = PANEL_W, entry.wanted
		if entry.grid then
			width = math.min(PANEL_W_TILE, camera.ViewportSize.X - 40)
			local inner = width - 28 - 6 -- side padding, and room for the scroll bar
			local cols = math.clamp(math.floor((inner + GAP) / (TILE_MIN_W + GAP)), 2, 6)
			local cellW = math.floor((inner - (cols - 1) * GAP) / cols)
			for _, list in ipairs(entry.grid.lists) do
				local grid = list:FindFirstChildOfClass("UIGridLayout")
				if grid then
					grid.CellSize = UDim2.fromOffset(cellW, TILE_H)
				end
			end
			wanted = entry.grid.chrome + math.ceil(entry.grid.count / cols) * (TILE_H + GAP)
		end
		entry.frame.Size = UDim2.fromOffset(width, math.min(wanted, band - 12))
		entry.frame.Position = UDim2.new(0.5, 0, 0, inset + band / 2)
	end
end

local function makePanel(name, title, rows, grid)
	local wanted = 92 + ROW_H * rows + (rows - 1) * 8 + 62
	local p = new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(PANEL_W, wanted),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = GROUND, BackgroundTransparency = 0.06, BorderSizePixel = 0,
		Visible = false,
	}, gui)
	round(p, 8)
	local stroke = new("UIStroke", {Color = AMBER, Transparency = 0.5, Thickness = 1}, p)
	new("TextLabel", {
		Name = "Title", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(160, 16),
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 13 or 11.5,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = AMBER, Text = title,
	}, p)
	local right = new("TextLabel", {
		Name = "Right", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-14, 11), Size = UDim2.new(1, 0, 0, 16),
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 13 or 11.5,
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = INK, Text = "",
	}, p)
	local close = new("TextButton", {
		Name = "Close", Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, -28, 0, BTN_H), BackgroundColor3 = SUNK, BorderSizePixel = 0,
		AutoButtonColor = true, Font = Enum.Font.GothamMedium,
		TextSize = TOUCH and 13 or 11, TextColor3 = DIM, Text = "Close",
	}, p)
	round(close, 6)
	if grid then
		-- up in the header, so the cards get the height
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, -8, 0, 5)
		close.Size = UDim2.fromOffset(40, 28)
		close.Text = "X"
		close.Font = Enum.Font.GothamBold
		close.TextSize = 15
		right.Position = UDim2.fromOffset(-58, 11)
	end
	local list = new("ScrollingFrame", {
		Name = "Items", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 1, -(38 + BTN_H + 46)),
		ScrollBarThickness = 4, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, p)
	if grid then
		new("UIGridLayout", {
			CellPadding = UDim2.fromOffset(GAP, GAP), CellSize = UDim2.fromOffset(TILE_MIN_W, TILE_H),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, list)
	else
		new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	end

	table.insert(panels, {frame = p, wanted = wanted, grid = grid and {lists = {list}, count = rows, chrome = 0} or nil})
	return p, list, right, stroke, close
end

local CARRY_ROWS = #ItemConfig.SortedItems()
-- carryables + the sell counter + the bag upgrade + every pass item
-- (contraband is carried, never sold here)
local SHOP_ROWS = #ItemConfig.SortedShopItems() + 2 + #ItemConfig.PassItems

local bag, bagList, bagCount, _, bagClose = makePanel("Panel", "DIVE BAG", CARRY_ROWS + 1, TILE)
local shop, shopList, shopWallet, shopStroke, shopClose = makePanel("Shop", "PALENGKE", SHOP_ROWS)
shopStroke.Color = Color3.fromRGB(120, 214, 255)

local function bigButton(parent, text, colour, order)
	local b = new("TextButton", {
		Name = text, Size = UDim2.fromOffset(BTN_W, BTN_H),
		Position = UDim2.new(1, -(BTN_W + 6) * order + 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = colour, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 13 or 11,
		TextColor3 = INK, Text = text,
	}, parent)
	round(b, 6)
	return b
end

local function makeRow(parent, key, order)
	local row = new("Frame", {
		Name = key .. "_row", BackgroundColor3 = SUNK, BackgroundTransparency = 0.3,
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = order,
	}, parent)
	round(row, 6)
	local textW = -((BTN_W + 6) * 2 + 16)
	local name = new("TextLabel", {
		Name = "Name", BackgroundTransparency = 1, Position = UDim2.fromOffset(11, TOUCH and 11 or 7),
		Size = UDim2.new(1, textW, 0, 16), Font = Enum.Font.GothamBold,
		TextSize = TOUCH and 13 or 11.5, TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = INK, Text = "",
	}, row)
	local sub = new("TextLabel", {
		Name = "Sub", BackgroundTransparency = 1, Position = UDim2.fromOffset(11, TOUCH and 32 or 25),
		Size = UDim2.new(1, textW, 0, 15), Font = Enum.Font.Gotham,
		TextSize = TOUCH and 11.5 or 10, TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM, Text = "",
	}, row)
	return row, name, sub
end

-- A picture card for the phone grid: the item's model on top, name and a status line
-- under it, and its buttons along the bottom. Returns the same three pieces as makeRow,
-- so the painting code below does not care which one it is looking at.
local function makeCard(parent, key, order, iconKey)
	local card = new("Frame", {
		Name = key .. "_row", BackgroundColor3 = SUNK, BackgroundTransparency = 0.3,
		BorderSizePixel = 0, LayoutOrder = order,
	}, parent)
	round(card, 8)
	local icon = new("Frame", {
		Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(64, 58),
		Position = UDim2.new(0.5, 0, 0, 3), AnchorPoint = Vector2.new(0.5, 0),
	}, card)
	ItemIcon.ForKey(iconKey or key, icon)
	local name = new("TextLabel", {
		Name = "Name", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 62),
		Size = UDim2.new(1, -8, 0, 16), Font = Enum.Font.GothamBold, TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = INK, Text = "",
	}, card)
	local sub = new("TextLabel", {
		Name = "Sub", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 79),
		Size = UDim2.new(1, -8, 0, 14), Font = Enum.Font.Gotham, TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = DIM, Text = "",
	}, card)
	return card, name, sub
end

-- order 1 is the right-hand button and 2 the left, the same as bigButton on a row
local function cardButton(card, text, colour, order)
	local b = new("TextButton", {
		Name = text, Size = UDim2.new(0.5, -6, 0, 34),
		Position = order == 1 and UDim2.new(1, -4, 1, -4) or UDim2.new(0, 4, 1, -4),
		AnchorPoint = order == 1 and Vector2.new(1, 1) or Vector2.new(0, 1),
		BackgroundColor3 = colour, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = INK, Text = text,
	}, card)
	round(b, 6)
	return b
end

local function cell(parent, key, order, iconKey)
	if TILE then
		return makeCard(parent, key, order, iconKey)
	end
	return makeRow(parent, key, order)
end

local function cellButton(row, text, colour, order)
	if TILE then
		return cardButton(row, text, colour, order)
	end
	return bigButton(row, text, colour, order)
end

-- ===== dive bag: carry and drop. no prices. =====
local bagRows = {}
for _, item in ipairs(ItemConfig.SortedItems()) do
	local row, name, sub = cell(bagList, item.key, item.order)
	local use = cellButton(row, "USE", SEA, 2)
	local drop = cellButton(row, "DROP", RUST, 1)
	onPress(use, function() requestItemUse:FireServer(item.key) end)
	onPress(drop, function() requestItemDrop:FireServer(item.key) end)
	bagRows[item.key] = {row = row, name = name, sub = sub, use = use, drop = drop, item = item}
end

-- anchored to the footer rather than to the row list, so it stays put when the panel clamps
local bagHint = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = TILE and UDim2.new(0, 14, 1, -22) or UDim2.new(0, 14, 1, -(BTN_H + 34)),
	Size = UDim2.new(1, -28, 0, 16), Font = Enum.Font.Gotham,
	TextSize = TOUCH and 11 or 10, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextColor3 = DIM, Text = "",
}, bag)

-- ===== bodega: the storehouse, and the packing screen =====
-- Gear lives in two places: the bodega (uncapped, standing somewhere on the island) and the
-- bag you swim with (slot-capped, and the only thing that scatters when you drown). Moving
-- gear between them happens only beside your own bodega -- the server enforces it too.
local TAB_H = TOUCH and 28 or 24
local LIST_TOP = 38 + TAB_H + 6
bagList.Position = UDim2.fromOffset(14, LIST_TOP)
-- the phone grid has no Close bar along the bottom (it moved to the header), just the hint
bagList.Size = TILE and UDim2.new(1, -28, 1, -(LIST_TOP + 26)) or UDim2.new(1, -28, 1, -(LIST_TOP + BTN_H + 46))

local bodegaList = new("ScrollingFrame", {
	Name = "Bodega", BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = bagList.Position, Size = bagList.Size,
	ScrollBarThickness = 4, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
}, bag)
if TILE then
	new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP, GAP), CellSize = UDim2.fromOffset(TILE_MIN_W, TILE_H),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, bodegaList)
else
	new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, bodegaList)
end

-- the panel grew by a tab strip; tell the clamp logic about it or it will crop a row
for _, entry in ipairs(panels) do
	if entry.frame == bag then
		entry.wanted += TAB_H + 6
		bag.Size = UDim2.fromOffset(PANEL_W, entry.wanted)
		if entry.grid then
			-- the bodega tab is the taller of the two: its condition card plus every item
			table.insert(entry.grid.lists, bodegaList)
			entry.grid.count = CARRY_ROWS + 1
			entry.grid.chrome = LIST_TOP + 26
		end
	end
end

local bagMode = "dala"
local function makeTab(text, order)
	local t = new("TextButton", {
		Name = text,
		Size = UDim2.new(0.5, -17, 0, TAB_H),
		Position = order == 1 and UDim2.fromOffset(14, 38) or UDim2.new(0.5, 3, 0, 38),
		BackgroundColor3 = SUNK, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = TOUCH and 12 or 10.5,
		TextColor3 = DIM, Text = text,
	}, bag)
	round(t, 6)
	return t
end
local tabDala = makeTab("DALA", 1)
local tabBodega = makeTab("BODEGA", 2)

-- the bodega's own condition sits at the top of its tab: life, and what a repair costs
local lifeRow, lifeName, lifeSub = cell(bodegaList, "bodega_life", 0, "bodega")
local repairBtn = cellButton(lifeRow, "REPAIR", Color3.fromRGB(46, 122, 96), 2)
onPress(repairBtn, function() requestBodega:FireServer("repair") end)
local upgradeBtn = cellButton(lifeRow, "UPGRADE", Color3.fromRGB(120, 122, 126), 1)
onPress(upgradeBtn, function() requestBodega:FireServer("upgradeStone") end)

local bodegaRows = {}
for _, item in ipairs(ItemConfig.SortedItems()) do
	local row, name, sub = cell(bodegaList, item.key, item.order)
	local pack = cellButton(row, "PACK", SEA, 2)
	local stow = cellButton(row, "STOW", RUST, 1)
	onPress(pack, function() requestTransfer:FireServer(item.key, "toGear", 1) end)
	onPress(stow, function() requestTransfer:FireServer(item.key, "toBodega", 1) end)
	bodegaRows[item.key] = {row = row, name = name, sub = sub, pack = pack, stow = stow, item = item}
end

-- ===== palengke: the only place money moves =====
-- SortedShopItems, not SortedItems: a licensed market does not stock the tolda that
-- exists to avoid it. The server refuses the purchase too.
local shopRows = {}
for _, item in ipairs(ItemConfig.SortedShopItems()) do
	local row, name, sub = makeRow(shopList, "shop_" .. item.key, item.order)
	local buy = bigButton(row, "BUY", SEA, 1)
	onPress(buy, function() requestItemBuy:FireServer(item.key) end)
	shopRows[item.key] = {row = row, name = name, sub = sub, buy = buy, item = item}
end

-- the sell counter sits at the top of the shop: it is the reason most divers walk in
local sellRow, sellName, sellSub = makeRow(shopList, "shop_sell", 0)
local sellBtn = bigButton(sellRow, "SELL", Color3.fromRGB(150, 110, 24), 1)
onPress(sellBtn, function() requestSellLoot:FireServer() end)

local upgradeRow, upgradeName, upgradeSub = makeRow(shopList, "shop_bag", 40)
local upgradeBuy = bigButton(upgradeRow, "BUY", SEA, 1)
onPress(upgradeBuy, function() requestBagUpgrade:FireServer() end)

-- pass-bought upgrades: Robux, not Peso, so they get their own colour
local PASS_GOLD = Color3.fromRGB(128, 94, 28)
local passRows = {}
for _, entry in ipairs(ItemConfig.PassItems) do
	local row, name, sub = makeRow(shopList, "shop_" .. entry.passKey, entry.order)
	local buy = bigButton(row, "PASS", PASS_GOLD, 1)
	onPress(buy, function()
		if requestPass then
			requestPass:FireServer(entry.passKey)
		end
	end)
	passRows[entry.passKey] = {row = row, name = name, sub = sub, buy = buy, entry = entry}
end

-- ===== shared toast =====
local toast = new("TextLabel", {
	Name = "Toast", BackgroundColor3 = GROUND, BackgroundTransparency = 0.15,
	Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_W + 40, 40), Font = Enum.Font.GothamBold,
	TextSize = TOUCH and 14 or 12.5, TextWrapped = true, TextColor3 = AMBER,
	Text = "", Visible = false,
}, gui)
round(toast, 8)
new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, toast)

local toastToken = 0
local function showToast(message, ok)
	toastToken += 1
	local mine = toastToken
	-- over the foot of whichever panel is open, just above its Close button (below the
	-- panel is the hotbar's band); low-centre when neither is open
	local openPanel = (bag.Visible and bag) or (shop.Visible and shop)
	if openPanel then
		local bottom = openPanel.AbsolutePosition.Y + openPanel.AbsoluteSize.Y
		toast.AnchorPoint = Vector2.new(0.5, 1)
		toast.Position = UDim2.new(0.5, 0, 0, bottom - BTN_H - 20)
	else
		toast.AnchorPoint = Vector2.new(0.5, 0.5)
		toast.Position = UDim2.new(0.5, 0, 0.62, 0)
	end
	toast.Text = message
	toast.TextColor3 = ok and AMBER or LOW
	toast.Visible = true
	task.delay(3.5, function()
		if toastToken == mine then
			toast.Visible = false
		end
	end)
end

-- ===== painting =====
local function refreshBag()
	local used, cap = state.used or 0, state.capacity or 4
	bagCount.Text = string.format("%s  %d/%d", state.tierLabel or "Sako", used, cap)

	local carryingAnything = false
	for key, r in pairs(bagRows) do
		local count = (state.items or {})[key] or 0
		carryingAnything = carryingAnything or count > 0
		r.name.Text = count > 0 and string.format("%s  x%d", r.item.short, count) or r.item.short
		r.name.TextColor3 = count > 0 and INK or DIM
		r.sub.Text = count > 0
			and (HOTBAR_TOOL[key] and "use it from your hotbar" or r.item.blurb)
			or "none carried"
		r.use.Visible = count > 0 and r.item.usable ~= false and not HOTBAR_TOOL[key]
		r.drop.Visible = count > 0
		r.row.BackgroundTransparency = count > 0 and 0.3 or 0.65
	end

	local atBodega = player:GetAttribute("AtBodega") == true
	for key, r in pairs(bodegaRows) do
		local stored = (state.bodega or {})[key] or 0
		local carried = (state.items or {})[key] or 0
		r.name.Text = string.format("%s  x%d", r.item.short, stored)
		r.name.TextColor3 = stored > 0 and INK or DIM
		r.sub.Text = carried > 0
			and string.format("%d in your bag", carried)
			or "none in your bag"
		r.pack.Visible = stored > 0 and atBodega
		r.stow.Visible = carried > 0 and atBodega
		r.row.BackgroundTransparency = (stored > 0 or carried > 0) and 0.3 or 0.65
	end

	-- the cap depends on which tier the player owns (wood or the stone upgrade), published
	-- by BodegaService rather than assumed here
	local maxHealth = tonumber(player:GetAttribute("BodegaMaxHealth")) or 100
	local health = tonumber(player:GetAttribute("BodegaHealth")) or maxHealth
	local missing = maxHealth - health
	lifeName.Text = string.format("Bodega  %d/%d", health, maxHealth)
	lifeName.TextColor3 = health <= maxHealth * 0.25 and LOW or INK
	lifeSub.Text = missing > 0
		and string.format("repair: %d Peso", math.ceil(missing * BODEGA.RepairPerPoint))
		or "solid"
	repairBtn.Visible = missing > 0 and atBodega
	-- unlike repair/pack/stow, buying the upgrade needs no proximity -- it only changes what
	-- tier gets built the next time a bodega goes down
	upgradeBtn.Visible = maxHealth < ItemConfig.BodegaTierFor("stone").maxHealth

	local parts = {}
	for _, loot in ipairs(ItemConfig.SortedLoot()) do
		local n = (state.finds or {})[loot.key] or 0
		if n > 0 then
			table.insert(parts, string.format("%s x%d", loot.short, n))
		end
	end

	if bagMode == "bodega" then
		if atBodega then
			bagHint.Text = "Unlimited storage. Pack what you need before you dive."
			bagHint.TextColor3 = DIM
		else
			bagHint.Text = "Walk to your bodega to pack or stow."
			bagHint.TextColor3 = Color3.fromRGB(255, 176, 120)
		end
	elseif #parts > 0 then
		bagHint.Text = string.format("SACK  %s  \u{2022}  worth %d at the Palengke",
			table.concat(parts, ", "), state.lootValue or 0)
		bagHint.TextColor3 = Color3.fromRGB(255, 206, 120)
	elseif not carryingAnything then
		bagHint.Text = "Empty. Gear only -- finds ride in the sack, not the bag."
		bagHint.TextColor3 = DIM
	else
		bagHint.Text = "Drop gear to hand it to a teammate."
		bagHint.TextColor3 = DIM
	end
end

local function setBagMode(mode)
	bagMode = mode
	local onDala = mode == "dala"
	bagList.Visible = onDala
	bodegaList.Visible = not onDala
	tabDala.TextColor3 = onDala and INK or DIM
	tabBodega.TextColor3 = onDala and DIM or INK
	tabDala.BackgroundColor3 = onDala and SEA or SUNK
	tabBodega.BackgroundColor3 = onDala and SUNK or SEA
	refreshBag()
end

onPress(tabDala, function() setBagMode("dala") end)
onPress(tabBodega, function() setBagMode("bodega") end)
setBagMode("dala")

local function refreshShop()
	for _, r in pairs(shopRows) do
		r.name.Text = r.item.label
		local bundle = r.item.bundle or 1
		r.sub.Text = bundle > 1
			and string.format("%d Peso  \u{2022}  pack of %d", r.item.price, bundle)
			or string.format("%d Peso  \u{2022}  %d slot%s",
				r.item.price, r.item.slots, r.item.slots > 1 and "s" or "")
	end
	local nextTier = ItemConfig.BagTiers[(state.tierIndex or 1) + 1]
	if state.passBag then
		upgradeName.Text = "Kaban ng Dagat"
		upgradeSub.Text = "already yours with the pass"
		upgradeBuy.Visible = false
	elseif nextTier then
		upgradeName.Text = nextTier.label
		upgradeSub.Text = string.format("%d Peso  \u{2022}  %d slots", nextTier.price, nextTier.slots)
		upgradeBuy.Visible = true
	else
		upgradeName.Text = "Kaban ng Dagat"
		upgradeSub.Text = "biggest bag on the island"
		upgradeBuy.Visible = false
	end
	for passKey, r in pairs(passRows) do
		local owned = player:GetAttribute(passKey) == true
		r.name.Text = r.entry.label
		r.sub.Text = owned and "fitted to your torch" or r.entry.blurb
		r.name.TextColor3 = owned and AMBER or INK
		r.buy.Visible = not owned
		r.row.BackgroundTransparency = owned and 0.6 or 0.3
	end

	local pieces = state.lootPieces or 0
	local value = state.lootValue or 0
	sellName.Text = pieces > 0 and string.format("Sell %d find%s", pieces, pieces == 1 and "" or "s")
		or "Nothing to sell"
	sellName.TextColor3 = pieces > 0 and Color3.fromRGB(255, 206, 120) or DIM
	sellSub.Text = pieces > 0 and string.format("%d Peso for the lot", value)
		or "Bring up finds from the sea"
	sellBtn.Visible = pieces > 0
	sellRow.BackgroundTransparency = pieces > 0 and 0.3 or 0.65

	shopWallet.Text = string.format("%s  %d/%d", state.tierLabel or "Sako", state.used or 0, state.capacity or 4)
end

-- ===== opening and closing =====
-- The bag only opens while your bodega is standing somewhere on the island.
PanelUtil.Register("bag", {
	open = function()
		if player:GetAttribute("BodegaUp") ~= true then
			showToast("Place your bodega first -- Bag menu, then Place bodega.", false)
			return
		end
		shop.Visible = false
		bag.Visible = true
		refreshBag()
	end,
	close = function()
		bag.Visible = false
	end,
	isOpen = function()
		return bag.Visible
	end,
	stayOpen = function()
		return player:GetAttribute("BodegaUp") == true
	end,
})

-- The Palengke opens from its counter and closes the moment you leave the market.
PanelUtil.Register("palengke", {
	open = function()
		bag.Visible = false
		shop.Visible = true
		refreshShop()
	end,
	close = function()
		shop.Visible = false
	end,
	isOpen = function()
		return shop.Visible
	end,
	stayOpen = function()
		return player:GetAttribute("AtPalengke") == true
	end,
})

onPress(bagClose, function() PanelUtil.Close("bag") end)
onPress(shopClose, function() PanelUtil.Close("palengke") end)

-- the counter prompt at the market stall is the Palengke's only way in
task.spawn(function()
	local isla = workspace:WaitForChild("IslaMarahuyo")
	local counter = isla:WaitForChild("PalengkeCounter", 30)
	local prompt = counter and counter:WaitForChild("PalengkePrompt", 10)
	if not prompt then
		warn("[GearHud] no PalengkeCounter prompt found -- the Palengke cannot be opened")
		return
	end
	prompt.Triggered:Connect(function()
		PanelUtil.Open("palengke", {anchor = counter, radius = 22})
	end)
end)

-- Opening your own bodega from its prompt lands on the packing tab, pinned to the bodega:
-- walk away and it closes.
bodegaOpen.OnClientEvent:Connect(function(model)
	setBagMode("bodega")
	-- the radius is measured from the hut's centre, so it has to clear the walls first
	local hitbox = model.PrimaryPart
	local halfWidth = hitbox and math.max(hitbox.Size.X, hitbox.Size.Z) / 2 or 0
	PanelUtil.Open("bag", {anchor = model, radius = halfWidth + BODEGA.UseRange + 8})
end)

-- Only the owner is offered Open on a bodega; to everyone else it is just a building they
-- could take an axe to. Enabled is a local-only override, same as ToldaHud's Seize filter.
task.spawn(function()
	local folder = workspace:WaitForChild("IslaMarahuyo"):WaitForChild("Bodegas", 60)
	if not folder then
		return
	end
	local function filter(inst)
		if inst:IsA("ProximityPrompt") and inst.Name == "Open" then
			local model = inst:FindFirstAncestorOfClass("Model")
			inst.Enabled = model ~= nil and model:GetAttribute("OwnerId") == player.UserId
		end
	end
	for _, d in ipairs(folder:GetDescendants()) do
		filter(d)
	end
	folder.DescendantAdded:Connect(filter)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == KEY_BAG then
		PanelUtil.Toggle("bag")
	end
end)

-- ===== dive tip =====
-- Fires the first time a player goes under without the gear that keeps them alive down
-- there. Once per session, and never when they are already carrying both.
local tip = new("TextLabel", {
	Name = "DiveTip", BackgroundColor3 = GROUND, BackgroundTransparency = 0.12,
	BorderSizePixel = 0, Visible = false,
	Size = UDim2.fromOffset(TOUCH and 330 or 372, TOUCH and 86 or 74),
	Position = UDim2.new(0.5, 0, 0.29, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	Font = Enum.Font.Gotham, TextSize = TOUCH and 12.5 or 12, TextWrapped = true,
	TextColor3 = INK,
	Text = "Going deep? Carry an O2 tank and a spare battery from the Palengke -- and you can drop either one for a teammate in trouble.",
}, gui)
round(tip, 8)
new("UIStroke", {Color = Color3.fromRGB(120, 214, 255), Transparency = 0.45, Thickness = 1}, tip)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
}, tip)

local tipShown = false
local function maybeShowTip()
	if tipShown or player:GetAttribute("InWater") ~= true then
		return
	end
	local tanks = (state.items or {}).oxygen or 0
	local charge = tonumber(player:GetAttribute("FlashlightBattery")) or 100
	if tanks > 0 and charge > 40 then
		return -- already properly kitted; no need to nag
	end
	tipShown = true
	tip.Visible = true
	task.delay(9, function()
		tip.Visible = false
	end)
end

-- ===== wiring =====
inventoryUpdated.OnClientEvent:Connect(function(snapshot)
	state = snapshot
	refreshBag()
	refreshShop()
end)

itemFeedback.OnClientEvent:Connect(showToast)
flashlightFeedback.OnClientEvent:Connect(showToast)

for _, attr in ipairs({"AtBodega", "BodegaHealth", "BodegaUp"}) do
	player:GetAttributeChangedSignal(attr):Connect(refreshBag)
end
player:GetAttributeChangedSignal("InWater"):Connect(maybeShowTip)
player:GetAttributeChangedSignal("BrightBeam"):Connect(refreshShop)

clampPanels()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(clampPanels)

refreshBag()
refreshShop()
