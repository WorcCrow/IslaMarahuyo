-- DailyLoginService
-- The "small content drip" from the roadmap: an escalating login-streak reward so
-- there's always a reason to come back tomorrow. Resets to day 1 if a day is missed.

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)

local DailyLoginService = {}

-- Day 1..7 reward, then repeats. Flat Shells -- not multiplied by VIP or the fiesta
-- bonus, since this is a login gift rather than "earned" Shells.
local STREAK_REWARDS = {10, 15, 20, 25, 30, 40, 50}
local PH_OFFSET_SECONDS = 8 * 3600

local function phDayStamp(unixTime)
	return math.floor((unixTime + PH_OFFSET_SECONDS) / 86400)
end

-- Returns reward, newStreakCount, alreadyClaimedToday
function DailyLoginService.Claim(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return 0, 0, false
	end

	profile.LoginStreak = profile.LoginStreak or { Count = 0, LastDayStamp = 0 }
	local streak = profile.LoginStreak
	local today = phDayStamp(os.time())

	if streak.LastDayStamp == today then
		return 0, streak.Count, true
	elseif streak.LastDayStamp == today - 1 then
		streak.Count += 1
	elseif streak.LastDayStamp == today - 2 and (profile.StreakSavers or 0) > 0 then
		-- Streak Saver: exactly one missed day is forgiven, and it costs a charge. Two or
		-- more missed days still resets -- a saver buys back a slip, not an absence.
		profile.StreakSavers -= 1
		streak.Count += 1
		streak.SaverUsedOn = today
	else
		streak.Count = 1
	end
	streak.LastDayStamp = today

	local rewardIndex = ((streak.Count - 1) % #STREAK_REWARDS) + 1
	local reward = STREAK_REWARDS[rewardIndex]
	CurrencyService.AddShells(player, reward, false, "DailyLogin")

	return reward, streak.Count, false
end

return DailyLoginService
