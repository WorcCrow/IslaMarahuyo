--!strict
-- generationId: a32ac2f8-65de-4bb4-a2e8-0ed11ecaf9e5
local CSG = require(script.Dependencies.ConstructiveSolidGeometry)
local GP = require(script.Dependencies.GeometryPrimitives)
local SO = require(script.Dependencies.SmartObject)
local MU = require(script.Dependencies.MathUtils)


local Pavilion = {}

type Parameters = {
	Size: Vector3,
	Attributes: {
		Scale: number?,
		RoofColor: Color3?,
		WoodColor: Color3?,
		FloorColor: Color3?,
		DarkWoodColor: Color3?,
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

Pavilion.OnGenerate = function(parameters: Parameters, targetContainer: Instance)
	-- Timer setup
	startTime = tick()

	local gazeboModel = GP.model("Pavilion", nil)-- Fix orientation of the model
	gazeboModel.WorldPivot = CFrame.identity
	
	
	-- == ATTRIBUTES ==
	local smartWidth = parameters.Size.X
	local smartHeight = parameters.Size.Y
	local smartDepth = parameters.Size.Z
	local userScale = parameters.Attributes.Scale or 1.0
	
	local roofColor = parameters.Attributes.RoofColor or Color3.fromRGB(190, 150, 90)
	local woodColor = parameters.Attributes.WoodColor or Color3.fromRGB(150, 100, 60)
	local floorColor = parameters.Attributes.FloorColor or Color3.fromRGB(140, 95, 60)
	local darkWoodColor = parameters.Attributes.DarkWoodColor or Color3.fromRGB(110, 70, 40)
	
	-- Apply overall scale
	local w = smartWidth * userScale
	local h = smartHeight * userScale
	local d = smartDepth * userScale
	
	-- Base Dimensions
	local baseRadius = math.max(w, d) / 2
	local platformHeight = h * 0.1
	local postHeight = h * 0.45
	local roofTotalHeight = h * 0.45
	
	local lowerRoofHeight = roofTotalHeight * 0.5
	local upperRoofHeight = roofTotalHeight * 0.4
	local finialHeight = roofTotalHeight * 0.1
	
	local postRadius = baseRadius * 0.06
	local postInset = baseRadius * 0.15
	local postCircleRadius = baseRadius - postInset
	
	local lowerEaveRadius = baseRadius * 1.1
	local upperEaveRadius = baseRadius * 0.65
	
	-- Materials
	local matWood = "WoodPlanks"
	local matPost = "Wood"
	local matRoof = "Grass" -- Represents thatch
	
	-- == REQUIRED TOP-LEVEL MODELS ==
	local platformGroup = GP.model("platform", gazeboModel)
	local postsGroup = GP.model("posts", gazeboModel)
	local roofGroup = GP.model("roof", gazeboModel)
	local roofTrimGroup = GP.model("roof trim", gazeboModel)
	
	-- == 1. PLATFORM ==
	-- Raised circular wooden platform
	local platformCenter = Vector3.new(0, 0, 0)
	local platformTop = Vector3.new(0, platformHeight, 0)
	GP.cylinder("PlatformBase", platformCenter + Vector3.new(0, -2e-3, 0), platformTop, baseRadius, floorColor, matWood, platformGroup) -- zf-prevention: vector3_component
	
	-- Add a slight trim ring around the base for detail
	GP.hollowCylinder("PlatformTrim", platformCenter, platformCenter + Vector3.new(0, platformHeight + 0.05, 0), baseRadius + 0.1, 0.2, darkWoodColor, matWood, platformGroup)
	
	
	-- == 2. POSTS ==
	local postCount = 8
	local roofBaseY = platformHeight + postHeight
	
	for i = 1, postCount do
	    local angle = (i - 1) * (math.pi * 2 / postCount) + (math.pi / 8) -- offset so posts align with octagonal roof corners
	    local px = math.cos(angle) * postCircleRadius
	    local pz = math.sin(angle) * postCircleRadius
	    
	    local pBottom = Vector3.new(px, platformHeight, pz)
	    local pTop = Vector3.new(px, roofBaseY, pz)
	    
	    -- Main Pillar
	    GP.cylinder("Post_" .. i, pBottom, pTop, postRadius, woodColor, matPost, postsGroup)
	    
	    -- Base block (Plinth)
	    GP.cylinder("PostBase_" .. i, pBottom, pBottom + Vector3.new(0, postHeight * 0.05, 0), postRadius * 1.3, woodColor, matPost, postsGroup)
	    
	    -- Capital block
	    GP.cylinder("PostCap_" .. i, pTop - Vector3.new(0, (postHeight * 0.05) - 2e-3, 0), pTop, postRadius * 1.3, woodColor, matPost, postsGroup) -- zf-prevention: vector3_component
	end
	
	
	-- == HELPER: OCTAGON POINTS ==
	local function getOctagonPoints(yLevel, radius)
	    local pts = {}
	    for i = 1, 8 do
	        local angle = (i - 1) * (math.pi * 2 / 8) + (math.pi / 8)
	        local px = math.cos(angle) * radius
	        local pz = math.sin(angle) * radius
	        table.insert(pts, Vector3.new(px, yLevel, pz))
	    end
	    return pts
	end
	
	
	-- == 3. ROOF ==
	local lowerEaveY = roofBaseY - (roofTotalHeight * 0.05) -- Overhang drops slightly
	local lowerApexY = lowerEaveY + lowerRoofHeight
	local upperEaveY = lowerApexY - (roofTotalHeight * 0.1) -- Overlaps the lower roof
	local upperApexY = upperEaveY + upperRoofHeight
	
	local lowerEavePts = getOctagonPoints(lowerEaveY, lowerEaveRadius)
	local lowerInnerPts = getOctagonPoints(lowerApexY, upperEaveRadius * 0.9) -- Tapers to support upper roof
	
	local upperEavePts = getOctagonPoints(upperEaveY, upperEaveRadius)
	local upperApexPt = Vector3.new(0, upperApexY, 0)
	
	-- Build Lower Roof Tier (Octagonal Frustum using quads)
	for i = 1, 8 do
	    local nextI = (i % 8) + 1
	    local p1 = lowerEavePts[i]
	    local p2 = lowerEavePts[nextI]
	    local p3 = lowerInnerPts[nextI]
	    local p4 = lowerInnerPts[i]
	    
	    -- Normal points generally upwards. Extrusion dir up.
	    GP.quadFromFourPoints("LowerRoofFace_" .. i, p4, p3, p2, p1, 0.4, Vector3.new(0, 1, 0), roofColor, matRoof, roofGroup)
	    
	    -- Roof Ridge (bamboo/wood covering the seams)
	    GP.strutFromTwoPoints("LowerRidge_" .. i, p1 + Vector3.new(0, 0.2, 0), p4 + Vector3.new(0, 0.2, 0), 0.3, 0.3, darkWoodColor, matPost, roofGroup)
	end
	
	-- Build Upper Roof Tier (Octagonal Pyramid using triangular prisms)
	for i = 1, 8 do
	    local nextI = (i % 8) + 1
	    local p1 = upperEavePts[i]
	    local p2 = upperEavePts[nextI]
	    
	    -- Extrude outwards/upwards
	    local midEave = (p1 + p2) / 2
	    local extrudeDir = (upperApexPt - midEave).Unit + Vector3.new(0, 1, 0)
	    
	    GP.triangularPrismFromThreePoints("UpperRoofFace_" .. i, p2, p1, upperApexPt, 0.4, extrudeDir, roofColor, matRoof, roofGroup)
	    
	    -- Roof Ridge
	    GP.strutFromTwoPoints("UpperRidge_" .. i, p1 + Vector3.new(0, 0.2, 0), upperApexPt + Vector3.new(0, 0.2, 0), 0.3, 0.3, darkWoodColor, matPost, roofGroup)
	end
	
	-- Apex Finial
	GP.taperedCylinder("FinialBase", upperApexPt, upperApexPt + Vector3.new(0, finialHeight * 0.4, 0), 0.6, 0.2, darkWoodColor, matPost, roofGroup)
	GP.taperedCylinder("FinialTip", upperApexPt + Vector3.new(0, finialHeight * 0.4, 0), upperApexPt + Vector3.new(0, finialHeight, 0), 0.3, 0.05, darkWoodColor, matPost, roofGroup)
	
	
	-- == 4. ROOF TRIM ==
	-- Adds decorative carved wooden eaves under the roof edges
	local function buildTrim(ptsGroup, namePrefix)
	    for i = 1, 8 do
	        local nextI = (i % 8) + 1
	        local p1 = ptsGroup[i]
	        local p2 = ptsGroup[nextI]
	        
	        -- Offset slightly inward and downward from the thatch edge
	        local inwardDir = (Vector3.new(0, p1.Y, 0) - p1).Unit
	        local trimP1 = p1 + inwardDir * 0.2 - Vector3.new(0, 0.1, 0)
	        local trimP2 = p2 + inwardDir * 0.2 - Vector3.new(0, 0.1, 0)
	        
	        -- Main Fascia Board
	        GP.strutFromTwoPoints(namePrefix .. "_Fascia_" .. i, trimP1, trimP2, 0.2, 0.6, woodColor, matWood, roofTrimGroup)
	        
	        -- Dangling carved scallops
	        local trimLength = (trimP2 - trimP1).Magnitude
	        local scallopSpacing = 1.0
	        local scallopCount = math.floor(trimLength / scallopSpacing)
	        
	        if scallopCount > 0 then
	            MU.linearArray(trimP1, trimP2, scallopCount, function(pos, index)
	                -- Avoid placing drops exactly at the corners
	                if index > 1 and index < scallopCount then
	                    local dropStart = pos - Vector3.new(0, 0.3, 0)
	                    local dropEnd = dropStart - Vector3.new(0, 0.5, 0)
	                    -- Intricate drop: cone -> sphere
	                    GP.taperedCylinder(namePrefix .. "_DropStem_" .. i .. "_" .. index, dropStart, dropEnd, 0.15, 0.05, darkWoodColor, matWood, roofTrimGroup)
	                    GP.sphere(namePrefix .. "_DropTip_" .. i .. "_" .. index, dropEnd - Vector3.new(0, 0.05, 0), 0.1, darkWoodColor, matWood, roofTrimGroup)
	                end
	            end)
	        end
	    end
	end
	
	-- Apply trim to both lower and upper eaves
	buildTrim(lowerEavePts, "Lower")
	buildTrim(upperEavePts, "Upper")
	
	-- Inner cross beams connecting posts at the top for structural support
	for i = 1, 8 do
	    local nextI = (i % 8) + 1
	    local angle1 = (i - 1) * (math.pi * 2 / 8) + (math.pi / 8)
	    local angle2 = (nextI - 1) * (math.pi * 2 / 8) + (math.pi / 8)
	    
	    local p1 = Vector3.new(math.cos(angle1) * postCircleRadius, roofBaseY, math.sin(angle1) * postCircleRadius)
	    local p2 = Vector3.new(math.cos(angle2) * postCircleRadius, roofBaseY, math.sin(angle2) * postCircleRadius)
	    
	    GP.strutFromTwoPoints("InnerBeam_" .. i, p1, p2, postRadius * 1.5, postRadius * 1.5, darkWoodColor, matWood, roofTrimGroup)
	    
	    -- Small corner brackets for the posts
	    local p1Dir = (p2 - p1).Unit
	    local bracketStart = p1 - Vector3.new(0, postHeight * 0.15, 0)
	    local bracketEnd = p1 + p1Dir * (postCircleRadius * 0.3)
	    GP.strutFromTwoPoints("BracketL_" .. i, bracketStart, bracketEnd, 0.2, 0.2, woodColor, matWood, roofTrimGroup)
	    
	    local p2Dir = (p1 - p2).Unit
	    local bracketStart2 = p2 - Vector3.new(0, postHeight * 0.15, 0)
	    local bracketEnd2 = p2 + p2Dir * (postCircleRadius * 0.3)
	    GP.strutFromTwoPoints("BracketR_" .. i, bracketStart2, bracketEnd2, 0.2, 0.2, woodColor, matWood, roofTrimGroup)
	end
	
	
	gazeboModel.Parent = targetContainer
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

return Pavilion
