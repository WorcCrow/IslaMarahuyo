-- MusicConfig
-- The island's soundtrack. This is the ONLY file to touch to change the music.
--
-- ON USING REAL BAND TRACKS (e.g. Cup of Joe):
-- Commercial recordings can't just be uploaded -- Roblox content-scans audio, and
-- unlicensed music gets the asset taken down and the upload counted against the
-- account. To use a specific band's songs you need one of:
--   1. the rights holder's written licence, then upload and paste the asset id below; or
--   2. the track appearing in Roblox's own licensed catalog (Creator Store -> Audio),
--      which is cleared for in-experience use.
-- Everything currently listed is from Roblox's free licensed catalog and is cleared for
-- use here. The mood is deliberately close to acoustic OPM -- soft fingerpicked guitar --
-- so swapping in licensed tracks later won't feel like a different game.
--
-- To add a track: append { id = "rbxassetid://<id>", title = ..., artist = ..., mood = ... }

local MusicConfig = {}

MusicConfig.Volume = 0.35
MusicConfig.GapSeconds = 3 -- quiet beat between tracks
MusicConfig.Shuffle = true

-- mood is used to pick what plays where: "day" on the island, "night" after dark,
-- "deep" inside the cave system.
MusicConfig.Tracks = {
	{ id = "rbxassetid://139568344220252", title = "Slow Mornings", artist = "Distrokid (licensed)", mood = "day", length = 129 },
	{ id = "rbxassetid://108826828000144", title = "Forest Coffee", artist = "Distrokid (licensed)", mood = "day", length = 121 },
	{ id = "rbxassetid://129921489936955", title = "Coffee and Slow Days", artist = "Distrokid (licensed)", mood = "day", length = 138 },
	{ id = "rbxassetid://135985954076772", title = "Morning Coffee Strings", artist = "Distrokid (licensed)", mood = "day", length = 97 },
	{ id = "rbxassetid://122785038651760", title = "Nature Cafe", artist = "Distrokid (licensed)", mood = "day", length = 144 },
	{ id = "rbxassetid://71231764133976", title = "Journey Through the Hills", artist = "Distrokid (licensed)", mood = "day", length = 240 },
	{ id = "rbxassetid://129981160870767", title = "Rainy Coffee", artist = "Distrokid (licensed)", mood = "night", length = 204 },
	{ id = "rbxassetid://92886910462358", title = "Lofi Guitar Under Stars", artist = "Distrokid (licensed)", mood = "night", length = 158 },
	{ id = "rbxassetid://133374308857950", title = "In The Forest Late", artist = "Distrokid (licensed)", mood = "night", length = 149 },
	{ id = "rbxassetid://115040904385760", title = "Mediterranean Breeze", artist = "Distrokid (licensed)", mood = "deep", length = 144 },
}

function MusicConfig.ByMood(mood)
	local out = {}
	for _, track in ipairs(MusicConfig.Tracks) do
		if track.mood == mood then
			out[#out + 1] = track
		end
	end
	-- never return an empty playlist -- fall back to the whole list
	if #out == 0 then
		return MusicConfig.Tracks
	end
	return out
end

return MusicConfig
