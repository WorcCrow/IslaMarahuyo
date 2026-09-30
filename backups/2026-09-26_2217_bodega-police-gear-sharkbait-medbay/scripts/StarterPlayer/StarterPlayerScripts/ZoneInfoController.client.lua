local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ZoneInfoGui")
local panel = gui.Panel

local zonesFolder = workspace:WaitForChild("IslaMarahuyo"):WaitForChild("Zones")

local hideTask = nil

local function showZoneInfo(sign)
	panel.Title.Text = sign:GetAttribute("ZoneDisplayName") or "Zone"
	panel.Description.Text = sign:GetAttribute("ZoneDescription") or ""
	panel.Hint.Text = sign:GetAttribute("ZoneHint") or ""
	gui.Enabled = true

	if hideTask then
		task.cancel(hideTask)
	end
	hideTask = task.delay(6, function()
		gui.Enabled = false
	end)
end

local function hookSign(sign)
	local prompt = sign:FindFirstChild("ZoneInfoPrompt")
	if prompt then
		prompt.Triggered:Connect(function()
			showZoneInfo(sign)
		end)
	end
end

for _, zone in ipairs(zonesFolder:GetChildren()) do
	local sign = zone:FindFirstChild("SignBoard")
	if sign then
		hookSign(sign)
	end
end

zonesFolder.ChildAdded:Connect(function(zone)
	local sign = zone:WaitForChild("SignBoard", 5)
	if sign then
		hookSign(sign)
	end
end)
