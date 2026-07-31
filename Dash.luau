local Dash = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = require(replicatedStorage.src.Client.Services.PlayerService)
local states = require(replicatedStorage.src.Shared.States)
local animPlayer = require(replicatedStorage.src.Client.AnimPlayer)

local quickNet =  require(replicatedStorage.src.Shared.QuickNet)
local replicateDashVFX = quickNet:register("ReplicateDashVFX", quickNet.Data.Vector3FX8)

local soundReplication = require(replicatedStorage.src.Client.SoundReplication)
local playDashSound = soundReplication.handleSoundEvent("DashSoundEvent", {script.DashSound, script.DashSound2})
local playRollSound = soundReplication.handleSoundEvent("RollSoundEvent", script.RollSound)

-- Constants
local DASH_COOLDOWN = 0.5
local DASH_POWER = 100
local DASH_DURATION = 0.3
local DASH_UPWARD_BOOST = 0.1
local DOUBLE_PRESS_INTERVAL = 0.3

-- State
local onCooldown = false
local isDashing = false
local lastKeyPressTime = {}
local animations = nil
local hasAirDashed = false

local function loadAnimations()
	animations = {
		FrontDash = animPlayer.load(script.FrontDash),
		BackDash  = animPlayer.load(script.BackDash),
		LeftDash  = animPlayer.load(script.LeftDash),
		RightDash = animPlayer.load(script.RightDash),
		FrontRoll = animPlayer.load(script.FrontRoll),
		BackRoll  = animPlayer.load(script.BackRoll),
		LeftRoll  = animPlayer.load(script.LeftRoll),
		RightRoll = animPlayer.load(script.RightRoll)
	}
end

local function getAnimation(dashDirection, useRoll)
	if not animations then return nil end
	local camCF = workspace.CurrentCamera.CFrame
	local forward = dashDirection:Dot(camCF.LookVector)
	local right = dashDirection:Dot(camCF.RightVector)

	if useRoll then
		if forward > 0.5 then return animations.FrontRoll
		elseif forward < -0.5 then return animations.BackRoll
		elseif right > 0.5 then return animations.RightRoll
		elseif right < -0.5 then return animations.LeftRoll
		end
		return animations.FrontRoll
	end

	if forward > 0.5 then return animations.FrontDash
	elseif forward < -0.5 then return animations.BackDash
	elseif right > 0.5 then return animations.RightDash
	elseif right < -0.5 then return animations.LeftDash
	end
	return animations.BackDash
end

local function isGrounded()
	return player.Humanoid().FloorMaterial ~= Enum.Material.Air
end

local function calculateDashDirection(keyCode)
	local camCF = workspace.CurrentCamera.CFrame
	local flatLook  = Vector3.new(camCF.LookVector.X,  0, camCF.LookVector.Z).Unit
	local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit

	if keyCode == Enum.KeyCode.W then return flatLook
	elseif keyCode == Enum.KeyCode.S then return -flatLook
	elseif keyCode == Enum.KeyCode.A then return -flatRight
	elseif keyCode == Enum.KeyCode.D then return flatRight
	end
	return flatLook
end



local function performDash(keyCode)
	local dashDirection = calculateDashDirection(keyCode)
	local wasAirborne = not isGrounded()

	if isGrounded() and dashDirection.Y < 0 then
		dashDirection = Vector3.new(dashDirection.X, 0, dashDirection.Z).Unit
	end

	local finalDashDirection = Vector3.new(
		dashDirection.X,
		dashDirection.Y + DASH_UPWARD_BOOST,
		dashDirection.Z
	).Unit

	local anim = getAnimation(dashDirection)
	if anim then anim:Play() end

	local rollAnim = getAnimation(dashDirection, true)

	local camLook = workspace.CurrentCamera.CFrame.LookVector
	local faceDirection = Vector3.new(camLook.X, 0, camLook.Z).Unit

	isDashing = true
	states.SetState(player.Player(), "IsDashing", true)
	task.spawn(function()
		local startTime = time()

		while time() - startTime < DASH_DURATION do
			local hrp = player.HRP()
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + faceDirection)
			hrp.AssemblyLinearVelocity = finalDashDirection * DASH_POWER
			task.wait()
		end
		
		if not isGrounded() then -- Hover if in air
			local attachment = Instance.new("Attachment")
			attachment.Parent = player.HRP()

			local force = Instance.new("VectorForce")
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World

			local mass = player.HRP().AssemblyMass
			force.Force = Vector3.new(0, workspace.Gravity * mass * 0.75, 0)

			force.Parent = player.HRP()

			task.delay(0.25, function()
				force:Destroy()
				attachment:Destroy()
			end)
		end

		while time() - startTime < 0.5 do -- keep facing dash direction
			local hrp = player.HRP()
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + faceDirection)
			task.wait()
		end

		isDashing = false
		states.SetState(player.Player(), "IsDashing", false)
	end)

	if wasAirborne and states.GetState(player.Player(), "IsRunning") then
		local conn
		conn = player.Humanoid().StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Landed then
				conn:Disconnect()
				if rollAnim and player.Humanoid().MoveDirection.Magnitude > 0 then
					rollAnim:Play()
					playRollSound(player.Player())
				end
			end
		end)
	end

	onCooldown = true
	task.delay(DASH_COOLDOWN, function()
		onCooldown = false
	end)
	return finalDashDirection
end

function Dash.OnDashInput(keyCode)
	if onCooldown or isDashing then return end
	if not player.HRP() or player.HRP().Anchored or not player.Humanoid() then return end
	if not isGrounded() and hasAirDashed then return end

	local now = tick()
	local last = lastKeyPressTime[keyCode]

	if last and (now - last) <= DOUBLE_PRESS_INTERVAL then
		lastKeyPressTime[keyCode] = nil
		if not isGrounded() then hasAirDashed = true end
		local dashDirection = performDash(keyCode)
		playDashSound(player.Player())
		replicateDashVFX:FireServer(dashDirection)
	else
		lastKeyPressTime[keyCode] = now
	end
end

local function connectLandingReset()
	player.Humanoid().StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running then
			hasAirDashed = false
		end
	end)
end

function Dash.Init()
	if player.Character() then
		loadAnimations()
		connectLandingReset()
	end

	player.CharacterAdded():Connect(function()
		onCooldown = false
		isDashing = false
		hasAirDashed = false
		lastKeyPressTime = {}
		loadAnimations()
		connectLandingReset()
	end)
end

return Dash
