-- QuestBootstrap
-- Pushes today's task list to each player once their profile is loaded, answers the
-- client's request for a refresh, and watches for zone visits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local QuestService = require(script.Parent.QuestService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local requestTasks = remotes:FindFirstChild("RequestTasks")
if not requestTasks then
	requestTasks = Instance.new("RemoteFunction")
	requestTasks.Name = "RequestTasks"
	requestTasks.Parent = remotes
end

requestTasks.OnServerInvoke = function(player)
	return QuestService.GetState(player)
end

local function pushWhenReady(player)
	task.spawn(function()
		for _ = 1, 40 do
			if not player.Parent then
				return
			end
			if PlayerProfileService.Get(player.UserId) then
				QuestService.Push(player)
				return
			end
			task.wait(0.5)
		end
	end)
end

Players.PlayerAdded:Connect(pushWhenReady)
for _, player in ipairs(Players:GetPlayers()) do
	pushWhenReady(player)
end

-- Zone proximity check, once a second rather than every frame -- 7 zones and a handful
-- of players makes this trivially cheap, and a second of latency is imperceptible here.
local VISIT_RADIUS = 26
local zonesFolder = Workspace:WaitForChild("IslaMarahuyo"):WaitForChild("Zones")

task.spawn(function()
	while true do
		task.wait(1)
		local zones = zonesFolder:GetChildren()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				for _, zone in ipairs(zones) do
					if zone:IsA("BasePart") and (zone.Position - root.Position).Magnitude <= VISIT_RADIUS then
						QuestService.NoteZoneVisit(player, zone.Name)
					end
				end
			end
		end
	end
end)

print("[QuestBootstrap] island tasks ready")
