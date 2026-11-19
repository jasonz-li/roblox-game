--!nonstrict
-- First-person camera: FOV blending (ADS / sprint) and visual recoil kick.
-- First-person lock itself comes from StarterPlayer.CameraMode (default.project.json).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}
CameraController.AllowScripted = false -- set true for future cutscenes / death cams

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

-- Always hide our own body/accessories in first person (the viewmodel is the only
-- thing we should see). Roblox's default fade can be interrupted by camera changes,
-- and big head accessories then fill the whole screen.
local ownParts = {}
local function trackCharacter(char: Model)
	table.clear(ownParts)
	local function add(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(ownParts, d)
		end
	end
	for _, d in char:GetDescendants() do
		add(d)
	end
	char.DescendantAdded:Connect(add)
end

function CameraController.Start()
	local player = Players.LocalPlayer
	if player.Character then
		trackCharacter(player.Character)
	end
	player.CharacterAdded:Connect(trackCharacter)
	RunService:BindToRenderStep("HideOwnBody", Enum.RenderPriority.Camera.Value + 3, function()
		for _, p in ownParts do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = 1
			else
				p.Transparency = 1
			end
		end
	end)

	-- Runs right after the default camera script has positioned the camera.
	-- IMPORTANT: Roblox's camera builds each frame from the previous camera CFrame, so any
	-- rotation we add carries over. We therefore apply only the CHANGE in our offset each
	-- frame (desired - applied). The visible offset then equals `desired`, and when the
	-- kick decays to 0 the aim returns exactly to where the player was pointing.
	-- (Applying the full offset every frame made it accumulate: shooting alone could
	-- spin the view 180°.)
	local appliedPitch, appliedYaw = 0, 0
	local baseFov = BASE_FOV
	local notCustomSince = nil
	RunService:BindToRenderStep("FpsCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Custom then
			appliedPitch, appliedYaw = 0, 0
			-- Self-heal: the game never uses a scripted camera (no cutscenes yet). If something
			-- (e.g. a Studio screenshot tool) leaves it Scriptable, the mouse stops turning the
			-- view. Restore after 0.5s unless a feature opts in via CameraController.AllowScripted.
			if not CameraController.AllowScripted then
				notCustomSince = notCustomSince or os.clock()
				if os.clock() - notCustomSince > 0.5 then
					cam.CameraType = Enum.CameraType.Custom
					local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if hum then
						cam.CameraSubject = hum
					end
					notCustomSince = nil
				end
			end
			return
		end
		notCustomSince = nil
		local targetFov = adsFov or (sprinting and BASE_FOV + SPRINT_FOV_BONUS or BASE_FOV)
		baseFov += (targetFov - baseFov) * math.min(1, dt * 14)
		fovPunch -= fovPunch * math.min(1, dt * 18)
		cam.FieldOfView = baseFov + fovPunch

		-- decay recoil + shake, then build this frame's desired offset
		local decay = math.min(1, dt * 12)
		recoilPitch -= recoilPitch * decay
		recoilYaw -= recoilYaw * decay
		shake -= shake * math.min(1, dt * 20)
		local shakeP = shake > 0.01 and (math.random() - 0.5) * shake or 0
		local shakeY = shake > 0.01 and (math.random() - 0.5) * shake or 0
		local desiredPitch = recoilPitch + shakeP
		local desiredYaw = recoilYaw + shakeY

		local dP, dY = desiredPitch - appliedPitch, desiredYaw - appliedYaw
		if math.abs(dP) > 1e-4 or math.abs(dY) > 1e-4 then
			cam.CFrame *= CFrame.Angles(math.rad(dP), math.rad(dY), 0)
		end
		appliedPitch, appliedYaw = desiredPitch, desiredYaw
	end)
end

return CameraController
