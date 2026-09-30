local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("TutorialGui")
local panel = gui.Panel
local overlay = gui.Overlay
local closeBtn = panel.CloseButton

local SHOWN_ATTR = "IslaMarahuyo_TutorialShown"

local function hide()
	gui.Enabled = false
end

local function show()
	gui.Enabled = true
	panel.Size = UDim2.fromOffset(0, 0)
	panel:TweenSize(UDim2.fromOffset(560, 460), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.35, true)
end

-- Reopened from the top bar's menu (TopBarController). Going through PanelUtil frees the
-- cursor, so Close is clickable even when joining zoomed into first person.
PanelUtil.Register("help", {
	open = show,
	close = hide,
	isOpen = function() return gui.Enabled end,
})

closeBtn.MouseButton1Click:Connect(function()
	PanelUtil.Close("help")
end)
overlay.InputBegan:Connect(function(input)
	-- clicking the dark backdrop does nothing (avoid accidental dismiss) -- intentional no-op
end)

-- Show once per client session on join
if not player:GetAttribute(SHOWN_ATTR) then
	player:SetAttribute(SHOWN_ATTR, true)
	gui.Enabled = false
	task.wait(1.2)
	PanelUtil.Open("help")
else
	gui.Enabled = false
end
