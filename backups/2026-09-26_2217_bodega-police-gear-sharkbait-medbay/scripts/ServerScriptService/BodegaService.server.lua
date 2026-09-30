-- BodegaService
-- The bodega as a thing standing in the world.
--
-- profile.Inventory has always been the bodega's contents; this gives it a body. The owner
-- places it, and only while it stands -- and only beside it -- can gear move between it and
-- the bag. While it stands, anyone with an axe can chop at it. It is built to take a crew:
-- one thief needs over a minute of uninterrupted swinging, five need about fifteen seconds,
-- which is the window an owner or a pulis has to show up. Broken, everything inside spills
-- out one piece at a time.
--
-- Health lives on the profile, so packing a damaged bodega away and placing it again later
-- never heals it. Only paying for a repair does.
--
-- A player may have more than one bodega up (the repurposed ExtraCabinPlot pass grants a
-- second slot) and may own either the wood or stone tier. Multiple structures always share
-- ONE hoard and ONE health pool -- they are two doors into the same warehouse, not two
-- independent stores -- so profile.Inventory/profile.BodegaHealth stay singular and every
-- structure an owner has up is kept in sync (see syncOwnerRecords) whenever either changes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)
local GamePassService = require(script.Parent.GamePassService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local CONFIG = ItemConfig.Bodega

local refreshSignal = ServerStorage:WaitForChild("InventoryRefresh")
local scatterItems = ServerStorage:WaitForChild("ScatterItems")
local itemAssets = ServerStorage:WaitForChild("ItemAssets")

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
local requestBodega = ensureRemote("RequestBodega")
local requestBodegaHit = ensureRemote("RequestBodegaHit")
local bodegaOpen = ensureRemote("BodegaOpen")
local itemFeedback = remotes:WaitForChild("ItemFeedback")

local isla = workspace:WaitForChild("IslaMarahuyo")
local folder = isla:FindFirstChild("Bodegas")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Bodegas"
	folder.Parent = isla
end

local SHOW_LIFE_SECONDS = 10 -- the floating bar stays up this long after the last hit
local WARN_EVERY = 15 -- seconds between "someone is chopping" warnings to the owner

-- ===== tiers: the prefab and its derived geometry, computed once per tier and cached =====
local prefabCache = {}
local function prefabFor(tierKey)
	local tier = ItemConfig.BodegaTierFor(tierKey)
	local prefab = prefabCache[tier.key]
	if not prefab then
		prefab = itemAssets:WaitForChild(tier.asset)
		prefabCache[tier.key] = prefab
	end
	return prefab, tier
end

local geomCache = {}
local function geometryFor(tierKey)
	local cached = geomCache[tierKey]
	if cached then
		return cached
	end
	local prefab = prefabFor(tierKey)
	local size = prefab.PrimaryPart.Size

	-- Every structure's floor is the flattest solid part in it (excluding the invisible
	-- hitbox itself), some way off the ground on the wood hut's stilts and near the bottom
	-- on the stone tier's slab base -- this works for either without caring which.
	local flattest
	for _, d in ipairs(prefab:GetChildren()) do
		if d:IsA("BasePart") and d ~= prefab.PrimaryPart and (not flattest or d.Size.Y < flattest.Size.Y) then
			flattest = d
		end
	end
	local base = prefab.PrimaryPart.Position.Y - size.Y / 2
	local floorHeight = flattest and (flattest.Position.Y + flattest.Size.Y / 2 - base) or 0
	local maxRise = math.max(3, size.Y * 0.27)

	-- The tiers were authored with different pivots (the wood hut at its base, the stone
	-- storehouse at its centre), so placement lifts by this to seat either one on the ground.
	local pivot = prefab:GetPivot()
	local pivotAboveBase = pivot.Position.Y - base

	-- The wood hut stands on stilts with its floor ~6.7 studs up: a player could walk into
	-- the gap underneath and wedge there. A solid block fills it, reaching below the base
	-- so the downhill side of a sloped placement is closed too.
	local skirt
	if flattest and floorHeight > 2 and floorHeight < size.Y / 2 then
		local rel = pivot:ToObjectSpace(flattest.CFrame)
		local bottom = (base - pivot.Position.Y) - (maxRise / 2 + 1)
		local top = rel.Y - flattest.Size.Y / 2
		skirt = {
			size = Vector3.new(flattest.Size.X, top - bottom, flattest.Size.Z),
			offset = CFrame.new(rel.X, (top + bottom) / 2, rel.Z),
		}
	end

	local geom = {
		size = size,
		-- derived from the structure's own footprint rather than a fixed "original hut" size,
		-- so a differently-shaped tier (the stone storehouse) still gets sane numbers
		minSpacing = math.max(size.X, size.Z) + 15, -- studs between two bodegas
		-- far enough ahead that the structure, and any steps out front, go down in front of
		-- the player rather than on top of them
		placeAhead = size.Z / 2 + 10,
		-- a little slope is fine: it is set at the middle height of its four corners, burying
		-- the downhill side and lifting the uphill one. Past this much rise across the
		-- footprint it would sink into the hill or float, so it is refused.
		maxRise = maxRise,
		floorHeight = floorHeight,
		pivotAboveBase = pivotAboveBase,
		hitboxOffset = pivot:ToObjectSpace(prefab.PrimaryPart.CFrame),
		skirt = skirt,
	}
	geomCache[tierKey] = geom
	return geom
end

-- Required on first use: PoliceUnit waits for a remote PoliceService creates, and bodegas
-- must not sit unplaceable waiting on the station to open.
local PoliceUnit
local function police()
	PoliceUnit = PoliceUnit or require(script.Parent.PoliceUnit)
	return PoliceUnit
end

local function bodegaLimit(player)
	return GamePassService.Owns(player, ItemConfig.BodegaSlotPass) and 2 or 1
end

local bodegaOf = {} -- [userId] = array of records (one per structure the owner has up)
local nearestRecordOf = {} -- [userId] = the record the owner is currently within UseRange of
local lastSwing = {} -- [userId] = os.clock() of their last counted swing
local rebuildAt = {} -- [userId] = os.clock() before which a broken bodega cannot be replaced

local function say(player, message, ok)
	if player then
		itemFeedback:FireClient(player, message, ok and true or false)
	end
end

local function profileOf(player)
	return PlayerProfileService.Get(player.UserId)
end

-- Distance from a point to the nearest face of the hitbox, so a 13-stud shed can be reached
-- from any wall rather than only by walking into its middle.
local function gapTo(record, position)
	local hitbox = record.hitbox
	local localPos = hitbox.CFrame:PointToObjectSpace(position)
	local half = hitbox.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z))
	return (localPos - clamped).Magnitude
end

local function rootOf(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- ===== the floating life bar =====

local function buildLifeBar(record)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BodegaLife"
	gui.Size = UDim2.fromOffset(170, 42)
	gui.StudsOffsetWorldSpace = Vector3.new(0, record.hitbox.Size.Y / 2 + 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = record.hitbox

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(245, 222, 170)
	title.TextStrokeTransparency = 0.4
	title.Text = record.ownerName .. "'s bodega"
	title.Parent = gui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(0, 22)
	track.Size = UDim2.new(1, 0, 0, 16)
	track.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
	track.BackgroundTransparency = 0.15
	track.BorderSizePixel = 0
	track.Parent = gui
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 5)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.BackgroundTransparency = 1
	number.Size = UDim2.fromScale(1, 1)
	number.Font = Enum.Font.GothamBold
	number.TextSize = 12
	number.TextColor3 = Color3.fromRGB(245, 245, 245)
	number.TextStrokeTransparency = 0.3
	number.ZIndex = 2
	number.Parent = track

	record.life = {gui = gui, title = title, fill = fill, number = number}
end

local function paint(record)
	local maxHealth = record.tier.maxHealth
	local health = record.model:GetAttribute("Health") or maxHealth
	local frac = math.clamp(health / maxHealth, 0, 1)
	local life = record.life
	life.fill.Size = UDim2.fromScale(frac, 1)
	life.fill.BackgroundColor3 = frac > 0.55 and Color3.fromRGB(96, 196, 110)
		or frac > 0.25 and Color3.fromRGB(236, 184, 70)
		or Color3.fromRGB(222, 76, 60)
	life.number.Text = string.format("%d / %d", health, maxHealth)
	life.title.Text = record.packing and (record.ownerName .. "'s bodega - packing up")
		or (record.ownerName .. "'s bodega")
	record.prompt.ObjectText = string.format("%s's %s  %d/%d", record.ownerName, record.tier.label, health, maxHealth)
end

-- Multiple structures share one hoard and one health pool, so any change to either has to
-- reach every live structure the owner has up, not just the one that was hit or repaired.
local function syncOwnerRecords(ownerId, health)
	local owner = Players:GetPlayerByUserId(ownerId)
	if owner then
		owner:SetAttribute("BodegaHealth", health)
	end
	for _, record in ipairs(bodegaOf[ownerId] or {}) do
		if record.model.Parent then
			record.model:SetAttribute("Health", health)
			paint(record)
		end
	end
end

-- ===== placing and removing =====

local placeParams = RaycastParams.new()
placeParams.FilterType = Enum.RaycastFilterType.Exclude
placeParams.IgnoreWater = false

local function placementFor(player, geom)
	local root = rootOf(player)
	if not root then
		return nil, ""
	end
	local ahead = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if ahead.Magnitude < 0.1 then
		ahead = Vector3.new(0, 0, -1)
	end
	local spot = root.Position + ahead.Unit * geom.placeAhead

	local ignore = {folder, player.Character}
	local drops = workspace:FindFirstChild("DroppedGear")
	if drops then
		table.insert(ignore, drops)
	end
	placeParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(spot + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), placeParams)
	-- same "dry land" rule the tolda uses: above the waterline, not on the sea itself
	if not hit or hit.Material == Enum.Material.Water or hit.Position.Y <= 1.5 then
		return nil, "A bodega needs dry land in front of you."
	end
	if hit.Normal.Y < 0.8 then
		return nil, "Too steep here -- find flatter ground."
	end
	for _, records in pairs(bodegaOf) do
		for _, other in ipairs(records) do
			local flat = other.hitbox.Position - hit.Position
			if Vector2.new(flat.X, flat.Z).Magnitude < geom.minSpacing then
				return nil, "Too close to another bodega."
			end
		end
	end

	local face = Vector3.new(root.Position.X, hit.Position.Y, root.Position.Z)
	local facing = CFrame.lookAt(hit.Position, face)

	-- sample the ground under each corner of the footprint, not just its centre
	local half = geom.size / 2
	local low, high = hit.Position.Y, hit.Position.Y
	for _, corner in ipairs({Vector3.new(half.X, 0, half.Z), Vector3.new(-half.X, 0, half.Z),
		Vector3.new(half.X, 0, -half.Z), Vector3.new(-half.X, 0, -half.Z)}) do
		local at = facing:PointToWorldSpace(corner)
		local ground = workspace:Raycast(at + Vector3.new(0, geom.maxRise + 14, 0),
			Vector3.new(0, -(geom.maxRise * 2 + 44), 0), placeParams)
		if not ground or ground.Material == Enum.Material.Water or ground.Position.Y <= 1.5 then
			return nil, "Not enough dry land here for a bodega."
		end
		low = math.min(low, ground.Position.Y)
		high = math.max(high, ground.Position.Y)
	end
	if high - low > geom.maxRise then
		return nil, "Too uneven here -- find flatter ground."
	end

	local y = (low + high) / 2
	local target = facing.Rotation + Vector3.new(hit.Position.X, y + geom.pivotAboveBase, hit.Position.Z)

	-- Nobody may be standing where it lands: an anchored hut appearing around a character
	-- shoves them out along whatever axis the solver picks, sometimes down into the ground.
	-- The margin covers the front steps, which reach past the hitbox.
	local box = target * geom.hitboxOffset
	local halfBox = geom.size / 2
	for _, other in ipairs(Players:GetPlayers()) do
		local r = rootOf(other)
		if r then
			local p = box:PointToObjectSpace(r.Position)
			if math.abs(p.X) <= halfBox.X + 4 and math.abs(p.Z) <= halfBox.Z + 4 and math.abs(p.Y) <= halfBox.Y + 4 then
				return nil, other == player and "Step back -- you're standing where the bodega would go."
					or "Someone is standing where the bodega would go."
			end
		end
	end
	return target
end

local function removeRecord(record)
	local at = record.hitbox.Position
	local records = bodegaOf[record.ownerId]
	if records then
		for i, r in ipairs(records) do
			if r == record then
				table.remove(records, i)
				break
			end
		end
		if #records == 0 then
			bodegaOf[record.ownerId] = nil
		end
	end
	if record.model then
		record.model:Destroy()
	end
	if nearestRecordOf[record.ownerId] == record then
		nearestRecordOf[record.ownerId] = nil
	end
	-- nothing left to guard; only loaded once a crime has ever been reported, and with no
	-- crime there are no officers out
	if PoliceUnit then
		PoliceUnit.EndWatch(at)
	end
	-- only clear the owner's flags once their LAST structure is gone
	if not bodegaOf[record.ownerId] then
		local owner = Players:GetPlayerByUserId(record.ownerId)
		if owner then
			owner:SetAttribute("BodegaUp", nil)
			owner:SetAttribute("AtBodega", nil)
			owner:SetAttribute("BodegaPacking", nil)
		end
	end
end

local function spawnFor(player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	local records = bodegaOf[player.UserId] or {}
	local limit = bodegaLimit(player)
	if #records >= limit then
		say(player, limit == 1 and "Your bodega is already up." or "You're already using both of your bodega slots.", false)
		return
	end
	local wait = (rebuildAt[player.UserId] or 0) - os.clock()
	if wait > 0 then
		say(player, string.format("Your last bodega was broken -- %d seconds before you can put up another.",
			math.ceil(wait)), false)
		return
	end
	if player:GetAttribute("InWater") then
		say(player, "A bodega goes on dry land.", false)
		return
	end

	local tierKey = profile.BodegaTier or "wood"
	local prefab, tier = prefabFor(tierKey)
	local geom = geometryFor(tierKey)

	local cframe, why = placementFor(player, geom)
	if not cframe then
		say(player, why, false)
		return
	end

	local model = prefab:Clone()
	model.Name = "Bodega_" .. player.UserId .. "_" .. (#records + 1)
	model:PivotTo(cframe)
	if geom.skirt then
		local skirt = Instance.new("Part")
		skirt.Name = "UnderSkirt"
		skirt.Size = geom.skirt.size
		skirt.CFrame = cframe * geom.skirt.offset
		skirt.Transparency = 1
		skirt.Anchored = true
		skirt.CanCollide = true
		skirt.CanTouch = false
		skirt.CanQuery = false
		skirt.Parent = model
	end
	local health = math.clamp(profile.BodegaHealth or tier.maxHealth, 1, tier.maxHealth)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", tier.maxHealth)

	local hitbox = model.PrimaryPart

	-- Storage only opens from a physical box inside the structure -- standing outside next
	-- to a wall must not reach it, which is why (unlike every other prompt in this game)
	-- this one asks for line of sight: the wall itself is what enforces "go inside."
	local box = Instance.new("Part")
	box.Name = "StorageBox"
	box.Size = Vector3.new(geom.size.X * 0.11, geom.size.Y * 0.09, geom.size.X * 0.075)
	box.Color = Color3.fromRGB(120, 84, 52)
	box.Material = Enum.Material.WoodPlanks
	box.Anchored = false
	box.CanCollide = true
	-- set back from the doorway (which faces -Z from the structure's centre on both tiers)
	-- so it reads as "the far side of the room," not something reachable from the entrance
	box.CFrame = hitbox.CFrame * CFrame.new(0, -hitbox.Size.Y / 2 + geom.floorHeight + box.Size.Y / 2, geom.size.Z * 0.16)
	box.Parent = model
	local boxWeld = Instance.new("WeldConstraint")
	boxWeld.Part0 = hitbox
	boxWeld.Part1 = box
	boxWeld.Parent = box

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open"
	prompt.ObjectText = "Storage box"
	prompt.ActionText = "Open"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = true
	prompt.Parent = box

	local record = {
		ownerId = player.UserId,
		ownerName = player.DisplayName,
		model = model,
		hitbox = hitbox,
		prompt = prompt,
		tier = tier,
		packing = nil,
		lastHit = 0,
		lastWarn = 0,
	}
	buildLifeBar(record)

	prompt.Triggered:Connect(function(who)
		if who.UserId ~= record.ownerId then
			say(who, "Not your bodega. An axe is the only way in.", false)
			return
		end
		bodegaOpen:FireClient(who, model)
	end)

	model.Parent = folder
	table.insert(records, record)
	bodegaOf[player.UserId] = records
	paint(record)
	player:SetAttribute("BodegaUp", true)
	player:SetAttribute("BodegaMaxHealth", tier.maxHealth)
	say(player, string.format("%s placed. Stand beside it to pack or stow gear -- and keep an eye on it.", tier.label), true)
end

-- ===== breaking in =====

local function breakOpen(record, attacker)
	local owner = Players:GetPlayerByUserId(record.ownerId)
	local profile = owner and profileOf(owner)
	local floorY = record.hitbox.Position.Y - record.hitbox.Size.Y / 2 + 1.2
	local spillAt = Vector3.new(record.hitbox.Position.X, floorY, record.hitbox.Position.Z)
	local maxHealth = record.tier.maxHealth

	-- empty the store BEFORE anything spawns, so a failure between the two can never
	-- duplicate a hoard
	local contents = {}
	if profile then
		contents = profile.Inventory or {}
		profile.Inventory = {}
		profile.BodegaHealth = maxHealth
	end
	removeRecord(record)
	rebuildAt[record.ownerId] = os.clock() + CONFIG.RebuildSeconds
	-- a second structure, if the owner has one up, shares the same hoard -- it just lost
	-- everything too, and its health resets to full along with the profile's
	syncOwnerRecords(record.ownerId, maxHealth)
	scatterItems:Fire(spillAt, contents)

	if owner then
		refreshSignal:Fire(owner)
		say(owner, "Your bodega was broken open -- everything in it is on the ground!", false)
	end
	local pieces = 0
	for _, count in pairs(contents) do
		if type(count) == "number" then
			pieces += count
		end
	end
	-- each piece is its own pickup, spread around the wreck; say how many so nobody walks
	-- off thinking the first one was all of it
	say(attacker, pieces > 0
		and string.format("The bodega splits open -- %d piece%s scattered around it. Grab what you can.",
			pieces, pieces == 1 and "" or "s")
		or "The bodega splits open -- it was empty.", true)
end

local function damage(record, amount, attacker)
	local health = math.max(0, (record.model:GetAttribute("Health") or record.tier.maxHealth) - amount)
	record.lastHit = os.clock()

	local owner = Players:GetPlayerByUserId(record.ownerId)
	local profile = owner and profileOf(owner)
	if profile then
		profile.BodegaHealth = math.max(health, 1)
	end
	syncOwnerRecords(record.ownerId, health)

	-- a pack-up in progress does not survive someone swinging at it
	if record.packing then
		record.packing = nil
		if owner then
			owner:SetAttribute("BodegaPacking", nil)
			say(owner, "Packing interrupted -- someone is hitting your bodega!", false)
		end
	elseif owner and os.clock() - record.lastWarn > WARN_EVERY then
		record.lastWarn = os.clock()
		say(owner, "Someone is chopping at your bodega!", false)
	end

	if health <= 0 then
		breakOpen(record, attacker)
		return
	end
	record.life.gui.Enabled = true
end

requestBodegaHit.OnServerEvent:Connect(function(attacker, model)
	if typeof(model) ~= "Instance" or model.Parent ~= folder then
		return
	end
	local record
	for _, r in ipairs(bodegaOf[model:GetAttribute("OwnerId")] or {}) do
		if r.model == model then
			record = r
			break
		end
	end
	if not record then
		return
	end
	if record.ownerId == attacker.UserId then
		return -- no chopping your own
	end

	-- The client only says which bodega it swung at. Whether the swing counted, and for how
	-- much, is decided here: an equipped axe, a live character, in reach, off cooldown.
	local character = attacker.Character
	local axe = character and character:FindFirstChild("Axe")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(attacker)
	if not (axe and axe:IsA("Tool") and humanoid and humanoid.Health > 0 and root) then
		return
	end
	local now = os.clock()
	if now - (lastSwing[attacker.UserId] or 0) < CONFIG.HitCooldown then
		return
	end
	-- +1 stud of slack for the attacker's position arriving a frame late
	if gapTo(record, root.Position) > CONFIG.AxeReach + 1 then
		return
	end
	lastSwing[attacker.UserId] = now
	-- every counted swing is a crime in progress: it starts (or refreshes) the attacker's
	-- 60 seconds of Wanted and draws an officer out of the station
	police().ReportCrime(attacker, record.hitbox.Position, "bodega")
	damage(record, CONFIG.AxeDamage, attacker)
end)

-- ===== owner requests =====

requestBodega.OnServerEvent:Connect(function(player, action)
	if action == "spawn" then
		spawnFor(player)
		return
	end

	if action == "upgradeStone" then
		local profile = profileOf(player)
		if not profile then
			return
		end
		local tier = ItemConfig.BodegaTierFor("stone")
		if (profile.BodegaTier or "wood") == tier.key then
			say(player, "You already have the stone bodega.", false)
			return
		end
		if GamePassService.Owns(player, tier.passKey) then
			profile.BodegaTier = tier.key
			say(player, "Stone bodega unlocked with your pass -- pack up and place again to build it.", true)
			return
		end
		if not CurrencyService.TrySpend(player, tier.price, "BodegaUpgrade") then
			say(player, string.format("The stone bodega costs %d Peso, or comes free with the Bahay Kubo Builder pass.",
				tier.price), false)
			return
		end
		profile.BodegaTier = tier.key
		say(player, "Stone bodega unlocked -- pack up and place again to build it.", true)
		return
	end

	local records = bodegaOf[player.UserId]
	if not records or #records == 0 then
		say(player, "Your bodega is not up -- place it first.", false)
		return
	end
	-- Which structure an action targets: whichever one the owner is nearest, refreshed every
	-- tick below. With only one bodega up this is unambiguous either way.
	local record = nearestRecordOf[player.UserId] or (#records == 1 and records[1] or nil)

	if action == "pack" then
		if not record then
			say(player, "Walk back to a bodega to pack it up.", false)
			return
		end
		if record.packing then
			return
		end
		local root = rootOf(player)
		if not root or gapTo(record, root.Position) > CONFIG.UseRange then
			say(player, "Walk back to your bodega to pack it up.", false)
			return
		end
		record.packing = os.clock() + CONFIG.PackSeconds
		player:SetAttribute("BodegaPacking", true)
		record.life.gui.Enabled = true
		paint(record)
		say(player, string.format("Packing up -- %d seconds. Stay beside it.", CONFIG.PackSeconds), true)
		return
	end

	if action == "repair" then
		if player:GetAttribute("AtBodega") ~= true or not record then
			say(player, "Stand at your bodega to repair it.", false)
			return
		end
		-- Deliberately allowed WHILE it is being hit: spending Peso to buy healing back is
		-- how an owner buys time for the police to arrive or to get a pack-up started.
		local maxHealth = record.tier.maxHealth
		local health = record.model:GetAttribute("Health") or maxHealth
		local missing = maxHealth - health
		if missing <= 0 then
			say(player, "Your bodega is already solid.", false)
			return
		end
		local fullCost = math.ceil(missing * CONFIG.RepairPerPoint)
		local balance = CurrencyService.GetShells(player.UserId) or 0
		if balance <= 0 then
			say(player, string.format("Repairs cost %d Peso.", fullCost), false)
			return
		end
		-- Partial repairs are allowed: spend whatever Peso the owner actually has, up to the
		-- full cost, and heal only the points that money actually paid for.
		local spend = math.min(fullCost, balance)
		local healed = math.min(missing, math.floor(spend / CONFIG.RepairPerPoint))
		if healed <= 0 then
			say(player, string.format("Repairs cost %d Peso -- not enough for even one point.", fullCost), false)
			return
		end
		spend = math.ceil(healed * CONFIG.RepairPerPoint)
		if not CurrencyService.TrySpend(player, spend, "BodegaRepair") then
			return
		end
		local newHealth = health + healed
		syncOwnerRecords(player.UserId, newHealth)
		local profile = profileOf(player)
		if profile then
			profile.BodegaHealth = newHealth
		end
		say(player, newHealth >= maxHealth
			and string.format("Bodega patched up. -%d Peso.", spend)
			or string.format("Patched %d points -- all the Peso you had. -%d Peso.", healed, spend), true)
		return
	end
end)

-- ===== the tick =====
-- Publishes AtBodega (the one flag InventoryService trusts for transfers), finishes or
-- cancels pack-ups, and hides the life bar once nobody has swung for a while.
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.3 then
		return
	end
	accumulated = 0
	local now = os.clock()

	for userId, records in pairs(bodegaOf) do
		local owner = Players:GetPlayerByUserId(userId)
		local snapshot = table.clone(records)
		if not owner then
			for _, record in ipairs(snapshot) do
				removeRecord(record)
			end
		else
			local root = rootOf(owner)
			local nearest, nearestGap = nil, math.huge
			local toRemove = {}
			for _, record in ipairs(snapshot) do
				if not record.model.Parent then
					table.insert(toRemove, record)
				else
					local gap = root and gapTo(record, root.Position) or math.huge
					local near = gap <= CONFIG.UseRange
					if near and gap < nearestGap then
						nearest, nearestGap = record, gap
					end

					if record.packing then
						if not near then
							record.packing = nil
							owner:SetAttribute("BodegaPacking", nil)
							paint(record)
							say(owner, "You walked off -- your bodega is still standing.", false)
						elseif now >= record.packing then
							table.insert(toRemove, record)
							say(owner, "Bodega packed away. Everything inside is safe.", true)
						end
					end

					if record.model.Parent then
						record.life.gui.Enabled = record.packing ~= nil or (now - record.lastHit) < SHOW_LIFE_SECONDS
					end
				end
			end
			owner:SetAttribute("AtBodega", nearest ~= nil or nil)
			nearestRecordOf[userId] = nearest
			for _, record in ipairs(toRemove) do
				removeRecord(record)
			end
		end
	end
end)

-- Leaving packs the bodega away. The profile is released on leave, so there is no safe
-- way to empty an offline player's hoard -- a bodega must never be breakable with nobody
-- able to answer for it.
Players.PlayerRemoving:Connect(function(player)
	for _, record in ipairs(table.clone(bodegaOf[player.UserId] or {})) do
		removeRecord(record)
	end
	nearestRecordOf[player.UserId] = nil
	lastSwing[player.UserId] = nil
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		for _ = 1, 150 do
			local profile = profileOf(player)
			if profile then
				local tier = ItemConfig.BodegaTierFor(profile.BodegaTier or "wood")
				player:SetAttribute("BodegaHealth", profile.BodegaHealth or tier.maxHealth)
				player:SetAttribute("BodegaMaxHealth", tier.maxHealth)
				return
			end
			task.wait(0.1)
		end
	end)
end)

print(string.format("[BodegaService] bodegas online -- wood %d life / stone %d life, %d per swing, %.1fs between swings",
	ItemConfig.BodegaTierFor("wood").maxHealth, ItemConfig.BodegaTierFor("stone").maxHealth,
	CONFIG.AxeDamage, CONFIG.HitCooldown))
