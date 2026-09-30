-- CaveInService -- the daily collapse in Perlas ng Dagat.
--
-- Once per in-game day the cave reshuffles: yesterday's rubble is cleared and a
-- new passage caves in near its FAR end, so a diver only finds the blockage after
-- spending most of a lung getting there. That is the point -- the map you
-- memorised yesterday is not quite the map you are swimming today, and the way
-- back out is the part you have to keep air for.
--
-- Two rules keep it cruel rather than merely unfair:
--   1) Only DEAD ENDS can collapse (CaveGen.Sealable). Sealing one can never cut
--      the cave in half, orphan an air pocket, or block a route to an exit -- the
--      trunk lines and every tunnel feeding a rest grotto are excluded by hand.
--   2) Nothing is ever sealed while a diver is behind it. CaveGen.BeyondPoints
--      enumerates everything that would end up on the far side of the rubble --
--      the rest of the passage, the chambers it leads to, and any deep run
--      launching from one of those chambers -- and if a player is within
--      CLEAR_RADIUS of any of it, that passage is skipped and another is drawn.
--      If every candidate is occupied the day simply passes without a collapse;
--      skipping a day is strictly better than burying somebody.
--
-- Terrain edits made here are RUNTIME ONLY. They live in the running server and
-- vanish on restart, which is right: a fresh server starts from the clean carve
-- baked into the place file, owing no rubble to anyone.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local CaveGen = require(ServerStorage:WaitForChild("CaveGen"))

local CLEAR_RADIUS = 45 -- no diver may be this close to anything behind the rubble
local MARKER_NAME = "CaveInMarker"

local rng = Random.new()
local currentIndex = nil

local function clearMarker()
	local existing = workspace:FindFirstChild(MARKER_NAME)
	if existing then
		existing:Destroy()
	end
end

-- A sign on the rubble face. Without it a diver who spends 40 seconds of air
-- reaching a blocked passage has no way to tell a fresh collapse from a mistake
-- in their own memory of the cave, and the mechanic just reads as the map being
-- broken.
local function placeMarker(entry, pos)
	clearMarker()
	local anchor = Instance.new("Part")
	anchor.Name = MARKER_NAME
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = pos
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "CaveInLabel"
	gui.Size = UDim2.fromScale(13, 4)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 168, 86)
	label.TextStrokeTransparency = 0.35
	label.Text = "GUHO \u{2014} CAVE-IN\nthis way is closed today"
	label.Parent = gui
end

local function isOccupied(entry)
	local pts = CaveGen.BeyondPoints(entry)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local at = hrp.Position
			for _, p in ipairs(pts) do
				if (at - p).Magnitude < CLEAR_RADIUS then
					return true
				end
			end
		end
	end
	return false
end

local function shuffled(n)
	local order = {}
	for i = 1, n do
		order[i] = i
	end
	for i = n, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

local function collapse()
	-- clear yesterday's rubble FIRST, so only ever one passage is shut at a time
	local previous = currentIndex
	if previous then
		CaveGen.OpenPassage(CaveGen.Sealable[previous])
		currentIndex = nil
		clearMarker()
	end

	for _, i in ipairs(shuffled(#CaveGen.Sealable)) do
		-- never the same passage two days running; the point is that it moves
		if i ~= previous then
			local entry = CaveGen.Sealable[i]
			if not isOccupied(entry) then
				local plugPos = CaveGen.SealPassage(entry)
				currentIndex = i
				workspace:SetAttribute("CaveInPassage", entry.label)
				placeMarker(entry, plugPos)
				print(string.format("[CaveInService] day %s: collapsed %s",
					tostring(workspace:GetAttribute("IslandDay")), entry.label))
				return entry
			end
		end
	end

	-- everything was occupied (or only yesterday's passage was free): no collapse
	workspace:SetAttribute("CaveInPassage", "")
	print("[CaveInService] no passage was safe to collapse today")
	return nil
end

workspace:GetAttributeChangedSignal("IslandDay"):Connect(collapse)

-- first collapse of the server's life
task.defer(collapse)
