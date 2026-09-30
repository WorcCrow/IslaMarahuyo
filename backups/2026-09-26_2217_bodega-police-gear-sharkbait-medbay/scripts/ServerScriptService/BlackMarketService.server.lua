-- BlackMarketService (Tolda)
-- The crime the pulis exist to police.
--
-- A tolda beats the Palengke on every axis except safety: no stall fee, pitch it on any
-- patch of land, and it will take unconverted FINDS straight for Peso instead of making
-- the seller walk them to the counter. That last part is the real draw -- it skips the
-- whole trip the legitimate economy is built around.
--
-- What it costs is exposure. Packing up takes twelve loud seconds, so you cannot pitch
-- and vanish: stay to pack and you can be caught standing over it, or run and leave it
-- open for an officer to seize. That single number is the entire risk mechanic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)
local RoleService = require(script.Parent.RoleService)
local LootService = require(script.Parent.LootService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local refreshSignal = ServerStorage:WaitForChild("InventoryRefresh")
local giveToBag = ServerStorage:WaitForChild("GiveToBag")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRemote(name, className)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className or "RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local requestTolda = ensureRemote("RequestTolda")
local toldaUpdated = ensureRemote("ToldaUpdated")
local toldaStatus = ensureRemote("ToldaStatus")

local isla = workspace:WaitForChild("IslaMarahuyo")
local PACK_SECONDS = ItemConfig.ToldaPackSeconds
local MAX_LISTINGS = ItemConfig.ToldaMaxListings
local CONFISCATION_CUT = ItemConfig.ConfiscationCut
local WANTED_RANGE = 26 -- how close to your own open stall counts as standing over it
local REPORT_COOLDOWN = 30 -- seconds before the same player can report the same stall again

-- Required on first use; see the matching note in BodegaService.
local PoliceUnit
local function police()
	PoliceUnit = PoliceUnit or require(script.Parent.PoliceUnit)
	return PoliceUnit
end
local SHOP_RANGE = 14
local MAX_PRICE = 1000000

-- No tolda inside the licensed market's own zone; smuggling next to the counter you are
-- undercutting is a step too far and makes the Palengke unreadable.
local PALENGKE_EXCLUSION = 90

local tents = {} -- [id] = tent record
local tentOf = {} -- [userId] = tent record
local nextTentId = 0

local folder = isla:FindFirstChild("Toldas")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Toldas"
	folder.Parent = isla
end

-- forward-declared: the pitch handler below calls it, but it is defined further down.
-- Without this it compiles as a global lookup and is nil at runtime.
local attachSeizePrompt
-- same trap: buildTent's Browse prompt calls this, and it is defined after buildTent
local rackRows

local function say(player, message, ok)
	toldaStatus:FireClient(player, message, ok and true or false)
end

local function profileOf(player)
	return PlayerProfileService.Get(player.UserId)
end

local function gearCount(profile, key)
	return (profile.Gear or {})[key] or 0
end

-- A tolda is set up on dry land, not carried into the water, so it may be pitched straight
-- out of the bodega. Requiring it in the dive bag meant buying one from Suki put it in the
-- bodega where the pitch button could not see it, and the player had no way to know they
-- had to PACK it across first.
local function heldAnywhere(profile, key)
	return ((profile.Gear or {})[key] or 0) + ((profile.Inventory or {})[key] or 0)
end

local function takeAnywhere(profile, key)
	profile.Gear = profile.Gear or {}
	profile.Inventory = profile.Inventory or {}
	-- bodega first, so pitching a stall never strips the bag a diver packed
	for _, store in ipairs({ profile.Inventory, profile.Gear }) do
		local have = store[key] or 0
		if have > 0 then
			store[key] = have - 1
			if store[key] <= 0 then
				store[key] = nil
			end
			return true
		end
	end
	return false
end

-- ===== value =====
-- What a stall is "worth" for the officer's cut: what the seller was asking for
-- everything still on the rack.
local function askingTotal(tent)
	local total = 0
	for _, listing in pairs(tent.listings) do
		total += listing.price
	end
	return total
end

-- ===== pitching =====

local function buildTent(player, position)
	nextTentId += 1
	local model = Instance.new("Model")
	model.Name = "Tolda_" .. player.Name

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(7, 0.4, 7)
	floor.Color = Color3.fromRGB(78, 62, 48)
	floor.Material = Enum.Material.WoodPlanks
	floor.Anchored = true
	floor.CanCollide = false
	floor.Position = position + Vector3.new(0, 0.2, 0)
	floor.Parent = model
	model.PrimaryPart = floor

	local canopy = Instance.new("Part")
	canopy.Name = "Canopy"
	canopy.Size = Vector3.new(7.6, 0.3, 7.6)
	canopy.Color = Color3.fromRGB(122, 64, 142)
	canopy.Material = Enum.Material.Fabric
	canopy.Anchored = true
	canopy.CanCollide = false
	canopy.Position = position + Vector3.new(0, 5.2, 0)
	canopy.Parent = model

	for _, corner in ipairs({ Vector3.new(3.2, 0, 3.2), Vector3.new(-3.2, 0, 3.2),
		Vector3.new(3.2, 0, -3.2), Vector3.new(-3.2, 0, -3.2) }) do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Size = Vector3.new(0.3, 5, 0.3)
		post.Color = Color3.fromRGB(96, 74, 52)
		post.Material = Enum.Material.Wood
		post.Anchored = true
		post.CanCollide = false
		post.Position = position + corner + Vector3.new(0, 2.6, 0)
		post.Parent = model
	end

	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.new(0, 190, 0, 40)
	sign.StudsOffset = Vector3.new(0, 6.6, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 110
	sign.Parent = floor
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(216, 176, 240)
	label.TextStrokeTransparency = 0.5
	label.Text = player.DisplayName .. "'s tolda\nopen"
	label.Parent = sign

	local browse = Instance.new("ProximityPrompt")
	browse.Name = "Browse"
	browse.ObjectText = "Tolda"
	browse.ActionText = "Look over the goods"
	browse.HoldDuration = 0
	browse.MaxActivationDistance = SHOP_RANGE
	browse.RequiresLineOfSight = false
	browse.Parent = floor

	model.Parent = folder

	local tent = {
		id = nextTentId,
		owner = player,
		ownerId = player.UserId,
		ownerName = player.DisplayName,
		position = position,
		model = model,
		label = label,
		listings = {},
		nextListing = 0,
		packing = nil,
	}
	browse.Triggered:Connect(function(who)
		-- the last argument says whether this is your own stall: the owner gets the stock
		-- controls, everybody else gets buy buttons
		toldaUpdated:FireClient(who, tent.id, tent.ownerName, tent.ownerId,
			rackRows(tent), who.UserId == tent.ownerId)
	end)

	tents[tent.id] = tent
	tentOf[player.UserId] = tent
	-- the Tolda hotbar tool reads this to know whether a click pitches or packs
	player:SetAttribute("ToldaUp", true)
	return tent
end

-- What is on the rack, oldest first, as the client renders it.
function rackRows(tent)
	local rows = {}
	for _, l in pairs(tent.listings) do
		table.insert(rows, { id = l.id, key = l.key, count = l.count, price = l.price, loot = l.loot })
	end
	table.sort(rows, function(a, b) return a.id < b.id end)
	return rows
end

-- Pushed to the OWNER after anything changes their rack, so the stock panel they are
-- looking at never disagrees with what is actually out.
local function pushOwner(tent)
	local owner = Players:GetPlayerByUserId(tent.ownerId)
	if owner then
		toldaUpdated:FireClient(owner, tent.id, tent.ownerName, tent.ownerId, rackRows(tent), true)
	end
end

local function repaintTent(tent)
	local n = 0
	for _ in pairs(tent.listings) do
		n += 1
	end
	local state
	if tent.packing then
		state = "PACKING UP"
	elseif n == 0 then
		state = "open - nothing out"
	else
		state = string.format("open - %d item%s, %d Peso", n, n == 1 and "" or "s", askingTotal(tent))
	end
	tent.label.Text = tent.ownerName .. "'s tolda\n" .. state
end

-- Returns the stock to whoever it belongs to. Used when a stall is packed up properly.
local function returnStock(tent, player)
	local profile = player and profileOf(player)
	for _, listing in pairs(tent.listings) do
		if listing.loot then
			if player then
				LootService.Give(player, listing.key, listing.count)
			end
		elseif profile then
			profile.Inventory = profile.Inventory or {}
			profile.Inventory[listing.key] = (profile.Inventory[listing.key] or 0) + listing.count
		else
			PlayerProfileService.DepositToMailbox(tent.ownerId, { Item = listing.key, Count = listing.count })
		end
	end
	tent.listings = {}
end

local function removeTent(tent)
	tents[tent.id] = nil
	if tentOf[tent.ownerId] == tent then
		tentOf[tent.ownerId] = nil
	end
	if tent.model then
		tent.model:Destroy()
	end
	local owner = Players:GetPlayerByUserId(tent.ownerId)
	if owner then
		-- Wanted is PoliceUnit's to clear: a reported owner who packs up in a hurry is still
		-- wanted until their window runs out
		owner:SetAttribute("ToldaUp", nil)
		refreshSignal:Fire(owner)
	end
end

-- ===== confiscation =====
-- Called by the pulis. The goods are destroyed, the officer takes a cut of what the stall
-- was asking, and the owner gets nothing. Note what this does NOT do: it never jails
-- anybody. An abandoned stall costs you the stock, not your freedom -- only being caught
-- standing over it does that, and that is PoliceService's call, not this one's.
local function confiscate(officer, tent)
	local value = askingTotal(tent)
	local cut = math.floor(value * CONFISCATION_CUT + 0.5)
	local ownerName = tent.ownerName

	tent.listings = {} -- seized goods are gone; they are not returned and not resold
	removeTent(tent)

	if cut > 0 then
		CurrencyService.AddShells(officer, cut, false, "Confiscation")
	end
	say(officer, string.format("Stall seized from %s. %d Peso of goods, your cut %d.",
		ownerName, value, cut), true)
	-- The tent itself is seized along with the stock. It was taken out of the owner's
	-- possession when they pitched it and it is never given back, so a confiscation costs
	-- them the goods AND the 260 Peso tolda -- which is what makes running one a real bet.

	local owner = Players:GetPlayerByUserId(tent.ownerId)
	if owner then
		local profile = profileOf(owner)
		if profile then
			profile.Strikes = (profile.Strikes or 0) + 1
			owner:SetAttribute("Strikes", profile.Strikes)
		end
		say(owner, string.format(
			"The pulis seized your tolda -- the tent and %d Peso of goods, all gone.", value), false)
	end
end

-- ===== the fixer =====
local fixer = isla:WaitForChild("RoleBots"):WaitForChild("SukiTheFixer")
fixer.Torso.BuyTolda.Triggered:Connect(function(player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	local item = ItemConfig.Items.tolda
	-- into the bag, like every other purchase; the bodega is only stocked by hand
	if not giveToBag:Invoke(player, "tolda", 1, true) then
		say(player, "Suki shakes his head -- your bag is full. Stow something at your bodega.", false)
		return
	end
	if not CurrencyService.TrySpend(player, item.price, "Item_tolda") then
		say(player, string.format("Suki wants %d Peso for a tolda.", item.price), false)
		return
	end
	giveToBag:Invoke(player, "tolda", 1)
	say(player, string.format("Suki hands over a tolda. -%d Peso. Equip it to pitch it.", item.price), true)
end)

-- ===== requests =====

local palengkeZone do
	local zones = isla:FindFirstChild("Zones")
	palengkeZone = zones and zones:FindFirstChild("PalengkeMarket")
end

-- Terrain above the waterline, or a built surface: anywhere you can stand.
--
-- The character MUST be excluded. The ray starts above the player's root and travels down
-- through their own torso and legs, so without this it reports the top of their own head
-- as "the ground" and the tent gets pitched floating in mid-air.
local function onLand(player, position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, player.Character }
	params.IgnoreWater = true
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -24, 0), params)
	return hit ~= nil and hit.Position.Y > 1.5, hit and hit.Position.Y or nil
end

requestTolda.OnServerEvent:Connect(function(player, action, a, b, c)
	local profile = profileOf(player)
	if not profile then
		return
	end

	-- ===== pitch =====
	if action == "pitch" then
		if tentOf[player.UserId] then
			say(player, "You already have a tolda up. One at a time.", false)
			return
		end
		if heldAnywhere(profile, "tolda") <= 0 then
			say(player, "No tolda on you. Suki keeps them at Terminal Cove.", false)
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local land, groundY = onLand(player, root.Position)
		if not land then
			say(player, "A tolda needs dry land under it.", false)
			return
		end
		if palengkeZone then
			local flat = Vector2.new(root.Position.X - palengkeZone.Position.X,
				root.Position.Z - palengkeZone.Position.Z).Magnitude
			if flat < PALENGKE_EXCLUSION then
				say(player, "Not under the Palengke's nose. Take it somewhere quieter.", false)
				return
			end
		end

		takeAnywhere(profile, "tolda")
		local tent = buildTent(player, Vector3.new(root.Position.X, groundY, root.Position.Z))
		-- after buildTent, so the tool sync sees ToldaUp and keeps the Tolda tool in hand
		-- for packing up instead of removing it with the last tent
		refreshSignal:Fire(player)
		attachSeizePrompt(tent)
		attachReportPrompt(tent)
		repaintTent(tent)
		say(player, "Tolda pitched. Put things out -- and watch who is watching you.", true)
		-- open the stock panel straight away rather than making them walk back onto their
		-- own tent and find the prompt; the whole point of pitching is to put things out
		pushOwner(tent)
		return
	end

	local tent = tentOf[player.UserId]

	-- ===== put something out =====
	if action == "list" then
		if not tent then
			say(player, "Pitch a tolda first.", false)
			return
		end
		local key, count, price = a, math.floor(tonumber(b) or 0), math.floor(tonumber(c) or 0)
		if type(key) ~= "string" or count < 1 or price < 1 or price > MAX_PRICE then
			say(player, "Pick a count and a price.", false)
			return
		end
		local n = 0
		for _ in pairs(tent.listings) do n += 1 end
		if n >= MAX_LISTINGS then
			say(player, string.format("Only %d things fit on the rack.", MAX_LISTINGS), false)
			return
		end

		-- a tolda takes FINDS as well as gear -- that is the whole reason to run one
		local isLoot = ItemConfig.IsLoot(key)
		if isLoot then
			local have = (profile.Finds or {})[key] or 0
			if have < count then
				say(player, "You do not have that many.", false)
				return
			end
			profile.Finds[key] = have - count
			if profile.Finds[key] <= 0 then
				profile.Finds[key] = nil
			end
		else
			local bodega = (profile.Inventory or {})[key] or 0
			local bag = (profile.Gear or {})[key] or 0
			if bodega + bag < count then
				say(player, "You do not have that many.", false)
				return
			end
			local fromBodega = math.min(bodega, count)
			if fromBodega > 0 then
				profile.Inventory[key] = bodega - fromBodega
				if profile.Inventory[key] <= 0 then profile.Inventory[key] = nil end
			end
			local rest = count - fromBodega
			if rest > 0 then
				profile.Gear[key] = bag - rest
				if profile.Gear[key] <= 0 then profile.Gear[key] = nil end
			end
		end

		tent.nextListing += 1
		tent.listings[tent.nextListing] = {
			id = tent.nextListing, key = key, count = count, price = price, loot = isLoot,
		}
		refreshSignal:Fire(player)
		repaintTent(tent)
		pushOwner(tent)
		say(player, "On the rack.", true)
		return
	end

	-- ===== take something back off the rack =====
	if action == "unlist" then
		if not tent then
			return
		end
		local listing = tent.listings[tonumber(a) or -1]
		if not listing then
			return
		end
		tent.listings[listing.id] = nil
		if listing.loot then
			LootService.Give(player, listing.key, listing.count)
		else
			profile.Inventory = profile.Inventory or {}
			profile.Inventory[listing.key] = (profile.Inventory[listing.key] or 0) + listing.count
			refreshSignal:Fire(player)
		end
		repaintTent(tent)
		pushOwner(tent)
		say(player, "Taken back off the rack.", true)
		return
	end

	-- ===== pack up =====
	if action == "pack" then
		if not tent then
			say(player, "You have no tolda up.", false)
			return
		end
		if tent.packing then
			return
		end
		tent.packing = os.clock() + PACK_SECONDS
		repaintTent(tent)
		say(player, string.format("Packing up -- %d seconds. Stay with it.", PACK_SECONDS), true)
		return
	end

	-- ===== buy from somebody else's stall =====
	if action == "buy" then
		local target = tents[tonumber(a) or -1]
		local listing = target and target.listings[tonumber(b) or -1]
		if not (target and listing) then
			say(player, "Gone already.", false)
			return
		end
		if target.ownerId == player.UserId then
			say(player, "That is your own stall.", false)
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - target.position).Magnitude > SHOP_RANGE + 6 then
			say(player, "Stand at the stall.", false)
			return
		end
		-- gear goes into the buyer's bag like any other purchase, so check the room first
		if not listing.loot and not giveToBag:Invoke(player, listing.key, listing.count, true) then
			say(player, "No room in your bag for that -- stow something at your bodega.", false)
			return
		end
		if not CurrencyService.TrySpend(player, listing.price, "ToldaBuy") then
			say(player, string.format("That costs %d Peso.", listing.price), false)
			return
		end

		-- off the rack before anything is handed over, so two buyers cannot race it
		target.listings[listing.id] = nil

		if listing.loot then
			LootService.Give(player, listing.key, listing.count)
		else
			giveToBag:Invoke(player, listing.key, listing.count)
		end

		-- the whole price, no cut: this is what the risk buys
		local seller = Players:GetPlayerByUserId(target.ownerId)
		if seller then
			CurrencyService.AddShells(seller, listing.price, false, "ToldaSale")
			say(seller, string.format("%s bought from your tolda -- +%d Peso, no cut.",
				player.DisplayName, listing.price), true)
		else
			PlayerProfileService.DepositToMailbox(target.ownerId, { Shells = listing.price })
		end

		local item = ItemConfig.Find(listing.key)
		say(player, string.format("Bought %d %s for %d Peso.",
			listing.count, item and item.short or listing.key, listing.price), true)
		repaintTent(target)
		pushOwner(target)
		return
	end
end)

-- ===== reporting =====
-- Running a tolda no longer tips anyone off by itself. It takes another player seeing the
-- owner at their open stall and reporting it -- that makes the owner Wanted and sends an
-- NPC officer to bring them in. Caught in the act only: the owner has to be standing at the
-- stall when the report lands, so nobody can be reported for a stall they walked away from.
local function attachReportPrompt(tent)
	local lastReport = {} -- [userId] = os.clock()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Report"
	prompt.ObjectText = "Illegal stall"
	prompt.ActionText = "Report to pulis"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.UIOffset = Vector2.new(0, 80)
	prompt:SetAttribute("OwnerId", tent.ownerId) -- lets ToldaHud hide it from the owner
	prompt.Parent = tent.model.Floor
	prompt.Triggered:Connect(function(reporter)
		if not tents[tent.id] then
			return
		end
		if reporter.UserId == tent.ownerId then
			say(reporter, "That is your own stall.", false)
			return
		end
		if os.clock() - (lastReport[reporter.UserId] or 0) < REPORT_COOLDOWN then
			say(reporter, "You already reported this stall. The pulis heard you.", false)
			return
		end
		local owner = Players:GetPlayerByUserId(tent.ownerId)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - tent.position).Magnitude > WANTED_RANGE then
			say(reporter, "Nobody is minding it right now -- a pulis can still seize it.", false)
			return
		end
		lastReport[reporter.UserId] = os.clock()
		police().ReportCrime(owner, tent.position, "tolda")
		say(reporter, string.format("Reported. The pulis are coming for %s.", owner.DisplayName), true)
	end)
end

-- ===== seizing =====
-- The prompt sits on every tent but only answers to a pulis. It is deliberately NOT gated
-- on the owner being absent -- an officer who walks up to a manned stall can still seize
-- it. Being present only matters once somebody reports the owner (see attachReportPrompt).
function attachSeizePrompt(tent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Seize"
	prompt.ObjectText = "Illegal stall"
	prompt.ActionText = "Confiscate"
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = tent.model.Floor
	prompt.Triggered:Connect(function(officer)
		if not RoleService.Has(officer, "pulis") then
			say(officer, "Only the pulis can seize a stall.", false)
			return
		end
		if not tents[tent.id] then
			return
		end
		confiscate(officer, tent)
	end)
end

-- ===== the tick =====
-- Finishes pack-ups. Wanted is no longer set here: standing at your own stall only matters
-- once another player reports you (attachReportPrompt), and PoliceUnit owns the flag.
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.3 then
		return
	end
	accumulated = 0
	local now = os.clock()

	for _, tent in pairs(tents) do
		if not tent.model.Parent then
			removeTent(tent)
		else
			local owner = Players:GetPlayerByUserId(tent.ownerId)
			local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
			local near = root ~= nil and (root.Position - tent.position).Magnitude <= WANTED_RANGE

			if tent.packing then
				if not near then
					-- walked away mid-pack; the stall stays up and stays seizable
					tent.packing = nil
					repaintTent(tent)
					if owner then
						say(owner, "You left it half-packed. The tolda is still standing.", false)
					end
				elseif now >= tent.packing then
					local profile = owner and profileOf(owner)
					returnStock(tent, owner)
					if profile then
						profile.Inventory = profile.Inventory or {}
						profile.Inventory.tolda = (profile.Inventory.tolda or 0) + 1
						refreshSignal:Fire(owner)
					end
					removeTent(tent)
					if owner then
						say(owner, "Packed up clean. Nobody saw a thing.", true)
					end
				end
			end

		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local tent = tentOf[player.UserId]
	if tent then
		-- The stall STAYS. Logging off is exactly the "leave it open and run" case, and it
		-- has to remain seizable or disconnecting would be the safest way to smuggle.
		tent.owner = nil
		tent.packing = nil
		repaintTent(tent)
	end
end)

print(string.format(
	"[BlackMarketService] tolda ready -- %ds to pack up, %d listings each, officer keeps %d%% of a seizure",
	PACK_SECONDS, MAX_LISTINGS, math.floor(CONFISCATION_CUT * 100)))
