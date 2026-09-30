-- AdminDashboardController
-- The admin panel opens from the top bar's menu (TopBarController) through PanelUtil; the
-- old on-screen ADMIN button is gone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("AdminDashboardGui")
local panel = gui.Panel
local feedback = panel.Feedback

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local adminAction = remotes:WaitForChild("AdminAction")
local adminFeedback = remotes:WaitForChild("AdminFeedback")
local adminStatus = remotes:WaitForChild("AdminStatus")

local vipState = false

local function send(actionName, payload)
	adminAction:FireServer(actionName, payload or {})
end

panel.Visible = false
PanelUtil.Register("admin", {
	open = function() panel.Visible = true end,
	close = function() panel.Visible = false end,
	isOpen = function() return gui.Enabled and panel.Visible end,
})
PanelUtil.AddCloseButton(panel, "admin")

-- AmountBox and GrantButton live nested under the Shells row Frame, not directly in panel
local amountBox, grantButton
for _, child in ipairs(panel:GetChildren()) do
	if child:IsA("Frame") then
		local ab = child:FindFirstChild("AmountBox")
		local gb = child:FindFirstChild("GrantButton")
		if ab then amountBox = ab end
		if gb then grantButton = gb end
	end
end

if grantButton then
	grantButton.MouseButton1Click:Connect(function()
		local amount = tonumber(amountBox and amountBox.Text) or 0
		send("GrantShells", { amount = amount })
	end)
end

local vipOn, vipOff
for _, child in ipairs(panel:GetChildren()) do
	if child:IsA("Frame") then
		if child:FindFirstChild("VipOnButton") then vipOn = child.VipOnButton end
		if child:FindFirstChild("VipOffButton") then vipOff = child.VipOffButton end
	end
end
if vipOn then
	vipOn.MouseButton1Click:Connect(function()
		send("SetTestVIP", { enabled = true })
	end)
end
if vipOff then
	vipOff.MouseButton1Click:Connect(function()
		send("SetTestVIP", { enabled = false })
	end)
end

for _, child in ipairs(panel:GetChildren()) do
	if child:IsA("Frame") then
		for _, btnName in ipairs({"ForceFiestaOn", "ForceFiestaOff", "ForceFiestaClear"}) do
			local b = child:FindFirstChild(btnName)
			if b then
				b.MouseButton1Click:Connect(function()
					send(btnName)
				end)
			end
		end
	end
end

local zoneGrid = panel:FindFirstChild("ZoneGrid")
if zoneGrid then
	for _, btn in ipairs(zoneGrid:GetChildren()) do
		if btn:IsA("TextButton") then
			local zoneName = btn.Name:gsub("^Zone_", "")
			btn.MouseButton1Click:Connect(function()
				send("TeleportToZone", { zoneName = zoneName })
			end)
		end
	end
end

local respawnBtn = panel:FindFirstChild("RespawnTreasureButton")
if respawnBtn then
	respawnBtn.MouseButton1Click:Connect(function()
		send("RespawnTreasure")
	end)
end

adminFeedback.OnClientEvent:Connect(function(message, success)
	feedback.Text = tostring(message)
	feedback.TextColor3 = success and Color3.fromRGB(150, 230, 150) or Color3.fromRGB(230, 130, 130)
end)

adminStatus.OnClientEvent:Connect(function(isAdmin)
	gui.Enabled = isAdmin
	-- a local-only flag (client-set attributes never replicate) that tells the top bar
	-- whether to offer the admin entries; the server still checks every admin action
	player:SetAttribute("ClientIsAdmin", isAdmin == true)
end)
