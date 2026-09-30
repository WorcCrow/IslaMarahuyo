-- GiftingBootstrap
-- Resolves the username typed into the gift panel to a UserId (server-side, so the
-- client never needs API access) and hands off to GiftingService, then reports back
-- a plain-English result for the UI to show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GiftingService = require(script.Parent.GiftingService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestGift = remotes:WaitForChild("RequestGift")
local giftFeedback = remotes:WaitForChild("GiftFeedback")

local REASON_MESSAGES = {
	invalid_amount = "Enter a valid gift amount.",
	cannot_gift_self = "You can't gift yourself.",
	friend_check_failed = "Couldn't check friend status right now -- try again in a moment.",
	not_friends = "You can only send gifts to Roblox friends.",
	stranger_not_here = "You can gift someone who isn't a friend only while they're on this island with you.",
	per_stranger_cap_reached = "You've hit today's limit for gifting that player. Add them as a friend to raise it.",
	sender_profile_unavailable = "Your data isn't loaded yet -- try again in a moment.",
	insufficient_shells = "You don't have enough Shells for that.",
	daily_cap_reached = "You've hit today's total gifting limit.",
	per_friend_cap_reached = "You've hit today's gifting limit for that friend.",
	user_not_found = "Couldn't find a player with that username.",
}

requestGift.OnServerEvent:Connect(function(player, username, amount)
	if type(username) ~= "string" or type(amount) ~= "number" then
		return
	end

	local ok, recipientUserId = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)

	if not ok or not recipientUserId then
		giftFeedback:FireClient(player, REASON_MESSAGES.user_not_found, false)
		return
	end

	local success, resultOrReason = GiftingService.SendGift(player, recipientUserId, amount)

	if success then
		local message = string.format("Sent %d Shells to %s!", amount, username)
		if resultOrReason.firstGiftBonus and resultOrReason.firstGiftBonus > 0 then
			message ..= string.format(" (+%d first-gift bonus)", resultOrReason.firstGiftBonus)
		end
		if not resultOrReason.deliveredLive then
			message ..= " They'll see it next time they're online."
		end
		if resultOrReason.wasFriend == false then
			message ..= string.format(" (%d left for them today -- add them as a friend to raise the limit)", math.max(0, resultOrReason.remainingForPerson or 0))
		end
		giftFeedback:FireClient(player, message, true)
	else
		giftFeedback:FireClient(player, REASON_MESSAGES[resultOrReason] or "Couldn't send that gift.", false)
	end
end)

print("[GiftingBootstrap] Gifting ready")
