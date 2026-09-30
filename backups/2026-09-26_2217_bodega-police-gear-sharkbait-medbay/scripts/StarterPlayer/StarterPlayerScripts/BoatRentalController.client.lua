-- BoatRentalController
-- The hire panel at the Bangkaan, plus the live rental countdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("BoatGui")
local panel = gui:WaitForChild("HirePanel")
local optionsFrame = panel:WaitForChild("Options")
local timer = gui:WaitForChild("Timer")
local timerLabel = timer:WaitForChild("Label")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRental = remotes:WaitForChild("RequestBoatRental")

local currentBoat = nil

local function closePanel()
	panel.Visible = false
	currentBoat = nil
	-- release the cursor lock the panel took
	UserInputService.ModalEnabled = false
end

local function choose(tierKey)
	if not currentBoat then
		return
	end
	requestRental:FireServer(currentBoat, tierKey)
	closePanel()
end

local TIER_SLOTS = 4

optionsFrame.VIP.Activated:Connect(function() choose("VIP") end)
for i = 1, TIER_SLOTS do
	local btn = optionsFrame:FindFirstChild("Tier" .. i)
	if btn then
		btn.Activated:Connect(function()
			choose(btn:GetAttribute("TierKey"))
		end)
	end
end
panel.Cancel.Activated:Connect(closePanel)

requestRental.OnClientEvent:Connect(function(kind, boatName, options, isVip)
	if kind ~= "open" then
		return
	end
	currentBoat = boatName
	panel.Title.Text = "Hire " .. (boatName:gsub("RentalBoat_", "Bangka "))

	optionsFrame.VIP.Visible = isVip == true
	optionsFrame.VIP.Text = "  Ride free  --  Kasama VIP, 10 min"
	optionsFrame.VIP.TextXAlignment = Enum.TextXAlignment.Left
	optionsFrame.VIP.BackgroundColor3 = Color3.fromRGB(58, 48, 26)

	for i = 1, TIER_SLOTS do
		local btn = optionsFrame:FindFirstChild("Tier" .. i)
		local opt = options and options[i]
		if btn then
			if opt then
				btn.Visible = true
				btn.TextXAlignment = Enum.TextXAlignment.Left
				btn.Text = string.format("  %s  --  %d min  --  %d Shells", opt.label, opt.minutes, opt.price)
				btn:SetAttribute("TierKey", opt.key)
			else
				btn.Visible = false
			end
		end
	end

	panel.Visible = true
	-- shift lock would pin the cursor and make the panel unclickable, same bug the market had
	UserInputService.ModalEnabled = true
end)

-- live countdown, driven off the attribute the server sets
task.spawn(function()
	while true do
		task.wait(0.25)
		local endsAt = player:GetAttribute("BoatRentalEndsAt")
		if endsAt then
			local remaining = math.max(0, endsAt - os.time())
			local prefix = player:GetAttribute("BoatRentalVIP") and "Bangka (VIP)" or "Bangka"
			timer.Visible = true
			timerLabel.Text = string.format("%s  %d:%02d", prefix, math.floor(remaining / 60), remaining % 60)
			timerLabel.TextColor3 = remaining <= 60 and Color3.fromRGB(236, 150, 120) or Color3.fromRGB(232, 216, 180)
		else
			timer.Visible = false
		end
	end
end)
