-- UseTank
-- Equip the tank and click (or tap) to crack it. Living in the hotbar is the point: on a
-- phone that is one thumb tap while you are drowning, instead of opening a bag menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent
local requestItemUse = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestItemUse")

local COOLDOWN = 1
local lastUse = 0

tool.Activated:Connect(function()
	local now = os.clock()
	if now - lastUse < COOLDOWN then
		return
	end
	lastUse = now
	requestItemUse:FireServer("oxygen")
end)
