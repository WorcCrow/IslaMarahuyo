-- SharkBaitService
-- Shark bait is one item with two uses. HELD, it is a lure: every shark that can smell it
-- comes for whoever is holding it -- set a lambat and stand in it, or draw the sharks off a
-- teammate. THROWN, it is a decoy: the sharks go for where it landed instead of you.
-- The first shark to reach it eats it, held or thrown.
--
-- Priority (enforced in SharkService): held bait > thrown bait > a plain swimmer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local SharkLure = require(script.Parent.SharkLure)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestBaitThrow = remotes:FindFirstChild("RequestBaitThrow")
if not requestBaitThrow then
	requestBaitThrow = Instance.new("RemoteEvent")
	requestBaitThrow.Name = "RequestBaitThrow"
	requestBaitThrow.Parent = remotes
end
local itemFeedback = remotes:WaitForChild("ItemFeedback")
local refreshSignal = ServerStorage:WaitForChild("InventoryRefresh")
local baitPrefab = ServerStorage:WaitForChild("ItemAssets"):WaitForChild("SharkBait")

local TOOL_NAME = "SharkBait"
local THROW_RANGE = 45
local MIN_THROW = 6
local THROW_COOLDOWN = 0.8
-- long enough to lie inside a lambat while the sharks converge on it
local BAIT_SECONDS = 90
local DUD_SECONDS = 15 -- one that landed on dry ground, before it is cleared away

local isla = workspace:WaitForChild("IslaMarahuyo")
local folder = isla:FindFirstChild("ThrownBait")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ThrownBait"
	folder.Parent = isla
end

local landParams = RaycastParams.new()
landParams.FilterType = Enum.RaycastFilterType.Exclude
landParams.IgnoreWater = false

local seabedParams = RaycastParams.new()
seabedParams.FilterType = Enum.RaycastFilterType.Include
seabedParams.FilterDescendantsInstances = {workspace.Terrain}
seabedParams.IgnoreWater = true

local lastThrow = {}

local function say(player, message, ok)
	if player and player.Parent then
		itemFeedback:FireClient(player, message, ok and true or false)
	end
end

local function takeOne(player)
	local profile = PlayerProfileService.Get(player.UserId)
	local gear = profile and profile.Gear
	local have = gear and gear.sharkbait or 0
	if have <= 0 then
		return false
	end
	gear.sharkbait = have > 1 and have - 1 or nil
	refreshSignal:Fire(player) -- InventoryService re-syncs the hotbar tool and the counts
	return true
end

SharkLure.EatHeld = function(player)
	if takeOne(player) then
		say(player, "A pating tore the bait off your hook.", false)
	end
end

SharkLure.OnEaten = function(bait)
	if bait.model and bait.model.Parent then
		bait.model:Destroy()
	end
	say(bait.owner, "A pating took your bait.", true)
end

local function spawnBait(at)
	local model = baitPrefab:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(235, 80, 70)
	glow.Brightness = 1.6
	glow.Range = 12
	glow.Shadows = false
	glow.Parent = model.PrimaryPart
	model:PivotTo(CFrame.new(at))
	model.Parent = folder
	return model
end

requestBaitThrow.OnServerEvent:Connect(function(player, aim)
	if typeof(aim) ~= "Vector3" or aim.Magnitude ~= aim.Magnitude or aim.Magnitude > 1e6 then
		return
	end
	local now = os.clock()
	if now - (lastThrow[player.UserId] or 0) < THROW_COOLDOWN then
		return
	end
	local character = player.Character
	local tool = character and character:FindFirstChild(TOOL_NAME)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (tool and root and humanoid and humanoid.Health > 0) then
		return
	end
	lastThrow[player.UserId] = now

	-- The client only says where it aimed. How far it goes is decided here.
	local flatDir = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	local reach = flatDir.Magnitude
	if reach < 0.5 then
		flatDir = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		reach = THROW_RANGE / 2
	end
	reach = math.clamp(reach, MIN_THROW, THROW_RANGE)
	local landXZ = root.Position + flatDir.Unit * reach

	landParams.FilterDescendantsInstances = {character, folder}
	local hit = workspace:Raycast(Vector3.new(landXZ.X, root.Position.Y + 60, landXZ.Z), Vector3.new(0, -300, 0), landParams)
	if not hit then
		return -- off the edge of the world; keep the bait
	end
	if not takeOne(player) then
		return
	end

	local inWater = hit.Material == Enum.Material.Water
	local landing = hit.Position
	local sharkPos
	if inWater then
		-- sharks keep a couple of studs under the surface, so the spot they swim to is below it
		local seabed = workspace:Raycast(landing - Vector3.new(0, 1, 0), Vector3.new(0, -300, 0), seabedParams)
		local floorY = seabed and seabed.Position.Y or (landing.Y - 50)
		sharkPos = Vector3.new(landing.X, math.max(floorY + 4, landing.Y - 3), landing.Z)
	end

	local handle = tool:FindFirstChild("Handle")
	local start = handle and handle.Position or (root.Position + Vector3.new(0, 1.5, 0))
	local rest = landing + Vector3.new(0, inWater and 0.1 or 0.35, 0)
	local model = spawnBait(start)
	local flight = 0.25 + reach / 70
	local peak = 4 + reach * 0.15

	task.spawn(function()
		local t0 = os.clock()
		while model.Parent do
			local a = math.min((os.clock() - t0) / flight, 1)
			local pos = start:Lerp(rest, a) + Vector3.new(0, math.sin(a * math.pi) * peak, 0)
			model:PivotTo(CFrame.new(pos) * CFrame.Angles(a * 8, 0, a * 3))
			if a >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end

		if not inWater then
			say(player, "The bait landed on dry ground -- no pating will come for it there.", false)
			Debris:AddItem(model, DUD_SECONDS)
			return
		end

		local bait = {pos = sharkPos, model = model, owner = player, expiresAt = os.clock() + BAIT_SECONDS}
		SharkLure.Add(bait)
		say(player, "Bait's in the water -- every pating nearby will want it more than you.", true)
		task.delay(BAIT_SECONDS, function()
			if not bait.gone then
				SharkLure.Remove(bait)
				if model.Parent then
					model:Destroy()
				end
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastThrow[player.UserId] = nil
end)

print(string.format("[SharkBaitService] bait ready -- %d-stud throw, %ds in the water", THROW_RANGE, BAIT_SECONDS))
