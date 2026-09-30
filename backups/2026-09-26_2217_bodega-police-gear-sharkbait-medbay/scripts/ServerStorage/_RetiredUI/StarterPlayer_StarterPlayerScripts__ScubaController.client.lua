-- ScubaController
-- Drives the underwater breath meter HUD: fill color shifts green -> amber -> red as air
-- runs low, and dive/rescue/upgrade moments get a small flash so they register even if
-- the player isn't staring at the bar.
--
-- Visibility is driven entirely by the NearWater attribute that WaterMovementService
-- publishes -- the meter belongs on screen when you're in or at the water and nowhere
-- else, so it no longer lingers while you walk around the island topping up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScubaHUD")
local frame = gui:WaitForChild("BreathFrame")
local barFill = frame.BarBg.BarFill
local upgradeLabel = frame.UpgradeLabel
local rescueFlash = frame.RescueFlash

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local breathUpdated = remotes:WaitForChild("BreathUpdated")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

local BASE_BREATH = 45
local UPGRADE_BONUS = 15

local flashUntil = 0

local function colorFor(frac)
	if frac > 0.55 then
		return Color3.fromRGB(90, 210, 230)
	elseif frac > 0.25 then
		return Color3.fromRGB(240, 200, 80)
	else
		return Color3.fromRGB(235, 90, 80)
	end
end

breathUpdated.OnClientEvent:Connect(function(breath, max, swimming)
	local frac = max > 0 and (breath / max) or 1
	TweenService:Create(barFill, TweenInfo.new(0.15), { Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0) }):Play()
	barFill.BackgroundColor3 = colorFor(frac)
	local upgrades = math.floor(((max - BASE_BREATH) / UPGRADE_BONUS) + 0.5)
	upgradeLabel.Text = string.format("Lung Corals: %d/3", math.clamp(upgrades, 0, 3))
end)

-- Show the meter only in or at the water (plus briefly while a flash message is up).
task.spawn(function()
	while true do
		task.wait(0.15)
		local nearWater = player:GetAttribute("NearWater") == true
		frame.Visible = nearWater or os.clock() < flashUntil
	end
end)

local function flash(text, color)
	rescueFlash.Text = text
	rescueFlash.TextColor3 = color
	rescueFlash.TextTransparency = 0
	flashUntil = os.clock() + 3
	frame.Visible = true
	TweenService:Create(rescueFlash, TweenInfo.new(2.2), { TextTransparency = 1 }):Play()
end

diveFeedback.OnClientEvent:Connect(function(kind)
	if kind == "rescue" then
		flash("Rescued!", Color3.fromRGB(255, 220, 120))
	elseif kind == "upgrade" then
		flash("Lung capacity up!", Color3.fromRGB(150, 230, 190))
	elseif kind == "drown" then
		flash("Out of air!", Color3.fromRGB(235, 120, 100))
	end
end)
