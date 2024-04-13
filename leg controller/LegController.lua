-- Services --
local RunService = game:GetService("RunService")

-- Modules / Direcotires --

local InverseKinematics = require(script:WaitForChild("InverseKinematics"))

local LegController = {}
LegController.__index = LegController

local ikAttachments = {
	["leftHip"] = CFrame.new(-0.466, -0.944, 0),
	["leftFoot"] = CFrame.new(-0.5, -2.9, 0),
	["rightHip"] = CFrame.new(0.5, -0.944, 0),
	["rightFoot"] = CFrame.new(0.5, -2.9, 0)
}
 
 
local function nilContentsExist(Tbl : any)
	for Index, Val in pairs(Tbl) do
		if Val == nil then
			return true
		end
	end
	
	return false
end

local function IsNan(Value)
	return Value ~= Value
end


function LegController.new(Character : Model, Configuration : any)
	local self = setmetatable({}, LegController)
	
	self.Connection = nil
	
	-- Important variables --
	local Humanoid = Character:WaitForChild("Humanoid")	
	local leftHip = Character:FindFirstChild(Humanoid.RigType == Enum.HumanoidRigType.R15 and "LeftHip" or "Left Hip", true)
	local rightHip = Character:FindFirstChild(Humanoid.RigType == Enum.HumanoidRigType.R15 and "RightHip" or "Right Hip", true)
	
	self.States = {
		["tiltingEnabled"] = true,
		["ikEnabled"] = Configuration.ikEnabled
	}
	
	local motor6D = {
		Hips = {
			["LeftHip"] = leftHip.C0,
			["RightHip"] = rightHip.C0,
		},
	}
	
	local characterIK = nil
	if Humanoid.RigType == Enum.HumanoidRigType.R6 then
		characterIK = InverseKinematics.New(Character)
	end
	
	-- Setting up raycast params for inverse kinematics --
	local ikParams = RaycastParams.new()
	ikParams.FilterType = Enum.RaycastFilterType.Exclude
	ikParams.FilterDescendantsInstances = {Character}
	ikParams.RespectCanCollide = true
	ikParams.IgnoreWater = true
	for Index, exclusionObject in pairs(Configuration.ikExclude) do
		table.insert(ikParams.FilterDescendantsInstances, exclusionObject)
	end
	
	local ikParts = {}
	for Index, CF in pairs(ikAttachments) do
		local newAttachment = Instance.new("Attachment")
		newAttachment.Name = Index
		newAttachment.CFrame = CF
		newAttachment.Parent = Humanoid.RootPart
		
		ikParts[newAttachment.Name] = newAttachment --Adding the newly created attachment to a table
	end
	
	
	self.Connection = RunService.RenderStepped:ConnectParallel(function(deltaTime : number)
		local normalizedDeltaTime = deltaTime * 60
		
		local rootVelocity = Vector3.new(1, 0, 1) * Humanoid.RootPart.Velocity
		local directionalRightVelocity = Humanoid.RootPart.CFrame.RightVector:Dot(rootVelocity.unit)
	
		if IsNan(directionalRightVelocity) then
			return
		end
		
		-- Inverse Kinematics --
		local ikLeftC0, ikRightC0 = nil, nil
		if characterIK and self.States.ikEnabled and not nilContentsExist(ikParts) and rootVelocity.Magnitude < Configuration.maxIkVelocity then
			local leftDir = ikParts.leftFoot.WorldCFrame.Position - ikParts.leftHip.WorldCFrame.Position
			local rightDir = ikParts.rightFoot.WorldCFrame.Position - ikParts.rightHip.WorldCFrame.Position
			
			local leftRay = workspace:Raycast(ikParts.leftHip.WorldCFrame.Position, leftDir, ikParams)
			local rightRay = workspace:Raycast(ikParts.rightHip.WorldCFrame.Position, rightDir, ikParams)
			
			if leftRay then
				ikLeftC0 = characterIK:LegIK("Left", leftRay.Position)
			end
			if rightRay then
				ikRightC0 = characterIK:LegIK("Right", rightRay.Position)
			end
		end
		
		-- For angle calculation --
		local canAngle = table.find(Configuration.onStates, Humanoid:GetState())
		local notInverse = Humanoid.RootPart.CFrame.LookVector:Dot(Humanoid.MoveDirection) < -0.1
	
		if IsNan(notInverse) then
			return
		end

		local legAngle = (self.States.tiltingEnabled and canAngle and rootVelocity.Magnitude > Configuration.activationVelocity and math.rad(directionalRightVelocity * Configuration.maxAngle) or 0)
			* (notInverse and 1 or -1)
		
		-- Setting motor6D C0s --
		local interpolationSpeed = Configuration.interploationSpeed.Speed * (rootVelocity.Magnitude < Configuration.interploationSpeed.highVelocityPoint and 2.8 or 1)
		
		
		local LC0 = leftHip.C0:Lerp(ikLeftC0 or motor6D.Hips.LeftHip * CFrame.Angles(0, legAngle, 0), interpolationSpeed * normalizedDeltaTime)
		local RC0 = rightHip.C0:Lerp(ikRightC0 or motor6D.Hips.RightHip * CFrame.Angles(0, legAngle, 0), interpolationSpeed * normalizedDeltaTime)
		
		if IsNan(LC0) or IsNan(RC0) then
			return
		end
		
		task.synchronize()
		
		leftHip.C0 = LC0
		rightHip.C0 = RC0
		
		task.desynchronize()		
	end)
	
	return self
end

function LegController:setState(stateString : string, Enabled : boolean)
	if not self.States[stateString] then error("Invalid string") return end
	
	self.States[stateString] = Enabled
end

function LegController:Destroy()	
	if self.Connection then
		self.Connection:Disconnect()
	end
	
	table.clear(self)
	setmetatable(self, nil)

	return
end

return LegController
