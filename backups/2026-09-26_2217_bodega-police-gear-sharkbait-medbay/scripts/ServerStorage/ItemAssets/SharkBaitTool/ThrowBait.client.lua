-- ThrowBait
-- Holding the bait is the lure; clicking (tapping) throws it at the aim point as a decoy.
-- The server decides where it actually lands and whether the throw counts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local requestBaitThrow = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestBaitThrow")

local COOLDOWN = 0.8
local last = 0

tool.Activated:Connect(function()
	if os.clock() - last < COOLDOWN then
		return
	end
	last = os.clock()
	local aim = mouse.Hit and mouse.Hit.Position
	if not aim then
		local camera = workspace.CurrentCamera
		aim = camera.CFrame.Position + camera.CFrame.LookVector * 30
	end
	requestBaitThrow:FireServer(aim)
end)
