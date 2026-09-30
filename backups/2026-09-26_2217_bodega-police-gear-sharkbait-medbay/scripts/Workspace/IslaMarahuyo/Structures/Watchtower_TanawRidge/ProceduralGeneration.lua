--!strict
-- generationId: 6be61c14-c09a-4d64-9982-6bc4ea420278
local CSG = require(script.Dependencies.ConstructiveSolidGeometry)
local GP = require(script.Dependencies.GeometryPrimitives)
local SO = require(script.Dependencies.SmartObject)
local MU = require(script.Dependencies.MathUtils)


local Watchtower = {}

type Parameters = {
	Size: Vector3,
	Attributes: {
		WoodColor: Color3?,
		ThatchColor: Color3?,
		StoneColor: Color3?,
	},
}
local startTime = 0
local timerThread : thread = task.spawn(function()
while true do
	if not script:IsDescendantOf(game) then
		startTime = 0
		return
	end
	if startTime > 0 then
		local elapsed = tick() - startTime
		print("[ProceduralModel] " .. script:GetFullName() .. " rendering... " .. string.format("%.0f", elapsed) .. " seconds")
	end
	task.wait(3)
end
end)
script.Destroying:Connect(function()
	task.cancel(timerThread)
end)

Watchtower.OnGenerate = function(parameters: Parameters, targetContainer: Instance)
	-- Timer setup
	startTime = tick()

	local tower = GP.model("Watchtower", nil)-- Fix orientation of the model
	tower.WorldPivot = CFrame.identity
	
	
	local smartWidth  = parameters.Size.X
	local smartHeight = parameters.Size.Y
	local smartDepth  = parameters.Size.Z
	
	local scaleX = smartWidth / 10
	local scaleY = smartHeight / 10
	local scaleZ = smartDepth / 10
	
	local colorWood = parameters.Attributes.WoodColor or Color3.fromRGB(180, 100, 60)
	local colorThatch = parameters.Attributes.ThatchColor or Color3.fromRGB(220, 180, 70)
	local colorStone = parameters.Attributes.StoneColor or Color3.fromRGB(150, 140, 130)
	
	local matWood = "Wood"
	local matRoof = "Grass"
	local matStone = "Slate"
	
	-- Base dimensions mapped via scale
	local pWidth = 8 * scaleX
	local pDepth = 8 * scaleZ
	local legH = 10 * scaleY
	local postH = 6 * scaleY
	local roofH = 3 * scaleY
	
	local halfW = pWidth / 2
	local halfD = pDepth / 2
	local legThick = 0.6 * math.min(scaleX, scaleZ)
	local braceThick = 0.4 * math.min(scaleX, scaleZ)
	
	local baseSpread = 1.2 * math.min(scaleX, scaleZ)
	
	-- Top coordinates (under platform)
	local tLF = Vector3.new(halfW, legH, -halfD)
	local tRF = Vector3.new(-halfW, legH, -halfD)
	local tLB = Vector3.new(halfW, legH, halfD)
	local tRB = Vector3.new(-halfW, legH, halfD)
	
	-- Bottom coordinates (on ground)
	local bLF = Vector3.new(halfW + baseSpread, 0.5 * scaleY, -halfD - baseSpread)
	local bRF = Vector3.new(-halfW - baseSpread, 0.5 * scaleY, -halfD - baseSpread)
	local bLB = Vector3.new(halfW + baseSpread, 0.5 * scaleY, halfD + baseSpread)
	local bRB = Vector3.new(-halfW - baseSpread, 0.5 * scaleY, halfD + baseSpread)
	
	-- == 1. GROUND FLOOR (enclosed room; replaces exposed legs which floated/gapped on sloped ground) ==
	local roomGroup = GP.model("groundFloor", tower)

	local wallThick = 0.6 * math.min(scaleX, scaleZ)

	-- Probe real terrain under each corner so the floor never floats above (or is suspended over) a gap
	local anchor = (script.Parent :: Instance).WorldPivot.Position
	local rcParams = RaycastParams.new()
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	rcParams.FilterDescendantsInstances = { script.Parent }
	rcParams.IgnoreWater = true

	local function probeGroundY(localX: number, localZ: number): number
	    local origin = Vector3.new(anchor.X + localX, anchor.Y + 200, anchor.Z + localZ)
	    local result = workspace:Raycast(origin, Vector3.new(0, -400, 0), rcParams)
	    if result then
	        return result.Position.Y
	    end
	    return anchor.Y - smartHeight / 2
	end

	local function toLocalY(worldY: number): number
	    return (worldY - anchor.Y) + smartHeight / 2
	end

	local cornerGroundY = {
	    probeGroundY(halfW, -halfD),
	    probeGroundY(-halfW, -halfD),
	    probeGroundY(halfW, halfD),
	    probeGroundY(-halfW, halfD),
	}
	-- Use the LOWEST probed corner so the slab can never float above sloped ground;
	-- a deep skirt below it absorbs the rest of the slope.
	local floorWorldY = math.min(cornerGroundY[1], cornerGroundY[2], cornerGroundY[3], cornerGroundY[4])
	local floorY = toLocalY(floorWorldY)
	local skirtDepth = 3 * scaleY

	GP.axisAlignedBlockFromCorners("GroundSlab",
	    Vector3.new(halfW + baseSpread, floorY - skirtDepth, -halfD - baseSpread),
	    Vector3.new(-halfW - baseSpread, floorY, halfD + baseSpread),
	    colorStone, matStone, roomGroup)

	-- Shared door/stair opening position (also used by the stair shaft and the railing gap below)
	local ladW = 2.2 * scaleX
	local ladX = halfW - ladW/2 - 0.4*scaleX

	local function wallSegment(name: string, xMin: number, xMax: number, zCenter: number)
	    GP.axisAlignedBlockFromCorners(name,
	        Vector3.new(xMin, floorY, zCenter - wallThick/2),
	        Vector3.new(xMax, legH, zCenter + wallThick/2),
	        colorWood, matWood, roomGroup)
	end

	-- Front wall (-Z), split around the door gap that lines up with the stair shaft
	wallSegment("WallFront_A", -halfW, ladX - ladW/2, -halfD)
	wallSegment("WallFront_B", ladX + ladW/2, halfW, -halfD)
	-- Back wall (+Z)
	GP.axisAlignedBlockFromCorners("WallBack",
	    Vector3.new(-halfW, floorY, halfD - wallThick/2),
	    Vector3.new(halfW, legH, halfD + wallThick/2),
	    colorWood, matWood, roomGroup)
	-- Side walls
	GP.axisAlignedBlockFromCorners("WallLeft",
	    Vector3.new(halfW - wallThick/2, floorY, -halfD),
	    Vector3.new(halfW + wallThick/2, legH, halfD),
	    colorWood, matWood, roomGroup)
	GP.axisAlignedBlockFromCorners("WallRight",
	    Vector3.new(-halfW - wallThick/2, floorY, -halfD),
	    Vector3.new(-halfW + wallThick/2, legH, halfD),
	    colorWood, matWood, roomGroup)

	-- == 2. STAIR SHAFT (enclosed switchback staircase; replaces the freestanding ladder that never reached the deck) ==
	local stairGroup = GP.model("stairShaft", tower)

	local stairX = ladX
	local stairW = ladW * 0.85
	local shaftNearZ = -halfD - 0.2*scaleZ -- flush with the deck's own front overhang, so the top step meets the deck with zero gap

	local totalRise = legH - floorY
	local midY = floorY + totalRise/2
	local desiredRise = 1.0 * scaleY
	local numSteps = math.max(3, math.ceil((totalRise/2) / desiredRise))
	local stepRise = (totalRise/2) / numSteps
	local stepRun = 1.1 * scaleZ
	local shaftFarZ = shaftNearZ - (numSteps * stepRun)
	local landingDepth = 2 * scaleZ

	-- Flight 1: climbs from the floor (near the tower) outward to the landing
	for i = 1, numSteps do
	    local zFar = shaftNearZ - stepRun * i
	    local zNear = shaftNearZ - stepRun * (i - 1)
	    local topY = floorY + stepRise * i
	    GP.axisAlignedBlockFromCorners("Step1_"..i,
	        Vector3.new(stairX - stairW/2, floorY, zFar),
	        Vector3.new(stairX + stairW/2, topY, zNear),
	        colorWood, matWood, stairGroup)
	end

	-- Landing (switchback turn)
	GP.axisAlignedBlockFromCorners("Landing",
	    Vector3.new(stairX - stairW/2, midY - 0.3*scaleY, shaftFarZ - landingDepth),
	    Vector3.new(stairX + stairW/2, midY, shaftFarZ),
	    colorWood, matWood, stairGroup)

	-- Flight 2: climbs back toward the tower, stacked above Flight 1, landing exactly flush with the deck underside
	for i = 1, numSteps do
	    local zNear = shaftFarZ + stepRun * (i - 1)
	    local zFar = shaftFarZ + stepRun * i
	    local topY = midY + stepRise * i
	    GP.axisAlignedBlockFromCorners("Step2_"..i,
	        Vector3.new(stairX - stairW/2, midY, zNear),
	        Vector3.new(stairX + stairW/2, topY, zFar),
	        colorWood, matWood, stairGroup)
	end

	-- Enclosing shaft walls + lean-to roof
	local shaftHalfW = stairW/2 + wallThick
	local shaftOuterZ = shaftFarZ - landingDepth - wallThick
	GP.axisAlignedBlockFromCorners("ShaftWallL",
	    Vector3.new(stairX - shaftHalfW - wallThick/2, floorY - skirtDepth, shaftOuterZ),
	    Vector3.new(stairX - shaftHalfW + wallThick/2, legH + 0.6*scaleY, shaftNearZ),
	    colorWood, matWood, stairGroup)
	GP.axisAlignedBlockFromCorners("ShaftWallR",
	    Vector3.new(stairX + shaftHalfW - wallThick/2, floorY - skirtDepth, shaftOuterZ),
	    Vector3.new(stairX + shaftHalfW + wallThick/2, legH + 0.6*scaleY, shaftNearZ),
	    colorWood, matWood, stairGroup)
	GP.axisAlignedBlockFromCorners("ShaftWallFar",
	    Vector3.new(stairX - shaftHalfW, floorY - skirtDepth, shaftOuterZ - wallThick),
	    Vector3.new(stairX + shaftHalfW, legH + 0.6*scaleY, shaftOuterZ),
	    colorWood, matWood, stairGroup)
	GP.axisAlignedBlockFromCorners("ShaftFloor",
	    Vector3.new(stairX - shaftHalfW - wallThick, floorY - skirtDepth, shaftOuterZ - wallThick),
	    Vector3.new(stairX + shaftHalfW + wallThick, floorY, shaftNearZ + 0.3*scaleZ),
	    colorStone, matStone, stairGroup)
	GP.axisAlignedBlockFromCorners("ShaftRoof",
	    Vector3.new(stairX - shaftHalfW - wallThick, legH + 0.3*scaleY, shaftOuterZ - wallThick),
	    Vector3.new(stairX + shaftHalfW + wallThick, legH + 0.6*scaleY, shaftNearZ + 0.3*scaleZ),
	    colorThatch, matRoof, stairGroup)
	
	-- == 3. PLATFORM ==
	local platGroup = GP.model("platform", tower)
	local platThick = 0.4 * scaleY
	local logExt = 0.8 * math.min(scaleX, scaleZ)
	
	-- Support Logs (extending outwards)
	local logRad = 0.4 * scaleY
	-- Z-running logs
	GP.cylinder("LogZ1", tLF + Vector3.new(0, -logRad, -logExt), tLB + Vector3.new(0, -logRad, logExt), logRad, colorWood, matWood, platGroup)
	GP.cylinder("LogZ2", tRF + Vector3.new(0, -logRad, -logExt), tRB + Vector3.new(0, -logRad, logExt), logRad, colorWood, matWood, platGroup)
	-- X-running logs
	GP.cylinder("LogX1", tLF + Vector3.new(logExt, 0, 0), tRF + Vector3.new(-logExt, 0, 0), logRad, colorWood, matWood, platGroup)
	GP.cylinder("LogX2", tLB + Vector3.new(logExt, 0, 0), tRB + Vector3.new(-logExt, 0, 0), logRad, colorWood, matWood, platGroup)
	
	-- Deck Planks
	local pDeck = GP.axisAlignedBlockFromCorners("Deck",
	    Vector3.new(halfW + 0.2*scaleX, legH, -halfD - 0.2*scaleZ),
	    Vector3.new(-halfW - 0.2*scaleX, legH + platThick, halfD + 0.2*scaleZ),
	    colorWood, "WoodPlanks", platGroup)
	
	-- 4 Corner Posts for Roof
	local postRad = 0.35 * math.min(scaleX, scaleZ)
	local pLF = Vector3.new(halfW - postRad, legH + platThick, -halfD + postRad)
	local pRF = Vector3.new(-halfW + postRad, legH + platThick, -halfD + postRad)
	local pLB = Vector3.new(halfW - postRad, legH + platThick, halfD - postRad)
	local pRB = Vector3.new(-halfW + postRad, legH + platThick, halfD - postRad)
	
	GP.cylinder("PostLF", pLF, pLF + Vector3.new(0, postH, 0), postRad, colorWood, matWood, platGroup)
	GP.cylinder("PostRF", pRF, pRF + Vector3.new(0, postH, 0), postRad, colorWood, matWood, platGroup)
	GP.cylinder("PostLB", pLB, pLB + Vector3.new(0, postH, 0), postRad, colorWood, matWood, platGroup)
	GP.cylinder("PostRB", pRB, pRB + Vector3.new(0, postH, 0), postRad, colorWood, matWood, platGroup)
	
	-- == 4. RAILING ==
	local railGroup = GP.model("railing", tower)
	local railH = 2.5 * scaleY
	local topRailY = legH + platThick + railH
	local botRailY = legH + platThick + 0.5 * scaleY
	local rRad = 0.25 * math.min(scaleX, scaleZ)
	local sRad = 0.15 * math.min(scaleX, scaleZ)
	
	local function buildRail(name, p1, p2)
	    local t1 = p1 + Vector3.new(0, topRailY - p1.Y, 0)
	    local t2 = p2 + Vector3.new(0, topRailY - p2.Y, 0)
	    local b1 = p1 + Vector3.new(0, botRailY - p1.Y, 0)
	    local b2 = p2 + Vector3.new(0, botRailY - p2.Y, 0)
	    
	    -- Extended main rails
	    local dir = (p2 - p1).Unit
	    local ext = 0.4 * scaleX
	    GP.cylinder("Top_"..name, t1 - dir*ext, t2 + dir*ext, rRad, colorWood, matWood, railGroup)
	    GP.cylinder("Bot_"..name, b1 - dir*ext, b2 + dir*ext, rRad, colorWood, matWood, railGroup)
	    
	    local numSpindles = 5
	    MU.linearArray(b1, b2, numSpindles + 2, function(pos, i)
	        if i > 1 and i <= numSpindles + 1 then
	            GP.cylinder("Spindle_"..name.."_"..i, pos, pos + Vector3.new(0, railH - 0.5*scaleY, 0), sRad, colorWood, matWood, railGroup)
	        end
	    end)
	end
	
	-- Full rails for sides and back
	buildRail("Left", pLF, pLB)
	buildRail("Right", pRF, pRB)
	buildRail("Back", pLB, pRB)
	
	-- Front rail has a gap for the ladder
	local ladInnerX = ladX - ladW/2 - 0.5*scaleX
	local railEnd = Vector3.new(ladInnerX, pRF.Y, pRF.Z)
	buildRail("FrontR", railEnd, pRF)
	-- Post at ladder gap
	GP.cylinder("GapPost", railEnd, railEnd + Vector3.new(0, railH, 0), rRad*1.2, colorWood, matWood, railGroup)
	
	-- == 5. ROOF ==
	local roofGroup = GP.model("roof", tower)
	local roofBaseY = legH + platThick + postH
	
	-- Top ring beams connecting posts
	local ringRad = 0.3 * scaleY
	GP.cylinder("RingF", pLF + Vector3.new(0, postH, 0), pRF + Vector3.new(0, postH, 0), ringRad, colorWood, matWood, roofGroup)
	GP.cylinder("RingB", pLB + Vector3.new(0, postH, 0), pRB + Vector3.new(0, postH, 0), ringRad, colorWood, matWood, roofGroup)
	GP.cylinder("RingL", pLF + Vector3.new(0, postH, 0), pLB + Vector3.new(0, postH, 0), ringRad, colorWood, matWood, roofGroup)
	GP.cylinder("RingR", pRF + Vector3.new(0, postH, 0), pRB + Vector3.new(0, postH, 0), ringRad, colorWood, matWood, roofGroup)
	
	local rOver = 2.5 * math.min(scaleX, scaleZ)
	local cLF = Vector3.new(halfW + rOver, roofBaseY - 0.5*scaleY, -halfD - rOver)
	local cRF = Vector3.new(-halfW - rOver, roofBaseY - 0.5*scaleY, -halfD - rOver)
	local cLB = Vector3.new(halfW + rOver, roofBaseY - 0.5*scaleY, halfD + rOver)
	local cRB = Vector3.new(-halfW - rOver, roofBaseY - 0.5*scaleY, halfD + rOver)
	local apex = Vector3.new(0, roofBaseY + roofH, 0)
	
	-- Pyramid thatched roof
	GP.pyramid("Thatch", cLF, cRB, apex, colorThatch, matRoof, roofGroup)
	
	-- Top wooden cap on the roof
	GP.axisAlignedBlockFromCorners("RoofCap",
	    Vector3.new(1.2*scaleX, roofBaseY + roofH - 0.1, -1.2*scaleZ),
	    Vector3.new(-1.2*scaleX, roofBaseY + roofH + 0.3*scaleY, 1.2*scaleZ),
	    colorWood, matWood, roofGroup)
	
	tower.Parent = targetContainer
	-- reposition
	for _, part in targetContainer:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame -= Vector3.yAxis * parameters.Size.Y / 2
		end
	end
	for _, model in targetContainer:GetDescendants() do
		if model:IsA("Model") then
			model.WorldPivot -= Vector3.yAxis * parameters.Size.Y / 2
		end
	end

	-- Stop timer when generation completes
	local timeElapsed = tick() - startTime
	startTime = 0
	if timeElapsed > 3 and script:IsDescendantOf(game) then
		print("[ProceduralModel] " .. script:GetFullName() .. " rendering completed")
	end

end

return Watchtower
