-- DeepRunService -- the warning plates at the mouth of each air-gated deep run.
--
-- The five deep runs are gated by physics, not by a permission check: they are
-- simply longer than a smaller lung survives the round trip on. That only works
-- as design if the diver can see the price BEFORE they commit. Without a plate it
-- is not a gate, it is an ambush -- a diver swims a beautiful winding tunnel for
-- forty seconds and drowns on the way back having never been told anything.
--
-- BreathService owns the real numbers; they are restated here only as display
-- text: base lung 45s, +15s per Lung Coral, 3 corals max -> 45 / 60 / 75 / 90.

local ServerStorage = game:GetService("ServerStorage")
local CaveGen = require(ServerStorage:WaitForChild("CaveGen"))

local FOLDER_NAME = "DeepRunMarkers"
local TIER_CAP = { [1] = 60, [2] = 75, [3] = 90 }

local function buildMarker(run, parent)
	local samples, length = CaveGen.DeepRunSamples(run)
	-- a few spheres in: at the point where it stops being the chamber and starts
	-- being the swim, so the plate is read at the decision, not after it
	local pos = samples[math.min(5, #samples)]

	local anchor = Instance.new("Part")
	anchor.Name = "Mouth_" .. run.key
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = pos
	anchor:SetAttribute("Tier", run.tier)
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Size = UDim2.fromScale(15, 6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 100
	gui.LightInfluence = 0
	gui.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(9, 21, 29)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 168, 86)
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local function line(order, height, font, colour, text)
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.Size = UDim2.fromScale(1, height)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = colour
		l.Text = text
		l.Parent = frame
		return l
	end

	line(1, 0.38, Enum.Font.GothamBold, Color3.fromRGB(235, 245, 250), run.label)
	line(2, 0.26, Enum.Font.Gotham, Color3.fromRGB(150, 200, 220),
		string.format("%.0f studs in \u{2014} and %.0f back out", length, length))
	line(3, 0.30, Enum.Font.GothamBold, Color3.fromRGB(255, 168, 86),
		string.format("NEEDS %d LUNG CORAL%s \u{2014} %ds of air",
			run.tier, run.tier > 1 and "S" or "", TIER_CAP[run.tier]))
end

local function build()
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	for _, run in ipairs(CaveGen.DeepRuns) do
		buildMarker(run, folder)
	end
	print("[DeepRunService] " .. #CaveGen.DeepRuns .. " deep-run plates placed")
end

build()
