-- GiftingService
-- Friends-only Shells gifting with daily caps (per-friend and total) and an audit
-- ledger, delivered immediately if the recipient is on this server, or into their
-- persisted mailbox otherwise (see PlayerProfileService.DepositToMailbox).

local Players = game:GetService("Players")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)

local GiftingService = {}

local MIN_GIFT = 1
local PER_FRIEND_DAILY_CAP = 50
local TOTAL_DAILY_CAP = 200
local FIRST_GIFT_BONUS = 5
local LEDGER_MAX_ENTRIES = 50

-- Friends-only gifting was safe but too strict for a hangout island where most of the
-- people you meet are strangers. Non-friends can now be gifted too, under a much
-- tighter cap and two extra conditions that remove the alt-farming incentive:
--   * the recipient must be on this server right now (someone you actually met),
--   * no first-gift bonus, so a stranger gift never creates Shells out of nothing.
local PER_STRANGER_DAILY_CAP = 15

local function currentDayStamp()
	return math.floor(os.time() / 86400)
end

local function rollDailyStatsIfNeeded(stats)
	local today = currentDayStamp()
	if stats.DayStamp ~= today then
		stats.DayStamp = today
		stats.TotalToday = 0
		stats.PerFriendToday = {}
	end
end

local function appendLedger(profile, entry)
	table.insert(profile.GiftLedger, entry)
	while #profile.GiftLedger > LEDGER_MAX_ENTRIES do
		table.remove(profile.GiftLedger, 1)
	end
end

-- Returns true/false, plus a machine-readable reason on failure and extra info on success.
function GiftingService.SendGift(senderPlayer, recipientUserId, amount)
	amount = math.floor(amount or 0)
	recipientUserId = tostring(recipientUserId) and tonumber(recipientUserId)

	if not recipientUserId or amount < MIN_GIFT then
		return false, "invalid_amount"
	end
	if recipientUserId == senderPlayer.UserId then
		return false, "cannot_gift_self"
	end

	local isFriends, friendCheckOk = false, false
	do
		local ok, result = pcall(function()
			return senderPlayer:IsFriendsWith(recipientUserId)
		end)
		friendCheckOk = ok
		isFriends = ok and result
	end
	if not friendCheckOk then
		return false, "friend_check_failed"
	end

	local recipientOnThisServer = Players:GetPlayerByUserId(recipientUserId)
	if not isFriends and not recipientOnThisServer then
		-- strangers can only be gifted face to face, on the same server
		return false, "stranger_not_here"
	end

	local senderProfile = PlayerProfileService.Get(senderPlayer.UserId)
	if not senderProfile then
		return false, "sender_profile_unavailable"
	end

	rollDailyStatsIfNeeded(senderProfile.GiftStats)
	local stats = senderProfile.GiftStats
	local friendKey = tostring(recipientUserId)
	local friendTotalToday = stats.PerFriendToday[friendKey] or 0
	local perPersonCap = isFriends and PER_FRIEND_DAILY_CAP or PER_STRANGER_DAILY_CAP

	if senderProfile.Shells < amount then
		return false, "insufficient_shells"
	end
	if stats.TotalToday + amount > TOTAL_DAILY_CAP then
		return false, "daily_cap_reached"
	end
	if friendTotalToday + amount > perPersonCap then
		return false, isFriends and "per_friend_cap_reached" or "per_stranger_cap_reached"
	end

	-- first gift between this pair today gets both sides a small bonus -- friends only,
	-- so gifting a stranger can never mint Shells
	local isFirstGiftToday = isFriends and friendTotalToday == 0

	local spent = CurrencyService.TrySpend(senderPlayer, amount, "GiftSent")
	if not spent then
		return false, "insufficient_shells"
	end

	stats.TotalToday += amount
	stats.PerFriendToday[friendKey] = friendTotalToday + amount
	-- lifetime total given away, shown as "donated" on the server roster
	senderProfile.Donated = (senderProfile.Donated or 0) + amount
	senderPlayer:SetAttribute("Donated", senderProfile.Donated)
	appendLedger(senderProfile, {
		Direction = "Sent",
		To = recipientUserId,
		Amount = amount,
		At = os.time(),
		Friend = isFriends,
	})

	local recipientPlayer = Players:GetPlayerByUserId(recipientUserId)
	local deliveredLive = false
	if recipientPlayer and PlayerProfileService.Get(recipientUserId) then
		CurrencyService.AddShells(recipientPlayer, amount, false, "GiftReceived")
		deliveredLive = true
	else
		PlayerProfileService.DepositToMailbox(recipientUserId, {
			From = senderPlayer.UserId,
			FromName = senderPlayer.Name,
			Shells = amount,
			SentAt = os.time(),
		})
	end

	if isFirstGiftToday then
		CurrencyService.AddShells(senderPlayer, FIRST_GIFT_BONUS, false, "GiftBonus")
		if deliveredLive then
			CurrencyService.AddShells(recipientPlayer, FIRST_GIFT_BONUS, false, "GiftBonus")
		else
			PlayerProfileService.DepositToMailbox(recipientUserId, {
				From = senderPlayer.UserId,
				FromName = senderPlayer.Name,
				Shells = FIRST_GIFT_BONUS,
				SentAt = os.time(),
				Reason = "FirstGiftBonus",
			})
		end
	end

	return true, {
		deliveredLive = deliveredLive,
		firstGiftBonus = isFirstGiftToday and FIRST_GIFT_BONUS or 0,
		wasFriend = isFriends,
		remainingForPerson = perPersonCap - (friendTotalToday + amount),
	}
end

return GiftingService
