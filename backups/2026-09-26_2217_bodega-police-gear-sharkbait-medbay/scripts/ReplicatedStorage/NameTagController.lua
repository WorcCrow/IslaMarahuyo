-- NameTagController
-- Local, per-viewer toggle for the floating name/health tag above other players' heads.
-- Off doesn't remove anything server-side -- it just tells your own client not to draw the
-- overhead UI, the same as any other client-side HUD preference.

local Players = game:GetService("Players")

local M = {}

local SHOWN_DISTANCE = 90
local namesVisible = true
local initialized = false

local function applyToHumanoid(humanoid)
	if not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	local distance = namesVisible and SHOWN_DISTANCE or 0
	humanoid.NameDisplayDistance = distance
	humanoid.HealthDisplayDistance = distance

	-- The floating title is our own BillboardGui, so the Humanoid distance settings don't
	-- touch it. Without this, turning names off left a row of disembodied titles hanging in
	-- the air -- which is worse than leaving names on.
	local character = humanoid.Parent
	local head = character and character:FindFirstChild("Head")
	-- RoleTag is the job chip RoleBootstrap hangs above the title; it has to follow the
	-- same rule, or turning names off leaves a row of floating job labels behind.
	for _, tagName in ipairs({ "TitleTag", "RoleTag" }) do
		local tag = head and head:FindFirstChild(tagName)
		if tag then
			-- only re-show a tag that actually has something to say
			local label = tag:FindFirstChild("Label")
			tag.Enabled = namesVisible and label ~= nil and label.Text ~= ""
		end
	end
end

local function watchCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	applyToHumanoid(humanoid)
end

local function watchPlayer(other)
	if other.Character then
		watchCharacter(other.Character)
	end
	other.CharacterAdded:Connect(watchCharacter)
end

function M.Init()
	if initialized then
		return
	end
	initialized = true
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

function M.SetVisible(visible)
	namesVisible = visible
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			applyToHumanoid(other.Character:FindFirstChildOfClass("Humanoid"))
		end
	end
end

function M.IsVisible()
	return namesVisible
end

return M