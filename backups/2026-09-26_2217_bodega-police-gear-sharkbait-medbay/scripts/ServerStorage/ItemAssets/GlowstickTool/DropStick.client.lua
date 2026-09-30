-- DropStick
-- Equip and click (tap) to leave a lit stick behind you. Replaces the old on-screen
-- DROP LIGHT button: the hotbar slot is the button now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent
local requestItemDrop = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestItemDrop")

local COOLDOWN = 0.5 -- the server refuses drops closer together than 0.4s anyway
local last = 0

tool.Activated:Connect(function()
	if os.clock() - last < COOLDOWN then
		return
	end
	last = os.clock()
	requestItemDrop:FireServer("glowstick")
end)
