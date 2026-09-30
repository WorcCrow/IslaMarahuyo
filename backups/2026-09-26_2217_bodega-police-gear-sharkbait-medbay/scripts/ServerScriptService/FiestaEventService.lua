-- FiestaEventService
-- "Pista sa Barangay" -- a recurring weekly fiesta, scheduled against Philippine time
-- (UTC+8) to match the setting rather than the server's own UTC clock. Every Saturday,
-- all earned Shells get a multiplier and the plaza's festival lights come on.

local FiestaEventService = {}

local PH_OFFSET_SECONDS = 8 * 3600
local FIESTA_MULTIPLIER = 1.5

-- Set to true/false to override the real schedule for testing; nil = use the real clock.
FiestaEventService.DebugForceActive = nil

-- Seasonal calendar. The weekly Saturday fiesta always runs; on top of it each month
-- carries its own named festival so the island has a reason to feel different in
-- January than it does in May. Months are Philippine-time months.
local SEASONS = {
	[1] = { name = "Sinulog sa Isla", blurb = "Drums and dancing all month", bonus = 0.1 },
	[2] = { name = "Panagbenga Blooms", blurb = "The island is in flower", bonus = 0.1 },
	[3] = { name = "Summer Opening", blurb = "Beach season begins", bonus = 0.15 },
	[4] = { name = "Moriones Week", blurb = "Masks and processions", bonus = 0.1 },
	[5] = { name = "Flores de Mayo", blurb = "Flower parades every evening", bonus = 0.15 },
	[6] = { name = "Tag-ulan", blurb = "Rainy season -- the fishing is best now", bonus = 0.2 },
	[7] = { name = "Pagoda Regatta", blurb = "Bangka races all month", bonus = 0.15 },
	[8] = { name = "Kadayawan Harvest", blurb = "Market stalls overflowing", bonus = 0.15 },
	[9] = { name = "Ber Months Begin", blurb = "Parol lanterns go up early", bonus = 0.1 },
	[10] = { name = "MassKara Nights", blurb = "Smiling masks after dark", bonus = 0.15 },
	[11] = { name = "Undas Lanterns", blurb = "Candles along the shore", bonus = 0.1 },
	[12] = { name = "Pasko sa Barangay", blurb = "Christmas on the island", bonus = 0.25 },
}

local function phDate(unixTime)
	return os.date("!*t", (unixTime or os.time()) + PH_OFFSET_SECONDS)
end

local function isFiestaActiveAt(unixTime)
	return phDate(unixTime).wday == 7 -- Saturday, Philippine time (1=Sunday..7=Saturday)
end

-- The month's festival, always on. Returns name, blurb, bonus multiplier contribution.
function FiestaEventService.GetSeason(unixTime)
	local month = phDate(unixTime).month
	return SEASONS[month] or { name = "Isla Marahuyo", blurb = "A quiet month on the island", bonus = 0 }
end

function FiestaEventService.IsActive()
	if FiestaEventService.DebugForceActive ~= nil then
		return FiestaEventService.DebugForceActive
	end
	return isFiestaActiveAt(os.time())
end

-- The weekly fiesta and the monthly season stack, so a Saturday in December is the
-- best time to be on the island.
function FiestaEventService.GetMultiplier()
	local multiplier = FiestaEventService.IsActive() and FIESTA_MULTIPLIER or 1
	return multiplier + FiestaEventService.GetSeason().bonus
end

function FiestaEventService.GetStatusText()
	local season = FiestaEventService.GetSeason()
	local seasonLine = string.format("%s -- %s (+%.0f%% Shells)", season.name, season.blurb, season.bonus * 100)
	if FiestaEventService.IsActive() then
		return string.format(
			"Pista sa Barangay is ON -- %.2fx Shells everywhere! | %s",
			FiestaEventService.GetMultiplier(),
			seasonLine
		)
	end
	return string.format("Next Pista sa Barangay: Saturday (Philippine time) | %s", seasonLine)
end

return FiestaEventService
