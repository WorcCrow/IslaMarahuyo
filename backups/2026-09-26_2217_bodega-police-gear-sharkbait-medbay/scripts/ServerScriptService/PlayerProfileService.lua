-- PlayerProfileService
-- Session-locked DataStore wrapper for Isla Marahuyo player data (Shells, inventory).
-- One server holds the "lock" on a player's save while they're connected here, so a
-- second server can't load and save the same profile at the same time and cause dupes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local PlayerProfileService = {}

local STORE_NAME = "IslaMarahuyo_Players_v1"

-- GetDataStore throws in an unpublished place (no real place id yet). Fall back to an
-- in-memory-only mode so Studio testing still works before this place is published;
-- once published, this picks up real DataStore persistence automatically.
local dataStore
local datastoreAvailable = true
do
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		dataStore = storeOrErr
	else
		datastoreAvailable = false
		warn("[PlayerProfileService] DataStore unavailable (place likely unpublished) -- running in-memory only, nothing will be saved between sessions:", storeOrErr)
	end
end

local SESSION_ID = HttpService:GenerateGUID(false)
local LOCK_TIMEOUT = 30 * 60 -- seconds; a lock older than this is treated as an abandoned/crashed server
local STARTING_SHELLS = 2000
-- Handed out once per player (new or existing), so every diver has hotbar gear from the
-- start instead of only the accounts that happened to buy some while testing.
local STARTER_KIT = {glowstick = 3, oxygen = 1}

local function grantStarterKit(data)
	if data.StarterKitGiven then
		return
	end
	data.StarterKitGiven = true
	for key, n in pairs(STARTER_KIT) do
		data.Gear[key] = (data.Gear[key] or 0) + n
	end
end

local profiles = {} -- [userId] = profile table, cached while the player is on this server
local memoryOnly = {} -- [userId] = true if this user's profile isn't being persisted this session

local function defaultProfile()
	local data = {
		Shells = STARTING_SHELLS,
		-- The bodega: everything the player owns, uncapped. Market purchases land here and
		-- can be hoarded indefinitely. Nothing in here is ever lost on drowning.
		Inventory = {},
		-- The carried bag. This is the ONLY table that goes into the water, it is capped by
		-- ItemConfig.BagTiers, and it is the only thing the death scatter empties.
		Gear = {},
		GiftLog = {}, -- [tostring(friendUserId)] = last gift unix time, for gifting cooldowns later
		Tasks = { DayStamp = 0, Progress = {}, Done = {}, BonusPaid = false },
		BreathUpgrades = 0, -- Lung Corals found in the cave system (0-3), each permanently +15s max breath
		CaveTreasureFound = false,
		Drowns = 0, -- times this player has run out of air; shown on the plaza board
		CaveVisited = {}, -- [chamberName] = true -- drives the cave-exploration badges
		CaveBadges = {}, -- [milestoneKey] = true -- which exploration milestones are already awarded
		CrystalsFound = 0, -- Kristal ng Kailaliman retrieved from the deep cave
		Revives = 0, -- times Nurse Fely has had to bring this diver back
		Donated = 0, -- total Shells this player has gifted to other players
		CustomTitle = nil, -- set by the Custom Title pass; earned cave titles show without it
		BangkaPaint = "default", -- Bangka Customs paint scheme, applied for the length of a rental
		PlaytimeSeconds = 0, -- drives the level readout (1 level per minute played)
		FlashlightBattery = 100, -- percent; drains only while the flashlight is lit, refilled with a battery item
		BagTier = 1, -- index into ItemConfig.BagTiers; caps how much gear one diver can carry
		BodegaHealth = 100, -- survives despawning; only a repair or a rebuild after a break resets it
		Finds = {}, -- shells gathered from the sea, uncapped; sold for money at the Palengke
		Ledger = {}, -- every Peso in and out, newest last; drives the account view
		Strikes = 0, -- illegal stalls seized off this player; the pulis keep count
		-- Jail rides in its OWN DataStore key, not here. A sentence has to be written the
		-- instant a vote lands, even if the player rage-quits in the same second, and this
		-- profile is behind a session lock that makes that race unsafe. See PoliceService.
		CreatedAt = os.time(),
		Meta = {
			SessionId = "",
			LockedAt = 0,
			ActiveSession = false,
		},
	}
	grantStarterKit(data)
	return data
end

-- Claims the session lock for this user and loads (or creates) their profile.
-- Returns profileTable on success, or nil + a reason string on failure.
local function fallBackToMemory(userId, reason)
	warn("[PlayerProfileService] Falling back to in-memory (unsaved) profile for", userId, "--", reason)
	local data = defaultProfile()
	data.Meta.SessionId = SESSION_ID
	data.Meta.LockedAt = os.time()
	data.Meta.ActiveSession = true
	memoryOnly[userId] = true
	profiles[userId] = data
	return data
end

function PlayerProfileService.Load(userId)
	if not datastoreAvailable then
		return fallBackToMemory(userId, "DataStore not reachable from this place")
	end

	local key = "Player_" .. tostring(userId)
	local mailboxDrained = 0

	local success, result = pcall(function()
		return dataStore:UpdateAsync(key, function(old)
			local data = old or defaultProfile()

			-- migrate/backfill fields for older saves
			data.Shells = data.Shells or STARTING_SHELLS
			data.Inventory = data.Inventory or {}
			-- One-time split: before the bodega existed, `Inventory` WAS the carried bag, so
			-- everything in it belongs in Gear. A nil Gear is the sentinel for "not migrated";
			-- an empty-but-present Gear means the player simply put everything away.
			if data.Gear == nil then
				data.Gear = data.Inventory
				data.Inventory = {}
			end
			grantStarterKit(data)
			data.GiftLog = data.GiftLog or {}
			data.GiftStats = data.GiftStats or { DayStamp = 0, TotalToday = 0, PerFriendToday = {} }
			data.Tasks = data.Tasks or { DayStamp = 0, Progress = {}, Done = {}, BonusPaid = false }
			data.BreathUpgrades = data.BreathUpgrades or 0
			data.PlaytimeSeconds = data.PlaytimeSeconds or 0
			-- a flat `or` is right here: an empty battery is 0, which is truthy in Lua
			data.FlashlightBattery = data.FlashlightBattery or 100
			data.BagTier = data.BagTier or 1
			data.BodegaHealth = data.BodegaHealth or 100
			data.Finds = data.Finds or {}
			data.Ledger = data.Ledger or {}
			data.Strikes = data.Strikes or 0
			data.Drowns = data.Drowns or 0
			data.CaveVisited = data.CaveVisited or {}
			data.CaveBadges = data.CaveBadges or {}
			data.CrystalsFound = data.CrystalsFound or 0
			data.Revives = data.Revives or 0
			data.Donated = data.Donated or 0
			-- CustomTitle is intentionally left nil when unset -- nil means "show earned title"
			data.BangkaPaint = data.BangkaPaint or "default"
			if data.CaveTreasureFound == nil then
				data.CaveTreasureFound = false
			end
			data.GiftLedger = data.GiftLedger or {}
			data.Mailbox = data.Mailbox or {}
			data.Meta = data.Meta or { SessionId = "", LockedAt = 0, ActiveSession = false }

			local lockedByOtherServer = data.Meta.ActiveSession
				and data.Meta.SessionId ~= SESSION_ID
				and (os.time() - (data.Meta.LockedAt or 0)) < LOCK_TIMEOUT

			if lockedByOtherServer then
				-- leave the data untouched; caller detects the SessionId mismatch below and fails the load
				return data
			end

			-- Drain any gifts sent to this player while they were away (or on another server).
			-- This runs inside the same transaction that claims the lock, so it's race-free.
			-- Entries carry Shells, an Item, or both. Items exist because gear can be in the
			-- world rather than in a bag when its owner disconnects -- a lambat still fishing
			-- at sea, say -- and it has to come back to them rather than evaporate.
			local drained = 0
			for _, entry in ipairs(data.Mailbox) do
				drained += (entry.Shells or 0)
				if entry.Item then
					data.Inventory = data.Inventory or {}
					data.Inventory[entry.Item] = (data.Inventory[entry.Item] or 0) + (entry.Count or 1)
				end
			end
			data.Shells += drained
			data.Mailbox = {}
			mailboxDrained = drained

			data.Meta.SessionId = SESSION_ID
			data.Meta.LockedAt = os.time()
			data.Meta.ActiveSession = true
			return data
		end)
	end)

	if not success then
		-- A real DataStore error (throttling, API access disabled in Studio, outage, etc).
		-- Degrade to an unsaved session rather than kicking the player over infrastructure.
		return fallBackToMemory(userId, tostring(result))
	end

	if result.Meta.SessionId ~= SESSION_ID then
		-- This one IS a real reason to refuse the load: another server is actively
		-- holding the lock, and loading anyway is how dupes happen.
		return nil, "locked_elsewhere"
	end

	profiles[userId] = result
	return result, nil, mailboxDrained
end

function PlayerProfileService.Get(userId)
	return profiles[userId]
end

-- Saves the in-memory profile back to the DataStore. If release is true, also clears
-- the active-session lock so another server can load this player immediately after.
function PlayerProfileService.Save(userId, release)
	local profile = profiles[userId]
	if not profile then
		return
	end

	if not datastoreAvailable or memoryOnly[userId] then
		if release then
			profiles[userId] = nil
			memoryOnly[userId] = nil
		end
		return
	end

	local success, err = pcall(function()
		dataStore:UpdateAsync("Player_" .. tostring(userId), function(old)
			-- Only write if we still hold the lock -- otherwise another server owns it now
			-- (e.g. this server hung past LOCK_TIMEOUT and got its lock stolen).
			if old and old.Meta and old.Meta.SessionId == SESSION_ID then
				profile.Meta.LockedAt = os.time()
				if release then
					profile.Meta.ActiveSession = false
				end
				-- Never save our own (possibly stale) in-memory Mailbox -- another server or an
				-- offline gift deposit may have added to it since we last read. Pass through
				-- whatever's currently stored; it'll be drained next time this player loads.
				profile.Mailbox = old.Mailbox or {}
				return profile
			end
			return old
		end)
	end)

	if not success then
		warn("[PlayerProfileService] Save failed for", userId, err)
	end

	if release then
		profiles[userId] = nil
	end
end

function PlayerProfileService.GetSessionId()
	return SESSION_ID
end

-- Delivers a gift directly into a player's persisted Mailbox, independent of any
-- session lock. Safe to call whether the recipient is offline, on another server, or
-- just not loaded here -- it only ever appends, never touches Shells/Meta directly.
function PlayerProfileService.DepositToMailbox(userId, entry)
	if not datastoreAvailable then
		warn("[PlayerProfileService] Cannot deliver offline gift -- DataStore unavailable for", userId)
		return false
	end

	local key = "Player_" .. tostring(userId)
	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(old)
			local data = old or defaultProfile()
			data.Mailbox = data.Mailbox or {}
			table.insert(data.Mailbox, entry)
			return data
		end)
	end)

	if not success then
		warn("[PlayerProfileService] Mailbox deposit failed for", userId, err)
	end
	return success
end

return PlayerProfileService
