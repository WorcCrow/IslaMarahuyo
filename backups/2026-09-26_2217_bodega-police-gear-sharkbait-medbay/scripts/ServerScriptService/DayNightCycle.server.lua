-- DayNightCycle
-- Slowly animates Lighting.ClockTime through a full day, replicated to everyone since
-- Lighting properties are server-owned. A full cycle takes CYCLE_MINUTES real minutes.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local CYCLE_MINUTES = 24
local HOURS_PER_SECOND = 24 / (CYCLE_MINUTES * 60)

-- The island's day counter. ClockTime only ever tells you the hour, so anything
-- that needs to happen ONCE per day (the cave-in, for one) has no edge to hook --
-- hence this attribute, bumped the moment the clock wraps past midnight.
-- Consumers listen with workspace:GetAttributeChangedSignal("IslandDay").
local day = 1
workspace:SetAttribute("IslandDay", day)

RunService.Heartbeat:Connect(function(dt)
	local before = Lighting.ClockTime
	local after = (before + dt * HOURS_PER_SECOND) % 24
	Lighting.ClockTime = after
	if after < before then -- wrapped through midnight
		day += 1
		workspace:SetAttribute("IslandDay", day)
	end
end)

print("[DayNightCycle] Running -- full cycle every", CYCLE_MINUTES, "minutes")
