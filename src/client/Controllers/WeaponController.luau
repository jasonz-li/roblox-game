--!nonstrict
-- Client weapon handling: input, predicted firing/ammo, PLACEHOLDER viewmodel, feedback.
-- The server (WeaponService) decides what actually hits and how much ammo you really have.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local HudController = require(script.Parent.HudController)
local SoundController = require(script.Parent.SoundController)

local WeaponController = {}

local player = Players.LocalPlayer
local fireRemote: RemoteEvent
local reloadRemote: RemoteEvent

local stats = WeaponConfig.Get(WeaponConfig.Default)
local mag, reserve = stats.MagSize, stats.ReserveAmmo
local reloading, reloadStartedAt = false, 0
local triggerHeld, adsHeld, sprintHeld = false, false, false
local nextShotAt, lastShotAt = 0, 0
local adsAlpha, sprintAlpha = 0, 0
local kickBack, kickPitch = 0, 0
local swayX, swayY = 0, 0
local bobTime = 0

----------------------------------------------------------------------
-- PLACEHOLDER viewmodel (block rifle + hands). Replace with a real rig in M10.
----------------------------------------------------------------------

local viewmodel: Model
local vmParts = {} -- { {part, offset} }
local muzzle: BasePart
local flash: BasePart
local flashLight: PointLight

local HIP_OFFSET = CFrame.new(0.95, -0.95, -2.6)
local ADS_OFFSET = CFrame.new(0, -0.36, -2.0)

local function addVmPart(name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = viewmodel
	table.insert(vmParts, { p, offset })
	return p
end

local function buildViewmodel()
	viewmodel = Instance.new("Model")
	viewmodel.Name = "PLACEHOLDER_Viewmodel"
	local metal = Color3.fromRGB(38, 40, 48)
	local skin = Color3.fromRGB(240, 200, 170)
	addVmPart("Body", Vector3.new(0.32, 0.42, 1.8), CFrame.new(), metal, Enum.Material.Metal)
	addVmPart("Barrel", Vector3.new(0.14, 0.14, 1.0), CFrame.new(0, 0.08, -1.35), metal, Enum.Material.Metal)
	muzzle = addVmPart("Muzzle", Vector3.new(0.2, 0.2, 0.16), CFrame.new(0, 0.08, -1.9), Color3.fromRGB(20, 20, 24))
	addVmPart("Mag", Vector3.new(0.24, 0.65, 0.35), CFrame.new(0, -0.48, -0.3) * CFrame.Angles(math.rad(-12), 0, 0), metal)
	addVmPart("Stock", Vector3.new(0.26, 0.36, 0.8), CFrame.new(0, -0.05, 1.2), Color3.fromRGB(60, 55, 70))
	addVmPart("Sight", Vector3.new(0.12, 0.1, 0.3), CFrame.new(0, 0.28, -0.2), Color3.fromRGB(255, 80, 170), Enum.Material.Neon)
	addVmPart("Accent", Vector3.new(0.34, 0.05, 1.1), CFrame.new(0, 0.13, -0.15), Color3.fromRGB(80, 220, 255), Enum.Material.Neon)
	addVmPart("RightHand", Vector3.new(0.34, 0.34, 0.6), CFrame.new(0.06, -0.32, 0.45), skin)
	addVmPart("LeftHand", Vector3.new(0.34, 0.34, 0.5), CFrame.new(-0.02, -0.18, -0.85), skin)
	flash = addVmPart("Flash", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.08, -2.15), Color3.fromRGB(255, 210, 120), Enum.Material.Neon)
	flash.Shape = Enum.PartType.Ball
	flash.Transparency = 1
	flashLight = Instance.new("PointLight")
	flashLight.Color = Color3.fromRGB(255, 190, 110)
	flashLight.Range = 12
	flashLight.Brightness = 0
	flashLight.Parent = flash
	viewmodel.Parent = workspace.CurrentCamera
end

local function setViewmodelVisible(visible: boolean)
	for _, entry in vmParts do
		local part = entry[1]
		if part ~= flash then
			part.LocalTransparencyModifier = visible and 0 or 1
		end
	end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getHumanoid()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum, char
	end
	return nil, nil
end

local function isMoving(hum): boolean
	return hum.MoveDirection.Magnitude > 0.1
end

local function currentSpread(hum): number
	if adsAlpha > 0.6 then
		return stats.AdsSpread
	end
	return stats.HipSpread * (isMoving(hum) and 1.7 or 1)
end

local function spreadDirection(look: Vector3, degrees: number): Vector3
	local r = math.rad(degrees) * math.sqrt(math.random())
	local theta = math.random() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(0, 0, theta) * CFrame.Angles(r, 0, 0)).LookVector
end

local function pushHud()
	HudController.SetAmmo(mag, reserve, reloading, stats.DisplayName, stats.MagSize)
end

local function syncFromServer()
	mag = player:GetAttribute("Ammo") or mag
	reserve = player:GetAttribute("Reserve") or reserve
	local id = player:GetAttribute("WeaponId")
	if id and WeaponConfig.Get(id) then
		stats = WeaponConfig.Get(id)
	end
	pushHud()
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

local function tryReload()
	if reloading or mag >= stats.MagSize or reserve <= 0 then
		return
	end
	if not getHumanoid() then
		return
	end
	reloading = true
	reloadStartedAt = os.clock()
	reloadRemote:FireServer()
	SoundController.Play("Reload")
	pushHud()
end

local function fire(hum, char)
	if reloading then
		return
	end
	if mag <= 0 then
		if reserve <= 0 and os.clock() >= nextShotAt then
			nextShotAt = os.clock() + 0.3
			SoundController.Play("DryFire")
		end
		tryReload()
		return
	end

	local now = os.clock()
	nextShotAt = now + 60 / stats.RPM
	lastShotAt = now
	mag -= 1

	local cam = workspace.CurrentCamera
	local origin = cam.CFrame.Position
	local direction = spreadDirection(cam.CFrame.LookVector, currentSpread(hum))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, viewmodel, EffectsController.GetFolder() }
	local result = workspace:Raycast(origin, direction * stats.Range, params)

	local claimed = nil
	local endPos = origin + direction * stats.Range
	local enemies = workspace:FindFirstChild("Enemies")
	if result then
		endPos = result.Position
		if enemies and result.Instance:IsDescendantOf(enemies) then
			claimed = result.Instance
		end
	end

	fireRemote:FireServer(origin, direction, claimed)
	SoundController.Play("RifleShot")

	-- Feedback (purely cosmetic)
	EffectsController.Tracer(muzzle.Position, endPos)
	if result then
		EffectsController.Impact(result.Position, result.Normal, claimed ~= nil)
	end
	flash.Transparency = 0.1
	flash.Size = Vector3.one * (0.4 + math.random() * 0.35)
	flashLight.Brightness = 4
	kickBack = math.min(kickBack + 0.14, 0.35)
	kickPitch = math.min(kickPitch + 2.5, 8)
	local adsScale = adsAlpha > 0.6 and 0.55 or 1
	CameraController.Kick(stats.RecoilKick * adsScale, (math.random() - 0.5) * 2 * stats.RecoilSide * adsScale)
	HudController.PulseCrosshair()
	pushHud()

	if mag <= 0 then
		task.delay(0.15, tryReload)
	end
end

----------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------

local function update(dt)
	local hum, char = getHumanoid()
	if not hum then
		setViewmodelVisible(false)
		triggerHeld = false
		return
	end
	setViewmodelVisible(true)

	-- Reload fallback: if the server never confirmed, resync after a grace period.
	if reloading and os.clock() - reloadStartedAt > stats.ReloadTime + 1 then
		reloading = false
		syncFromServer()
	end

	-- Sprint (cancelled by ADS, firing, reloading)
	local wantsSprint = sprintHeld and isMoving(hum) and not adsHeld and not triggerHeld and not reloading
	hum.WalkSpeed = wantsSprint and GameConfig.Player.SprintSpeed or GameConfig.Player.WalkSpeed
	CameraController.SetSprinting(wantsSprint)

	-- ADS
	local wantsAds = adsHeld and not reloading
	CameraController.SetAds(wantsAds and stats.AdsFov or nil)
	HudController.SetAds(wantsAds)
	adsAlpha += ((wantsAds and 1 or 0) - adsAlpha) * math.min(1, dt * 16)
	sprintAlpha += ((wantsSprint and 1 or 0) - sprintAlpha) * math.min(1, dt * 10)

	-- Firing
	if triggerHeld and os.clock() >= nextShotAt then
		fire(hum, char)
		if stats.FireMode == "Semi" then
			triggerHeld = false
		end
	end

	HudController.SetCrosshairSpread(currentSpread(hum))

	-- Viewmodel pose
	local delta = UserInputService:GetMouseDelta()
	swayX += (math.clamp(-delta.X * 0.004, -0.12, 0.12) - swayX) * math.min(1, dt * 10)
	swayY += (math.clamp(-delta.Y * 0.004, -0.12, 0.12) - swayY) * math.min(1, dt * 10)
	local moving = isMoving(hum) and 1 or 0
	bobTime += dt * (wantsSprint and 14 or 9) * moving
	local bobAmount = (1 - adsAlpha * 0.85) * moving
	local bob = CFrame.new(math.sin(bobTime) * 0.04 * bobAmount, math.abs(math.cos(bobTime)) * 0.04 * bobAmount, 0)

	kickBack -= kickBack * math.min(1, dt * 18)
	kickPitch -= kickPitch * math.min(1, dt * 14)
	flash.Transparency = math.min(1, flash.Transparency + dt * 25)
	flashLight.Brightness = math.max(0, flashLight.Brightness - dt * 60)

	local reloadPose = CFrame.new()
	if reloading then
		local t = math.clamp((os.clock() - reloadStartedAt) / stats.ReloadTime, 0, 1)
		local s = math.sin(t * math.pi)
		reloadPose = CFrame.new(0, -0.35 * s, 0) * CFrame.Angles(math.rad(-25) * s, 0, math.rad(35) * s)
	end

	local base = HIP_OFFSET:Lerp(ADS_OFFSET, adsAlpha)
	local sprintPose = CFrame.new(-0.2 * sprintAlpha, -0.15 * sprintAlpha, 0) * CFrame.Angles(math.rad(-15) * sprintAlpha, math.rad(40) * sprintAlpha, math.rad(10) * sprintAlpha)
	local sway = CFrame.Angles(swayY * (1 - adsAlpha * 0.7), swayX * (1 - adsAlpha * 0.7), swayX * 0.5)
	local kick = CFrame.new(0, 0, kickBack) * CFrame.Angles(math.rad(kickPitch), 0, 0)

	local rootCf = workspace.CurrentCamera.CFrame * base * sprintPose * bob * sway * reloadPose * kick
	for _, entry in vmParts do
		entry[1].CFrame = rootCf * entry[2]
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function WeaponController.Init()
	fireRemote = Remotes.Get("Fire")
	reloadRemote = Remotes.Get("Reload")
	buildViewmodel()
end

function WeaponController.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			adsHeld = true
		elseif input.KeyCode == Enum.KeyCode.R then
			tryReload()
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			adsHeld = false
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
		end
	end)

	-- Server ammo is authoritative; adopt it whenever we're not mid-burst.
	player:GetAttributeChangedSignal("Ammo"):Connect(function()
		if not reloading and os.clock() - lastShotAt > 0.4 then
			syncFromServer()
		end
	end)
	player:GetAttributeChangedSignal("Reserve"):Connect(function()
		reserve = player:GetAttribute("Reserve") or reserve
		pushHud()
	end)
	player:GetAttributeChangedSignal("Reloading"):Connect(function()
		if player:GetAttribute("Reloading") == false and reloading then
			reloading = false
			syncFromServer()
		end
	end)
	player.CharacterAdded:Connect(function()
		reloading = false
		task.defer(syncFromServer)
	end)

	Remotes.Get("HitConfirm").OnClientEvent:Connect(function(isHeadshot, isKill)
		HudController.ShowHitmarker(isHeadshot == true, isKill == true)
		SoundController.Play(isKill and "KillConfirm" or "Hitmarker", isHeadshot and 1.3 or 1)
	end)

	-- After the camera (and CameraController's recoil at Camera+1), so the gun never lags a frame.
	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 2, update)
	syncFromServer()
end

return WeaponController
