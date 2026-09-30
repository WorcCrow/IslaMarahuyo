-- AdminConfig
-- Whitelist of developer/admin UserIds who get access to the in-game admin dashboard.
-- The game's own creator (you) is always included automatically. Add teammates by
-- UserId below -- usernames can change, UserIds don't.

local AdminConfig = {}

AdminConfig.AdminUserIds = {
	-- [123456789] = true, -- add teammate UserIds here
}

function AdminConfig.IsAdmin(userId)
	if AdminConfig.AdminUserIds[userId] then
		return true
	end

	-- the place's creator (you, or your group) always has admin access
	local creatorType = game.CreatorType
	if creatorType == Enum.CreatorType.User and game.CreatorId == userId then
		return true
	end

	return false
end

return AdminConfig
