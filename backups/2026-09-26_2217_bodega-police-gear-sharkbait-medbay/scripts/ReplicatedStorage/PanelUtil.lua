-- PanelUtil (client only)
-- One owner for every popup panel on screen.
--
-- Two bugs this exists to fix, both of which happened because each script ran its own
-- panel in isolation:
--   * zoomed into first person (or with shift lock on) the mouse is locked to the centre
--     of the screen, so an open panel's Close button could not be reached at all;
--   * a panel opened at a counter, a stall or a bodega stayed open after you walked off.
--
-- Scripts register a panel once, then open and close it through here. While anything is
-- open the cursor is freed: a Modal button (the engine's own release), plus a render step
-- just after the camera's, because the camera re-locks the mouse every frame in first
-- person and the Modal button alone did not win that fight.
-- A panel opened with an anchor closes itself when the player walks out of range, and a
-- panel with a stayOpen() check closes the moment that check fails.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local PanelUtil = {}

local player = Players.LocalPlayer
local entries = {} -- [name] = {open, close, isOpen, stayOpen}
local anchors = {} -- [name] = {at = Vector3 | Instance, radius = number}
local lastState = {} -- [name] = bool, so Changed only fires on a real change

local changed = Instance.new("BindableEvent")
PanelUtil.Changed = changed.Event -- (name, isOpen)

local DEFAULT_RADIUS = 18

local modalButton
local function ensureModal()
	if modalButton and modalButton.Parent and modalButton.Parent.Parent then
		return modalButton
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PanelModal"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10
	gui.Parent = player:WaitForChild("PlayerGui")
	modalButton = Instance.new("TextButton")
	modalButton.Name = "FreeCursor"
	modalButton.Size = UDim2.fromOffset(1, 1)
	modalButton.BackgroundTransparency = 1
	modalButton.Text = ""
	modalButton.Modal = true
	modalButton.Visible = false
	modalButton.Parent = gui
	return modalButton
end

local function positionOf(at)
	if typeof(at) == "Vector3" then
		return at
	end
	if typeof(at) == "Instance" and at.Parent then
		if at:IsA("BasePart") then
			return at.Position
		end
		if at:IsA("Model") then
			return at:GetPivot().Position
		end
	end
	return nil
end

local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function isOpen(name)
	local e = entries[name]
	return e ~= nil and e.isOpen() == true
end

local FREE_CURSOR = "PanelUtilFreeCursor"
local cursorBound = false
local function setCursorFree(free)
	if free and not cursorBound then
		cursorBound = true
		RunService:BindToRenderStep(FREE_CURSOR, Enum.RenderPriority.Camera.Value + 10, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	elseif not free and cursorBound then
		cursorBound = false
		RunService:UnbindFromRenderStep(FREE_CURSOR)
	end
end

local function sync()
	local any = false
	for name in pairs(entries) do
		local open = isOpen(name)
		any = any or open
		if lastState[name] ~= open then
			lastState[name] = open
			if not open then
				anchors[name] = nil
			end
			changed:Fire(name, open)
		end
	end
	ensureModal().Visible = any
	setCursorFree(any)
end

-- spec = {open = fn, close = fn, isOpen = fn -> bool, stayOpen = fn -> bool (optional)}
function PanelUtil.Register(name, spec)
	entries[name] = spec
	lastState[name] = spec.isOpen() == true
end

function PanelUtil.IsOpen(name)
	return isOpen(name)
end

-- opts.anchor: a Vector3, BasePart or Model the panel belongs to, or "here" for wherever
-- the player is standing when it opens. opts.radius: how far they may wander.
function PanelUtil.Open(name, opts)
	local e = entries[name]
	if not e then
		return
	end
	if not e.isOpen() then
		e.open()
	end
	local at = opts and opts.anchor
	if at == "here" then
		at = rootPosition()
	end
	anchors[name] = at and {at = at, radius = (opts and opts.radius) or DEFAULT_RADIUS} or nil
	sync()
end

function PanelUtil.Close(name)
	local e = entries[name]
	if e and e.isOpen() then
		e.close()
	end
	anchors[name] = nil
	sync()
end

function PanelUtil.Toggle(name, opts)
	if isOpen(name) then
		PanelUtil.Close(name)
	else
		PanelUtil.Open(name, opts)
	end
end

-- A small x in the top-right corner, for panels that were only ever closed by the same
-- button that opened them. Idempotent, so a panel rebuilt on respawn does not get two.
function PanelUtil.AddCloseButton(frame, name)
	local closeName = "PanelClose_" .. name
	if frame:FindFirstChild(closeName) or (frame.Parent and frame.Parent:FindFirstChild(closeName)) then
		return
	end
	local close = Instance.new("TextButton")
	close.Name = closeName
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.Size = UDim2.fromOffset(26, 26)
	close.BackgroundColor3 = Color3.fromRGB(52, 40, 36)
	close.BackgroundTransparency = 0.2
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(236, 210, 190)
	close.Text = "\u{00D7}"
	close.ZIndex = 10
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)

	-- A panel laid out by a UIListLayout would pull the button into its flow, so there it
	-- floats beside the panel instead, following its corner and its visibility.
	if frame:FindFirstChildWhichIsA("UIGridStyleLayout") and frame.Parent then
		close.Parent = frame.Parent
		local function follow()
			local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
			close.Position = UDim2.fromOffset(pos.X + size.X - 6, pos.Y + 6)
			close.Visible = frame.Visible
		end
		frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow)
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
		frame:GetPropertyChangedSignal("Visible"):Connect(follow)
		follow()
	else
		close.Parent = frame
	end
	close.Activated:Connect(function()
		PanelUtil.Close(name)
	end)
end

-- For panels a script shows or hides on its own (a server push, its own X button):
-- call this afterwards so the cursor and any topbar icon catch up straight away.
function PanelUtil.Refresh()
	sync()
end

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < 0.25 then
		return
	end
	accum = 0

	local here = rootPosition()
	for name, e in pairs(entries) do
		if e.isOpen() then
			local anchor = anchors[name]
			local target = anchor and positionOf(anchor.at)
			local walkedOff = anchor ~= nil and (target == nil
				or (here ~= nil and (here - target).Magnitude > anchor.radius))
			local lostReason = e.stayOpen ~= nil and not e.stayOpen()
			if walkedOff or lostReason then
				e.close()
				anchors[name] = nil
			end
		end
	end
	sync()
end)

return PanelUtil
