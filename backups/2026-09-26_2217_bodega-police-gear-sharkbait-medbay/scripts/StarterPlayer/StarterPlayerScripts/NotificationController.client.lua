-- NotificationController
-- Surfaces daily-login and fiesta announcements as system chat messages -- visible
-- immediately without needing any custom UI open.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dailyRewardClaimed = remotes:WaitForChild("DailyRewardClaimed")
local fiestaStatusUpdated = remotes:WaitForChild("FiestaStatusUpdated")
local vendorFeedback = remotes:WaitForChild("VendorFeedback")
local ferryFeedback = remotes:WaitForChild("FerryFeedback")
local diveFeedback = remotes:WaitForChild("DiveFeedback")
local boatFeedback = remotes:WaitForChild("BoatFeedback")

local function announce(text, color)
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color or Color3.fromRGB(230, 210, 170),
			Font = Enum.Font.GothamMedium,
		})
	end)
end

dailyRewardClaimed.OnClientEvent:Connect(function(reward, streak)
	announce(string.format("Daily login streak: day %d -- +%d Shells!", streak, reward), Color3.fromRGB(31, 170, 150))
end)

-- The restock cycle depends on hitting the crates in order, so it needs to say which
-- crate is next -- otherwise a wrong crate silently resets progress and reads as broken.
local GOOD = Color3.fromRGB(120, 210, 180)
local BAD = Color3.fromRGB(226, 140, 90)

vendorFeedback.OnClientEvent:Connect(function(text, ok)
	announce(text, ok and GOOD or BAD)
end)

ferryFeedback.OnClientEvent:Connect(function(text, ok)
	announce(text, ok and GOOD or BAD)
end)

local DIVE_COLORS = {
	drown = Color3.fromRGB(226, 140, 90),
	rescue = Color3.fromRGB(120, 210, 180),
	upgrade = Color3.fromRGB(120, 210, 180),
	treasure = Color3.fromRGB(210, 190, 120),
	harvest = Color3.fromRGB(150, 210, 235),
	shark = Color3.fromRGB(240, 110, 96),
	explore = Color3.fromRGB(150, 205, 225),
	badge = Color3.fromRGB(245, 200, 90),
	crystal = Color3.fromRGB(120, 240, 255),
	sign = Color3.fromRGB(215, 190, 150),
}

diveFeedback.OnClientEvent:Connect(function(kind, text)
	announce(text, DIVE_COLORS[kind] or Color3.fromRGB(230, 210, 170))
end)

boatFeedback.OnClientEvent:Connect(function(text, ok)
	announce(text, ok and GOOD or BAD)
end)

local announcedActiveOnce = false
fiestaStatusUpdated.OnClientEvent:Connect(function(text, active)
	if active and not announcedActiveOnce then
		announcedActiveOnce = true
		announce(text, Color3.fromRGB(230, 130, 60))
	elseif not active then
		announcedActiveOnce = false
	end
end)
