-- MarketShiftService (Tindero)
-- What happens to a diver's shells after they sell them.
--
-- Before this, LootService.SellAll deleted the finds and paid out. Now the goods land in
-- a backlog on the Palengke floor and somebody has to carry them to a stall. That is the
-- market role's whole job, and it is why the stalls can show a diver where their haul
-- actually went instead of it vanishing into a number.
--
-- The staff area is the BACK strip of the deck, where the stalls are. The front stays
-- public, because the shop prompt lives at the deck centre and gating the whole deck
-- would lock every shopper out of the shop.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoleService = require(script.Parent.RoleService)
local CurrencyService = require(script.Parent.CurrencyService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local marketSold = ServerStorage:WaitForChild("MarketSold")
-- A jailed player working off a sentence does the tindero's job for nothing. This is the
-- "help other role without pay" half of the sentence, and it is why the crate prompts
-- below answer to OnService as well as to the role.
local serviceCredit = ServerStorage:WaitForChild("ServiceCredit")
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
local shiftStatus = ensureRemote("ShiftStatus")

local isla = workspace:WaitForChild("IslaMarahuyo")
local deck = isla:WaitForChild("PalengkeMarketDeck")
local structures = isla:WaitForChild("Structures")

-- ===== geometry =====
-- deck spans x -331..-273, z 154..206, walking surface at y = 8.00
local DECK_TOP = deck.Position.Y + deck.Size.Y / 2
local DECK_MIN_X = deck.Position.X - deck.Size.X / 2
local DECK_MAX_X = deck.Position.X + deck.Size.X / 2
local DECK_MAX_Z = deck.Position.Z + deck.Size.Z / 2
-- Stalls were resized 1.4x for taller characters (2026-09 pass) and now occupy roughly
-- z 190..202 (was 191..201) -- both constants below are rebased off the new footprint,
-- keeping the same clearances the original author used (3 studs / 2 studs).
local STAFF_MIN_Z = 187 -- the back strip, where the stalls stand
local EJECT_TO_Z = STAFF_MIN_Z - 5

-- Goods land at the WEST end of the staff strip. The stalls occupy z 190..202, so the
-- pile sits at z=188 to stay clear of their footprints, and starting it west of Stall_A
-- means the far stall is a real walk rather than a step.
local PILE = Vector3.new(-322, DECK_TOP, 188)
local STALLS = { "Stall_A", "Stall_B", "Stall_C" }

-- ===== shift economics =====
-- One island day is 24 real minutes, so 06:00-19:00 is about 13 real minutes of work.
local SHIFT_BASE = 180
local PER_CRATE = 12
local CRATE_CAP = 40
-- You cannot claim the job at dusk and collect a full day's pay. 70% rather than 100%
-- because a tindero has to be able to step off the deck without losing the shift.
local REQUIRED_COVERAGE = 0.7
local WARN_HOUR = 17

local MAX_BACKLOG = 24 -- beyond this the floor stops accepting crates and just piles text

local backlog = {} -- array of { key, count, seller }
local crates = {} -- [Model] = backlog entry
local carrying = {} -- [userId] = Model
local shift = {} -- [userId] = { onDeck = seconds, crates = n, day = islandDay }
local stallLog = {} -- [stallName] = array of { key, count, seller }

local function isTindero(player)
	return RoleService.Has(player, "tindero")
end

-- Who is allowed to work this floor: the tindero, or somebody serving a sentence on
-- Palengke duty.
local function onService(player)
	return player:GetAttribute("ServiceTrack") == "vendor"
end

local function mayWorkFloor(player)
	return isTindero(player) or onService(player)
end

local function inStaffArea(position)
	return position.X >= DECK_MIN_X and position.X <= DECK_MAX_X
		and position.Z >= STAFF_MIN_Z and position.Z <= DECK_MAX_Z
		and position.Y > DECK_TOP - 4 and position.Y < DECK_TOP + 14
end

local function shiftOf(player)
	local day = workspace:GetAttribute("IslandDay") or 1
	local s = shift[player.UserId]
	if not s or s.day ~= day then
		s = { onDeck = 0, crates = 0, day = day, paid = false, warned = false }
		shift[player.UserId] = s
	end
	return s
end

-- ===== crates on the floor =====

local cratesFolder = isla:FindFirstChild("PalengkeBacklog")
if not cratesFolder then
	cratesFolder = Instance.new("Folder")
	cratesFolder.Name = "PalengkeBacklog"
	cratesFolder.Parent = isla
end

local function say(player, message, ok)
	shiftStatus:FireClient(player, "toast", message, ok and 1 or 0)
end

local function pileSpot(index)
	-- a tidy 4-wide stack so a big backlog reads as a mess without becoming a wall
	local col = (index - 1) % 4
	local row = math.floor((index - 1) / 4)
	return PILE + Vector3.new(col * 2.4, 0.7 + row * 1.5, -row * 0.4)
end

local function buildCrate(entry, index)
	local loot = ItemConfig.Loot[entry.key]
	local model = Instance.new("Model")
	model.Name = "Crate_" .. entry.key

	local box = Instance.new("Part")
	box.Name = "Box"
	box.Size = Vector3.new(2, 1.4, 2)
	box.Color = Color3.fromRGB(124, 88, 52)
	box.Material = Enum.Material.WoodPlanks
	box.Anchored = true
	box.CanCollide = false -- a crate you have to walk around is a crate you trip over
	box.Position = pileSpot(index)
	box.Parent = model
	model.PrimaryPart = box

	-- a nodule on top in the find's own colour, so a crate reads at a glance
	local nodule = Instance.new("Part")
	nodule.Name = "Goods"
	nodule.Shape = Enum.PartType.Ball
	nodule.Size = Vector3.new(0.9, 0.9, 0.9)
	nodule.Color = (loot and loot.glow) or Color3.fromRGB(220, 220, 200)
	nodule.Material = Enum.Material.Neon
	nodule.Anchored = true
	nodule.CanCollide = false
	nodule.Position = box.Position + Vector3.new(0, 1.05, 0)
	nodule.Parent = model

	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.new(0, 170, 0, 34)
	tag.StudsOffset = Vector3.new(0, 2.1, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 70
	tag.Parent = box

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(255, 226, 170)
	label.TextStrokeTransparency = 0.5
	label.Text = string.format("%s x%d\nfrom %s", loot and loot.short or entry.key, entry.count, entry.seller)
	label.Parent = tag

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Lift"
	prompt.ObjectText = "Crate"
	prompt.ActionText = "Carry"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = box

	model.Parent = cratesFolder
	crates[model] = entry
	return model, prompt
end

local restack -- forward-declared: prompt handlers below call it

local function dropCarried(player)
	local model = carrying[player.UserId]
	carrying[player.UserId] = nil
	if model and model.Parent then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("WeldConstraint") then
				part:Destroy()
			end
		end
		for _, part in ipairs(model:GetChildren()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		restack()
	end
	return model
end

local function liftCrate(player, model)
	if carrying[player.UserId] then
		say(player, "You are already carrying one -- put it on a stall first.", false)
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not model.Parent then
		return
	end

	carrying[player.UserId] = model
	local box = model.PrimaryPart
	local offset = CFrame.new(0, 2.4, -1.2)
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end
	box.CFrame = root.CFrame * offset
	model.Goods.CFrame = box.CFrame * CFrame.new(0, 1.05, 0)

	-- weld AFTER positioning and before physics gets a frame, or the crate bursts apart
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = root, box
	w.Parent = box
	local w2 = Instance.new("WeldConstraint")
	w2.Part0, w2.Part1 = box, model.Goods
	w2.Parent = model.Goods

	box.Lift.Enabled = false
	say(player, "Carry it to a stall.", true)
end

-- ===== the stalls =====

local function stallDisplay(stallName)
	local stall = structures:FindFirstChild(stallName)
	if not stall then
		return nil
	end
	local anchor = stall:FindFirstChild("ShelfAnchor")
	if not anchor then
		local cf, size = stall:GetBoundingBox()
		anchor = Instance.new("Part")
		anchor.Name = "ShelfAnchor"
		anchor.Size = Vector3.new(6, 0.2, 4)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.Anchored = true
		anchor.Position = Vector3.new(cf.X, DECK_TOP + 3.2, cf.Z - size.Z / 2 + 1.4)
		anchor.Parent = stall

		local tag = Instance.new("BillboardGui")
		tag.Name = "Shelf"
		tag.Size = UDim2.new(0, 210, 0, 78)
		tag.StudsOffset = Vector3.new(0, 3.4, 0)
		tag.AlwaysOnTop = false
		tag.MaxDistance = 85
		tag.Parent = anchor

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 12
		label.TextColor3 = Color3.fromRGB(236, 240, 242)
		label.TextStrokeTransparency = 0.5
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Text = "empty"
		label.Parent = tag

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Place"
		prompt.ObjectText = stallName:gsub("_", " ")
		prompt.ActionText = "Set out the goods"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
	end
	return anchor
end

local function repaintStall(stallName)
	local anchor = stallDisplay(stallName)
	local label = anchor and anchor.Shelf.Label
	if not label then
		return
	end
	local log = stallLog[stallName] or {}
	if #log == 0 then
		label.Text = "empty"
		return
	end
	local lines = {}
	-- newest first, and only the last few: a shelf is a display, not a ledger
	for i = #log, math.max(1, #log - 3), -1 do
		local e = log[i]
		local loot = ItemConfig.Loot[e.key]
		table.insert(lines, string.format("%s x%d  (%s)", loot and loot.short or e.key, e.count, e.seller))
	end
	label.Text = table.concat(lines, "\n")
end

local function setOutGoods(player, stallName)
	local model = carrying[player.UserId]
	if not model then
		say(player, "Fetch a crate from the pile first.", false)
		return
	end
	local entry = crates[model]
	carrying[player.UserId] = nil
	crates[model] = nil
	model:Destroy()

	stallLog[stallName] = stallLog[stallName] or {}
	table.insert(stallLog[stallName], entry)
	repaintStall(stallName)

	local loot = ItemConfig.Loot[entry.key]

	-- Service work pays nothing and counts toward no shift. That is the point of it: the
	-- crate still gets shelved, the worker still gets nothing, and the time comes off
	-- their sentence instead of their wage.
	if not isTindero(player) and onService(player) then
		serviceCredit:Fire(player, "restock")
		say(player, string.format("%s x%d set out. Unpaid -- it comes off your time.",
			loot and loot.short or entry.key, entry.count), true)
		restack()
		return
	end

	local s = shiftOf(player)
	s.crates = math.min(CRATE_CAP, s.crates + 1)
	shiftStatus:FireClient(player, "crate", stallName, s.crates)

	say(player, string.format("%s x%d set out. %d crate%s this shift.",
		loot and loot.short or entry.key, entry.count, s.crates, s.crates == 1 and "" or "s"), true)
	restack()
end

for _, name in ipairs(STALLS) do
	local anchor = stallDisplay(name)
	if anchor then
		anchor.Place.Triggered:Connect(function(player)
			if not mayWorkFloor(player) then
				say(player, "Only the tindero sets out the goods.", false)
				return
			end
			setOutGoods(player, name)
		end)
	end
end

-- ===== the backlog =====

function restack()
	local index = 0
	for model, _ in pairs(crates) do
		if model.Parent and not model.PrimaryPart.Anchored then
			-- being carried; leave it alone
		elseif model.Parent then
			index += 1
			local spot = pileSpot(index)
			model.PrimaryPart.Position = spot
			model.Goods.Position = spot + Vector3.new(0, 1.05, 0)
			model.PrimaryPart.Lift.Enabled = true
		end
	end
end

local function addToBacklog(seller, key, count)
	local pending = 0
	for _ in pairs(crates) do
		pending += 1
	end
	if pending >= MAX_BACKLOG then
		return false
	end
	local entry = { key = key, count = count, seller = seller }
	table.insert(backlog, entry)
	local model, prompt = buildCrate(entry, pending + 1)
	prompt.Triggered:Connect(function(player)
		if not mayWorkFloor(player) then
			say(player, "Only the tindero works the Palengke floor.", false)
			return
		end
		liftCrate(player, model)
	end)
	return true
end

marketSold.Event:Connect(function(player, sold, earned)
	for key, count in pairs(sold or {}) do
		addToBacklog(player.DisplayName, key, count)
	end
end)

-- ===== who may stand behind the stalls =====
-- Only the back strip is staff-only. Gating the whole deck would put the shop prompt --
-- which sits at the deck centre -- behind the same door and lock every shopper out.
local warnedAt = {}
local function enforceStaffArea(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or mayWorkFloor(player) then
		return
	end
	if not inStaffArea(root.Position) then
		return
	end
	-- step them back out to the public side rather than flinging them; a hard shove here
	-- would punt shoppers into the sea
	root.CFrame = CFrame.new(root.Position.X, DECK_TOP + 3, EJECT_TO_Z)
	if os.clock() - (warnedAt[player.UserId] or 0) > 4 then
		warnedAt[player.UserId] = os.clock()
		say(player, "Staff only behind the stalls. Take the tindero job at the Barangay board.", false)
	end
end

-- ===== the shift clock =====
-- Must match DayNightCycle.CYCLE_MINUTES; the two together decide what a shift is worth.
local REAL_SECONDS_PER_ISLAND_DAY = 24 * 60
local SHIFT_REAL_SECONDS = (RoleService.DAY_END - RoleService.DAY_START) / 24 * REAL_SECONDS_PER_ISLAND_DAY

-- Exposed so the HUD can say what the bar is, rather than hard-coding 70% in two places.
workspace:SetAttribute("ShiftRequiredCoverage", REQUIRED_COVERAGE)

local function payShift(player)
	local s = shiftOf(player)
	if s.paid then
		return
	end
	s.paid = true
	local coverage = math.min(1, s.onDeck / SHIFT_REAL_SECONDS)
	if coverage < REQUIRED_COVERAGE then
		shiftStatus:FireClient(player, "unpaid", string.format(
			"Closing time. You worked %d%% of the shift -- %d%% is needed for a day's pay.",
			math.floor(coverage * 100), math.floor(REQUIRED_COVERAGE * 100)), 0)
		return
	end
	local pay = SHIFT_BASE + PER_CRATE * s.crates
	CurrencyService.AddShells(player, pay, false, "MarketShift")
	shiftStatus:FireClient(player, "paid", string.format(
		"Palengke closed. %d crates, a full shift worked. +%d Peso.", s.crates, pay), pay)
end

local lastHour = Lighting.ClockTime
task.spawn(function()
	while true do
		task.wait(1)
		local hour = Lighting.ClockTime
		local function crossed(mark)
			-- handles the midnight wrap, where hour jumps back below lastHour
			if hour >= lastHour then
				return lastHour < mark and hour >= mark
			end
			return lastHour < mark or hour >= mark
		end

		if crossed(WARN_HOUR) then
			for _, player in ipairs(RoleService.Holders("tindero")) do
				shiftStatus:FireClient(player, "warn",
					"Two hours to closing. Stay on the floor to get paid.", 0)
			end
		end
		if crossed(RoleService.DAY_END) then
			for _, player in ipairs(RoleService.Holders("tindero")) do
				payShift(player)
			end
		end
		lastHour = hour
	end
end)

-- ===== Aling Nena =====
-- Works the backlog at roughly half a player's pace whenever nobody holds the job, so an
-- unstaffed Palengke drains slowly instead of jamming solid. Slow enough that a real
-- tindero is obviously better; fast enough that a solo player never hits a wall.
local BOT_SECONDS = 20
task.spawn(function()
	while true do
		task.wait(BOT_SECONDS)
		if RoleService.BotIsCovering("tindero") then
			for model, entry in pairs(crates) do
				if model.Parent and model.PrimaryPart.Anchored then
					local stallName = STALLS[math.random(1, #STALLS)]
					stallLog[stallName] = stallLog[stallName] or {}
					table.insert(stallLog[stallName], entry)
					repaintStall(stallName)
					crates[model] = nil
					model:Destroy()
					restack()
					break -- one crate per tick, never the whole pile at once
				end
			end
		end
	end
end)

-- ===== per-frame bookkeeping =====
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.4 then
		return
	end
	local step = accumulated
	accumulated = 0

	local shiftOpen = RoleService.ShiftOpen("tindero")
	for _, player in ipairs(Players:GetPlayers()) do
		enforceStaffArea(player)

		if isTindero(player) then
			local s = shiftOf(player)
			if shiftOpen then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and inStaffArea(root.Position) then
					s.onDeck += step
				end
			end
			-- published so the tindero can watch their own shift fill up, and so the pay
			-- threshold is never a surprise at closing time
			player:SetAttribute("ShiftCoverage", math.min(1, s.onDeck / SHIFT_REAL_SECONDS))
			player:SetAttribute("ShiftCrates", s.crates)
		elseif player:GetAttribute("ShiftCoverage") ~= nil then
			player:SetAttribute("ShiftCoverage", nil)
			player:SetAttribute("ShiftCrates", nil)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	dropCarried(player)
	shift[player.UserId] = nil
	warnedAt[player.UserId] = nil
end)

print(string.format(
	"[MarketShiftService] Palengke floor open -- staff area z>=%d, shift %02d:00-%02d:00 (~%.0fs), %d+%d/crate",
	STAFF_MIN_Z, RoleService.DAY_START, RoleService.DAY_END, SHIFT_REAL_SECONDS, SHIFT_BASE, PER_CRATE))
