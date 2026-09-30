-- LambatService (Mangingisda)
-- Four stakes planted at sea make the net -- whatever quadrilateral the player actually
-- walked, not a square snapped to their average. Sharks that cross it shake loose a find,
-- which sinks to the seabed for ANYONE to pick up -- which is what makes a well-sited net
-- a visible island event rather than private income.
--
-- WHY DISTANCE FROM SHORE, NOT DEPTH: the plan called for depth-weighted payouts, but the
-- seabed here is flat. A survey across the whole map found the floor sitting at -12 almost
-- everywhere, bottoming out at -26 in one southeastern shelf, against a sea surface at 0.
-- There is no depth gradient to weight against. What DOES vary is how far out you are, and
-- that is the real cost anyway: a long swim, a shark-thick crossing and a bangka hire.
--
-- REACH IS CAPPED BY TIER, SHAPE IS NOT. Each stake must stay within LambatHalfSide studs
-- of the other three's running average -- the same footprint a fixed square would have --
-- but inside that circle the player draws whatever shape they like. The circle shown while
-- staking is that same cap made visible, tinted green/amber/red by how stretched the net
-- already is, and a stake landing outside it is refused on the spot rather than after all
-- four are down.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local RoleService = require(script.Parent.RoleService)
local GamePassService = require(script.Parent.GamePassService)
local LootService = require(script.Parent.LootService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local refreshSignal = ServerStorage:WaitForChild("InventoryRefresh")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRemote(name)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local requestLambat = ensureRemote("RequestLambat")
local lambatStatus = ensureRemote("LambatStatus")

local isla = workspace:WaitForChild("IslaMarahuyo")

-- ===== the sea =====
local ISLAND_CENTRE = Vector2.new(0, 20) -- roughly the centroid of the seven zones
local SEA_LEVEL = 0
-- Beyond this you are off the shelf and need a boat under you.
local BANGKA_RADIUS = 550
local BANDS = {
	{ name = "inshore", upTo = 550, label = "inshore" },
	{ name = "offshore", upTo = 850, label = "offshore" },
	{ name = "deepsea", upTo = math.huge, label = "the deep sea" },
}

-- Weighted by how far out the net is. perlas is absent everywhere: the top find stays a
-- cave reward and must never fall out of a net.
local DROP_TABLE = {
	inshore = { {"kabibe", 55}, {"bahura", 30}, {"yungib", 10}, {"kailaliman", 3}, {"kristal", 1.5}, {"yaman", 0.5} },
	offshore = { {"kabibe", 30}, {"bahura", 30}, {"yungib", 20}, {"kailaliman", 10}, {"kristal", 7}, {"yaman", 3} },
	deepsea = { {"kabibe", 15}, {"bahura", 25}, {"yungib", 25}, {"kailaliman", 15}, {"kristal", 12}, {"yaman", 8} },
}

-- "30 seconds of in-game time" would be half a real second at a 24-minute day, which is no
-- cooldown at all -- a shark would drop on nearly every pass. Read as 30 REAL seconds.
local SHARK_COOLDOWN = 30
local SCAN_HZ = 10 -- a shark drifting through a net does not need frame-perfect detection
local MAX_LIVE_DROPS = 14 -- per net, so an unattended net cannot carpet the seabed
local DROP_LIFETIME = 8 * 60

local nets = {} -- [id] = net record
local netOf = {} -- [userId] = net record
local pending = {} -- [userId] = { Vector3 stake positions }
local pendingParts = {} -- [userId] = { Part }
local pendingGuide = {} -- [userId] = the reach-circle Part being staked against
local lastDrop = {} -- [sharkModel] = os.clock()
local nextNetId = 0

local netFolder = isla:FindFirstChild("Lambat")
if not netFolder then
	netFolder = Instance.new("Folder")
	netFolder.Name = "Lambat"
	netFolder.Parent = isla
end

local function say(player, message, ok)
	lambatStatus:FireClient(player, message, ok and true or false)
end

local function bandFor(position)
	local r = (Vector2.new(position.X, position.Z) - ISLAND_CENTRE).Magnitude
	for _, band in ipairs(BANDS) do
		if r < band.upTo then
			return band, r
		end
	end
	return BANDS[#BANDS], r
end

-- Ray-casting point-in-polygon: works for whatever quadrilateral a player actually walked,
-- convex or not, as long as they did not cross their own net into a bowtie.
local function pointInPolygon(px, pz, corners)
	local inside = false
	local n = #corners
	local j = n
	for i = 1, n do
		local xi, zi = corners[i].X, corners[i].Z
		local xj, zj = corners[j].X, corners[j].Z
		if (zi > pz) ~= (zj > pz) then
			local xCross = (xj - xi) * (pz - zi) / (zj - zi) + xi
			if px < xCross then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { workspace.Terrain }
waterParams.IgnoreWater = true

local function seabedUnder(x, z)
	local hit = workspace:Raycast(Vector3.new(x, SEA_LEVEL + 20, z), Vector3.new(0, -500, 0), waterParams)
	return hit and hit.Position.Y or nil
end

-- Terrain water is a material, not a part, so a raycast is the wrong question -- read the
-- voxel instead.
local function isWater(x, z)
	local region = Region3.new(
		Vector3.new(x - 2, SEA_LEVEL - 6, z - 2),
		Vector3.new(x + 2, SEA_LEVEL - 2, z + 2)
	):ExpandToGrid(4)
	local ok, materials = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok then
		return false
	end
	for i = 1, materials.Size.X do
		for j = 1, materials.Size.Y do
			for k = 1, materials.Size.Z do
				if materials[i][j][k] == Enum.Material.Water then
					return true
				end
			end
		end
	end
	return false
end

-- Holding a rental receipt is not the same as being in the boat. Check the seat, or players
-- will hire once and swim out on the paperwork.
local function aboardBangka(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return false
	end
	local boats = isla.Activities:FindFirstChild("Bangkaan")
	boats = boats and boats:FindFirstChild("Boats")
	return boats ~= nil and seat:IsDescendantOf(boats)
end

local function gearCount(profile, key)
	return (profile.Gear or {})[key] or 0
end

local function takeGear(profile, key)
	profile.Gear = profile.Gear or {}
	local have = profile.Gear[key] or 0
	if have <= 0 then
		return false
	end
	profile.Gear[key] = have - 1
	if profile.Gear[key] <= 0 then
		profile.Gear[key] = nil
	end
	return true
end

-- returns the net to the carried bag, the same place planting takes it from, so a haul
-- makes it immediately usable again instead of stranding it in the bodega, which cannot
-- even be reached while standing in the water a lambat is planted in
local function giveGear(profile, key)
	profile.Gear = profile.Gear or {}
	profile.Gear[key] = (profile.Gear[key] or 0) + 1
end

-- ===== building a net =====

local function makeStake(position, tint)
	local stake = Instance.new("Part")
	stake.Name = "Stake"
	stake.Size = Vector3.new(0.5, 9, 0.5)
	stake.Color = Color3.fromRGB(122, 92, 56)
	stake.Material = Enum.Material.Wood
	stake.Anchored = true
	stake.CanCollide = false
	stake.Position = Vector3.new(position.X, SEA_LEVEL + 1.5, position.Z)

	local float = Instance.new("Part")
	float.Name = "Float"
	float.Shape = Enum.PartType.Ball
	float.Size = Vector3.new(1.3, 1.3, 1.3)
	float.Color = tint
	float.Material = Enum.Material.Neon
	float.Anchored = true
	float.CanCollide = false
	float.Position = stake.Position + Vector3.new(0, 4.6, 0)
	float.Parent = stake
	return stake
end

-- Green/amber/red by how close the current stakes already are to the reach cap, so the
-- guide doubles as a stretch meter instead of just marking a static boundary.
local function stretchColor(t)
	t = math.clamp(t, 0, 1)
	if t < 0.55 then
		return Color3.fromRGB(120, 210, 150)
	elseif t < 0.85 then
		return Color3.fromRGB(255, 200, 90)
	else
		return Color3.fromRGB(236, 96, 96)
	end
end

-- A flattened, squashed ball reads as a flat circle from above without any CFrame rotation
-- math -- exactly the area the LambatHalfSide reach check in formNet actually allows, since
-- the stakes are never required to form a square, only to stay within reach of their own
-- average position.
local function makeGuide(centre, radius, color)
	local disc = Instance.new("Part")
	disc.Name = "PlantGuide"
	disc.Shape = Enum.PartType.Ball
	disc.Size = Vector3.new(radius * 2, 0.15, radius * 2)
	disc.Color = color
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.82
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CFrame = CFrame.new(centre.X, SEA_LEVEL - 0.35, centre.Z)
	return disc
end

-- The net itself: rope edges strung between the corners IN PLANTING ORDER -- whatever
-- quadrilateral the player actually walked, drawn just under the surface so it reads from
-- a boat without blocking anything.
local function drawNet(net)
	local corners = net.corners
	local n = #corners
	for i = 1, n do
		local a = Vector3.new(corners[i].X, SEA_LEVEL - 0.4, corners[i].Z)
		local b = Vector3.new(corners[i % n + 1].X, SEA_LEVEL - 0.4, corners[i % n + 1].Z)
		local edge = Instance.new("Part")
		edge.Name = "Edge"
		edge.Size = Vector3.new(0.3, 0.3, (b - a).Magnitude)
		edge.CFrame = CFrame.lookAt((a + b) / 2, b)
		edge.Color = Color3.fromRGB(196, 214, 224)
		edge.Material = Enum.Material.Neon
		edge.Transparency = 0.35
		edge.Anchored = true
		edge.CanCollide = false
		edge.Parent = net.model
	end
end

local function haulIn(net, reason)
	if not nets[net.id] then
		return
	end
	nets[net.id] = nil
	if netOf[net.ownerId] == net then
		netOf[net.ownerId] = nil
	end
	if net.model then
		net.model:Destroy()
	end

	-- the lambat is a tool, not a consumable: it always comes back
	local profile = PlayerProfileService.Get(net.ownerId)
	if profile then
		giveGear(profile, "lambat")
		local owner = Players:GetPlayerByUserId(net.ownerId)
		if owner then
			refreshSignal:Fire(owner)
			say(owner, string.format("Lambat hauled in (%s). Ready to plant again.", reason), true)
		end
	else
		-- owner left before it expired; post it so they get it back on their next login
		PlayerProfileService.DepositToMailbox(net.ownerId, { Item = "lambat", Count = 1 })
	end
end

local function formNet(player, profile, stakes)
	local cx, cz = 0, 0
	for _, s in ipairs(stakes) do
		cx += s.X
		cz += s.Z
	end
	cx, cz = cx / #stakes, cz / #stakes

	local hasPass = GamePassService.Owns(player, ItemConfig.LambatPass)
	local reach = ItemConfig.LambatHalfSide(hasPass)

	-- each stake was already checked against the running average as it went in; this stays
	-- as a last defence, since the true average only exists once all four are down
	local span = 0
	for i, s in ipairs(stakes) do
		if (Vector2.new(s.X, s.Z) - Vector2.new(cx, cz)).Magnitude > reach then
			return nil, "Those stakes drifted too far apart. Haul up and try again, closer together."
		end
		for j = i + 1, #stakes do
			span = math.max(span, (s - stakes[j]).Magnitude)
		end
	end

	-- each stake was checked as it went in, but the net is centred on their average, which
	-- can land somewhere none of them did
	if not seabedUnder(cx, cz) then
		return nil, "The middle of that net has no bottom. Set it over the shelf."
	end

	nextNetId += 1
	local model = Instance.new("Model")
	model.Name = string.format("Lambat_%s", player.Name)
	model.Parent = netFolder

	local band, radius = bandFor(Vector3.new(cx, SEA_LEVEL, cz))
	local net = {
		id = nextNetId,
		owner = player,
		ownerId = player.UserId,
		centre = Vector3.new(cx, SEA_LEVEL, cz),
		-- the literal planting order, not a square snapped to their average -- this is the
		-- shape the shark scan tests against and the shape drawNet renders
		corners = stakes,
		span = span,
		band = band.name,
		bandLabel = band.label,
		radius = radius,
		model = model,
		expiresAt = os.clock() + ItemConfig.LambatLifetime,
		live = 0,
		caught = 0,
	}

	drawNet(net)
	local tint = hasPass and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(120, 200, 235)
	for _, corner in ipairs(net.corners) do
		local stake = makeStake(corner, tint)
		stake.Parent = model
	end

	-- a prompt on one corner so the owner can pull it up early
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Haul"
	prompt.ObjectText = "Lambat"
	prompt.ActionText = "Haul in"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = model:FindFirstChild("Stake")
	prompt.Triggered:Connect(function(who)
		if who.UserId ~= net.ownerId then
			say(who, "That is not your lambat.", false)
			return
		end
		haulIn(net, "hauled up")
	end)

	nets[net.id] = net
	netOf[player.UserId] = net
	return net
end

-- ===== planting =====

local function clearPending(userId)
	for _, part in ipairs(pendingParts[userId] or {}) do
		if part.Parent then
			part:Destroy()
		end
	end
	pending[userId] = nil
	pendingParts[userId] = nil
	pendingGuide[userId] = nil
end

requestLambat.OnServerEvent:Connect(function(player, action)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return
	end

	if action == "cancel" then
		clearPending(player.UserId)
		say(player, "Stakes pulled back up.", true)
		return
	end
	if action ~= "stake" then
		return
	end

	if not RoleService.Has(player, "mangingisda") then
		say(player, "Only a mangingisda sets a lambat. Take the job at the Barangay board.", false)
		return
	end
	if netOf[player.UserId] then
		say(player, "You already have a lambat out. Haul it in first.", false)
		return
	end
	if gearCount(profile, "lambat") <= 0 then
		say(player, "No lambat in your bag. Buy one at the Palengke and pack it.", false)
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local x, z = root.Position.X, root.Position.Z

	if not isWater(x, z) then
		say(player, "A lambat only sets in open water.", false)
		return
	end

	-- A survey of the sea found roughly a third of it is bottomless: water with no terrain
	-- beneath it at all, mostly the outer ring past x = +/-700 and the whole northern edge.
	-- A net there would look fine and catch nothing, because every find it shook loose
	-- would have nowhere to land. Refuse the stake instead of failing silently later.
	if not seabedUnder(x, z) then
		say(player, "No bottom here to hold a net -- set it where the seabed comes up.", false)
		return
	end

	local _, radius = bandFor(Vector3.new(x, SEA_LEVEL, z))
	if radius >= BANGKA_RADIUS and not aboardBangka(player) then
		say(player, "Too far out to set by hand -- hire a bangka at the Bangkaan and stake it from the boat.", false)
		return
	end

	pending[player.UserId] = pending[player.UserId] or {}
	pendingParts[player.UserId] = pendingParts[player.UserId] or {}
	local list = pending[player.UserId]

	local hasPass = GamePassService.Owns(player, ItemConfig.LambatPass)
	local reach = ItemConfig.LambatHalfSide(hasPass)
	local candidate = Vector3.new(x, SEA_LEVEL, z)

	-- stop the player right here rather than letting them plant all four and only then
	-- find out the net was rejected: check the candidate, and every stake already down,
	-- against what their average would become if this one goes in too
	if #list > 0 then
		local tx, tz = candidate.X, candidate.Z
		for _, s in ipairs(list) do
			tx += s.X
			tz += s.Z
		end
		tx, tz = tx / (#list + 1), tz / (#list + 1)
		local tooFar = (Vector2.new(candidate.X, candidate.Z) - Vector2.new(tx, tz)).Magnitude > reach
		if not tooFar then
			for _, s in ipairs(list) do
				if (Vector2.new(s.X, s.Z) - Vector2.new(tx, tz)).Magnitude > reach then
					tooFar = true
					break
				end
			end
		end
		if tooFar then
			say(player, string.format("Too far from your other stakes -- stay inside the circle (%d studs).", math.floor(reach)), false)
			return
		end
	end

	table.insert(list, candidate)

	local marker = makeStake(candidate, Color3.fromRGB(240, 168, 96))
	marker.Parent = netFolder
	table.insert(pendingParts[player.UserId], marker)

	-- a live guide so the player can see the reach cap and how stretched they already are:
	-- shape is entirely up to them, so the circle tracks the running average of whatever
	-- they have planted so far, tinted green/amber/red by how close to the cap it is
	local cx, cz = 0, 0
	for _, s in ipairs(list) do
		cx += s.X
		cz += s.Z
	end
	cx, cz = cx / #list, cz / #list
	local stretch = 0
	for _, s in ipairs(list) do
		stretch = math.max(stretch, (Vector2.new(s.X, s.Z) - Vector2.new(cx, cz)).Magnitude)
	end
	local fraction = reach > 0 and (stretch / reach) or 0
	local guide = pendingGuide[player.UserId]
	if not guide then
		guide = makeGuide(Vector3.new(cx, SEA_LEVEL, cz), reach, stretchColor(fraction))
		guide.Parent = netFolder
		table.insert(pendingParts[player.UserId], guide)
		pendingGuide[player.UserId] = guide
	else
		guide.CFrame = CFrame.new(cx, SEA_LEVEL - 0.35, cz)
		guide.Color = stretchColor(fraction)
	end

	if #list < ItemConfig.LambatStakes then
		say(player, string.format(
			"Stake %d of %d planted -- shape it however you like, just stay inside the circle.",
			#list, ItemConfig.LambatStakes), true)
		return
	end

	local stakes = list
	clearPending(player.UserId)

	local net, err = formNet(player, profile, stakes)
	if not net then
		say(player, err, false)
		return
	end

	takeGear(profile, "lambat")
	refreshSignal:Fire(player)
	say(player, string.format("Lambat set %s -- spans %d studs. It fishes for %d minutes.",
		net.bandLabel, math.floor(net.span), math.floor(ItemConfig.LambatLifetime / 60)), true)
end)

-- ===== what the sharks shake loose =====

local rng = Random.new()

local function rollFind(bandName)
	local table_ = DROP_TABLE[bandName] or DROP_TABLE.inshore
	local total = 0
	for _, row in ipairs(table_) do
		total += row[2]
	end
	local pick = rng:NextNumber() * total
	for _, row in ipairs(table_) do
		pick -= row[2]
		if pick <= 0 then
			return row[1]
		end
	end
	return table_[1][1]
end

local function spawnDrop(net, key, x, z)
	local floorY = seabedUnder(x, z)
	if not floorY then
		return
	end
	local loot = ItemConfig.Loot[key]

	local drop = Instance.new("Part")
	drop.Name = "Catch_" .. key
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(1.5, 1.5, 1.5)
	drop.Color = (loot and loot.glow) or Color3.fromRGB(220, 220, 200)
	drop.Material = Enum.Material.Neon
	-- anchored and non-collidable, sitting just ABOVE the floor: a find embedded in
	-- terrain is the same as a deleted one
	drop.Anchored = true
	drop.CanCollide = false
	drop.Position = Vector3.new(x, floorY + 1.6, z)
	drop.Parent = net.model

	-- a beacon, because underwater fog hides a 1.5-stud ball from ten studs away
	local light = Instance.new("PointLight")
	light.Color = drop.Color
	light.Brightness = 3
	light.Range = 26
	light.Parent = drop

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.new(0, 120, 0, 22)
	tag.StudsOffset = Vector3.new(0, 1.7, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 90
	tag.Parent = drop
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = drop.Color
	label.TextStrokeTransparency = 0.5
	label.Text = loot and loot.short or key
	label.Parent = tag

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = loot and loot.short or key
	prompt.ActionText = "Take"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = drop

	net.live += 1
	local taken = false
	prompt.Triggered:Connect(function(who)
		if taken then
			return
		end
		taken = true
		-- anyone may take it, not just the net's owner: that is what makes a good net a
		-- thing the whole island notices
		LootService.Give(who, key, 1)
		say(who, string.format("%s off the seabed.", loot and loot.short or key), true)
		net.live = math.max(0, net.live - 1)
		drop:Destroy()
	end)

	task.delay(DROP_LIFETIME, function()
		if drop.Parent and not taken then
			net.live = math.max(0, net.live - 1)
			drop:Destroy()
		end
	end)
end

-- ===== the scan =====
-- Up to 200 sharks at night. This runs on its own 10Hz accumulator rather than riding the
-- shark movement tick: a shark drifting through a net does not need frame-perfect
-- detection, and 10Hz cuts the work threefold for nothing.
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 1 / SCAN_HZ then
		return
	end
	accumulated = 0

	local now = os.clock()

	-- expire first, so a dead net is never scanned
	for _, net in pairs(nets) do
		if now >= net.expiresAt then
			haulIn(net, "the tide turned")
		end
	end

	local sharkFolder = isla.Activities:FindFirstChild("Sharks")
	if not sharkFolder or not next(nets) then
		return
	end

	for _, shark in ipairs(sharkFolder:GetChildren()) do
		local body = shark.PrimaryPart or shark:FindFirstChild("Body")
		if body then
			local since = now - (lastDrop[shark] or -math.huge)
			if since >= SHARK_COOLDOWN then
				local p = body.Position
				for _, net in pairs(nets) do
					if net.live < MAX_LIVE_DROPS and pointInPolygon(p.X, p.Z, net.corners) then
						lastDrop[shark] = now
						net.caught += 1
						spawnDrop(net, rollFind(net.band), p.X, p.Z)
						break -- one net per shark per pass
					end
				end
			end
		end
	end

	-- sharks are destroyed when the population shrinks; do not leak their cooldowns
	for shark in pairs(lastDrop) do
		if not shark.Parent then
			lastDrop[shark] = nil
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	clearPending(player.UserId)
	local net = netOf[player.UserId]
	if net then
		-- the net comes up with its owner; leaving it fishing unattended forever would let
		-- one player park income on a server they are not in
		haulIn(net, "you left the island")
	end
end)

print(string.format(
	"[LambatService] lambat ready -- %d-stud net (%d with the pass), %d stakes, %ds shark cooldown, bangka past %d studs",
	ItemConfig.LambatSide.free, ItemConfig.LambatSide.pass, ItemConfig.LambatStakes,
	SHARK_COOLDOWN, BANGKA_RADIUS))
