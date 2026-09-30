-- Hotbar
-- Replaces Roblox's built-in backpack bar. The built-in one can only show a tool's NAME
-- (a picture needs an uploaded TextureId per tool) and has nowhere to say how many tanks
-- or sticks are left. This one renders each tool's own model in a ViewportFrame, so no
-- image assets exist to keep in sync, and puts the count on the slot.
--
-- It only displays and equips. What a player owns is still decided by InventoryService,
-- which puts Tool instances in the Backpack; this reads whatever is there.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemIcon = require(ReplicatedStorage:WaitForChild("ItemIcon"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local inventoryUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryUpdated")

local TOUCH = UserInputService.TouchEnabled
local SLOT = TOUCH and 50 or 56
local GAP = 6
local MAX_SLOTS = 9

local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 172, 184)
local AMBER = Color3.fromRGB(232, 168, 64)
local LOW = Color3.fromRGB(235, 96, 80)
local GROUND = Color3.fromRGB(10, 18, 24)

-- mirrors InventoryService's HOTBAR_RANK, so the order does not change on respawn
local ORDER = {Flashlight = 1, OxygenTank = 2, Axe = 3, Glowstick = 4, SharkBait = 5, Lambat = 6, Tolda = 7, Binoculars = 8}
-- tools that stand for a stack in the bag: the slot shows how many are left
local COUNT_KEY = {OxygenTank = "oxygen", Glowstick = "glowstick", SharkBait = "sharkbait", Lambat = "lambat"}

local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

-- PhotoModeController switches ALL core gui back on when it closes, so this is retried
-- from there as well; SetCore can also fail for the first few frames after join.
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			return
		end
		task.wait(0.5)
	end
end)

local counts = {}

local gui = Instance.new("ScreenGui")
gui.Name = "Hotbar"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = playerGui

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -10)
bar.Size = UDim2.fromOffset(0, SLOT)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundTransparency = 1
bar.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

-- ===== slots =====
local slots = {} -- [tool] = slot record

local function toggle(tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

local function makeSlot(tool)
	local button = Instance.new("TextButton")
	button.Name = tool.Name
	button.Size = UDim2.fromOffset(SLOT, SLOT)
	button.BackgroundColor3 = GROUND
	button.BackgroundTransparency = 0.25
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = ""
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = DIM
	stroke.Transparency = 0.5
	stroke.Parent = button

	local view = ItemIcon.View(tool, button)
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -4, 1, 0)
	name.Position = UDim2.fromOffset(2, 0)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 10
	name.TextWrapped = true
	name.TextColor3 = INK
	name.Text = tool.Name
	name.Visible = view == nil -- only when there was nothing to draw
	name.Parent = button

	-- InventoryService re-seats the backpack by unparenting every tool, and a tool coming
	-- back can land here a moment before its parts do: keep trying for a few seconds.
	if not view then
		task.spawn(function()
			for _ = 1, 10 do
				task.wait(0.3)
				if not button.Parent or button:FindFirstChild("View") then
					return
				end
				if ItemIcon.View(tool, button) then
					name.Visible = false
					return
				end
			end
		end)
	end

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Position = UDim2.fromOffset(4, 2)
	key.Size = UDim2.fromOffset(14, 14)
	key.Font = Enum.Font.GothamBold
	key.TextSize = 11
	key.TextColor3 = DIM
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.Visible = not TOUCH
	key.ZIndex = 3
	key.Parent = button

	local badge = Instance.new("TextLabel")
	badge.Name = "Count"
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.new(1, -3, 1, -2)
	badge.Size = UDim2.fromOffset(0, 15)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = GROUND
	badge.BackgroundTransparency = 0.15
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 11
	badge.TextColor3 = AMBER
	badge.Visible = false
	badge.ZIndex = 3
	badge.Parent = button
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingRight = UDim.new(0, 3)
	pad.Parent = badge

	button.Activated:Connect(function()
		toggle(tool)
	end)

	return {button = button, stroke = stroke, key = key, badge = badge}
end

local function paintBadge(tool, slot)
	local badge = slot.badge
	local key = COUNT_KEY[tool.Name]
	if key then
		badge.Text = "x" .. tostring(counts[key] or 0)
		badge.TextColor3 = AMBER
		badge.Visible = true
	elseif tool.Name == "Flashlight" then
		-- the torch has no stack of its own: its charge, and the spares in the bag
		local charge = math.floor(tonumber(player:GetAttribute("FlashlightBattery")) or 100)
		local spares = counts.battery or 0
		badge.Text = spares > 0 and string.format("%d%% +%d", charge, spares) or string.format("%d%%", charge)
		badge.TextColor3 = charge <= 20 and LOW or AMBER
		badge.Visible = true
	else
		badge.Visible = false
	end
end

local ordered = {}

local function currentTools()
	local list = {}
	for _, holder in ipairs({player:FindFirstChildOfClass("Backpack"), player.Character}) do
		if holder then
			for _, t in ipairs(holder:GetChildren()) do
				if t:IsA("Tool") then
					table.insert(list, t)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = ORDER[a.Name] or 50, ORDER[b.Name] or 50
		if ra ~= rb then
			return ra < rb
		end
		return a.Name < b.Name
	end)
	return list
end

local function rebuild()
	local list = currentTools()
	local alive = {}
	ordered = {}
	for i, tool in ipairs(list) do
		if i > MAX_SLOTS then
			break
		end
		alive[tool] = true
		local slot = slots[tool]
		if not slot then
			slot = makeSlot(tool)
			slots[tool] = slot
		end
		slot.button.LayoutOrder = i
		slot.button.Parent = bar
		slot.key.Text = tostring(i)
		local equipped = player.Character ~= nil and tool.Parent == player.Character
		slot.stroke.Color = equipped and AMBER or DIM
		slot.stroke.Thickness = equipped and 2 or 1
		slot.stroke.Transparency = equipped and 0 or 0.5
		paintBadge(tool, slot)
		ordered[i] = tool
	end
	for tool, slot in pairs(slots) do
		if not alive[tool] then
			slot.button:Destroy()
			slots[tool] = nil
		end
	end
end

-- InventoryService re-seats the backpack by unparenting and reparenting every tool, so a
-- burst of Added/Removed events arrives at once; fold them into one rebuild.
local pending = false
local function queue()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		rebuild()
	end)
end

local function watch(holder)
	if not holder then
		return
	end
	holder.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			queue()
		end
	end)
	holder.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			queue()
		end
	end)
	queue()
end

player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then
		watch(c)
	end
end)
watch(player:FindFirstChildOfClass("Backpack"))
player.CharacterAdded:Connect(watch)
watch(player.Character)

inventoryUpdated.OnClientEvent:Connect(function(snapshot)
	counts = (snapshot and snapshot.items) or {}
	queue()
end)
player:GetAttributeChangedSignal("FlashlightBattery"):Connect(queue)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	for i, code in ipairs(KEYS) do
		if input.KeyCode == code then
			local tool = ordered[i]
			if tool then
				toggle(tool)
			end
			return
		end
	end
end)
