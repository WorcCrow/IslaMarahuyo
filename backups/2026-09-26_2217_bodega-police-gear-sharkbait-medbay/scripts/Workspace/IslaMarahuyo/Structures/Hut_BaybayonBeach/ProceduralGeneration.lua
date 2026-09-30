--!strict
-- generationId: 4043f588-908f-4e10-8a4d-3824c05a1971
local CSG = require(script.Dependencies.ConstructiveSolidGeometry)
local GP = require(script.Dependencies.GeometryPrimitives)
local SO = require(script.Dependencies.SmartObject)
local MU = require(script.Dependencies.MathUtils)


local BahayKubo = {}

type Parameters = {
	Size: Vector3,
	Attributes: {
		RoofColor: Color3?,
		WallColor: Color3?,
		FrameColor: Color3?,
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

BahayKubo.OnGenerate = function(parameters: Parameters, targetContainer: Instance)
	-- Timer setup
	startTime = tick()

	local kubo = GP.model("BahayKubo", nil)-- Fix orientation of the model
	kubo.WorldPivot = CFrame.identity
	
	
	-- ==========================================
	-- SMART SCALING & ATTRIBUTES
	-- ==========================================
	local smartWidth = parameters.Size.X
	local smartHeight = parameters.Size.Y
	local smartDepth = parameters.Size.Z
	
	local scaleX = smartWidth / 10
	local scaleY = smartHeight / 10
	local scaleZ = smartDepth / 10
	
	local roofColor = parameters.Attributes.RoofColor or Color3.fromRGB(130, 110, 90)
	local wallColor = parameters.Attributes.WallColor or Color3.fromRGB(200, 150, 80)
	local frameColor = parameters.Attributes.FrameColor or Color3.fromRGB(80, 50, 40)
	
	-- ==========================================
	-- LAYOUT VARIABLES
	-- ==========================================
	-- Base dimensions before scaling
	local baseWidth = 14
	local baseDepth = 16
	local baseFloorY = 5
	local baseWallH = 6
	local baseRoofH = 7
	local basePorchD = 4
	
	-- Scaled dimensions
	local w = baseWidth * scaleX
	local d = baseDepth * scaleZ
	local floorY = baseFloorY * scaleY
	local wallH = baseWallH * scaleY
	local roofH = baseRoofH * scaleY
	local porchD = basePorchD * scaleZ
	
	local halfW = w / 2
	local halfD = d / 2
	
	-- X axis: Left is +X, Right is -X
	local leftX = halfW
	local rightX = -halfW
	
	-- Z axis: Front is -Z, Back is +Z
	local frontZ = -halfD
	local backZ = halfD
	local cabinFrontZ = frontZ + porchD
	
	-- Top level Ys
	local ceilingY = floorY + wallH
	local peakY = ceilingY + roofH
	
	-- Wall thickness and post radius
	local wallT = 0.4 * scaleX
	local postR = 0.3 * math.min(scaleX, scaleZ)
	
	-- ==========================================
	-- TOP-LEVEL MODELS (Strictly Named)
	-- ==========================================
	local m_stilts = GP.model("stilts", kubo)
	local m_floor = GP.model("floor platform", kubo)
	local m_walls = GP.model("walls", kubo)
	local m_roof = GP.model("roof", kubo)
	local m_porch = GP.model("porch", kubo)
	local m_ladder = GP.model("ladder", kubo)
	
	-- ==========================================
	-- 1. STILTS
	-- ==========================================
	local postXs = {leftX - postR, rightX + postR}
	local postZs = {frontZ + postR, cabinFrontZ + postR, backZ - postR}
	
	for i, px in ipairs(postXs) do
	    for j, pz in ipairs(postZs) do
	        -- Skip middle posts if not needed, but kubos often have them. We'll use 6 posts.
	        GP.cylinder("Stilt_"..i.."_"..j,
	            Vector3.new(px, 0, pz),
	            Vector3.new(px, floorY, pz),
	            postR, frameColor, "Wood", m_stilts)
	    end
	end
	
	-- ==========================================
	-- 2. FLOOR PLATFORM
	-- ==========================================
	local floorT = 0.4 * scaleY
	GP.axisAlignedBlockFromCorners("MainFloor",
	    Vector3.new(rightX, floorY - floorT, frontZ),
	    Vector3.new(leftX, floorY + 2e-3, backZ),
	    wallColor, "WoodPlanks", m_floor) -- zf-prevention: vector3_component
	
	-- Under-floor support beams
	GP.cylinder("BeamFront", Vector3.new(leftX, floorY - floorT, frontZ + postR), Vector3.new(rightX + 2e-3, floorY - floorT, frontZ + postR), postR*0.8, frameColor, "Wood", m_floor) -- zf-prevention: vector3_component
	GP.cylinder("BeamMid", Vector3.new(leftX, floorY - floorT, cabinFrontZ + postR), Vector3.new(rightX + 2e-3, floorY - floorT, cabinFrontZ + postR), postR*0.8, frameColor, "Wood", m_floor) -- zf-prevention: vector3_component
	GP.cylinder("BeamBack", Vector3.new(leftX, floorY - floorT, backZ - postR), Vector3.new(rightX + 2e-3, floorY - floorT, backZ - postR), postR*0.8, frameColor, "Wood", m_floor) -- zf-prevention: vector3_component
	GP.cylinder("BeamLeft", Vector3.new(leftX - postR, floorY - floorT, frontZ), Vector3.new(leftX - postR, floorY - floorT, backZ + 2e-3), postR*0.8, frameColor, "Wood", m_floor) -- zf-prevention: vector3_component
	GP.cylinder("BeamRight", Vector3.new(rightX + postR, floorY - floorT, frontZ), Vector3.new(rightX + postR, floorY - floorT, backZ + 2e-3), postR*0.8, frameColor, "Wood", m_floor) -- zf-prevention: vector3_component
	
	-- ==========================================
	-- 3. WALLS
	-- ==========================================
	-- Cabin occupies from cabinFrontZ to backZ, and leftX to rightX
	local cLeft = leftX - 0.2*scaleX
	local cRight = rightX + 0.2*scaleX
	local cFront = cabinFrontZ
	local cBack = backZ - 0.2*scaleZ
	
	-- Back Wall
	GP.axisAlignedBlockFromCorners("WallBack",
	    Vector3.new(cRight, floorY, cBack - wallT),
	    Vector3.new(cLeft, ceilingY, cBack),
	    wallColor, "WoodPlanks", m_walls)
	
	-- Left Wall
	GP.axisAlignedBlockFromCorners("WallLeft",
	    Vector3.new(cLeft - wallT, floorY, cFront),
	    Vector3.new(cLeft, ceilingY, cBack - wallT),
	    wallColor, "WoodPlanks", m_walls)
	
	-- Right Wall
	GP.axisAlignedBlockFromCorners("WallRight",
	    Vector3.new(cRight, floorY, cFront),
	    Vector3.new(cRight + wallT, ceilingY, cBack - wallT),
	    wallColor, "WoodPlanks", m_walls)
	
	-- Front Wall (with door gap in the middle)
	local doorW = 3.5 * scaleX
	local doorH = 5 * scaleY
	local dLeft = doorW / 2
	local dRight = -doorW / 2
	
	-- Left part of front wall
	GP.axisAlignedBlockFromCorners("WallFrontLeft",
	    Vector3.new(dLeft, floorY, cFront),
	    Vector3.new(cLeft, ceilingY, cFront + wallT),
	    wallColor, "WoodPlanks", m_walls)
	
	-- Right part of front wall
	GP.axisAlignedBlockFromCorners("WallFrontRight",
	    Vector3.new(cRight, floorY, cFront),
	    Vector3.new(dRight, ceilingY, cFront + wallT),
	    wallColor, "WoodPlanks", m_walls)
	
	-- Top part of front wall (above door)
	GP.axisAlignedBlockFromCorners("WallFrontTop",
	    Vector3.new(dRight, floorY + doorH, cFront),
	    Vector3.new(dLeft, ceilingY, cFront + wallT),
	    wallColor, "WoodPlanks", m_walls)
	
	-- A closed door (slightly recessed)
	GP.axisAlignedBlockFromCorners("Door",
	    Vector3.new(dRight + 0.1, floorY, cFront + wallT*0.8),
	    Vector3.new(dLeft - 0.1, floorY + doorH - 0.1, cFront + wallT*1.2),
	    wallColor, "WoodPlanks", m_walls)
	
	-- ==========================================
	-- 4. ROOF
	-- ==========================================
	local eavesOverhang = 2.5 * math.max(scaleX, scaleZ)
	local rLeft = cLeft + eavesOverhang
	local rRight = cRight - eavesOverhang
	local rFront = cFront - eavesOverhang - (porchD*0.5) -- Cover porch partially
	local rBack = cBack + eavesOverhang
	local eavesY = ceilingY - (1 * scaleY)
	
	local ridgeLen = w * 0.4
	local ridgeLeft = ridgeLen / 2
	local ridgeRight = -ridgeLen / 2
	local ridgeZ = (cFront + cBack) / 2
	local roofT = 0.6 * scaleY
	
	-- Front Roof Plane
	GP.quadFromFourPoints("RoofFront",
	    Vector3.new(ridgeLeft, peakY, ridgeZ),
	    Vector3.new(ridgeRight, peakY, ridgeZ),
	    Vector3.new(rRight, eavesY, rFront),
	    Vector3.new(rLeft, eavesY, rFront),
	    roofT, Vector3.new(0,1,0), roofColor, "Grass", m_roof)
	
	-- Back Roof Plane
	GP.quadFromFourPoints("RoofBack",
	    Vector3.new(ridgeRight, peakY, ridgeZ),
	    Vector3.new(ridgeLeft, peakY, ridgeZ),
	    Vector3.new(rLeft, eavesY, rBack),
	    Vector3.new(rRight, eavesY, rBack),
	    roofT, Vector3.new(0,1,0), roofColor, "Grass", m_roof)
	
	-- Left Roof Plane
	GP.quadFromFourPoints("RoofLeft",
	    Vector3.new(ridgeLeft, peakY, ridgeZ),
	    Vector3.new(rLeft, eavesY, rFront),
	    Vector3.new(rLeft, eavesY, rBack),
	    Vector3.new(ridgeLeft, peakY, ridgeZ), -- Triangle degenerate quad
	    roofT, Vector3.new(1,1,0), roofColor, "Grass", m_roof)
	
	-- Right Roof Plane
	GP.quadFromFourPoints("RoofRight",
	    Vector3.new(ridgeRight, peakY, ridgeZ),
	    Vector3.new(ridgeRight, peakY, ridgeZ), -- Triangle degenerate quad
	    Vector3.new(rRight, eavesY, rBack),
	    Vector3.new(rRight, eavesY, rFront),
	    roofT, Vector3.new(-1,1,0), roofColor, "Grass", m_roof)
	
	-- Ridge cap
	GP.cylinder("RidgeCap",
	    Vector3.new(ridgeLeft + 0.5, peakY + roofT, ridgeZ),
	    Vector3.new(ridgeRight - 0.5, peakY + roofT, ridgeZ),
	    0.4 * scaleY, frameColor, "Wood", m_roof)
	
	-- ==========================================
	-- 5. PORCH
	-- ==========================================
	local railH = 2.5 * scaleY
	local railT = 0.2 * scaleX
	
	-- Left railing
	GP.cylinder("RailLeftTop", Vector3.new(leftX - 0.2, floorY + railH, frontZ), Vector3.new(leftX - 0.2, floorY + railH, cabinFrontZ), railT, wallColor, "Wood", m_porch)
	GP.cylinder("RailLeftBot", Vector3.new(leftX - 0.2, floorY + 0.5, frontZ), Vector3.new(leftX - 0.2, floorY + 0.5, cabinFrontZ), railT, wallColor, "Wood", m_porch)
	
	-- Right railing
	GP.cylinder("RailRightTop", Vector3.new(rightX + 0.2, floorY + railH, frontZ), Vector3.new(rightX + 0.2, floorY + railH, cabinFrontZ), railT, wallColor, "Wood", m_porch)
	GP.cylinder("RailRightBot", Vector3.new(rightX + 0.2, floorY + 0.5, frontZ), Vector3.new(rightX + 0.2, floorY + 0.5, cabinFrontZ), railT, wallColor, "Wood", m_porch)
	
	-- Front railing (left side of ladder)
	local ladGapL = 2 * scaleX
	local ladGapR = -2 * scaleX
	GP.cylinder("RailFrontLTop", Vector3.new(leftX, floorY + railH, frontZ + 0.2), Vector3.new(ladGapL, floorY + railH, frontZ + 0.2), railT, wallColor, "Wood", m_porch)
	GP.cylinder("RailFrontLBot", Vector3.new(leftX, floorY + 0.5, frontZ + 0.2), Vector3.new(ladGapL, floorY + 0.5, frontZ + 0.2), railT, wallColor, "Wood", m_porch)
	
	-- Front railing (right side of ladder)
	GP.cylinder("RailFrontRTop", Vector3.new(ladGapR, floorY + railH, frontZ + 0.2), Vector3.new(rightX, floorY + railH, frontZ + 0.2), railT, wallColor, "Wood", m_porch)
	GP.cylinder("RailFrontRBot", Vector3.new(ladGapR, floorY + 0.5, frontZ + 0.2), Vector3.new(rightX, floorY + 0.5, frontZ + 0.2), railT, wallColor, "Wood", m_porch)
	
	-- Vertical balusters
	local function makeBalusters(p1, p2, count)
	    for i=1, count do
	        local t = i / (count + 1)
	        local bx = p1.X + (p2.X - p1.X) * t
	        local bz = p1.Z + (p2.Z - p1.Z) * t
	        GP.cylinder("Baluster", Vector3.new(bx, floorY + 0.5, bz), Vector3.new(bx, floorY + railH, bz), railT*0.6, wallColor, "Wood", m_porch)
	    end
	end
	
	makeBalusters(Vector3.new(leftX, 0, frontZ), Vector3.new(leftX, 0, cabinFrontZ), 4)
	makeBalusters(Vector3.new(rightX, 0, frontZ), Vector3.new(rightX, 0, cabinFrontZ), 4)
	makeBalusters(Vector3.new(leftX, 0, frontZ), Vector3.new(ladGapL, 0, frontZ), 3)
	makeBalusters(Vector3.new(ladGapR, 0, frontZ), Vector3.new(rightX, 0, frontZ), 3)
	
	-- ==========================================
	-- 6. LADDER
	-- ==========================================
	local ladW = 3 * scaleX
	local ladBaseZ = frontZ - (4 * scaleZ)
	local ladRailR = 0.25 * math.min(scaleX, scaleZ)
	
	local lTopL = Vector3.new(ladW/2, floorY, frontZ)
	local lTopR = Vector3.new(-ladW/2, floorY, frontZ)
	local lBotL = Vector3.new(ladW/2, 0, ladBaseZ)
	local lBotR = Vector3.new(-ladW/2, 0, ladBaseZ)
	
	GP.cylinder("LadderRailL", lBotL, lTopL, ladRailR, frameColor, "Wood", m_ladder)
	GP.cylinder("LadderRailR", lBotR, lTopR, ladRailR, frameColor, "Wood", m_ladder)
	
	local rungCount = 5
	for i = 1, rungCount do
	    local t = i / (rungCount + 1)
	    local rL = MU.lerpVector3(lBotL, lTopL, t)
	    local rR = MU.lerpVector3(lBotR, lTopR, t)
	    GP.cylinder("Rung_"..i, rL, rR, ladRailR * 0.8, wallColor, "Wood", m_ladder)
	end
	
	kubo.Parent = targetContainer
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

return BahayKubo
