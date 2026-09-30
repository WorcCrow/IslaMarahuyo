-- FiestaBootstrap
-- Broadcasts fiesta status to players, toggles the plaza's festival lights, and
-- re-checks once a minute so a server that's been up for a while still flips on time.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FiestaEventService = require(script.Parent.FiestaEventService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fiestaStatusUpdated = remotes:WaitForChild("FiestaStatusUpdated")

local plazaLights = Workspace.IslaMarahuyo.Activities.PlazaStage.FiestaLights

local function setLightsActive(active)
	for _, bulb in ipairs(plazaLights:GetChildren()) do
		if bulb:IsA("BasePart") then
			bulb.Material = active and Enum.Material.Neon or Enum.Material.SmoothPlastic
			local pointLight = bulb:FindFirstChildOfClass("PointLight")
			if pointLight then
				pointLight.Enabled = active
			end
		end
	end
end

local function broadcastStatus()
	local active = FiestaEventService.IsActive()
	setLightsActive(active)
	fiestaStatusUpdated:FireAllClients(FiestaEventService.GetStatusText(), active)
	return active
end

Players.PlayerAdded:Connect(function(player)
	fiestaStatusUpdated:FireClient(player, FiestaEventService.GetStatusText(), FiestaEventService.IsActive())
end)

local lastActive = broadcastStatus()

task.spawn(function()
	while true do
		task.wait(60)
		local nowActive = FiestaEventService.IsActive()
		if nowActive ~= lastActive then
			lastActive = broadcastStatus()
		end
	end
end)

print("[FiestaBootstrap] Live-ops calendar running --", FiestaEventService.GetStatusText())
