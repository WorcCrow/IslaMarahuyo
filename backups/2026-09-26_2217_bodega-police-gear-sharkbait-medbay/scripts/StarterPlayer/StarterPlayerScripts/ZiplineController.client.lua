-- ZiplineController
-- Rides the line. The character is dragged along the cable frame by frame with a trolley
-- overhead and the same sag the cable was built with, so the trip is watched, not skipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ziplineStatus = remotes:WaitForChild("ZiplineStatus")

local riding = false

local function announce(text, color)
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color or Color3.fromRGB(230, 210, 170),
			Font = Enum.Font.GothamMedium,
		})
	end)
end

-- same curve the cable segments were built along
local function pointOnCable(a, b, t)
	local span = (b - a).Magnitude
	local base = a:Lerp(b, t)
	local sag = math.sin(t * math.pi) * math.min(9, span * 0.02)
	return base - Vector3.new(0, sag, 0)
end

local function ride(a, b, duration, destinationName)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and hrp) then
		return
	end

	riding = true
	humanoid.PlatformStand = true
	hrp.Anchored = true

	-- trolley riding the cable above the player
	local trolley = Instance.new("Part")
	trolley.Name = "ZipTrolley"
	trolley.Size = Vector3.new(1.4, 0.8, 2.2)
	trolley.Material = Enum.Material.Metal
	trolley.Color = Color3.fromRGB(198, 176, 120)
	trolley.Anchored = true
	trolley.CanCollide = false
	trolley.CanQuery = false
	trolley.Parent = workspace

	local strap = Instance.new("Part")
	strap.Name = "ZipStrap"
	strap.Size = Vector3.new(0.2, 4.4, 0.2)
	strap.Material = Enum.Material.Fabric
	strap.Color = Color3.fromRGB(60, 52, 44)
	strap.Anchored = true
	strap.CanCollide = false
	strap.CanQuery = false
	strap.Parent = workspace

	local wind = Instance.new("Sound")
	wind.SoundId = "rbxassetid://9112775414"
	wind.Volume = 0.25
	wind.Looped = true
	wind.Parent = hrp
	wind:Play()

	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - t0
		local t = math.clamp(elapsed / duration, 0, 1)
		-- ease out of the platform and into the landing
		local eased = t * t * (3 - 2 * t)
		local cablePoint = pointOnCable(a, b, eased)
		local facing = (b - a) * Vector3.new(1, 0, 1)
		if facing.Magnitude < 0.1 then
			facing = Vector3.new(0, 0, 1)
		end

		trolley.CFrame = CFrame.lookAt(cablePoint, cablePoint + facing.Unit)
		strap.CFrame = CFrame.new(cablePoint - Vector3.new(0, 2.4, 0))
		-- hang below the line, leaning into the direction of travel
		hrp.CFrame = CFrame.lookAt(cablePoint - Vector3.new(0, 4.6, 0), cablePoint - Vector3.new(0, 4.6, 0) + facing.Unit)
			* CFrame.Angles(math.rad(-14), 0, 0)

		if t >= 1 then
			conn:Disconnect()
		end
	end)

	task.delay(duration + 0.05, function()
		if conn.Connected then
			conn:Disconnect()
		end
		wind:Stop()
		wind:Destroy()
		trolley:Destroy()
		strap:Destroy()
		-- set down on the landing platform
		hrp.Anchored = false
		humanoid.PlatformStand = false
		hrp.CFrame = CFrame.new(b - Vector3.new(0, 3.4, 0))
		hrp.AssemblyLinearVelocity = Vector3.zero
		riding = false
		ziplineStatus:FireServer("arrived")
		announce("Landed at " .. tostring(destinationName) .. ".", Color3.fromRGB(120, 210, 180))
	end)
end

ziplineStatus.OnClientEvent:Connect(function(kind, a, b, duration, destinationName)
	if kind == "ride" and not riding then
		ride(a, b, duration, destinationName)
	elseif kind == "denied" then
		announce(tostring(a), Color3.fromRGB(226, 140, 90))
	elseif kind == "charged" then
		announce(tostring(a), Color3.fromRGB(210, 190, 120))
	end
end)

-- never leave a character stuck anchored if it respawns mid-ride
player.CharacterAdded:Connect(function()
	riding = false
end)
