-- CaveAudit -- ground truth on whether Perlas ng Dagat is actually swimmable.
--
-- Looking at a flooded tunnel from inside the rock tells you almost nothing, and
-- FillBall cheerfully reports success for fills that silently did nothing, so the
-- only trustworthy answer comes from re-measuring the finished terrain. This audits
-- every passage two independent ways, because each one misses what the other catches:
--
--   1) RAYCAST between consecutive sample centres, terrain only, water ignored.
--      This is the strictest test available because it asks the same question the
--      engine asks when a player swims into something: is there solid collision
--      geometry in the way? Water is transparent to it, rock is not.
--   2) VOXEL PROBE at each sample centre. A raycast that starts INSIDE a solid does
--      not register that solid, so a passage plugged along its whole length can pass
--      test 1 while being completely impassable. Reading the voxel catches exactly
--      that case -- which is the failure mode this cave has actually produced before.
--
-- It then measures how much clear water surrounds the centre line, because a
-- passage can be technically open and still too pinched to swim, and finally floods
-- the passage graph from open water to report which chambers can be reached at all.

local CaveGen = require(script.Parent:WaitForChild("CG18528"))

local M = {}

M.SURFACE = "SURFACE" -- virtual node: open water above the seabed

-- A diver needs roughly this much clear water either side of the centre line.
-- Below it the passage is open but pinched, which is worth flagging separately
-- from blocked -- it is the difference between "broken" and "nasty".
M.PINCH_LIMIT = 2.5

-- Basalt is the daily cave-in's rubble and is SUPPOSED to be there. Anything else
-- blocking a passage is a carve fault, and that distinction is the whole point of
-- this report -- otherwise an admin cannot tell a working mechanic from a bug.
M.RUBBLE_MATERIAL = Enum.Material.Basalt

local INCLUDE_FILTER = (function()
	local ok, v = pcall(function() return Enum.RaycastFilterType.Include end)
	if ok and v then return v end
	return Enum.RaycastFilterType.Whitelist -- older API name
end)()

local function terrainParams()
	local p = RaycastParams.new()
	p.FilterType = INCLUDE_FILTER
	p.FilterDescendantsInstances = { workspace.Terrain }
	p.IgnoreWater = true -- water must not read as an obstruction; it is the passage
	return p
end

local function isOpen(material)
	return material == Enum.Material.Water or material == Enum.Material.Air
end

-- Every passage in the system, in one shape, so nothing gets audited twice or missed.
function M.Passages()
	local out = {}

	local entrances = {}
	for name, n in pairs(CaveGen.Nodes) do
		if n.kind == "entrance" then
			entrances[#entrances + 1] = name
		end
	end
	table.sort(entrances) -- pairs() order is not stable; the report should be
	for _, name in ipairs(entrances) do
		local n = CaveGen.Nodes[name]
		local samples, radii = CaveGen.EntranceSamples(n)
		out[#out + 1] = {
			id = "entrance:" .. name, kind = "entrance", key = name,
			label = n.label, a = M.SURFACE, b = name,
			samples = samples, bore = CaveGen.EffectiveRadius(radii[#radii], true),
		}
	end

	for i, spec in ipairs(CaveGen.Tunnels) do
		out[#out + 1] = {
			id = "tunnel:" .. i, kind = "tunnel", index = i,
			label = spec[1] .. " \u{2192} " .. spec[2],
			a = spec[1], b = spec[2],
			samples = CaveGen.TunnelSamples(i),
			bore = CaveGen.EffectiveRadius(spec[3], true),
		}
	end

	for i, run in ipairs(CaveGen.DeepRuns) do
		out[#out + 1] = {
			id = "run:" .. i, kind = "run", index = i, tier = run.tier,
			label = run.label, a = run.from, b = run.endNode,
			samples = CaveGen.DeepRunSamples(run),
			bore = CaveGen.EffectiveRadius(run.radius, true),
		}
	end

	return out
end

-- Audits one passage. `budget` is an optional table used to yield periodically so a
-- live server does not stall while an admin runs this.
function M.AuditPassage(p, params, budget)
	params = params or terrainParams()
	local samples = p.samples
	local blockedSegments, faults = {}, {}
	local firstBlock = nil

	local function tick()
		if not budget then return end
		budget.n = (budget.n or 0) + 1
		if budget.n % 120 == 0 then task.wait() end
	end

	-- (1) solid geometry BETWEEN consecutive centres
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		local hit = workspace:Raycast(a, b - a, params)
		if hit then
			blockedSegments[#blockedSegments + 1] = i
			local rec = { at = i, pos = hit.Position, material = hit.Material, how = "wall between samples" }
			faults[#faults + 1] = rec
			firstBlock = firstBlock or rec
		end
		tick()
	end

	-- (2) centres that are themselves buried -- invisible to (1), because a ray that
	-- starts inside a solid never reports it
	for i, c in ipairs(samples) do
		-- inside a breathable chamber Air is correct, not a blockage
		if not CaveGen.InAirChamber(c) then
			local mat = CaveGen.ProbeMaterial(c)
			if not isOpen(mat) then
				local seg = math.min(i, #samples - 1)
				blockedSegments[#blockedSegments + 1] = seg
				local rec = { at = i, pos = c, material = mat, how = "centre line buried" }
				faults[#faults + 1] = rec
				firstBlock = firstBlock or rec
			end
		end
		tick()
	end

	-- (3) how much clear water actually surrounds the centre line
	local minFree, minFreeAt = math.huge, samples[1]
	for i, c in ipairs(samples) do
		local fwd = (i < #samples) and (samples[i + 1] - c) or (c - samples[i - 1])
		if fwd.Magnitude < 1e-3 then fwd = Vector3.new(0, 0, 1) end
		fwd = fwd.Unit
		local up = (math.abs(fwd.Y) > 0.9) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local right = fwd:Cross(up).Unit
		up = right:Cross(fwd).Unit
		local reach = p.bore + 3
		local free = reach
		for _, dir in ipairs({ right, -right, up, -up }) do
			local hit = workspace:Raycast(c, dir * reach, params)
			if hit then
				local d = (hit.Position - c).Magnitude
				if d < free then free = d end
			end
		end
		if free < minFree then minFree = free; minFreeAt = c end
		tick()
	end

	local rubble, rock = false, false
	for _, f in ipairs(faults) do
		if f.material == M.RUBBLE_MATERIAL then rubble = true else rock = true end
	end

	local cause = "clear"
	if rock then cause = "carve fault"
	elseif rubble then cause = "cave-in rubble" end

	return {
		id = p.id, kind = p.kind, index = p.index, key = p.key, tier = p.tier,
		label = p.label, a = p.a, b = p.b, bore = p.bore,
		passable = #faults == 0,
		cause = cause,
		expected = rubble and not rock, -- sealed on purpose by today's cave-in
		faultCount = #faults,
		firstBlock = firstBlock,
		blockedSegments = blockedSegments,
		minClearance = minFree,
		minClearanceAt = minFreeAt,
		pinched = minFree < M.PINCH_LIMIT,
		samples = samples,
	}
end

-- Walks every passage, then floods the graph from open water to answer the question
-- that actually matters: can a diver still get to everything they are meant to?
function M.Audit(yielding)
	local params = terrainParams()
	local budget = yielding and { n = 0 } or nil
	local results = {}
	for _, p in ipairs(M.Passages()) do
		results[#results + 1] = M.AuditPassage(p, params, budget)
	end

	-- Flooded twice, and the difference between the two runs is the whole point.
	-- "today" is what a diver can reach right now, rubble included. "structural" is
	-- what they could reach if the cave-in were cleared. A chamber missing from
	-- today's pass but present in the structural one is the mechanic working as
	-- designed; one missing from BOTH is a bug in the carve.
	local function flood(countRubbleAsOpen)
		local adj = {}
		local function link(a, b)
			adj[a] = adj[a] or {}
			table.insert(adj[a], b)
		end
		for _, r in ipairs(results) do
			if r.passable or (countRubbleAsOpen and r.expected) then
				link(r.a, r.b); link(r.b, r.a)
			end
		end
		local seen = { [M.SURFACE] = true }
		local queue = { M.SURFACE }
		while #queue > 0 do
			local cur = table.remove(queue)
			for _, to in ipairs(adj[cur] or {}) do
				if not seen[to] then
					seen[to] = true
					table.insert(queue, to)
				end
			end
		end
		return seen
	end

	local seen = flood(false)
	local structural = flood(true)

	local names = {}
	for name in pairs(CaveGen.Nodes) do names[#names + 1] = name end
	table.sort(names)

	local unreachable, unreachableAir = {}, {}
	local sealedOffToday = {}
	for _, name in ipairs(names) do
		local n = CaveGen.Nodes[name]
		if n.kind ~= "entrance" and not seen[name] then
			if structural[name] then
				-- behind today's rubble only; it comes back tomorrow
				sealedOffToday[#sealedOffToday + 1] = name
			else
				unreachable[#unreachable + 1] = name
				if CaveGen.AirKinds[n.kind] then
					unreachableAir[#unreachableAir + 1] = name
				end
			end
		end
	end

	local blocked, faults, pinches = 0, 0, 0
	for _, r in ipairs(results) do
		if not r.passable then
			blocked += 1
			if not r.expected then faults += 1 end
		end
		if r.pinched then pinches += 1 end
	end

	return {
		passages = results,
		reachable = seen,
		structural = structural,
		unreachable = unreachable,
		unreachableAir = unreachableAir,
		sealedOffToday = sealedOffToday,
		total = #results,
		blocked = blocked,
		carveFaults = faults,
		pinched = pinches,
		-- the verdict judges the CAVE, not the weather: today's rubble is the mechanic
		-- doing its job, so only unexplained blockages and permanently orphaned air
		-- pockets count against it
		healthy = faults == 0 and #unreachableAir == 0,
		day = workspace:GetAttribute("IslandDay"),
		sealedToday = workspace:GetAttribute("CaveInPassage"),
	}
end

-- Printable version, for the Studio output window and the server log.
function M.Report(audit)
	audit = audit or M.Audit()
	local lines = {}
	lines[#lines + 1] = string.format(
		"=== Perlas ng Dagat passability audit === day %s | %d passages | %d blocked (%d carve faults) | %d pinched",
		tostring(audit.day), audit.total, audit.blocked, audit.carveFaults, audit.pinched)
	if audit.sealedToday and audit.sealedToday ~= "" then
		lines[#lines + 1] = "today's cave-in: " .. audit.sealedToday
	end
	for _, r in ipairs(audit.passages) do
		local status
		if r.passable then
			status = r.pinched and string.format("PASSABLE but pinched to %.1f studs", r.minClearance) or "PASSABLE"
		elseif r.expected then
			status = string.format("SEALED by today's cave-in (%d spheres)", r.faultCount)
		else
			status = string.format("BLOCKED -- %s at %s (sample %d of %d)",
				r.firstBlock.material.Name,
				string.format("%d, %d, %d", r.firstBlock.pos.X, r.firstBlock.pos.Y, r.firstBlock.pos.Z),
				r.firstBlock.at, #r.samples)
		end
		lines[#lines + 1] = string.format("  %-14s %-34s %s", r.kind, r.label, status)
	end
	if #audit.sealedOffToday > 0 then
		lines[#lines + 1] = "behind today's rubble (expected, returns tomorrow): "
			.. table.concat(audit.sealedOffToday, ", ")
	end
	if #audit.unreachable > 0 then
		lines[#lines + 1] = "!! UNREACHABLE even with the cave-in cleared: " .. table.concat(audit.unreachable, ", ")
	end
	if #audit.unreachableAir > 0 then
		lines[#lines + 1] = "!! AIR POCKETS PERMANENTLY CUT OFF: " .. table.concat(audit.unreachableAir, ", ")
	end
	lines[#lines + 1] = audit.healthy
		and "VERDICT: cave is playable -- every air pocket reachable, no unexplained blockage."
		or "VERDICT: needs attention (see above)."
	return table.concat(lines, "\n")
end

-- Trimmed down for sending to an admin's client: geometry plus status, no more.
function M.Snapshot(audit)
	audit = audit or M.Audit()
	local out = { day = audit.day, sealedToday = audit.sealedToday, healthy = audit.healthy,
		blocked = audit.blocked, carveFaults = audit.carveFaults, pinched = audit.pinched,
		unreachable = audit.unreachable, unreachableAir = audit.unreachableAir,
		sealedOffToday = audit.sealedOffToday, passages = {} }
	for _, r in ipairs(audit.passages) do
		-- every 2nd centre is plenty to draw a tube from, and halves what crosses the wire
		local pts = {}
		for i = 1, #r.samples, 2 do pts[#pts + 1] = r.samples[i] end
		pts[#pts + 1] = r.samples[#r.samples]
		local blocked = {}
		for _, seg in ipairs(r.blockedSegments) do
			blocked[math.max(1, math.floor(seg / 2))] = true
		end
		-- Somewhere safe to stand when inspecting this passage: a few samples SHORT of
		-- the blockage, so "take me there" never drops an admin inside solid rock.
		local goTo
		if r.firstBlock then
			goTo = r.samples[math.max(1, r.firstBlock.at - 3)]
		else
			goTo = r.samples[math.ceil(#r.samples / 2)]
		end

		out.passages[#out.passages + 1] = {
			id = r.id, kind = r.kind, label = r.label, tier = r.tier,
			a = r.a, b = r.b, bore = r.bore,
			passable = r.passable, expected = r.expected, cause = r.cause,
			pinched = r.pinched, minClearance = r.minClearance,
			blockPos = r.firstBlock and r.firstBlock.pos or nil,
			blockMaterial = r.firstBlock and r.firstBlock.material.Name or nil,
			goTo = goTo,
			points = pts, blockedPoints = blocked,
		}
	end

	out.nodes = {}
	local names = {}
	for name in pairs(CaveGen.Nodes) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local n = CaveGen.Nodes[name]
		out.nodes[#out.nodes + 1] = {
			name = name, label = n.label, kind = n.kind,
			pos = Vector3.new(n.x, n.y, n.z), r = n.r,
			air = CaveGen.AirKinds[n.kind] and true or false,
			reachable = audit.reachable[name] and true or false,
			structural = audit.structural[name] and true or false,
		}
	end

	return out
end

return M
