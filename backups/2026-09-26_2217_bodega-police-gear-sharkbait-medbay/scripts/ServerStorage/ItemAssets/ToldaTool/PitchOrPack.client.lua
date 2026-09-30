-- PitchOrPack
-- Equip and click (tap): pitches your stall where you stand, or starts packing it up if
-- one is already standing. Replaces the old floating PITCH TOLDA button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent
local player = Players.LocalPlayer
local requestTolda = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestTolda")

local COOLDOWN = 1
local last = 0

tool.Activated:Connect(function()
	if os.clock() - last < COOLDOWN then
		return
	end
	last = os.clock()
	-- the server sets ToldaUp while this player's stall stands
	requestTolda:FireServer(player:GetAttribute("ToldaUp") == true and "pack" or "pitch")
end)
