-- Parallel, run this script under an actor. 

local LegController = require(game.ReplicatedStorage.Modules:WaitForChild("LegController"))

local function Add(Plr: Player)
	local function Load(Char: Model)
		local New = LegController.new(Char, {
			ikEnabled = true,
			ikExclude = {},
			maxIkVelocity = 2.5,

			onStates = {
				Enum.HumanoidStateType.None,
				Enum.HumanoidStateType.Freefall,
				Enum.HumanoidStateType.Running,
			},

			activationVelocity = 2.5,
			maxRootAngle = 30,
			maxAngle = 42.5,
			interploationSpeed = {
				highVelocityPoint = 2.5,
				Speed = 0.1,
			}
		})
		
		Plr.Character.Destroying:Once(function()
			New:Destroy()
		end)
	end
	
	if Plr.Character then
		Load(Plr.Character)
	end
	
	local Connection = Plr.CharacterAdded:Connect(Load)
	Plr.Destroying:Once(function()
		if Connection then
			Connection:Disconnect()
		end
	end)
end

for _, Plr in pairs(game.Players:GetPlayers()) do
	Add(Plr)
end

game.Players.PlayerAdded:Connect(Add)
