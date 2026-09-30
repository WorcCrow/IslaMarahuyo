-- LevelController
-- The level chip and its progress bar are gone from the HUD: a permanently-visible bar
-- creeping toward the next minute is a lot of phone screen spent on a number nobody acts
-- on. Level now lives in the roster panel (the people icon), where you can see everyone's
-- rather than only your own.
--
-- What's kept is the moment that actually carries information: a one-line chat message
-- when you tick over a level. The Level attribute stays authoritative on the player, so
-- the roster and anything else can read it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local levelUpdated = remotes:WaitForChild("LevelUpdated")

levelUpdated.OnClientEvent:Connect(function(level, _progress, levelledUp)
	if levelledUp then
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = string.format("Level %d! Check the roster (people icon) for everyone's.", level),
				Color = Color3.fromRGB(255, 226, 150),
				Font = Enum.Font.GothamMedium,
			})
		end)
	end
end)
