-- CaveSignService (Karatula sa Yungib)
-- A slate at every fork in the cave that ANY diver can rewrite. The point is that the
-- game never verifies what it says: an honest diver marks the way to the air pocket, and
-- a dishonest one points you down the Blind Burrow with no air at the end. Both are
-- legitimate uses -- the signs are player-to-player information, trustworthy or not, and
-- working out which is which is the game.
--
-- Two things are enforced regardless. Every message goes through Roblox text filtering
-- before anyone else can read it (and is refused outright if filtering can't be reached,
-- rather than broadcast unchecked), and the author's name is stamped on the slate they
-- wrote -- so lying is allowed, but lying anonymously is not.
--
-- Sign text lives for the life of the server rather than in the DataStore, same as the
-- cabin plots: a persistent cross-server board is a moderation surface of a different
-- size and wants its own decision.

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaveGen = require(game.ServerStorage.CaveGen)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

local function ensureRemote(name)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local signPrompt = ensureRemote("CaveSignPrompt") -- server -> client: open the writing panel
local signWrite = ensureRemote("CaveSignWrite") -- client -> server: here is my message

local MAX_LENGTH = 70
local WRITE_COOLDOWN = 8
local REACH = 24

-- One slate per air chamber. A pocket is the only place in the cave a diver can stand
-- still long enough to read or write anything, and it is the one place they arrive
-- wanting to know which way the next hole leads.
local SIGN_NODES = { "Hub", "RestA", "RestB", "RestC", "RestD", "RestE", "RestF", "RestG", "RestH", "RestI", "RestJ", "Treasure" }

local DEFAULT_TEXT = "Blank slate -- hold F to write a hint for the next diver."

local caveFolder = workspace.IslaMarahuyo.Activities:WaitForChild("CaveSystem")
local signs = {} -- [nodeName] = { model=, label=, byline=, pos=, chamberLabel= }
local lastWriteAt = {} -- [userId] = os.clock()

-- used to stand each slate on the actual chamber floor instead of leaving it hanging in
-- mid-air at the chamber's nominal centre height
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { workspace.Terrain }
floorParams.IgnoreWater = true

local function buildSign(nodeName, node)
	local existing = caveFolder:FindFirstChild("CaveSign_" .. nodeName)
	if existing then
		existing:Destroy()
	end

	local centre = Vector3.new(node.x, node.y, node.z)
	-- Stand it off-centre, facing back toward the middle of the room so it reads from
	-- wherever you come in. The height is found by dropping a ray to the real chamber
	-- floor rather than assuming one: the chambers are spherical hollows, so a fixed
	-- offset from the centre left every slate floating 9-13 studs above the ground.
	local probeFrom = centre + Vector3.new(node.r * 0.55, 0, node.r * 0.2)
	local floorHit = workspace:Raycast(probeFrom, Vector3.new(0, -(node.r + 16), 0), floorParams)
	-- 4.1 lifts the post's base to the floor: the post is 5 tall, hung 1.6 below the anchor
	local baseY = floorHit and (floorHit.Position.Y + 4.1) or (centre.Y - node.r * 0.3)
	local signPos = Vector3.new(probeFrom.X, baseY, probeFrom.Z)
	local facing = CFrame.lookAt(signPos, Vector3.new(centre.X, signPos.Y, centre.Z))

	local model = Instance.new("Model")
	model.Name = "CaveSign_" .. nodeName

	local post = Instance.new("Part")
	post.Name = "Post"
	post.Size = Vector3.new(0.4, 5, 0.4)
	post.CFrame = facing * CFrame.new(0, -1.6, 0)
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.Material = Enum.Material.Wood
	post.Color = Color3.fromRGB(104, 76, 50)
	post.Parent = model

	local plank = Instance.new("Part")
	plank.Name = "Plank"
	plank.Size = Vector3.new(7, 3.4, 0.3)
	plank.CFrame = facing * CFrame.new(0, 1.6, 0)
	plank.Anchored = true
	plank.CanCollide = false
	plank.Material = Enum.Material.WoodPlanks
	plank.Color = Color3.fromRGB(176, 138, 92)
	plank.Parent = model
	model.PrimaryPart = plank

	-- the cave is pitch dark; without its own light the slate is unreadable
	local lamp = Instance.new("PointLight")
	lamp.Brightness = 1.1
	lamp.Range = 13
	lamp.Color = Color3.fromRGB(255, 226, 170)
	lamp.Parent = plank

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(420, 200)
	gui.LightInfluence = 0
	gui.Adornee = plank
	gui.Parent = plank

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(38, 28, 19)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local heading = Instance.new("TextLabel")
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, -16, 0, 26)
	heading.Position = UDim2.new(0, 8, 0, 6)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 18
	heading.TextColor3 = Color3.fromRGB(240, 190, 120)
	heading.Text = node.label or nodeName
	heading.TextTruncate = Enum.TextTruncate.AtEnd
	heading.Parent = bg

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.Size = UDim2.new(1, -20, 1, -74)
	message.Position = UDim2.new(0, 10, 0, 36)
	message.BackgroundTransparency = 1
	message.Font = Enum.Font.GothamMedium
	message.TextSize = 20
	message.TextWrapped = true
	message.TextColor3 = Color3.fromRGB(240, 232, 216)
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.TextYAlignment = Enum.TextYAlignment.Top
	message.Text = DEFAULT_TEXT
	message.Parent = bg

	local byline = Instance.new("TextLabel")
	byline.Name = "Byline"
	byline.Size = UDim2.new(1, -20, 0, 24)
	byline.Position = UDim2.new(0, 10, 1, -30)
	byline.BackgroundTransparency = 1
	byline.Font = Enum.Font.Gotham
	byline.TextSize = 15
	byline.TextColor3 = Color3.fromRGB(178, 158, 130)
	byline.TextXAlignment = Enum.TextXAlignment.Left
	byline.Text = "unsigned"
	byline.Parent = bg

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WritePrompt"
	prompt.ActionText = "Write on this sign"
	prompt.ObjectText = "Karatula"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	-- THIS is why writing on a slate did nothing. Sea-harvest finds spawn inside these same
	-- chambers, and their prompt is also on E. With the default OnePerButton exclusivity the
	-- two prompts fight over the key -- they visibly alternate, and the press lands on the
	-- harvest orb instead of the sign. Moving the slate onto its own key, and letting it show
	-- alongside other prompts, settles it for keyboard and for touch (where both are tappable).
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Parent = plank

	model.Parent = caveFolder

	local record = {
		model = model,
		label = message,
		byline = byline,
		pos = signPos,
		chamberLabel = node.label or nodeName,
	}

	prompt.Triggered:Connect(function(player)
		signPrompt:FireClient(player, nodeName, record.chamberLabel, message.Text)
	end)

	return record
end

for _, nodeName in ipairs(SIGN_NODES) do
	local node = CaveGen.Nodes[nodeName]
	if node then
		signs[nodeName] = buildSign(nodeName, node)
	end
end

-- Returns filtered text, or nil + a reason the player can be shown.
local function filterFor(player, text)
	local ok, resultOrErr = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok then
		warn("[CaveSignService] text filtering unavailable:", resultOrErr)
		return nil, "The sign couldn't be checked just now -- try again in a moment."
	end

	local okBroadcast, filtered = pcall(function()
		return resultOrErr:GetNonChatStringForBroadcastAsync()
	end)
	if not okBroadcast or type(filtered) ~= "string" then
		warn("[CaveSignService] broadcast filtering failed:", filtered)
		return nil, "The sign couldn't be checked just now -- try again in a moment."
	end

	return filtered
end

signWrite.OnServerEvent:Connect(function(player, nodeName, text)
	if type(nodeName) ~= "string" or type(text) ~= "string" then
		return
	end

	local record = signs[nodeName]
	if not record then
		return
	end

	text = text:gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
	if #text == 0 then
		return
	end
	if #text > MAX_LENGTH then
		text = text:sub(1, MAX_LENGTH)
	end

	local now = os.clock()
	local last = lastWriteAt[player.UserId]
	if last and now - last < WRITE_COOLDOWN then
		diveFeedback:FireClient(player, "sign", string.format(
			"Give it a second before writing again (%.0fs).", WRITE_COOLDOWN - (now - last)), 0)
		return
	end

	-- proximity is re-checked here: the prompt firing is not proof the player is still
	-- standing at the slate by the time the message arrives
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - record.pos).Magnitude > REACH then
		diveFeedback:FireClient(player, "sign", "You're too far from that sign now.", 0)
		return
	end

	local filtered, reason = filterFor(player, text)
	if not filtered then
		diveFeedback:FireClient(player, "sign", reason, 0)
		return
	end

	lastWriteAt[player.UserId] = now
	record.label.Text = filtered
	record.byline.Text = "-- " .. player.DisplayName

	diveFeedback:FireClient(player, "sign", string.format(
		"Your message is up on the %s slate. Every diver in the cave reads it now.",
		record.chamberLabel), 0)

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			diveFeedback:FireClient(other, "sign", string.format(
				"%s wrote on the slate at %s. Whether it's true is their business.",
				player.DisplayName, record.chamberLabel), 0)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastWriteAt[player.UserId] = nil
end)

local built = 0
for _ in pairs(signs) do
	built += 1
end
print(string.format("[CaveSignService] %d player-writable slates up in the cave", built))
