--!strict
-- generationId: 2f64b111-129a-4e09-b97e-9459472ed904
local CSG = require(script.Dependencies.ConstructiveSolidGeometry)
local GP = require(script.Dependencies.GeometryPrimitives)
local SO = require(script.Dependencies.SmartObject)
local MU = require(script.Dependencies.MathUtils)


local PalengkeStall = {}

type Parameters = {
	Size: Vector3,
	Attributes: {
		AwningColor: Color3?,
		AwningStripeColor: Color3?,
		BambooColor: Color3?,
		WoodColor: Color3?,
		SignWoodColor: Color3?,
		ChalkboardColor: Color3?,
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

PalengkeStall.OnGenerate = function(parameters: Parameters, targetContainer: Instance)
	-- Timer setup
	startTime = tick()

	-- local GP = require(script.Parent.GeometryPrimitives)
	-- local CSG = require(script.Parent.ConstructiveSolidGeometry)
	-- local SO = require(script.Parent.SmartObject)
	-- local MU = require(script.Parent.MathUtils)
	
	local stallModel = GP.model("PalengkeStall", nil)-- Fix orientation of the model
	stallModel.WorldPivot = CFrame.identity
	
	
	-- ==========================================
	-- SEMANTIC PARAMETERS (Attributes)
	-- ==========================================
	local smartWidth = parameters.Size.X
	local smartHeight = parameters.Size.Y
	local smartDepth = parameters.Size.Z
	
	local awningColor = parameters.Attributes.AwningColor or Color3.fromRGB(220, 60, 60)
	local awningStripeColor = parameters.Attributes.AwningStripeColor or Color3.fromRGB(240, 240, 240)
	local bambooColor = parameters.Attributes.BambooColor or Color3.fromRGB(235, 190, 130)
	local woodColor = parameters.Attributes.WoodColor or Color3.fromRGB(210, 165, 110)
	local signWoodColor = parameters.Attributes.SignWoodColor or Color3.fromRGB(180, 140, 90)
	local chalkboardColor = parameters.Attributes.ChalkboardColor or Color3.fromRGB(50, 50, 55)
	
	local matWood = "Wood"
	local matSmooth = "SmoothPlastic"
	
	-- ==========================================
	-- DERIVED METRICS
	-- ==========================================
	local scaleX = smartWidth / 10
	local scaleY = smartHeight / 10
	local scaleZ = smartDepth / 10
	
	-- Counter dimensions
	local counterW = 8 * scaleX
	local counterD = 5 * scaleZ
	local counterH = 3 * scaleY
	local counterTopThickness = 0.3 * scaleY
	local counterOverhang = 0.4 * scaleX
	
	-- Post dimensions
	local postRadius = 0.25 * math.min(scaleX, scaleZ)
	local postH = 4.5 * scaleY
	local postTopY = counterH + counterTopThickness + postH
	
	-- Roof dimensions
	local roofRidgeY = postTopY + 2.5 * scaleY
	local roofEaveY = postTopY - 0.5 * scaleY
	local roofEaveZOffset = (counterD / 2) + 1.5 * scaleZ
	local roofOverhangX = 1.0 * scaleX
	local roofW = counterW + (counterOverhang * 2) + (roofOverhangX * 2)
	
	-- ==========================================
	-- TOP-LEVEL MODELS (Strictly following prompt)
	-- ==========================================
	local counterModel = GP.model("counter", stallModel)
	local postsModel = GP.model("posts", stallModel)
	local awningModel = GP.model("awning", stallModel)
	local signboardModel = GP.model("signboard", stallModel)
	
	-- ==========================================
	-- 1. COUNTER
	-- ==========================================
	-- Inner solid base (slightly recessed to prevent z-fighting with cladding)
	GP.axisAlignedBlockFromCorners("BaseCore",
	    Vector3.new(counterW/2 - 0.1, 0.1, counterD/2 - 0.1),
	    Vector3.new(-counterW/2 + 0.1, counterH, -counterD/2 + 0.1),
	    bambooColor, matWood, counterModel)
	
	-- Bamboo cladding along front and back (-Z and +Z)
	local logRadius = 0.3 * scaleX
	local numLogsFront = math.floor(counterW / (logRadius * 2))
	local logSpacingX = counterW / numLogsFront
	
	for i = 1, numLogsFront do
	    local xPos = (counterW / 2) - (i - 0.5) * logSpacingX
	    -- Front
	    GP.cylinder("FrontLog_" .. i,
	        Vector3.new(xPos, 0, -counterD/2),
	        Vector3.new(xPos, counterH + 2e-3, -counterD/2),
	        logRadius, bambooColor, matWood, counterModel) -- zf-prevention: vector3_component
	    -- Back
	    GP.cylinder("BackLog_" .. i,
	        Vector3.new(xPos, 0, counterD/2),
	        Vector3.new(xPos, counterH + 2e-3, counterD/2),
	        logRadius, bambooColor, matWood, counterModel) -- zf-prevention: vector3_component
	end
	
	-- Bamboo cladding along sides (+X and -X)
	local numLogsSide = math.floor(counterD / (logRadius * 2))
	local logSpacingZ = counterD / numLogsSide
	
	for i = 1, numLogsSide do
	    local zPos = (-counterD / 2) + (i - 0.5) * logSpacingZ
	    -- Left Side (+X)
	    GP.cylinder("LeftLog_" .. i,
	        Vector3.new(counterW/2, 0, zPos),
	        Vector3.new(counterW/2, counterH + 2e-3, zPos),
	        logRadius, bambooColor, matWood, counterModel) -- zf-prevention: vector3_component
	    -- Right Side (-X)
	    GP.cylinder("RightLog_" .. i,
	        Vector3.new(-counterW/2, 0, zPos),
	        Vector3.new(-counterW/2, counterH + 2e-3, zPos),
	        logRadius, bambooColor, matWood, counterModel) -- zf-prevention: vector3_component
	end
	
	-- Countertop
	GP.roundedBox("CounterTop",
	    Vector3.new(0, counterH + counterTopThickness/2, 0),
	    Vector3.new(counterW + counterOverhang*2, counterTopThickness, counterD + counterOverhang*2),
	    0.1 * scaleY, woodColor, matWood, counterModel)
	
	
	-- ==========================================
	-- 2. POSTS
	-- ==========================================
	local pX = counterW/2 - 0.2
	local pZ = counterD/2 - 0.2
	local postBaseY = counterH + counterTopThickness
	
	local corners = {
	    {name="FL", x=pX, z=-pZ},
	    {name="FR", x=-pX, z=-pZ},
	    {name="BL", x=pX, z=pZ},
	    {name="BR", x=-pX, z=-pZ} -- Wait, BR z should be pZ
	}
	corners[4].z = pZ
	
	for _, corner in ipairs(corners) do
	    -- Main Post
	    GP.cylinder("Post_" .. corner.name,
	        Vector3.new(corner.x, postBaseY, corner.z),
	        Vector3.new(corner.x, postTopY, corner.z),
	        postRadius, bambooColor, matWood, postsModel)
	        
	    -- Bamboo nodes (little rings)
	    local numNodes = 3
	    for n = 1, numNodes do
	        local nodeY = postBaseY + (n / (numNodes + 1)) * postH
	        GP.cylinder("Node_" .. corner.name .. "_" .. n,
	            Vector3.new(corner.x, nodeY - 0.05, corner.z),
	            Vector3.new(corner.x, nodeY + 0.05, corner.z),
	            postRadius * 1.1, bambooColor, matWood, postsModel)
	    end
	end
	
	-- Top Horizontal Beams connecting posts
	local beamRadius = postRadius * 0.9
	-- Front Beam
	GP.cylinder("BeamFront",
	    Vector3.new(pX + 0.5, postTopY, -pZ),
	    Vector3.new(-pX - 0.5, postTopY, -pZ),
	    beamRadius, bambooColor, matWood, postsModel)
	-- Back Beam
	GP.cylinder("BeamBack",
	    Vector3.new(pX + 0.5, postTopY, pZ),
	    Vector3.new(-pX - 0.5, postTopY, pZ),
	    beamRadius, bambooColor, matWood, postsModel)
	-- Left Beam (+X)
	GP.cylinder("BeamLeft",
	    Vector3.new(pX, postTopY, -pZ - 0.5),
	    Vector3.new(pX, postTopY, pZ + 0.5),
	    beamRadius, bambooColor, matWood, postsModel)
	-- Right Beam (-X)
	GP.cylinder("BeamRight",
	    Vector3.new(-pX, postTopY, -pZ - 0.5),
	    Vector3.new(-pX, postTopY, pZ + 0.5),
	    beamRadius, bambooColor, matWood, postsModel)
	
	
	-- ==========================================
	-- 3. AWNING
	-- ==========================================
	-- Base structural panels for the roof to sit on
	local roofThickness = 0.1 * scaleY
	local leftX = (roofW / 2)
	local rightX = -(roofW / 2)
	
	-- Helper to create a striped sloped panel
	local function buildStripedRoofPanel(name, pBaseLeft, pBaseRight, pTopRight, pTopLeft, isFront)
	    local panelGroup = GP.model(name, awningModel)
	    
	    -- Solid under-layer
	    GP.quadFromFourPoints("UnderPanel",
	        pBaseLeft, pBaseRight, pTopRight, pTopLeft,
	        roofThickness, isFront and Vector3.new(0,1,-1) or Vector3.new(0,1,1),
	        bambooColor, matWood, panelGroup)
	        
	    -- Stripes (corrugated effect)
	    local numStripes = 11 -- odd number looks good for alternating
	    local stripeW = roofW / numStripes
	    
	    local dirX = (pBaseRight - pBaseLeft).Unit
	    local dirUp = (pTopLeft - pBaseLeft)
	    
	    for i = 0, numStripes - 1 do
	        local color = (i % 2 == 0) and awningColor or awningStripeColor
	        
	        local startBase = pBaseLeft + dirX * (i * stripeW)
	        local endBase = pBaseLeft + dirX * ((i + 1) * stripeW)
	        local startTop = startBase + dirUp
	        local endTop = endBase + dirUp
	        
	        -- Extrude a quad to form the thick stripe
	        local extrudeDir = isFront and Vector3.new(0,1,-1).Unit or Vector3.new(0,1,1).Unit
	        
	        GP.quadFromFourPoints("Stripe_" .. i,
	            startBase + Vector3.new(-2e-3, -3e-3, -3e-3), endBase + Vector3.new(2e-3, 0, 3e-3), endTop, startTop,
	            0.15 * scaleY, extrudeDir, color, matSmooth, panelGroup) -- zf-prevention: vector3_component
	            
	        -- Add a rounded edge at the bottom (eave) for the corrugated look
	        local eaveMid = (startBase + endBase) / 2
	        GP.cylinder("EaveCap_" .. i,
	            startBase, endBase,
	            0.075 * scaleY, color, matSmooth, panelGroup)
	    end
	end
	
	-- Front Panel (slopes from ridge down to -Z)
	buildStripedRoofPanel("FrontPanel",
	    Vector3.new(leftX, roofEaveY, -roofEaveZOffset),
	    Vector3.new(rightX, roofEaveY, -roofEaveZOffset),
	    Vector3.new(rightX, roofRidgeY, 0),
	    Vector3.new(leftX, roofRidgeY, 0),
	    true)
	
	-- Back Panel (slopes from ridge down to +Z)
	buildStripedRoofPanel("BackPanel",
	    Vector3.new(rightX, roofEaveY, roofEaveZOffset),
	    Vector3.new(leftX, roofEaveY, roofEaveZOffset),
	    Vector3.new(leftX, roofRidgeY, 0),
	    Vector3.new(rightX, roofRidgeY, 0),
	    false)
	
	-- Ridge Cap (cylinder covering the top seam)
	GP.cylinder("RidgeCap",
	    Vector3.new(leftX + 0.2, roofRidgeY + 0.1, 0),
	    Vector3.new(rightX - 0.2, roofRidgeY + 0.1, 0),
	    0.2 * scaleY, awningColor, matSmooth, awningModel)
	
	
	-- ==========================================
	-- 4. SIGNBOARD
	-- ==========================================
	local signW = 3.5 * scaleX
	local signH = 1.8 * scaleY
	local signThickness = 0.15 * scaleZ
	local signY = postTopY - 1.2 * scaleY
	local signZ = -pZ - 0.1 -- Hangs just in front of the front beam
	
	-- Outer Frame
	GP.roundedBox("SignFrame",
	    Vector3.new(0, signY, signZ),
	    Vector3.new(signW, signH, signThickness),
	    0.05, signWoodColor, matWood, signboardModel)
	
	-- Inner Chalkboard (slightly thicker in Z to protrude/prevent z-fight, but smaller in X/Y)
	GP.axisAlignedBlockFromCorners("Chalkboard",
	    Vector3.new(signW/2 - 0.2, signY - signH/2 + 0.2, signZ - signThickness/2 - 0.02),
	    Vector3.new(-signW/2 + 0.2, signY + signH/2 - 0.2, signZ + signThickness/2 + 0.02),
	    chalkboardColor, matSmooth, signboardModel)
	
	-- Hanging ropes/chains
	local ropeDist = signW / 2 - 0.4
	-- Left Rope (+X)
	GP.cylinder("RopeLeft",
	    Vector3.new(ropeDist, signY + signH/2, signZ),
	    Vector3.new(ropeDist, postTopY, -pZ),
	    0.03 * scaleX, signWoodColor, matWood, signboardModel)
	-- Right Rope (-X)
	GP.cylinder("RopeRight",
	    Vector3.new(-ropeDist, signY + signH/2, signZ),
	    Vector3.new(-ropeDist, postTopY, -pZ),
	    0.03 * scaleX, signWoodColor, matWood, signboardModel)
	
	stallModel.Parent = targetContainer
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

return PalengkeStall
