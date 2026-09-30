-- CaveXrayController -- admin-only X-ray of Perlas ng Dagat ("Cave Map" in the top bar's
-- menu, or F8 on a keyboard).
--
-- Everything this builds is parented to workspace.CurrentCamera, which is the point:
-- children of the camera exist ONLY on this client and never replicate, so the
-- overlay is physically incapable of leaking to a player who is not an admin. The
-- server-side permission check is still the real boundary -- this is just belt and
-- braces, and it means no one else sees a lit-up cave hanging in the water.
--
-- Seeing through the rock is done with Highlight at DepthMode.AlwaysOnTop, which
-- draws the adornee over everything in front of it. Highlights are a limited
-- resource (Roblox starts complaining past ~31), so there is exactly ONE per status
-- group rather than one per segment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local caveXray = remotes:WaitForChild("CaveXray")

-- The server may not have bound OnServerInvoke yet on a cold start; an unbound
-- RemoteFunction throws rather than returning nil, so this retries rather than
-- concluding "not an admin" from a startup race.
local function confirmAdmin()
	for _ = 1, 12 do
		local ok, res = pcall(function()
			return caveXray:InvokeServer("whoami")
		end)
		if ok then
			return res == true
		end
		task.wait(1)
	end
	return false
end

if not confirmAdmin() then
	return -- not an admin: no keybind, no button, no UI, nothing built
end

local COLOURS = {
	passable = Color3.fromRGB(74, 226, 154),
	pinched  = Color3.fromRGB(255, 190, 72),
	rubble   = Color3.fromRGB(255, 138, 62),
	fault    = Color3.fromRGB(255, 76, 76),
	air      = Color3.fromRGB(255, 190, 90),
	water    = Color3.fromRGB(90, 180, 225),
}
local STATUS_TEXT = {
	passable = "passable",
	pinched  = "passable, pinched",
	rubble   = "sealed by today's cave-in",
	fault    = "BLOCKED",
}

local function statusOf(p)
	if not p.passable then
		return p.expected and "rubble" or "fault"
	end
	return p.pinched and "pinched" or "passable"
end

-- ---------------------------------------------------------------- overlay ----
local root = nil
local shown = false
local snapshot = nil

local function destroyOverlay()
	if root then
		root:Destroy()
		root = nil
	end
end

local function newGroup(parent, colour)
	local model = Instance.new("Model")
	model.Parent = parent
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- this is the see-through-rock bit
	hl.FillColor = colour
	hl.OutlineColor = Color3.new(
		math.min(1, colour.R + 0.35), math.min(1, colour.G + 0.35), math.min(1, colour.B + 0.35))
	hl.FillTransparency = 0.3
	hl.OutlineTransparency = 0
	hl.Adornee = model
	hl.Parent = model
	return model
end

-- Plain matte parts, NOT Neon. Neon ignores colour under bright lighting and blows
-- every status out to the same white, which loses the one thing the overlay exists
-- to communicate. The Highlight supplies both the colour and the see-through.
local function wire(a, b, thickness, colour, parent)
	local delta = b - a
	local len = delta.Magnitude
	if len < 0.05 then return end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = colour
	p.Size = Vector3.new(thickness, thickness, len)
	p.CFrame = CFrame.lookAt(a + delta * 0.5, b)
	p.Parent = parent
end

local function blob(pos, size, colour, parent)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = colour
	-- chambers are big; left solid they swallow the passages that matter more
	p.Transparency = 0.45
	p.Size = Vector3.new(size, size, size)
	p.Position = pos
	p.Parent = parent
	return p
end

local function tag(part, text, colour, distance)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(12, 2.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = distance or 400
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = colour
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
end

local function buildOverlay(snap)
	destroyOverlay()
	root = Instance.new("Folder")
	root.Name = "CaveXray"
	-- camera children are local-only; this can never reach another player
	root.Parent = workspace.CurrentCamera

	local groups = {}
	for key, colour in pairs(COLOURS) do
		groups[key] = newGroup(root, colour)
	end

	for _, p in ipairs(snap.passages) do
		local key = statusOf(p)
		local group = groups[key]
		-- trunk tunnels draw fatter than deep runs, so the bore difference that makes
		-- the air gate work is visible in the X-ray too
		local thickness = math.clamp(p.bore / 3.5, 1.2, 3)
		for i = 1, #p.points - 1 do
			-- a single bad segment inside an otherwise fine passage still draws red
			local segKey = p.blockedPoints[i] and "fault" or key
			wire(p.points[i], p.points[i + 1], thickness, COLOURS[segKey], groups[segKey])
		end
		if p.blockPos then
			local blockKey = p.expected and "rubble" or "fault"
			local marker = blob(p.blockPos, 9, COLOURS[blockKey], groups[blockKey])
			tag(marker, (p.expected and "CAVE-IN\n" or "BLOCKED " .. tostring(p.blockMaterial) .. "\n") .. p.label,
				COLOURS[blockKey], 600)
		end
	end

	for _, n in ipairs(snap.nodes) do
		local key = n.air and "air" or "water"
		if not n.reachable then
			key = n.structural and "rubble" or "fault"
		end
		local marker = blob(n.pos, math.max(6, n.r), COLOURS[key], groups[key])
		local suffix = ""
		if not n.reachable then
			suffix = n.structural and "  (behind today's rubble)" or "  (CUT OFF)"
		end
		tag(marker, n.label .. suffix, COLOURS[key], 500)
	end
end

-- -------------------------------------------------------------------- UI ----
local gui = Instance.new("ScreenGui")
gui.Name = "CaveXrayGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 12, 0.5, 0)
panel.Size = UDim2.new(0, 320, 0, 430)
panel.BackgroundColor3 = Color3.fromRGB(9, 20, 27)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(60, 110, 130)
panelStroke.Thickness = 1

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 10)
title.Size = UDim2.new(1, -60, 0, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 245, 250)
title.Text = "CAVE X-RAY"
title.Parent = panel

local verdict = Instance.new("TextLabel")
verdict.BackgroundTransparency = 1
verdict.Position = UDim2.new(0, 14, 0, 31)
verdict.Size = UDim2.new(1, -28, 0, 32)
verdict.Font = Enum.Font.Gotham
verdict.TextSize = 11
verdict.TextWrapped = true
verdict.TextXAlignment = Enum.TextXAlignment.Left
verdict.TextYAlignment = Enum.TextYAlignment.Top
verdict.TextColor3 = Color3.fromRGB(150, 195, 215)
verdict.Text = "Measuring..."
verdict.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Position = UDim2.new(1, -34, 0, 8)
closeBtn.Size = UDim2.fromOffset(24, 24)
closeBtn.BackgroundTransparency = 1
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = Color3.fromRGB(150, 195, 215)
closeBtn.Text = "\u{00D7}"
closeBtn.Parent = panel

local refreshBtn = Instance.new("TextButton")
refreshBtn.AnchorPoint = Vector2.new(0, 1)
refreshBtn.Position = UDim2.new(0, 14, 1, -12)
refreshBtn.Size = UDim2.new(1, -28, 0, 28)
refreshBtn.BackgroundColor3 = Color3.fromRGB(24, 52, 66)
refreshBtn.BorderSizePixel = 0
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 12
refreshBtn.TextColor3 = Color3.fromRGB(215, 238, 246)
refreshBtn.Text = "RE-MEASURE"
refreshBtn.Parent = panel
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 8, 0, 68)
list.Size = UDim2.new(1, -16, 1, -114)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.ScrollBarImageColor3 = Color3.fromRGB(80, 140, 165)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function row(p, order)
	local key = statusOf(p)
	local btn = Instance.new("TextButton")
	btn.LayoutOrder = order
	btn.Size = UDim2.new(1, -6, 0, 34)
	btn.BackgroundColor3 = Color3.fromRGB(15, 32, 42)
	btn.BackgroundTransparency = 0.25
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = true
	btn.Parent = list
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

	local dot = Instance.new("Frame")
	dot.Position = UDim2.new(0, 8, 0.5, -9)
	dot.Size = UDim2.fromOffset(4, 18)
	dot.BackgroundColor3 = COLOURS[key]
	dot.BorderSizePixel = 0
	dot.Parent = btn

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 20, 0, 3)
	name.Size = UDim2.new(1, -28, 0, 15)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 11
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = Color3.fromRGB(225, 240, 247)
	name.Text = p.label
	name.Parent = btn

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0, 20, 0, 17)
	status.Size = UDim2.new(1, -28, 0, 13)
	status.Font = Enum.Font.Gotham
	status.TextSize = 10
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextColor3 = COLOURS[key]
	local extra = ""
	if key == "pinched" then
		extra = string.format(" \u{2013} %.1f studs clear", p.minClearance)
	elseif key == "fault" then
		extra = " \u{2013} " .. tostring(p.blockMaterial)
	end
	status.Text = STATUS_TEXT[key] .. extra .. "  \u{2022} tap to go"
	status.Parent = btn

	btn.Activated:Connect(function()
		if p.goTo then
			caveXray:InvokeServer("goto", { pos = p.goTo })
		end
	end)
end

local function render(snap)
	snapshot = snap
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end

	local head = snap.healthy
		and "Cave is playable. Every air pocket reachable, no unexplained blockage."
		or string.format("NEEDS ATTENTION \u{2013} %d carve fault(s), %d air pocket(s) cut off.",
			snap.carveFaults, #snap.unreachableAir)
	if snap.sealedToday and snap.sealedToday ~= "" then
		head = head .. "  Today's cave-in: " .. snap.sealedToday .. "."
	end
	verdict.Text = head
	verdict.TextColor3 = snap.healthy and COLOURS.passable or COLOURS.fault

	-- worst first: an admin opening this wants the problem, not an alphabet
	local rank = { fault = 1, rubble = 2, pinched = 3, passable = 4 }
	local sorted = table.clone(snap.passages)
	table.sort(sorted, function(x, y)
		local rx, ry = rank[statusOf(x)], rank[statusOf(y)]
		if rx ~= ry then return rx < ry end
		return x.label < y.label
	end)
	for i, p in ipairs(sorted) do
		row(p, i)
	end

	buildOverlay(snap)
end

local busy = false
local function measure()
	if busy then return end
	busy = true
	refreshBtn.Text = "MEASURING..."
	local ok, snap = pcall(function()
		return caveXray:InvokeServer("audit")
	end)
	refreshBtn.Text = "RE-MEASURE"
	busy = false
	if ok and snap then
		render(snap)
	else
		verdict.Text = "Could not reach the server for a measurement."
		verdict.TextColor3 = COLOURS.fault
	end
end

local function setShown(state)
	shown = state
	gui.Enabled = state
	if state then
		measure()
	else
		destroyOverlay()
	end
end

PanelUtil.Register("cavemap", {
	open = function() setShown(true) end,
	close = function() setShown(false) end,
	isOpen = function() return shown end,
})

closeBtn.Activated:Connect(function() PanelUtil.Close("cavemap") end)
refreshBtn.Activated:Connect(measure)

-- F8 on a keyboard. Touch admins open it from the top bar's menu, so no floating
-- on-screen button is created any more.
ContextActionService:BindAction("ToggleCaveXray", function(_, state)
	if state == Enum.UserInputState.Begin then
		PanelUtil.Toggle("cavemap")
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.F8)

-- tells the top bar to offer the Cave Map entry (local-only; the server still gates every
-- x-ray request)
player:SetAttribute("ClientCaveXray", true)

print("[CaveXrayController] admin cave X-ray armed -- press F8")
