local function SolveArmIK(originCFF, targetPos, l1, l2, C1Off, Side : "Left" | "Right")	
	-- build intial values for solving
	local originCF
	if Side == "Left" then
		originCF = originCFF*CFrame.new(0,0,C1Off.X)
	elseif Side == "Right" then
		originCF = originCFF*CFrame.new(0,0,-C1Off.X)
	end
	local localized = originCF:pointToObjectSpace(targetPos)
	local localizedUnit = localized.unit
	local l3 = localized.magnitude

	-- build a "rolled" planeCF for a more natural arm look
	local axis = Vector3.new(0, 0, -1):Cross(localizedUnit)
	local angle = math.acos(-localizedUnit.Z)
	local planeCF = originCF * CFrame.fromAxisAngle(axis, angle)

	-- case: point is to close, unreachable
	-- return: push back planeCF so the "hand" still reaches, angles fully compressed
	if l3 < math.max(l2, l1) - math.min(l2, l1) then
		return planeCF * CFrame.new(0, 0,  math.max(l2, l1) - math.min(l2, l1) - l3), -math.pi/2, math.pi

		-- case: point is to far, unreachable
		-- return: for forward planeCF so the "hand" still reaches, angles fully extended
	elseif l3 > l1 + l2 then
		return planeCF, math.pi/2, 0, l3

		-- case: point is reachable
		-- return: planeCF is fine, solve the angles of the triangle
	else
		local a1 = -math.acos((-(l2 * l2) + (l1 * l1) + (l3 * l3)) / (2 * l1 * l3))
		local a2 = math.acos(((l2  * l2) - (l1 * l1) + (l3 * l3)) / (2 * l2 * l3))

		return planeCF, a1 + math.pi/2, a2 - a1
	end
end

local function SolveLegIK(originCFF, targetPos, l1, l2, C1Off)	
	-- build intial values for solving
	local originCF = originCFF*CFrame.new(-C1Off.X,0,0)
	local localized = originCF:pointToObjectSpace(targetPos)
	local localizedUnit = localized.unit
	local l3 = localized.magnitude

	-- build a "rolled" planeCF for a more natural arm look
	local axis = Vector3.new(0, 0, -1):Cross(-localizedUnit)
	local angle = math.acos(-localizedUnit.Z)
	local planeCF = originCF * CFrame.fromAxisAngle(axis, angle):Inverse()

	-- case: point is to close, unreachable
	-- return: push back planeCF so the "hand" still reaches, angles fully compressed
	if l3 < math.max(l2, l1) - math.min(l2, l1) then
		return planeCF * CFrame.new(0, 0,  math.max(l2, l1) - math.min(l2, l1) - l3), -math.pi/2, math.pi

		-- case: point is to far, unreachable
		-- return: for forward planeCF so the "hand" still reaches, angles fully extended
	elseif l3 > l1 + l2 then
		return planeCF, math.pi/2, 0, l3

		-- case: point is reachable
		-- return: planeCF is fine, solve the angles of the triangle
	else
		local a1 = -math.acos((-(l2 * l2) + (l1 * l1) + (l3 * l3)) / (2 * l1 * l3))
		local a2 = math.acos(((l2  * l2) - (l1 * l1) + (l3 * l3)) / (2 * l2 * l3))

		return planeCF, math.pi/2-a1, -(a2 - a1)
	end
end

local function SolveLesIK(o,t,l0,l1) -- Does the major math calculations for IK
	-- Make the position local relative to the origin
	local l = o:pointToObjectSpace(t) -- World space to local space
	local lu = l.Unit -- Get normalized unit for future math

	local m = l.Magnitude -- Get the length from the position to the target

	-- Make a CFrame pointing from the shoulder position directing to the second position
	local x = Vector3.new(0,0,-1):Cross(-lu) -- Cross the forward vector with the negative of the normalized unit
	local g = math.acos(-lu.Z) -- Get the arc-cosine of the negative normalized unit
	local p = o*CFrame.fromAxisAngle(x,g):Inverse() -- Get the IK plane

	-- In a self.RightRotationAngle-triangle, we have the hypotenuse and the two shorter legs.
	-- In a self.RightRotationAngle triangle, the hypotenuse is side "c," and the legs are a and b.
	-- This information will be helpful later on.

	if m < math.max(l1,l0)-math.min(l1,l0) then
		-- If c is between the lengths of a and b then return an offsetted plane so that one of the lengths reaches the goal,
		-- but the other length is folded so it looks natural
		-- This cacluation is done when a position comes before the end of the leg, and may look a bit... odd

		return p*CFrame.new(0,0,math.max(l1,l0)-math.min(l1,l0)-m),-math.pi/2,math.pi
	elseif m > l0+l1 then
		-- If c > a + b then return flat angles and an offsetted plane which reaches its target
		-- Basically, this makes the leg flat if there is nothing to place it on

		return p,math.pi/2,0
	else
		-- Otherwise, use the law of cosines
		-- This is going to be all cases where the leg actually bends

		local a1 = -math.acos((-(l1*l1)+(l0*l0)+(m*m))/(2*l0*m))
		local a2 = math.acos(((l1*l1)-(l0*l0)+(m*m))/(2*l1*m))
		return p,math.pi/2-a1,-(a2-a1)
	end
end


local function WorldCFrameToC0ObjectSpace(motor6DJoint,worldCFrame)
	local part1CF = motor6DJoint.Part1.CFrame
	local part0 = motor6DJoint.Part0
	local c1Store = motor6DJoint.C1
	local c0Store = motor6DJoint.C0
	local relativeToPart0 = part0.CFrame:inverse() * worldCFrame * c1Store

	local goalC0CFrame = relativeToPart0

	return goalC0CFrame
end

local R6IK = {}
R6IK.__index = R6IK

function R6IK.New(Character)
	local self = {}
	self.Torso = Character.Torso
	self.HumanoidRootPart = Character.HumanoidRootPart
	self.LeftArm = Character["Left Arm"]
	self.RightArm = Character["Right Arm"]
	self.LeftLeg = Character["Left Leg"]
	self.RightLeg = Character["Right Leg"]

	self.Motor6Ds = {
		["Left Shoulder"] = self.Torso["Left Shoulder"],
		["Right Shoulder"] = self.Torso["Right Shoulder"],
		["Left Hip"] = self.Torso["Left Hip"],
		["Right Hip"] = self.Torso["Right Hip"],
		["RootJoint"] = self.HumanoidRootPart["RootJoint"]
	}

	self.C0s = {
		["Left Shoulder"] = self.Motor6Ds["Left Shoulder"].C0,
		["Right Shoulder"] = self.Motor6Ds["Right Shoulder"].C0,
		["Left Hip"] = self.Motor6Ds["Left Hip"].C0,
		["Right Hip"] = self.Motor6Ds["Right Hip"].C0,
		["RootJoint"] = self.Motor6Ds["RootJoint"].C0
	}

	self.C1s = {
		["Left Shoulder"] = self.Motor6Ds["Left Shoulder"].C1,
		["Right Shoulder"] = self.Motor6Ds["Right Shoulder"].C1,
		["Left Hip"] = self.Motor6Ds["Left Hip"].C1,
		["Right Hip"] = self.Motor6Ds["Right Hip"].C1,
		["RootJoint"] = self.Motor6Ds["RootJoint"].C1
	}

	self.Part0s = {
		["Left Shoulder"] = self.Motor6Ds["Left Shoulder"].Part0,
		["Right Shoulder"] = self.Motor6Ds["Right Shoulder"].Part0,
		["Left Hip"] = self.Motor6Ds["Left Hip"].Part0,
		["Right Hip"] = self.Motor6Ds["Right Hip"].Part0,
		["RootJoint"] = self.Motor6Ds["RootJoint"].Part0
	}

	self.Part1s = {
		["Left Shoulder"] = self.Motor6Ds["Left Shoulder"].Part1,
		["Right Shoulder"] = self.Motor6Ds["Right Shoulder"].Part1,
		["Left Hip"] = self.Motor6Ds["Left Hip"].Part1,
		["Right Hip"] = self.Motor6Ds["Right Hip"].Part1,
		["RootJoint"] = self.Motor6Ds["RootJoint"].Part1
	}

	self.LeftUpperArmLength = 1
	self.LeftLowerArmLength = 1

	self.RightUpperArmLength = 1
	self.RightLowerArmLength = 1

	self.LeftUpperLegLength = .8
	self.LeftLowerLegLength = 1

	self.RightUpperLegLength = .8
	self.RightLowerLegLength = 1

	self.TorsoIK = false

	return setmetatable(self, R6IK)
end

function R6IK:ArmIK(Side : "Left" | "Right", Position)
	if Side == "Left" then
		local OriginCF = self.Torso.CFrame*self.C0s["Left Shoulder"]
		local C1Off = self.C1s["Left Shoulder"]
		local PlaneCF,ShoulderAngle,ElbowAngle, l3 = SolveArmIK(OriginCF, Position, self.LeftUpperArmLength, self.LeftLowerArmLength, C1Off, Side)

		local ShoulderAngleCFrame, ElbowAngleCFrame = CFrame.Angles(ShoulderAngle, 0, 0), CFrame.Angles(ElbowAngle, 0, 0)

		local ShoulderCF = PlaneCF * ShoulderAngleCFrame*CFrame.new(0,-self.LeftUpperArmLength * 0.5,0)
		local ElbowCF = ShoulderCF*CFrame.new(0,-self.LeftUpperArmLength * 0.5,0)* ElbowAngleCFrame * CFrame.new(0, -self.LeftLowerArmLength*0.5, 0)*CFrame.new(0,(self.LeftArm.Size.Y-self.LeftLowerArmLength)*0.5,0)
		
		task.synchronize()
		
		self.Motor6Ds["Left Shoulder"].C0 = WorldCFrameToC0ObjectSpace(self.Motor6Ds["Left Shoulder"], ElbowCF)
		
		task.desynchronize()
	elseif Side == "Right" then
		local OriginCF = self.Torso.CFrame*self.C0s["Right Shoulder"]
		local C1Off = self.C1s["Right Shoulder"]
		local PlaneCF,ShoulderAngle,ElbowAngle, l3 = SolveArmIK(OriginCF, Position, self.RightUpperArmLength, self.RightLowerArmLength, C1Off, Side)

		local ShoulderAngleCFrame, ElbowAngleCFrame = CFrame.Angles(ShoulderAngle, 0, 0), CFrame.Angles(ElbowAngle, 0, 0)

		local ShoulderCF = PlaneCF * ShoulderAngleCFrame*CFrame.new(0,-self.RightUpperArmLength * 0.5,0)
		local ElbowCF = ShoulderCF*CFrame.new(0,-self.RightUpperArmLength * 0.5,0)* ElbowAngleCFrame * CFrame.new(0, -self.RightLowerArmLength*0.5, 0)*CFrame.new(0,(self.RightArm.Size.Y-self.RightLowerArmLength)*0.5,0)


		task.synchronize()
		
		self.Motor6Ds["Right Shoulder"].C0 = WorldCFrameToC0ObjectSpace(self.Motor6Ds["Right Shoulder"], ElbowCF)
		
		task.desynchronize()
	end
end

function R6IK:LegIK(Side : "Left" | "Right", Position)
	if Side == "Left" then
		local OriginCF = self.Torso.CFrame*self.C0s["Left Hip"]
		local C1Off = self.C1s["Left Hip"]
		local PlaneCF,ShoulderAngle,ElbowAngle, l3 = SolveLegIK(OriginCF*CFrame.Angles(0, math.pi/2, 0), Position, self.LeftUpperLegLength, self.LeftLowerLegLength, C1Off)

		local HipAngleCFrame, KneeAngleCFrame = CFrame.Angles(ShoulderAngle, 0, 0), CFrame.Angles(ElbowAngle, 0, 0)

		local HipCF = PlaneCF * HipAngleCFrame*CFrame.new(0,-self.LeftUpperLegLength * 0.5,0)
		local KneeCF = HipCF*CFrame.new(0,-self.LeftUpperLegLength * 0.5,0)* KneeAngleCFrame * CFrame.new(-0.1, -self.LeftLowerLegLength*0.5, 0)*CFrame.new(0,(self.LeftLeg.Size.Y-self.LeftLowerLegLength)*0.5,0) * CFrame.Angles(0, 0.15, 0)

		return WorldCFrameToC0ObjectSpace(self.Motor6Ds["Left Hip"], KneeCF)
	elseif Side == "Right" then
		local OriginCF = self.Torso.CFrame*self.C0s["Right Hip"]
		local C1Off = self.C1s["Right Hip"]
		local PlaneCF,ShoulderAngle,ElbowAngle, l3 = SolveLegIK(OriginCF*CFrame.Angles(0, -math.pi/2, 0), Position, self.RightUpperLegLength, self.RightLowerLegLength, C1Off)

		local HipAngleCFrame, KneeAngleCFrame = CFrame.Angles(ShoulderAngle, 0, 0), CFrame.Angles(ElbowAngle, 0, 0)

		local HipCF = PlaneCF * HipAngleCFrame*CFrame.new(0,-self.RightUpperLegLength * 0.5,0)
		local KneeCF = HipCF*CFrame.new(0,-self.RightUpperLegLength * 0.5,0)* KneeAngleCFrame * CFrame.new(0.1, -self.RightLowerLegLength*0.5, 0)*CFrame.new(0,(self.RightLeg.Size.Y-self.RightLowerLegLength)*0.5,0) * CFrame.Angles(0, -0.15, 0)

		return WorldCFrameToC0ObjectSpace(self.Motor6Ds["Right Hip"], KneeCF)
	end
end

return R6IK
