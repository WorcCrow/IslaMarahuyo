-- StatusHud
-- The one column of numbers on the right edge: a sentence (when serving one), sharks, air,
-- torch, and the sack of finds.
--
-- These used to be four widgets owned by four scripts (SharkAlertController's counter,
-- ScubaHUD's breath bar, GearHud's torch card and finds chip), each placing itself against
-- the right edge on its own. Same failure TopBarLayout once documented for the top strip:
-- fine until two pick the same spot. Now it is one list, each row an icon and a number,
-- and rows that do not apply right now (air on dry land, torch not in hand) simply drop out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local TOUCH = UserInputService.TouchEnabled
local ROW_W = TOUCH and 78 or 70
local ROW_H = TOUCH and 32 or 28

local INK = Color3.fromRGB(236, 240, 242)
local DIM = Color3.fromRGB(150, 172, 184)
local LOW = Color3.fromRGB(235, 96, 80)
local WARN = Color3.fromRGB(240, 200, 80)
local GROUND = Color3.fromRGB(12, 18, 26)

local SHARK = "\u{1F988}"
local AIR = "\u{1F93F}" -- diving mask
local TORCH = "\u{1F526}"
local SACK = "\u{1F41A}"
local LOCK = "\u{1F512}"
local CRATE = "\u{1F4E6}" -- vendor track jobs left
local MEDKIT = "\u{2795}" -- nurse track jobs left
local BACK_ICON = "\u{21A9}" -- back-to-cell button
local FREE_GREEN = Color3.fromRGB(110, 206, 170)

local gui = Instance.new("ScreenGui")
gui.Name = "StatusHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = playerGui

-- Hung a little above centre: on a phone the bottom-right quarter belongs to the jump
-- button, and four rows at this height clear it even on a 375px-tall landscape screen.
local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(1, 0.5)
column.Position = UDim2.new(1, -10, 0.4, 0)
column.Size = UDim2.fromOffset(ROW_W, (ROW_H + 6) * 7)
column.BackgroundTransparency = 1
column.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = column

local function makeRow(name, glyph, order)
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(ROW_W, ROW_H)
	row.BackgroundColor3 = GROUND
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Parent = column
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 170, 255)
	stroke.Transparency = 0.5
	stroke.Parent = row

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(6, 0)
	icon.Size = UDim2.new(0, ROW_H - 6, 1, 0)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = TOUCH and 17 or 15
	icon.Text = glyph
	icon.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Position = UDim2.fromOffset(0, 0)
	value.Size = UDim2.new(1, -8, 1, 0)
	value.Font = Enum.Font.GothamBold
	value.TextSize = TOUCH and 14 or 13
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = INK
	value.Text = "--"
	value.Parent = row

	return {row = row, value = value, stroke = stroke, icon = icon}
end

-- Two narrow rows, same width as every other row in the column, instead of one wide one:
-- the time left, and (only while on service) the jobs left with a small icon for which job.
local jailRow = makeRow("Jail", LOCK, -3)
jailRow.row.Visible = false
local jobsRow = makeRow("Jobs", CRATE, -2)
jobsRow.row.Visible = false

local backToCell = Instance.new("TextButton")
backToCell.Name = "BackToCell"
backToCell.LayoutOrder = -1
backToCell.Size = UDim2.fromOffset(ROW_W, ROW_H - 4)
backToCell.BackgroundColor3 = GROUND
backToCell.BackgroundTransparency = 0.3
backToCell.BorderSizePixel = 0
backToCell.AutoButtonColor = true
backToCell.Font = Enum.Font.GothamBold
backToCell.TextSize = TOUCH and 15 or 13
backToCell.TextColor3 = DIM
backToCell.Text = BACK_ICON
backToCell.Visible = false
backToCell.Parent = column
Instance.new("UICorner", backToCell).CornerRadius = UDim.new(0, 6)

local sharkRow = makeRow("Sharks", SHARK, 1)
local airRow = makeRow("Air", AIR, 2)
local torchRow = makeRow("Torch", TORCH, 3)
local sackRow = makeRow("Sack", SACK, 4)

-- ===== sharks =====
-- SharkAlertController still owns the danger banner and the scare; this is only the count.
local DANGER_SHARKS = 100
local sharkAlertUpdated = remotes:WaitForChild("SharkAlertUpdated")
sharkAlertUpdated.OnClientEvent:Connect(function(count, _, totalSharks)
	local n = totalSharks or count or 0
	sharkRow.value.Text = tostring(n)
	local danger = n > DANGER_SHARKS
	sharkRow.value.TextColor3 = danger and LOW or INK
	sharkRow.stroke.Color = danger and LOW or Color3.fromRGB(0, 170, 255)
end)

-- ===== air =====
-- Shown in or at the water (the NearWater flag WaterMovementService publishes), plus a few
-- seconds after a rescue/drown/upgrade so those moments still register.
local breathUpdated = remotes:WaitForChild("BreathUpdated")
local diveFeedback = remotes:WaitForChild("DiveFeedback")
local airPct = 100
local flashUntil = 0

local function paintAir()
	airRow.value.Text = string.format("%d%%", airPct)
	local colour = airPct <= 25 and LOW or airPct <= 55 and WARN or INK
	airRow.value.TextColor3 = colour
	airRow.stroke.Color = airPct <= 25 and LOW or Color3.fromRGB(90, 210, 230)
	airRow.row.Visible = player:GetAttribute("NearWater") == true or os.clock() < flashUntil
end

breathUpdated.OnClientEvent:Connect(function(breath, max)
	breath, max = tonumber(breath) or 0, tonumber(max) or 0
	airPct = max > 0 and math.clamp(math.floor(breath / max * 100 + 0.5), 0, 100) or 100
	paintAir()
end)

-- The old breath card had room for a line of text under the bar; the column does not, so
-- these moments pulse the row and float a short word beside it instead.
local flashLabel = Instance.new("TextLabel")
flashLabel.Name = "AirFlash"
flashLabel.BackgroundTransparency = 1
flashLabel.AnchorPoint = Vector2.new(1, 0.5)
flashLabel.Size = UDim2.fromOffset(160, 20)
flashLabel.Font = Enum.Font.GothamBold
flashLabel.TextSize = TOUCH and 14 or 13
flashLabel.TextXAlignment = Enum.TextXAlignment.Right
flashLabel.TextStrokeTransparency = 0.4
flashLabel.TextTransparency = 1
flashLabel.Parent = gui

local FLASHES = {
	rescue = {"Rescued!", Color3.fromRGB(255, 220, 120)},
	upgrade = {"Lung capacity up!", Color3.fromRGB(150, 230, 190)},
	drown = {"Out of air!", Color3.fromRGB(235, 120, 100)},
}
diveFeedback.OnClientEvent:Connect(function(kind)
	local f = FLASHES[kind]
	if not f then
		return
	end
	flashUntil = os.clock() + 3
	paintAir()
	local abs = airRow.row.AbsolutePosition
	flashLabel.Position = UDim2.fromOffset(abs.X - 8, abs.Y + ROW_H / 2)
	flashLabel.Text = f[1]
	flashLabel.TextColor3 = f[2]
	flashLabel.TextTransparency = 0
	TweenService:Create(flashLabel, TweenInfo.new(2.4), {TextTransparency = 1}):Play()
end)

player:GetAttributeChangedSignal("NearWater"):Connect(paintAir)

-- ===== torch =====
-- Only while the flashlight is actually in hand: that is when the number matters.
local function paintTorch()
	local character = player.Character
	torchRow.row.Visible = character ~= nil and character:FindFirstChild("Flashlight") ~= nil
	local charge = math.floor(tonumber(player:GetAttribute("FlashlightBattery")) or 100)
	torchRow.value.Text = string.format("%d%%", charge)
	local low = charge <= 20
	torchRow.value.TextColor3 = low and LOW or INK
	torchRow.stroke.Color = low and LOW or Color3.fromRGB(232, 168, 64)
end

player:GetAttributeChangedSignal("FlashlightBattery"):Connect(paintTorch)
local function watchCharacter(character)
	character.ChildAdded:Connect(paintTorch)
	character.ChildRemoved:Connect(paintTorch)
	paintTorch()
end
if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

-- ===== the sack =====
-- Finds are not bag items and have no cap; the count only shows once there is something
-- in it, and the Palengke value rides along so you know what the swim home is worth.
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
inventoryUpdated.OnClientEvent:Connect(function(snapshot)
	local pieces = snapshot and snapshot.lootPieces or 0
	sackRow.row.Visible = pieces > 0
	sackRow.value.Text = tostring(pieces)
	sackRow.value.TextColor3 = Color3.fromRGB(255, 206, 120)
	sackRow.stroke.Color = Color3.fromRGB(255, 206, 120)
end)

-- ===== the sentence =====
-- PoliceService now ticks JailDays down continuously in real time (both in the cell and on
-- service) and republishes it roughly every 0.3s, so reading the attribute directly is
-- already a smooth live countdown -- no client-side interpolation needed.
local MINUTES_PER_DAY = 24 -- DayNightCycle.CYCLE_MINUTES
local requestJailAction = remotes:WaitForChild("RequestJailAction")

local function paintJail()
	local days = tonumber(player:GetAttribute("JailDays"))
	local jailed = player:GetAttribute("Jailed") == true and days ~= nil and days > 0
	local jobs = player:GetAttribute("ServiceJobsLeft")
	jailRow.row.Visible = jailed
	jobsRow.row.Visible = jailed and jobs ~= nil
	backToCell.Visible = jailed and jobs ~= nil
	if not jailed then
		return
	end

	local colour = jobs and FREE_GREEN or LOW
	jailRow.value.Text = string.format("%dm", math.ceil(days * MINUTES_PER_DAY - 1e-6))
	jailRow.value.TextColor3 = colour
	jailRow.stroke.Color = colour

	if jobs then
		local nurse = player:GetAttribute("ServiceTrack") == "nurse"
		jobsRow.icon.Text = nurse and MEDKIT or CRATE
		jobsRow.value.Text = tostring(jobs)
		jobsRow.value.TextColor3 = FREE_GREEN
		jobsRow.stroke.Color = FREE_GREEN
	end
end

backToCell.Activated:Connect(function()
	requestJailAction:FireServer("backToCell")
end)
for _, name in ipairs({"Jailed", "JailDays", "ServiceJobsLeft", "ServiceTrack"}) do
	player:GetAttributeChangedSignal(name):Connect(paintJail)
end

sackRow.row.Visible = false
paintAir()
paintTorch()
paintJail()
