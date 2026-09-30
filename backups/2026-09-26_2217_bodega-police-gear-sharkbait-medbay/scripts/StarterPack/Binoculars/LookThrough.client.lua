-- LookThrough
-- Holding the binoculars is looking through them. BinocularController does the view; this
-- only flips the local BinocularsOn flag it follows (client-set attributes never replicate).

local Players = game:GetService("Players")

local tool = script.Parent
local player = Players.LocalPlayer

tool.Equipped:Connect(function()
	player:SetAttribute("BinocularsOn", true)
end)

tool.Unequipped:Connect(function()
	player:SetAttribute("BinocularsOn", false)
end)

-- a respawn or a hotbar re-seat destroys this copy while held; never leave the view stuck on
script.Destroying:Connect(function()
	if player:GetAttribute("BinocularsOn") then
		player:SetAttribute("BinocularsOn", false)
	end
end)
