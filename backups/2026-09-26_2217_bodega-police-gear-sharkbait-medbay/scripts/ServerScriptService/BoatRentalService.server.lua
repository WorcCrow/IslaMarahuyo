-- BoatRentalService
-- The Bangkaan: six hireable bangka. Kasama VIP rides free and untimed; everyone else
-- pays Shells for one of three rental lengths or extends an active rental mid-trip.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyService = require(script.Parent.CurrencyService)
local GamePassService = require(script.Parent.GamePassService)
local BreathService = require(script.Parent.BreathService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local boatFeedback = remotes:WaitForChild("BoatFeedback")
local requestRental = remotes:WaitForChild("RequestBoatRental")
local extendRental = remotes:FindFirstChild("ExtendBoatRental") or Instance.new("RemoteEvent", remotes)
extendRental.Name = "ExtendBoatRental"

local port = workspace.IslaMarahuyo.Activities:WaitForChild("Bangkaan")
local boatsFolder = port:WaitForChild("Boats")

-- Boat Speed reduced by 50%
local MAX_SPEED = 27.5 -- Was 55 studs/s
local MAX_TURN = 2.2
local SPEED_PASS_MULTIPLIER = 1.35

local WATER_LINE = 0.8
local LEVEL_GAIN = 4
local LEVEL_MAX = 14

local TIERS = {
	Quick = { label = "Sandali", minutes = 1, price = 15 },
	Short = { label = "Maikli", minutes = 3, price = 40 },
	Medium = { label = "Katamtaman", minutes = 5, price = 70 },
	Long = { label = "Mahaba", minutes = 10, price = 180 },
}
local TIER_ORDER = { "Quick", "Short", "Medium", "Long" }
local VIP_MINUTES = 10 

local rentals = {} -- [boat] = {player=, expiresAt=, tier=, warned60=, warned15=}
local boatOf = {} -- [userId] = boat

--------------------------------------------------------------------------------
-- Bangka Customs -- the BangkaCustom pass.
-- The boats are shared property, so a paint job lasts exactly as long as your rental:
-- applied when you board, put back atom-for-atom when the bangka returns to port. Every
-- part's original colour is captured once at startup, so restoring is exact rather than
-- a guess at what the default was.
--------------------------------------------------------------------------------

local PlayerProfileService = require(script.Parent.PlayerProfileService)

local PAINTS = {
	{ key = "default", label = "Standard" },
	{ key = "pearl", label = "Pearl White", hull = Color3.fromRGB(238, 232, 220), trim = Color3.fromRGB(180, 170, 150), canopy = Color3.fromRGB(206, 198, 182) },
	{ key = "indigo", label = "Indigo Tide", hull = Color3.fromRGB(46, 68, 120), trim = Color3.fromRGB(28, 44, 84), canopy = Color3.fromRGB(214, 196, 150) },
	{ key = "sunrise", label = "Sunrise", hull = Color3.fromRGB(214, 96, 52), trim = Color3.fromRGB(160, 66, 34), canopy = Color3.fromRGB(246, 206, 138) },
	{ key = "palay", label = "Palay Green", hull = Color3.fromRGB(74, 126, 70), trim = Color3.fromRGB(50, 92, 50), canopy = Color3.fromRGB(228, 216, 176) },
	{ key = "ube", label = "Ube", hull = Color3.fromRGB(108, 72, 140), trim = Color3.fromRGB(74, 48, 100), canopy = Color3.fromRGB(226, 208, 236) },
}

local paintByKey = {}
for _, p in ipairs(PAINTS) do
	paintByKey[p.key] = p
end

do -- publish the list so the settings panel and the server can't disagree
	local existing = ReplicatedStorage:FindFirstChild("BangkaPaints")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "BangkaPaints"
	for index, p in ipairs(PAINTS) do
		local cfg = Instance.new("Configuration")
		cfg.Name = string.format("%02d_%s", index, p.key)
		cfg:SetAttribute("Key", p.key)
		cfg:SetAttribute("Label", p.label)
		cfg.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local setPaintRemote = remotes:FindFirstChild("SetBangkaPaint") or Instance.new("RemoteEvent", remotes)
setPaintRemote.Name = "SetBangkaPaint"

local originalColour = {} -- [BasePart] = Color3, captured once

local function rememberColours(boat)
	for _, d in ipairs(boat:GetDescendants()) do
		if d:IsA("BasePart") and originalColour[d] == nil then
			originalColour[d] = d.Color
		end
	end
end

local function slotFor(partName)
	local n = partName:lower()
	if n:find("canopy") or n:find("sail") or n:find("roof") or n:find("awning") then
		return "canopy"
	elseif n:find("katig") or n:find("spar") or n:find("outrigger") or n:find("rail") then
		return "trim"
	elseif n:find("hull") or n:find("prow") or n:find("stern") or n:find("body") or n:find("deck") then
		return "hull"
	end
	return nil -- seats, name plates and prompts keep their own colours
end

local function restorePaint(boat)
	for _, d in ipairs(boat:GetDescendants()) do
		if d:IsA("BasePart") and originalColour[d] then
			d.Color = originalColour[d]
		end
	end
end

local function applyPaint(boat, player)
	restorePaint(boat)
	if not GamePassService.Owns(player, "BangkaCustom") then
		return
	end
	local profile = PlayerProfileService.Get(player.UserId)
	local scheme = paintByKey[profile and profile.BangkaPaint or "default"]
	if not scheme or not scheme.hull then
		return -- "Standard" means leave the boat as built
	end
	for _, d in ipairs(boat:GetDescendants()) do
		if d:IsA("BasePart") then
			local slot = slotFor(d.Name)
			if slot and scheme[slot] then
				d.Color = scheme[slot]
			end
		end
	end
end

setPaintRemote.OnServerEvent:Connect(function(player, key)
	if type(key) ~= "string" or not paintByKey[key] then
		return
	end
	if not GamePassService.Owns(player, "BangkaCustom") then
		return
	end
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return
	end
	profile.BangkaPaint = key
	player:SetAttribute("BangkaPaint", key)
	-- repaint immediately if they're already out on the water
	local boat = boatOf[player.UserId]
	if boat then
		applyPaint(boat, player)
	end
	boatFeedback:FireClient(player, string.format("Bangka paint set to %s.", paintByKey[key].label), true)
end)

local boatRayParams = RaycastParams.new()
boatRayParams.FilterType = Enum.RaycastFilterType.Exclude
boatRayParams.IgnoreWater = true

local function updateRayFilter()
	local filterList = { boatsFolder, port:FindFirstChild("Pier") }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end
	boatRayParams.FilterDescendantsInstances = filterList
end

local function seatInput(seat)
	local throttle = seat.Throttle ~= 0 and seat.Throttle or seat.ThrottleFloat
	local steer = seat.Steer ~= 0 and seat.Steer or seat.SteerFloat
	return throttle, steer
end

local function levelVelocity(hull)
	local hit = workspace:Raycast(hull.Position + Vector3.new(0, 12, 0), Vector3.new(0, -50, 0), boatRayParams)
	local target = WATER_LINE
	if hit then
		target = math.max(target, hit.Position.Y + 1.8)
	end
	return math.clamp((target - hull.Position.Y) * LEVEL_GAIN, -LEVEL_MAX, LEVEL_MAX)
end

local function statusLabel(boat)
	local hull = boat.PrimaryPart
	local plate = hull and hull:FindFirstChildWhichIsA("BillboardGui")
	return plate and plate:FindFirstChild("Status")
end

local function setStatus(boat, text)
	local label = statusLabel(boat)
	if label then
		label.Text = (boat:GetAttribute("BoatName") or "Bangka") .. "\n" .. text
	end
end

local function homeCFrame(boat)
	return CFrame.new(
		boat:GetAttribute("HomeX") or 0,
		boat:GetAttribute("HomeY") or 0,
		boat:GetAttribute("HomeZ") or 0
	) * CFrame.Angles(0, boat:GetAttribute("HomeYaw") or 0, 0)
end

-- Teleport boat directly back to pier slot instantly
local function returnToPortInstantly(boat)
	local hull = boat.PrimaryPart
	if hull then
		hull.AssemblyLinearVelocity = Vector3.zero
		hull.AssemblyAngularVelocity = Vector3.zero
		boat:PivotTo(homeCFrame(boat))
		hull.Anchored = true
	end
	setStatus(boat, "Available")
end

local function endRental(boat, reason)
	local rental = rentals[boat]
	if not rental then
		return
	end
	local player = rental.player
	rentals[boat] = nil
	if player then
		boatOf[player.UserId] = nil
	end

	local seat = boat:FindFirstChild("DriverSeat")
	if seat then
		local occupant = seat.Occupant
		if occupant then
			occupant.Sit = false -- Unseat player into water
		end
		seat.Disabled = true
	end

	if player then
		player:SetAttribute("BoatRentalEndsAt", nil)
		player:SetAttribute("BoatRentalVIP", nil)
	end

	restorePaint(boat) -- the next hirer gets the bangka as it was built

	if player and player.Parent then
		if reason == "expired" then
			local runtime = BreathService.GetRuntime(player)
			if runtime then
				runtime.breath = runtime.max
				player:SetAttribute("Breath", runtime.max)
			end
			boatFeedback:FireClient(player, "Rental expired! The bangka vanished back to port. Swim for shore!", false)
		elseif reason == "returned" then
			boatFeedback:FireClient(player, "Bangka returned. Salamat!", true)
		end
	end

	returnToPortInstantly(boat)
end

local function startRental(player, boat, tierKey)
	local isVip = GamePassService.Owns(player, "KasamaVIP")
	local tier = TIERS[tierKey]

	if boatOf[player.UserId] then
		boatFeedback:FireClient(player, "You already have a bangka out. Return or extend it.", false)
		return
	end
	if rentals[boat] then
		boatFeedback:FireClient(player, "That one's taken -- try another.", false)
		return
	end

	local expiresAt = nil
	local vipRide = false
	if isVip and tierKey == "VIP" then
		vipRide = true
		expiresAt = os.clock() + VIP_MINUTES * 60
	else
		if not tier then
			boatFeedback:FireClient(player, "Pick a rental length first.", false)
			return
		end
		if not CurrencyService.TrySpend(player, tier.price, "BoatRental") then
			boatFeedback:FireClient(player, string.format("Not enough Shells -- %s costs %d.", tier.label, tier.price), false)
			return
		end
		expiresAt = os.clock() + tier.minutes * 60
	end

	rentals[boat] = {
		player = player,
		expiresAt = expiresAt,
		tier = tierKey,
		warned60 = false,
		warned15 = false,
	}
	boatOf[player.UserId] = boat

	applyPaint(boat, player)

	local hull = boat.PrimaryPart
	hull.Anchored = false
	local seat = boat:FindFirstChild("DriverSeat")
	if seat then
		seat.Disabled = false
		task.defer(function()
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				seat:Sit(humanoid)
			end
		end)
	end

	if vipRide then
		player:SetAttribute("BoatRentalEndsAt", os.time() + VIP_MINUTES * 60)
		player:SetAttribute("BoatRentalVIP", true)
		setStatus(boat, "Kasama VIP aboard")
		boatFeedback:FireClient(player, string.format("%s is yours -- Kasama VIP rides free for %d minutes.", boat:GetAttribute("BoatName"), VIP_MINUTES), true)
	else
		player:SetAttribute("BoatRentalEndsAt", os.time() + tier.minutes * 60)
		setStatus(boat, string.format("Hired by %s", player.DisplayName))
		boatFeedback:FireClient(player, string.format("%s hired for %d minutes.", boat:GetAttribute("BoatName"), tier.minutes), true)
	end
end

-- Remote to extend duration mid-ride
extendRental.OnServerEvent:Connect(function(player, tierKey)
	local boat = boatOf[player.UserId]
	if not boat then
		boatFeedback:FireClient(player, "You don't have an active boat rental to extend.", false)
		return
	end

	local rental = rentals[boat]
	if not rental then
		return
	end

	local tier = TIERS[tierKey]
	if not tier then
		boatFeedback:FireClient(player, "Invalid extension option.", false)
		return
	end

	if not CurrencyService.TrySpend(player, tier.price, "BoatExtension") then
		boatFeedback:FireClient(player, string.format("Not enough Shells -- %s costs %d.", tier.label, tier.price), false)
		return
	end

	-- Add time to current expiry
	rental.expiresAt += tier.minutes * 60
	rental.warned60 = false
	rental.warned15 = false

	local currentEnds = player:GetAttribute("BoatRentalEndsAt") or os.time()
	player:SetAttribute("BoatRentalEndsAt", currentEnds + (tier.minutes * 60))

	boatFeedback:FireClient(player, string.format("Rental extended by %d minutes!", tier.minutes), true)
end)

for _, boat in ipairs(boatsFolder:GetChildren()) do
	rememberColours(boat)
	local hull = boat.PrimaryPart
	local prompt = hull and hull:FindFirstChild("HirePrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			if rentals[boat] then
				boatFeedback:FireClient(player, "That one's taken -- try another.", false)
				return
			end
			if boatOf[player.UserId] then
				boatFeedback:FireClient(player, "You already have a bangka out.", false)
				return
			end
			local isVip = GamePassService.Owns(player, "KasamaVIP")
			local options = {}
			for _, key in ipairs(TIER_ORDER) do
				local t = TIERS[key]
				options[#options + 1] = { key = key, label = t.label, minutes = t.minutes, price = t.price }
			end
			requestRental:FireClient(player, "open", boat.Name, options, isVip)
		end)
	end
end

requestRental.OnServerEvent:Connect(function(player, boatName, tierKey)
	local boat = boatsFolder:FindFirstChild(boatName)
	if not boat then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - boat.PrimaryPart.Position).Magnitude > 30 then
		boatFeedback:FireClient(player, "Step over to the bangka first.", false)
		return
	end
	if tierKey == "VIP" and not GamePassService.Owns(player, "KasamaVIP") then
		boatFeedback:FireClient(player, "That's a Kasama VIP perk.", false)
		return
	end
	startRental(player, boat, tierKey)
end)

RunService.Heartbeat:Connect(function()
	for _, boat in ipairs(boatsFolder:GetChildren()) do
		local hull = boat.PrimaryPart
		local seat = boat:FindFirstChild("DriverSeat")
		if hull and seat and not hull.Anchored then
			local maxSpeed = MAX_SPEED
			local occupant = seat.Occupant
			if occupant then
				local driver = Players:GetPlayerFromCharacter(occupant.Parent)
				if driver and driver:GetAttribute("BoatSpeedBoost") then
					maxSpeed *= SPEED_PASS_MULTIPLIER
				end
			end
			local throttle, steer = seatInput(seat)
			local forward = hull.CFrame.LookVector * (throttle * maxSpeed)
			hull.AssemblyLinearVelocity = Vector3.new(forward.X, levelVelocity(hull), forward.Z)
			hull.AssemblyAngularVelocity = Vector3.new(0, -steer * MAX_TURN, 0)
		end
	end

	local now = os.clock()
	for boat, rental in pairs(rentals) do
		if rental.expiresAt then
			local remaining = rental.expiresAt - now
			local player = rental.player
			if player and player.Parent then
				if remaining <= 60 and not rental.warned60 then
					rental.warned60 = true
					boatFeedback:FireClient(player, "One minute left! Extend your rental or head to shore.", false)
				elseif remaining <= 15 and not rental.warned15 then
					rental.warned15 = true
					boatFeedback:FireClient(player, "15 seconds! The bangka will vanish soon.", false)
				end
			end
			-- Teleport directly on expiry
			if remaining <= 0 then
				endRental(boat, "expired")
			end
		end
	end
end)

-- Early return loop
task.spawn(function()
	while true do
		task.wait(2)
		for boat, rental in pairs(rentals) do
			local seat = boat:FindFirstChild("DriverSeat")
			local hull = boat.PrimaryPart
			if seat and hull and not seat.Occupant then
				local home = homeCFrame(boat)
				local distance2D = (Vector3.new(hull.Position.X, 0, hull.Position.Z) - Vector3.new(home.Position.X, 0, home.Position.Z)).Magnitude
				if distance2D < 45 then
					endRental(boat, "returned")
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local boat = boatOf[player.UserId]
	if boat then
		endRental(boat, "left")
	end
	updateRayFilter()
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(updateRayFilter)
	updateRayFilter()
end)

for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		p.CharacterAdded:Connect(updateRayFilter)
	end
end
updateRayFilter()

print("[BoatRentalService] Bangkaan open --", #boatsFolder:GetChildren(), "bangka for hire")