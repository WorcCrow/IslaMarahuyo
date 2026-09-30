-- IslandNameController
-- Client-side show/hide for the always-on location-name billboards scattered across the
-- island: the 7 zone signs ("Palengke Market", "Baybayon Beach", ...) and the 4 zipline
-- tower markers ("Batong Timog", ...). These are world-space BillboardGuis with
-- MaxDistance = inf, so once shown they're visible from anywhere on the map -- this just
-- flips their Enabled flag on the local client, the same pattern NameTagController uses for
-- player name tags. Purely cosmetic clutter, not the interactive tags (crate orders, net
-- buoy info, plot signs, boat names, the nurse's name), so those are left alone.

local M = {}

local visible = false
local billboards = {}
local initialized = false

local function applyTo(billboard)
	billboard.Enabled = visible
end

local function track(billboard)
	if billboard:IsA("BillboardGui") then
		billboards[billboard] = true
		applyTo(billboard)
		billboard.AncestryChanged:Connect(function(_, parent)
			if not parent then
				billboards[billboard] = nil
			end
		end)
	end
end

-- WaitForChild (not FindFirstChild) on the way down: the workspace streams in, and a zone's
-- Part can exist a frame or two before its Label BillboardGui (or a station's Anchor/
-- BillboardGui) has replicated, so a plain FindFirstChild here can silently find nothing.
local function watchZone(zone)
	local label = zone:WaitForChild("Label", 5)
	if label then
		track(label)
	end
end

local function watchStation(station)
	local anchor = station:WaitForChild("Anchor", 5)
	local billboard = anchor and anchor:WaitForChild("BillboardGui", 5)
	if billboard then
		track(billboard)
	end
end

function M.Init()
	if initialized then
		return
	end
	initialized = true

	local isla = workspace:WaitForChild("IslaMarahuyo")

	local zonesFolder = isla:WaitForChild("Zones")
	for _, zone in ipairs(zonesFolder:GetChildren()) do
		task.spawn(watchZone, zone)
	end
	zonesFolder.ChildAdded:Connect(function(zone)
		task.spawn(watchZone, zone)
	end)

	local zipline = isla:WaitForChild("Activities"):WaitForChild("Zipline", 5)
	if zipline then
		for _, station in ipairs(zipline:GetChildren()) do
			task.spawn(watchStation, station)
		end
		zipline.ChildAdded:Connect(function(station)
			task.spawn(watchStation, station)
		end)
	end
end

function M.SetVisible(state)
	visible = state
	for billboard in pairs(billboards) do
		applyTo(billboard)
	end
end

function M.IsVisible()
	return visible
end

return M
