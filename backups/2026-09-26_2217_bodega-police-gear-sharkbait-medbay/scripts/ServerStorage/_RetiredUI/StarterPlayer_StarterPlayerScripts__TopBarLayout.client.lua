-- TopBarLayout
-- One owner for the strip along the top of the screen.
--
-- The pieces up there are built by three different scripts (the Shells chip and the toggle
-- row by HUDController, the music pill by MusicController, the ADMIN button by
-- AdminDashboardController), and each used to position itself independently against a
-- corner. That works until two of them pick the same corner -- which is exactly what
-- happened: the toggles landed underneath the music pill and the ADMIN button, and the
-- ADMIN button sat on top of the music pill.
--
-- Independent corner anchoring can't be made safe by nudging numbers, because the widths
-- are fixed and the screen is not. So this lays the row out AS a row: fixed things from the
-- left, fixed things from the right, and the one genuinely elastic element (the music pill)
-- absorbs whatever width is left. It re-runs whenever the viewport changes, so it holds on
-- a phone, on a tablet, and after a rotation.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local MARGIN = 8
local GAP = 8
local ROW_Y = 6
local ROW_H = 32

local BUTTON = 32
local BUTTON_GAP = 7
local BUTTONS_W = BUTTON * 3 + BUTTON_GAP * 2
local CHIP_W = 96
local ADMIN_W = 90
local PILL_MAX = 244
local PILL_MIN = 78

local function findGui(name, timeout)
	local t0 = os.clock()
	repeat
		local g = playerGui:FindFirstChild(name)
		if g then
			return g
		end
		task.wait(0.2)
	until os.clock() - t0 > (timeout or 10)
	return nil
end

local hud = findGui("ShellsHUD", 20)
if not hud then
	warn("[TopBarLayout] no ShellsHUD -- top bar left as built")
	return
end

local buttons = hud:WaitForChild("HudButtons", 20)
local chip = hud:WaitForChild("ShellsChip", 20)

local function layout()
	if not (buttons and buttons.Parent and chip and chip.Parent) then
		return
	end

	local width = camera.ViewportSize.X

	-- toggles at the far left of the strip
	buttons.AnchorPoint = Vector2.new(0, 0)
	buttons.Position = UDim2.new(0, MARGIN, 0, ROW_Y)
	buttons.Size = UDim2.new(0, BUTTONS_W, 0, ROW_H)
	for _, b in ipairs(buttons:GetChildren()) do
		if b:IsA("TextButton") then
			b.Size = UDim2.new(0, BUTTON, 0, BUTTON)
		end
	end
	local listLayout = buttons:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.Padding = UDim.new(0, BUTTON_GAP)
	end

	-- Shells chip immediately to their right
	local chipX = MARGIN + BUTTONS_W + GAP
	chip.AnchorPoint = Vector2.new(0, 0)
	chip.Position = UDim2.new(0, chipX, 0, ROW_Y)
	chip.Size = UDim2.new(0, CHIP_W, 0, ROW_H)

	local leftEnd = chipX + CHIP_W -- anything on the right must start after this

	-- ADMIN button hugs the right edge, when the viewer is an admin at all
	local adminGui = playerGui:FindFirstChild("AdminDashboardGui")
	local adminBtn = adminGui and adminGui:FindFirstChild("ToggleButton")
	local adminShown = adminBtn ~= nil and adminBtn.Visible
	local rightEdge = width - MARGIN

	if adminShown then
		adminBtn.AnchorPoint = Vector2.new(1, 0)
		adminBtn.Position = UDim2.new(1, -MARGIN, 0, ROW_Y)
		adminBtn.Size = UDim2.new(0, ADMIN_W, 0, ROW_H)
		rightEdge = rightEdge - ADMIN_W - GAP
	end

	-- the music pill takes whatever is left between the two, and is the thing that gives
	local pillGui = playerGui:FindFirstChild("MusicHUD")
	local pill = pillGui and pillGui:FindFirstChild("Pill")
	if pill then
		local available = rightEdge - leftEnd - GAP

		if available < PILL_MIN and adminShown then
			-- A creator on a narrow phone: even the smallest pill won't fit beside the ADMIN
			-- button, so ADMIN drops to a second row rather than the two stacking. It's the
			-- rarest element on screen, so it's the right one to move.
			adminBtn.Position = UDim2.new(1, -MARGIN, 0, ROW_Y + ROW_H + 6)
			rightEdge = width - MARGIN
			available = rightEdge - leftEnd - GAP
		end

		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Size = UDim2.new(0, math.clamp(available, PILL_MIN, PILL_MAX), 0, ROW_H)
		pill.Position = UDim2.new(0, rightEdge, 0, ROW_Y)
	end
end

layout()

-- Re-run on rotation/resize, and a few times just after joining: some of these panels are
-- built by their own scripts a frame or two late and would otherwise keep the position they
-- were born with.
camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
task.spawn(function()
	for _ = 1, 12 do
		task.wait(0.5)
		local ok, err = pcall(layout)
		if not ok then
			warn("[TopBarLayout] layout failed:", err)
			return
		end
	end
end)
