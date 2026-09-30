-- ReviveService (ServerScriptService)
-- The Health Post: five standing scanner bays. A drowned diver is held upright in a bay
-- while the scan beam sweeps and a nurse works the console beside it -- Nurse Fely and the
-- other bot nurses for free, or a player nurse who plays the rhythm for a fee.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ServerStorage = game:GetService("ServerStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local RoleService = require(script.Parent.RoleService)
local CurrencyService = require(script.Parent.CurrencyService)

-- A jailed nurse serving their sentence works for free, same as a tindero on the
-- Palengke floor: the treatment still happens, but it pays down time, not Peso.
local serviceCredit = ServerStorage:WaitForChild("ServiceCredit")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reviveStatus = remotes:WaitForChild("ReviveStatus")
local nurseStatus = remotes:FindFirstChild("NurseStatus")
if not nurseStatus then
	nurseStatus = Instance.new("RemoteEvent")
	nurseStatus.Name = "NurseStatus"
	nurseStatus.Parent = remotes
end

local M = {}

local REVIVE_SECONDS = 20
M.REVIVE_SECONDS = REVIVE_SECONDS

-- ===== the player nurse =====
-- Nurse Fely stays free and stays 20 seconds. That matters: drowning must never be a
-- dead end for someone with no money, and a new player must never be stuck waiting for
-- a stranger. What a player nurse sells is SPEED -- roughly half the time if they work
-- the rhythm cleanly -- not the rescue itself. You are paying to get back in the water.
M.NURSE_FEE = 60
local POOR_WORK_RATE = 0.6 -- a fumbled treatment bills less; the patient can see why

local NURSE_ARRIVE_SECONDS = 12 -- reach the bay in this long or Fely takes over, unpaid
local BAY_RANGE = 3.5 -- bays sit 7.5 studs apart; a wide range would blur which bay you're actually at
local BEATS = 8
local BEAT_GAP = 0.75
local HIT_WINDOW = 0.24 -- how close to the beat a press counts
local GOOD_HITS = 5 -- below this the pulses are run again
local STEP_TIMEOUT = 14 -- a nurse who wanders off mid-step hands back to the bot

local STAGES = {
	{ at = 0, text = "Pulled from the water..." },
	{ at = 4, text = "Nurse Fely is working on you" },
	{ at = 10, text = "Water out of your lungs. Breathing again." },
	{ at = 15, text = "Coming to..." },
	{ at = 18.5, text = "On your feet." },
}

local reviving = {} -- [userId] = { start = os.clock(), spot = Part }
local busyNurses = {} -- [userId] = true while a player-nurse is mid-treatment at some bay

local function dock()
	return workspace.IslaMarahuyo.Activities:FindFirstChild("MedicalDock")
end

-- ===== the 5 scanner bays =====
-- RecoverySpot_1..RecoverySpot_5 mark where a patient stands in MedScanner_1..5, each
-- tagged with which bot nurse works its console, so every bay can run its own
-- sound/animation/occupancy independently.
local function getSpots()
	local d = dock()
	local folder = d and d:FindFirstChild("RecoverySpots")
	if not folder then
		local single = d and d:FindFirstChild("RecoverySpot")
		return single and { single } or {}
	end
	local list = {}
	for i = 1, 5 do
		local s = folder:FindFirstChild("RecoverySpot_" .. i)
		if s then table.insert(list, s) end
	end
	return list
end

local spotOccupied = {} -- [spot] = true while a patient is on it

local function pickFreeSpot()
	for _, spot in ipairs(getSpots()) do
		if not spotOccupied[spot] then
			return spot
		end
	end
	return nil
end

-- Create 3D Heart Monitor Sound at a given bay
local function getOrCreateEKGSound(spot)
	if not spot then return nil end
	local sound = spot:FindFirstChild("MedicalEKGSound")
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "MedicalEKGSound"
		sound.SoundId = "rbxassetid://9114233513"
		sound.Volume = 0.5
		sound.Looped = true
		sound.RollOffMinDistance = 5
		sound.RollOffMaxDistance = 35
		sound.Parent = spot
	end
	return sound
end

local medicConns = {} -- [spot] = the Heartbeat connection animating that bay's bot nurse
local scanConns = {} -- [spot] = the Heartbeat connection sweeping that bay's scan beam

local function nurseModelFor(spot)
	local d = dock()
	local name = spot and spot:GetAttribute("NurseName")
	return name and d and d:FindFirstChild(name)
end

local function scannerFor(spot)
	local n = spot and spot.Name:match("_(%d+)$")
	local d = dock()
	return n and d and d:FindFirstChild("MedScanner_" .. n)
end

-- The bot nurses are anchored part-figures, posed from the floor point under them
-- (PoseRoot attribute) and the way they face (PoseYaw). Offsets are in her own frame,
-- -Z forward, +X to her right.
local POSE = {
	Torso = CFrame.new(0, 3.0, 0),
	Head = CFrame.new(0, 4.85, 0),
	LegL = CFrame.new(-0.5, 1.0, 0),
	LegR = CFrame.new(0.5, 1.0, 0),
	ArmL = CFrame.new(-1.35, 2.9, 0),
	ArmR = CFrame.new(1.35, 2.9, 0),
	Badge = CFrame.new(0.5, 3.3, -0.675),
}
local SHOULDER_Y = 3.9

-- `t` nil is the rest pose; a time is her working the console: both hands out on the
-- panel tapping in turn, eyes down on the screen.
local function poseMedic(medic, t)
	local root = medic:GetAttribute("PoseRoot")
	if typeof(root) ~= "Vector3" then
		return
	end
	local base = CFrame.new(root) * CFrame.Angles(0, math.rad(medic:GetAttribute("PoseYaw") or 0), 0)
	for name, offset in pairs(POSE) do
		local part = medic:FindFirstChild(name)
		if part then
			part.CFrame = base * offset
		end
	end
	if not t then
		return
	end
	for side, name in ipairs({ "ArmL", "ArmR" }) do
		local arm = medic:FindFirstChild(name)
		if arm then
			local pitch = 45 + math.sin(t * 7 + side * math.pi) * 8
			arm.CFrame = base * CFrame.new(side == 1 and -1.35 or 1.35, SHOULDER_Y, 0)
				* CFrame.Angles(math.rad(pitch), 0, 0) * CFrame.new(0, -1, 0)
		end
	end
	local head = medic:FindFirstChild("Head")
	if head then
		head.CFrame = base * POSE.Head * CFrame.Angles(math.rad(-14), 0, 0)
	end
end

-- The beam rides up and down the arch for as long as someone is in the bay, whoever is
-- treating them.
local function sweepScan(spot, on)
	local scanner = scannerFor(spot)
	local plane = scanner and scanner:FindFirstChild("ScanPlane")
	local pad = scanner and scanner:FindFirstChild("Pad")
	if not (plane and pad) then
		return
	end
	local conn = scanConns[spot]
	if on then
		if conn then
			return
		end
		local low = pad.Position + Vector3.new(0, 0.25, 0)
		local rot = plane.CFrame - plane.Position
		plane.Transparency = 0.45
		scanConns[spot] = RunService.Heartbeat:Connect(function()
			local h = (1 - math.cos(os.clock() * 1.8)) / 2 * 6.4
			plane.CFrame = CFrame.new(low + Vector3.new(0, h, 0)) * rot
		end)
	else
		if conn then
			conn:Disconnect()
			scanConns[spot] = nil
		end
		plane.Transparency = 1
	end
end

-- `animateMedic` is false when a player nurse is treating: the EKG and the scan still
-- run, because the patient hears one and sees the other, but the bot nurse must not also
-- be working a patient somebody else is treating. Each bay's sound and animation are
-- independent, so five bays can run this at once without clobbering each other.
local function setMedicWorking(on, animateMedic, spot)
	if not spot then return end
	local sound = getOrCreateEKGSound(spot)
	sweepScan(spot, on)

	if on then
		if sound and not sound.IsPlaying then
			sound.TimePosition = 0
			sound:Play()
		end

		if medicConns[spot] or animateMedic == false then return end

		local medic = nurseModelFor(spot)
		if not medic then return end

		medicConns[spot] = RunService.Heartbeat:Connect(function()
			poseMedic(medic, os.clock())
		end)
	else
		if sound and sound.IsPlaying then
			sound:Stop()
		end

		local conn = medicConns[spot]
		if conn then
			conn:Disconnect()
			medicConns[spot] = nil
		end

		local medic = nurseModelFor(spot)
		if medic then
			poseMedic(medic)
		end
	end
end

-- ===== RecoveryCot cosmetic (Bilao Box drop, tracked in profile.Cosmetics) =====
-- The key predates the scanners and is kept so nobody who already owns it loses it.
-- Purely visual, same 20-second wait either way: whichever bay the owner is assigned to
-- has its trim turned gold for the length of their stay, then reverts.
local function hasVipBay(player)
	local profile = PlayerProfileService.Get(player.UserId)
	return profile and profile.Cosmetics and (profile.Cosmetics.RecoveryCot or 0) > 0
end

local VIP_ACCENT = Color3.fromRGB(255, 206, 90)
local baseAccent = {} -- [part] = its own colour, captured before the first reskin

local function setBayVip(spot, vip)
	local scanner = scannerFor(spot)
	if not scanner then return end
	for _, part in ipairs(scanner:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("Accent") then
			baseAccent[part] = baseAccent[part] or part.Color
			part.Color = vip and VIP_ACCENT or baseAccent[part]
		end
	end
end

-- ===== treatment props =====

local function ensureTreatmentPrompt(spot)
	if not spot then
		return nil
	end
	local prompt = spot:FindFirstChild("TreatmentPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TreatmentPrompt"
		prompt.ObjectText = "Patient"
		prompt.ActionText = "Treat"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = BAY_RANGE
		prompt.RequiresLineOfSight = false
		prompt.Parent = spot
	end
	prompt.Enabled = false
	return prompt
end

-- A kit welded into the nurse's hand. There is no treatment animation for players and
-- faking one with an emote would read worse than none, so the "busy" read comes from the
-- prop, the rhythm they are actually playing, and the EKG the patient can hear.
local function attachKit(nurse)
	local character = nurse.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand then
		return nil
	end
	local kit = Instance.new("Part")
	kit.Name = "MedicKit"
	kit.Size = Vector3.new(0.9, 0.62, 0.5)
	kit.Color = Color3.fromRGB(242, 242, 242)
	kit.Material = Enum.Material.SmoothPlastic
	kit.Anchored = false
	kit.CanCollide = false
	kit.Massless = true
	kit.CFrame = hand.CFrame * CFrame.new(0, -0.7, 0)
	kit.Parent = character

	local cross = Instance.new("Part")
	cross.Name = "Cross"
	cross.Size = Vector3.new(0.34, 0.12, 0.52)
	cross.Color = Color3.fromRGB(214, 48, 48)
	cross.Material = Enum.Material.SmoothPlastic
	cross.Anchored = false
	cross.CanCollide = false
	cross.Massless = true
	cross.CFrame = kit.CFrame
	cross.Parent = character

	-- weld before anything can fall: an unwelded loose part bursts apart the moment
	-- physics touches it, which is exactly how the first dropped oxygen tank broke
	local w1 = Instance.new("WeldConstraint")
	w1.Part0, w1.Part1 = hand, kit
	w1.Parent = kit
	local w2 = Instance.new("WeldConstraint")
	w2.Part0, w2.Part1 = kit, cross
	w2.Parent = cross

	return { kit, cross }
end

local function removeKit(parts)
	for _, part in ipairs(parts or {}) do
		if part and part.Parent then
			part:Destroy()
		end
	end
end

local function atBay(player, spot)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and spot) then
		return false
	end
	return (root.Position - spot.Position).Magnitude <= BAY_RANGE
end

-- The nurse on duty who is nearest the bay, never the patient themselves, and never one
-- already mid-treatment at a different bay -- with 5 bays live at once, RoleService's
-- plain "nearest holder" would happily double-book the same nurse onto two patients.
local function pickNurse(patient, spot)
	local candidates = {}
	local function consider(player)
		if player ~= patient and player.Character and not busyNurses[player.UserId]
			and not table.find(candidates, player) then
			table.insert(candidates, player)
		end
	end
	if RoleService.ShiftOpen("nurse") then
		for _, player in ipairs(RoleService.Holders("nurse")) do
			consider(player)
		end
	end
	-- Somebody serving a sentence here is held at the Health Post until they have revived
	-- enough people, so they are on call at any hour -- not just during the paid shift.
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("ServiceTrack") == "nurse" then
			consider(player)
		end
	end
	if #candidates == 0 then
		return nil
	end
	if not spot then
		return candidates[1]
	end
	local best, bestDist
	for _, player in ipairs(candidates) do
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - spot.Position).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = player, d
			end
		end
	end
	return best or candidates[1]
end

local function payNurse(patient, nurse, quality)
	if nurse:GetAttribute("ServiceTrack") == "nurse" then
		serviceCredit:Fire(nurse, "revive")
		nurseStatus:FireClient(nurse, "done",
			string.format("%s treated. Unpaid -- it comes off your time.", patient.DisplayName), 0)
		return 0
	end

	local fee = quality and M.NURSE_FEE or math.floor(M.NURSE_FEE * POOR_WORK_RATE + 0.5)
	local balance = CurrencyService.GetShells(patient.UserId) or 0
	-- capped at what the patient actually has: drowning broke must never be a dead end,
	-- and the shortfall simply is not billed rather than becoming a debt to chase
	local due = math.min(fee, balance)
	if due <= 0 then
		nurseStatus:FireClient(nurse, "done",
			string.format("%s had nothing to pay with. Written off.", patient.DisplayName), 0)
		return 0
	end
	if not CurrencyService.TrySpend(patient, due, "NurseFee") then
		return 0
	end
	CurrencyService.AddShells(nurse, due, false, "NurseWork")
	nurseStatus:FireClient(nurse, "done",
		string.format("%s treated. +%d Peso.", patient.DisplayName, due), due)
	return due
end

function M.IsReviving(player)
	return reviving[player.UserId] ~= nil
end

-- ===== driver: Nurse Fely =====
-- Unchanged from the original: a fixed twenty seconds on a staged script. This is the
-- floor the whole system rests on, so it stays free and it stays reliable.
local function runBotTreatment(patient)
	local t0 = os.clock()
	local nextStage = 2
	while os.clock() - t0 < REVIVE_SECONDS do
		task.wait(0.2)
		local elapsed = os.clock() - t0
		if STAGES[nextStage] and elapsed >= STAGES[nextStage].at then
			reviveStatus:FireClient(patient, "stage", STAGES[nextStage].text, REVIVE_SECONDS - elapsed)
			nextStage += 1
		end
		if not patient.Parent then break end
	end
end

-- ===== driver: a player nurse =====
-- Four steps, each mapped onto a stage line the patient already sees. The rhythm step is
-- the heart of it: the nurse taps in time with the EKG the patient can hear, so the audio
-- is not decoration, it is the thing being played to.
local function runNurseTreatment(patient, nurse, spot)
	local prompt = ensureTreatmentPrompt(spot)
	if not prompt then
		runBotTreatment(patient)
		return
	end

	nurseStatus:FireClient(nurse, "called",
		string.format("%s is down at the Health Post -- get to the scanner.", patient.DisplayName), 0)
	reviveStatus:FireClient(patient, "stage",
		string.format("%s is on the way", nurse.DisplayName), 0)

	-- 1. haul: the nurse has to actually be here
	local arrivedBy = os.clock() + NURSE_ARRIVE_SECONDS
	while os.clock() < arrivedBy and not atBay(nurse, spot) do
		if not (nurse.Parent and patient.Parent) then
			break
		end
		task.wait(0.2)
	end
	if not atBay(nurse, spot) then
		nurseStatus:FireClient(nurse, "lost", "Too slow -- Nurse Fely took over. No fee.", 0)
		setMedicWorking(true, true, spot) -- hand the bay back to Fely and let her animate
		runBotTreatment(patient)
		return
	end

	local kit = attachKit(nurse)
	reviveStatus:FireClient(patient, "stage", STAGES[1].text, 0)

	local step, lastBeatAt = "idle", 0
	local hits, lungsDone, maskDone = 0, false, false

	local conn = prompt.Triggered:Connect(function(who)
		-- the prompt is visible to anyone standing at the bay, but only the nurse who was
		-- actually called can work it
		if who ~= nurse then
			return
		end
		if step == "pulse" then
			local since = os.clock() - lastBeatAt
			-- distance to the nearest beat, whether the press was early or late
			local offBy = math.min(since, math.max(0, BEAT_GAP - since))
			if offBy <= HIT_WINDOW then
				hits += 1
				nurseStatus:FireClient(nurse, "hit", "Good pulse", hits)
			else
				nurseStatus:FireClient(nurse, "miss", "Off rhythm", hits)
			end
		elseif step == "lungs" then
			lungsDone = true
		elseif step == "mask" then
			maskDone = true
		end
	end)

	local function runBeats(count)
		step = "pulse"
		prompt.ActionText = "Pulse"
		prompt.HoldDuration = 0
		prompt.Enabled = true
		for i = 1, count do
			lastBeatAt = os.clock()
			nurseStatus:FireClient(nurse, "beat", "Pulse the scanner on the beat", i)
			task.wait(BEAT_GAP)
		end
	end

	-- 2. the rhythm: pulse the scanner in time with the heartbeat
	reviveStatus:FireClient(patient, "stage",
		string.format("%s is working on you", nurse.DisplayName), 0)
	runBeats(BEATS)

	-- fumbled work costs time as well as money: the pulses are run again
	if hits < GOOD_HITS then
		nurseStatus:FireClient(nurse, "again", "Losing them -- pulse again, on the beat.", hits)
		runBeats(4)
	end
	local quality = hits >= GOOD_HITS

	-- 3. clear the lungs
	step = "lungs"
	prompt.ActionText = "Clear the lungs"
	prompt.HoldDuration = 2.5
	nurseStatus:FireClient(nurse, "hold", "Hold to clear the lungs", 0)
	local deadline = os.clock() + STEP_TIMEOUT
	while not lungsDone and os.clock() < deadline and nurse.Parent do
		task.wait(0.15)
	end
	reviveStatus:FireClient(patient, "stage", STAGES[3].text, 0)

	-- 4. the mask
	step = "mask"
	prompt.ActionText = "Fit the mask"
	prompt.HoldDuration = 0
	nurseStatus:FireClient(nurse, "mask", "Fit the oxygen mask", 0)
	deadline = os.clock() + STEP_TIMEOUT
	while not maskDone and os.clock() < deadline and nurse.Parent do
		task.wait(0.15)
	end
	reviveStatus:FireClient(patient, "stage", STAGES[5].text, 0)

	step = "done"
	conn:Disconnect()
	prompt.Enabled = false
	prompt.HoldDuration = 0
	removeKit(kit)

	if nurse.Parent and patient.Parent then
		payNurse(patient, nurse, quality)
	end
end

function M.Begin(player, onComplete)
	if reviving[player.UserId] then return false end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and hrp) then return false end

	-- 5 bays means drowning spikes rarely queue, but a short bounded wait beats an error
	-- on the rare server where all of them are full at once
	local spot = pickFreeSpot()
	if not spot then
		local deadline = os.clock() + 8
		while not spot and os.clock() < deadline do
			task.wait(0.3)
			spot = pickFreeSpot()
		end
	end
	if spot then
		spotOccupied[spot] = true
	end

	reviving[player.UserId] = { start = os.clock(), spot = spot }

	-- counted for the server roster: how many times this diver has needed bringing back
	local profile = PlayerProfileService.Get(player.UserId)
	if profile then
		profile.Revives = (profile.Revives or 0) + 1
		player:SetAttribute("Revives", profile.Revives)
	end

	player:SetAttribute("Reviving", true)

	local nurse = pickNurse(player, spot)

	-- the bot nurse only animates when she is the one doing the work
	setMedicWorking(true, nurse == nil, spot)
	if spot then
		setBayVip(spot, hasVipBay(player))
	end

	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	-- held upright on the pad, facing out of the arch
	if spot then
		hrp.CFrame = spot.CFrame
	end
	hrp.Anchored = true

	reviveStatus:FireClient(player, "begin", STAGES[1].text, REVIVE_SECONDS)

	task.spawn(function()
		if nurse then
			-- a nurse who disconnects or errors mid-treatment must not strand the patient
			-- held in the scanner forever, so the whole run is wrapped
			busyNurses[nurse.UserId] = true
			local ok, err = pcall(runNurseTreatment, player, nurse, spot)
			busyNurses[nurse.UserId] = nil
			if not ok then
				warn("[ReviveService] nurse treatment failed, falling back to the bot:", err)
				setMedicWorking(true, true, spot)
				pcall(runBotTreatment, player)
			end
		else
			runBotTreatment(player)
		end

		if character and character.Parent then
			hrp.Anchored = false
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = 16
			if humanoid.UseJumpPower then
				humanoid.JumpPower = 50
			else
				humanoid.JumpHeight = 7.2
			end
			if spot then
				-- step out the open front of the arch
				hrp.CFrame = spot.CFrame * CFrame.new(0, 0.5, -3.5)
			end
		end

		reviveStatus:FireClient(player, "done", "You're alright.", 0)
		player:SetAttribute("Reviving", nil)
		reviving[player.UserId] = nil

		if spot then
			spotOccupied[spot] = nil
			setMedicWorking(false, nil, spot)
			setBayVip(spot, false)
		end
		if onComplete then
			onComplete()
		end
	end)

	return true
end

function M.Cancel(player)
	local rec = reviving[player.UserId]
	if not rec then return end
	player:SetAttribute("Reviving", nil)
	reviving[player.UserId] = nil
	if rec.spot then
		spotOccupied[rec.spot] = nil
		setMedicWorking(false, nil, rec.spot)
		setBayVip(rec.spot, false)
	end
end

-- every bot nurse starts in her rest pose, so no server ever inherits one frozen mid-reach
task.defer(function()
	for _, spot in ipairs(getSpots()) do
		local medic = nurseModelFor(spot)
		if medic then
			poseMedic(medic)
		end
	end
end)

return M