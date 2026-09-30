-- QuestService (Gawain sa Isla -- island tasks)
-- The island had plenty of activities but no reason to pick one, so players wandered
-- and left. This gives everyone a short, visible list of things to do today, each with
-- a Shells payout, drawn from a pool so the list changes day to day.
--
-- Progress is server-side only: every service calls Report() after it has already
-- validated the action, so the client is never trusted for task credit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)

local QuestService = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function ensureRemote(name, className)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local tasksUpdated = ensureRemote("TasksUpdated", "RemoteEvent")
local taskCompleted = ensureRemote("TaskCompleted", "RemoteEvent")

-- The pool. `kind` is what services report against; `goal` is how many it takes.
local POOL = {
	-- The net-buoy haul, the dock-fishing minigame and the bangka race were removed;
	-- the lambat fishery replaces them and brings its own tasks back into this pool.
	{ kind = "TreasureDig", goal = 2, reward = 45, title = "Dig up 2 treasures", hint = "Look for the X marks on Baybayon Beach" },
	{ kind = "Dance", goal = 1, reward = 30, title = "Join a Sayawan dance", hint = "Hop on the Barangay Plaza stage" },
	{ kind = "ZoneVisit", goal = 7, reward = 60, title = "Visit all 7 zones", hint = "Read the signpost at each one" },
	{ kind = "SeaHarvest", goal = 6, reward = 55, title = "Gather 6 finds from the sea", hint = "Glowing finds on the seabed -- the deeper ones pay far better" },
	{ kind = "SeaHarvest", goal = 2, reward = 70, title = "Bring up 2 finds from the cave", hint = "Yungib and Kailaliman finds only -- mind your air" },
	{ kind = "VendorRestock", goal = 3, reward = 40, title = "Run 3 market restocks", hint = "Restock the Palengke crates 1 to 2 to 3" },
	{ kind = "CaveCrystal", goal = 1, reward = 80, title = "Retrieve a deep-cave kristal", hint = "It forms in the far chambers, past the last air pocket -- bring lungs" },
}

local DAILY_COUNT = 4
local ALL_DONE_BONUS = 50

local function dayStamp()
	-- UTC day number; the whole server rolls over together
	return math.floor(os.time() / 86400)
end

-- Deterministic pick so every player on every server sees the same list for a given day.
local function todaysTasks()
	local day = dayStamp()
	local order = {}
	for i = 1, #POOL do
		order[i] = i
	end
	local rng = Random.new(day * 7919)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local picked = {}
	for i = 1, math.min(DAILY_COUNT, #order) do
		picked[#picked + 1] = POOL[order[i]]
	end
	return picked
end

local function blankState()
	return { DayStamp = 0, Progress = {}, Done = {}, BonusPaid = false }
end

-- Returns the player's task state for today, resetting it if the day rolled over.
local function stateFor(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return nil
	end
	profile.Tasks = profile.Tasks or blankState()
	local state = profile.Tasks
	if state.DayStamp ~= dayStamp() then
		state.DayStamp = dayStamp()
		state.Progress = {}
		state.Done = {}
		state.BonusPaid = false
	end
	return state
end

-- Today's list is deliberately the same for everyone, so a Task Reroll can't just pick a
-- different global list -- it records a per-player swap of one slot and everything else
-- resolves through here. Slot keys are strings because a sparse numeric table does not
-- survive a DataStore round trip intact.
local function tasksFor(player)
	local state = stateFor(player)
	local base = todaysTasks()
	if not state or not state.Swaps then
		return base
	end
	local out = {}
	for i, def in ipairs(base) do
		local poolIndex = state.Swaps[tostring(i)]
		out[i] = (poolIndex and POOL[poolIndex]) or def
	end
	return out
end
QuestService.TasksFor = tasksFor

-- Swaps one unfinished task for something that isn't already on the player's list.
-- Returns true + the new task's title, or false + a reason.
function QuestService.RerollTask(player)
	local state = stateFor(player)
	if not state then
		return false, "no_profile"
	end

	local current = tasksFor(player)
	local onList = {}
	for _, def in ipairs(current) do
		onList[def.kind] = true
	end

	local openSlots = {}
	for i, def in ipairs(current) do
		if not state.Done[def.kind] then
			openSlots[#openSlots + 1] = i
		end
	end
	if #openSlots == 0 then
		return false, "all_done"
	end

	local candidates = {}
	for poolIndex, def in ipairs(POOL) do
		if not onList[def.kind] then
			candidates[#candidates + 1] = poolIndex
		end
	end
	if #candidates == 0 then
		return false, "no_alternatives"
	end

	local slot = openSlots[math.random(1, #openSlots)]
	local poolIndex = candidates[math.random(1, #candidates)]

	state.Swaps = state.Swaps or {}
	state.Swaps[tostring(slot)] = poolIndex

	QuestService.Push(player)
	return true, POOL[poolIndex].title
end

function QuestService.GetState(player)
	local state = stateFor(player)
	if not state then
		return nil
	end
	local list = {}
	for _, def in ipairs(tasksFor(player)) do
		list[#list + 1] = {
			kind = def.kind,
			title = def.title,
			hint = def.hint,
			goal = def.goal,
			reward = def.reward,
			progress = math.min(state.Progress[def.kind] or 0, def.goal),
			done = state.Done[def.kind] == true,
		}
	end
	return { tasks = list, bonus = ALL_DONE_BONUS, bonusPaid = state.BonusPaid == true }
end

function QuestService.Push(player)
	local payload = QuestService.GetState(player)
	if payload then
		tasksUpdated:FireClient(player, payload)
	end
end

-- Called by the gameplay services after they have validated and paid out an action.
function QuestService.Report(player, kind, amount)
	if not player or not player.Parent then
		return
	end
	local state = stateFor(player)
	if not state then
		return
	end

	local def
	for _, candidate in ipairs(tasksFor(player)) do
		if candidate.kind == kind then
			def = candidate
			break
		end
	end
	if not def or state.Done[kind] then
		return -- not on today's list, or already finished
	end

	local current = (state.Progress[kind] or 0) + (amount or 1)
	state.Progress[kind] = math.min(current, def.goal)

	if current >= def.goal then
		state.Done[kind] = true
		CurrencyService.AddShells(player, def.reward, true, "Quest")
		taskCompleted:FireClient(player, def.title, def.reward, false)

		local allDone = true
		for _, candidate in ipairs(tasksFor(player)) do
			if not state.Done[candidate.kind] then
				allDone = false
				break
			end
		end
		if allDone and not state.BonusPaid then
			state.BonusPaid = true
			CurrencyService.AddShells(player, ALL_DONE_BONUS, true, "Quest")
			taskCompleted:FireClient(player, "All island tasks complete", ALL_DONE_BONUS, true)
		end
	end

	QuestService.Push(player)
end

-- Zone visits are the one task with no prompt behind it, so it is tracked here by
-- proximity rather than by a service reporting in.
function QuestService.NoteZoneVisit(player, zoneName)
	local state = stateFor(player)
	if not state then
		return
	end
	state.VisitedZones = state.VisitedZones or {}
	if state.VisitedZones[zoneName] then
		return
	end
	state.VisitedZones[zoneName] = true
	QuestService.Report(player, "ZoneVisit", 1)
end

QuestService.Pool = POOL
QuestService.TodaysTasks = todaysTasks

return QuestService
