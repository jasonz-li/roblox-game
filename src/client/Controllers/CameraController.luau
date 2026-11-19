--!nonstrict
-- First-person camera: FOV blending (ADS / sprint) and visual recoil kick.
-- First-person lock itself comes from StarterPlayer.CameraMode (default.project.json).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}

local BASE_FOV = 78
local SPRINT_FOV_BONUS = 6

local adsFov: number? = nil
local sprinting = false
local recoilPitch, recoilYaw = 0, 0 -- current offset (degrees)

function CameraController.SetAds(fov: number?)
	adsFov = fov
end

function CameraController.SetSprinting(value: boolean)
	sprinting = value
end

-- Short FOV punch for kills / knife hits.
local fovPunch = 0
function CameraController.Punch(amount: number)
	fovPunch = math.max(fovPunch, amount)
end

-- Small random screen shake (decays fast).
local shake = 0
function CameraController.Shake(amount: number)
	shake = math.max(shake, amount)
end

function CameraController.Kick(pitch: number, yaw: number)
	recoilPitch = math.min(recoilPitch + pitch, 8)
	recoilYaw += yaw
end

function CameraController.Init()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	UserInputService.MouseIconEnabled = false
end

function CameraController.Start()
	-- Runs right after the default camera script has positioned the camera,
	-- so the kick is layered on top and decays back to the player's aim.
	RunService:BindToRenderStep("FpsCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		local targetFov = adsFov or (sprinting and BASE_FOV + SPRINT_FOV_BONUS or BASE_FOV)
		cam.FieldOfView += (targetFov - cam.FieldOfView) * math.min(1, dt * 14)
		if fovPunch > 0.01 then
			cam.FieldOfView += fovPunch
			fovPunch -= fovPunch * math.min(1, dt * 18)
		end
		if shake > 0.01 then
			cam.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * shake), math.rad((math.random() - 0.5) * shake), 0)
			shake -= shake * math.min(1, dt * 20)
		end

		if math.abs(recoilPitch) > 0.001 or math.abs(recoilYaw) > 0.001 then
			cam.CFrame *= CFrame.Angles(math.rad(recoilPitch), math.rad(recoilYaw), 0)
			local decay = math.min(1, dt * 12)
			recoilPitch -= recoilPitch * decay
			recoilYaw -= recoilYaw * decay
		end
	end)
end

return CameraController
