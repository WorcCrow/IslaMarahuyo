-- RoleBootstrap
-- Starts RoleService and owns everything physical about it: the work board at the plaza,
-- the idle animation on the four role bots, and the duty line under each bot's name.
--
-- One shared Heartbeat drives all the bots, the same shape as AmbientAnimalController's
-- single loop for seven chickens. Nurse Fely is deliberately left out of the idle sway --
-- ReviveService already animates her from its own loop and two loops fighting over the
-- same parts would jitter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RoleService = require(script.Parent.RoleService)

local isla = workspace:WaitForChild("IslaMarahuyo")
local botFolder = isla:WaitForChild("RoleBots")
local board = isla:WaitForChild("RoleBoard")
local boardFace = board.Board:WaitForChild("Face")
local roster = boardFace.Frame:WaitForChild("Roster")
local prompt = board.Board:WaitForChild("RolePrompt")

local openBoard = game:GetService("ReplicatedStorage").Remotes:FindFirstChild("OpenRoleBoard")
if not openBoard then
	openBoard = Instance.new("RemoteEvent")
	openBoard.Name = "OpenRoleBoard"
	openBoard.Parent = game:GetService("ReplicatedStorage").Remotes
end

-- forward-declared: OnRosterChanged below closes over it, but it is defined further down.
-- Without this it compiles as a global lookup and is nil at runtime.
local refreshChip

-- ===== the board face =====
local function repaintBoard(rows)
	local lines = {}
	for _, row in ipairs(rows) do
		local who
		if #row.holders > 0 then
			who = table.concat(row.holders, ", ")
		elseif not row.open then
			who = "closed until sunrise"
		else
			who = row.bot .. " is covering"
		end
		table.insert(lines, string.format("%s  -  %s", string.upper(row.label), who))
	end
	roster.Text = table.concat(lines, "\n")
end

-- ===== the duty line under each bot's name =====
local function repaintBots(rows)
	for _, row in ipairs(rows) do
		local role = RoleService.Roles[row.key]
		local model = botFolder:FindFirstChild(role.bot)
			or isla.Activities.MedicalDock:FindFirstChild(role.bot)
		local torso = model and (model.PrimaryPart or model:FindFirstChild("Torso"))
		local tag = torso and torso:FindFirstChild("NameTag")
		local label = tag and tag:FindFirstChild("TextLabel")
		if label then
			local duty
			if #row.holders > 0 then
				-- the bot stays put; what changes is who the work is routed to
				duty = string.format("off duty - %s: %s", row.label, table.concat(row.holders, ", "))
			elseif not row.open then
				duty = "closed until sunrise"
			else
				duty = "on duty - " .. row.post
			end
			label.Text = role.botLine .. "\n" .. duty
		end
	end
end

RoleService.OnRosterChanged = function(rows)
	repaintBoard(rows)
	repaintBots(rows)
	-- the market chip flips to "off shift" on the clock, not only when someone claims
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Role") then
			task.spawn(refreshChip, player)
		end
	end
end

prompt.Triggered:Connect(function(player)
	openBoard:FireClient(player, RoleService.Snapshot(), player:GetAttribute("Role"))
end)

-- ===== the role chip above a player's head =====
-- Deliberately its own BillboardGui rather than a line inside TitleTagService's tag.
-- That service documents a priority -- custom pass > Island Legend > earned cave title --
-- and a job anybody can take for free must not be able to displace something bought or
-- earned. So the role rides above the title instead of competing with it.
local ROLE_TAG = "RoleTag"

local function roleTagFor(character)
	local head = character and character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local existing = head:FindFirstChild(ROLE_TAG)
	if existing then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = ROLE_TAG
	gui.Size = UDim2.new(0, 200, 0, 22)
	-- clears TitleTagService's tag, which sits at 3.1
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.95, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90 -- same draw distance as names and titles
	gui.Enabled = false
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = ""
	label.Parent = gui
	return gui
end

function refreshChip(player)
	local character = player.Character
	local gui = character and roleTagFor(character)
	if not gui then
		return
	end
	local label = gui:FindFirstChild("Label")
	local key = player:GetAttribute("Role")
	local role = key and RoleService.Roles[key]
	if not role then
		label.Text = ""
		gui.Enabled = false
		return
	end
	local onShift = RoleService.ShiftOpen(key)
	label.Text = onShift and string.upper(role.label)
		or (string.upper(role.label) .. " (off shift)")
	label.TextColor3 = onShift and role.tint or Color3.fromRGB(150, 156, 168)
	gui.Enabled = true
end

local function watchPlayer(player)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		refreshChip(player)
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.4) -- let the Head replicate before parenting a billboard to it
		refreshChip(player)
	end)
	if player.Character then
		refreshChip(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

-- ===== idle sway =====
-- Attribute-driven rest pose plus a slow sine, so a bot standing at its post is never
-- quite still. Each bot is offset by a per-bot phase or the four of them breathe in sync
-- and read as one machine rather than four people.
local swaying = {}
for index, model in ipairs(botFolder:GetChildren()) do
	local entry = { model = model, phase = index * 1.7, parts = {} }
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("HomeY") then
			table.insert(entry.parts, part)
		end
	end
	table.insert(swaying, entry)
end

local t = 0
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	-- 20Hz is plenty for a breathing idle and keeps four bots off the frame budget
	accumulated += dt
	if accumulated < 0.05 then
		return
	end
	t += accumulated
	accumulated = 0

	for _, entry in ipairs(swaying) do
		local breath = math.sin(t * 1.4 + entry.phase) * 0.05
		local lean = math.sin(t * 0.55 + entry.phase) * 0.025
		for _, part in ipairs(entry.parts) do
			local home = Vector3.new(
				part:GetAttribute("HomeX"),
				part:GetAttribute("HomeY"),
				part:GetAttribute("HomeZ")
			)
			-- legs stay planted; everything above the waist rides the breath
			local rise = (part.Name == "LegL" or part.Name == "LegR") and 0 or breath
			part.CFrame = CFrame.new(home + Vector3.new(0, rise, 0)) * CFrame.Angles(0, lean, 0)
		end
	end
end)

RoleService.Init()
task.defer(RoleService.Broadcast)

print(string.format("[RoleBootstrap] %d roles open at the Barangay work board, %d bots covering",
	#RoleService.Snapshot(), #botFolder:GetChildren() + 1))
