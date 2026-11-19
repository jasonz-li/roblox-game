--!nonstrict
-- Client weapon handling: input, predicted firing/ammo, weapon switching,
-- PLACEHOLDER block viewmodels (built from WeaponConfig View specs), feedback.
-- The server (WeaponService) decides what actually hits and how much ammo you really have.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)
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
local switchRemote: RemoteEvent

local weaponId, upgraded = WeaponConfig.Default, false
local stats = WeaponConfig.Get(weaponId)
local mag, reserve = stats.MagSize, stats.ReserveAmmo
local reloading, reloadStartedAt, reloadDuration = false, 0, 1
local switchUntil, switchStartedAt = 0, 0
local triggerHeld, adsHeld, sprintHeld = false, false, false
local nextShotAt, lastShotAt = 0, 0
local adsAlpha, sprintAlpha = 0, 0
local kickBack, kickPitch = 0, 0
local swayX, swayY = 0, 0
local bobTime = 0
local meleeRemote: RemoteEvent

-- Stamina (client-side: movement is client-authoritative in Roblox anyway)
local stamina = GameConfig.Stamina.Max
local exhausted = false
local lastSprintAt = 0

-- Knife
local KNIFE_TIME = 0.32
local meleeStartedAt, nextMeleeAt = -10, 0
local knifeParts = {} -- { {part, offset} }

----------------------------------------------------------------------
-- PLACEHOLDER viewmodel (block gun + hands), rebuilt per weapon.
----------------------------------------------------------------------

local viewmodel: Model
local vmParts = {} -- { {part, offset} }
local muzzle: BasePart
local flash: BasePart
local flashLight: PointLight
local adsOffset = CFrame.new(0, -0.36, -2.0)

local HIP_OFFSET = CFrame.new(0.95, -0.95, -2.6)

local function addVmPart(name, size, offset, color, material, shape)
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
	if shape then
		p.Shape = shape
	end
	p.Parent = viewmodel
	table.insert(vmParts, { p, offset })
	return p
end

local function buildViewmodel()
	if viewmodel then
		viewmodel:Destroy()
	end
	table.clear(vmParts)
	viewmodel = Instance.new("Model")
	viewmodel.Name = "PLACEHOLDER_Viewmodel"

	local v = stats.View
	local L, B = v.Length, v.Barrel
	local skin = Color3.fromRGB(240, 200, 170)
	addVmPart("Body", Vector3.new(0.32, 0.42, L), CFrame.new(), v.Color, Enum.Material.Metal)
	addVmPart("Barrel", Vector3.new(0.14, 0.14, B), CFrame.new(0, 0.08, -(L / 2 + B / 2)), v.Color, Enum.Material.Metal)
	muzzle = addVmPart("Muzzle", Vector3.new(0.2, 0.2, 0.16), CFrame.new(0, 0.08, -(L / 2 + B + 0.08)), Color3.fromRGB(20, 20, 24))
	addVmPart("Mag", Vector3.new(0.24, v.MagHeight, 0.35), CFrame.new(0, -0.21 - v.MagHeight / 2, -L * 0.15) * CFrame.Angles(math.rad(-10), 0, 0), v.Color)
	if v.Stock then
		addVmPart("Stock", Vector3.new(0.26, 0.36, 0.7), CFrame.new(0, -0.05, L / 2 + 0.35), v.Color:Lerp(Color3.new(1, 1, 1), 0.1))
	end
	if v.Scope then
		addVmPart("Scope", Vector3.new(0.9, 0.22, 0.22), CFrame.new(0, 0.38, -0.1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(20, 20, 26), Enum.Material.Metal, Enum.PartType.Cylinder)
		addVmPart("ScopeGlass", Vector3.new(0.02, 0.2, 0.2), CFrame.new(0, 0.38, -0.56) * CFrame.Angles(0, math.rad(90), 0), v.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	else
		addVmPart("Sight", Vector3.new(0.12, 0.1, 0.3), CFrame.new(0, 0.28, -L * 0.1), v.Accent, Enum.Material.Neon)
	end
	addVmPart("Accent", Vector3.new(0.34, 0.05, L * 0.6), CFrame.new(0, 0.13, -L * 0.08), v.Accent, Enum.Material.Neon)
	addVmPart("RightHand", Vector3.new(0.34, 0.34, 0.6), CFrame.new(0.06, -0.32, L * 0.25), skin)
	addVmPart("LeftHand", Vector3.new(0.34, 0.34, 0.5), CFrame.new(-0.02, -0.18, -L * 0.45), skin)
	flash = addVmPart("Flash", Vector3.one * 0.5, CFrame.new(0, 0.08, -(L / 2 + B + 0.33)), Color3.fromRGB(255, 210, 120), Enum.Material.Neon, Enum.PartType.Ball)
	flash.Transparency = 1
	flashLight = Instance.new("PointLight")
	flashLight.Color = stats.TracerColor or Color3.fromRGB(255, 190, 110)
	flashLight.Range = 12
	flashLight.Brightness = 0
	flashLight.Parent = flash

	adsOffset = CFrame.new(0, -(v.AdsHeight or 0.33), -2.0)
	viewmodel.Parent = workspace.CurrentCamera
end

-- PLACEHOLDER knife: blade + handle, only visible during a melee swing.
local function buildKnife()
	local model = Instance.new("Model")
	model.Name = "PLACEHOLDER_Knife"
	local function add(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.LocalTransparencyModifier = 1
		p.Parent = model
		table.insert(knifeParts, { p, offset })
	end
	add("Handle", Vector3.new(0.18, 0.22, 0.6), CFrame.new(0, 0, 0.3), Color3.fromRGB(40, 30, 30), Enum.Material.SmoothPlastic)
	add("Guard", Vector3.new(0.4, 0.08, 0.08), CFrame.new(0, 0, 0), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
	add("Blade", Vector3.new(0.06, 0.22, 1.1), CFrame.new(0, 0, -0.55), Color3.fromRGB(220, 225, 235), Enum.Material.Metal)
	add("Edge", Vector3.new(0.07, 0.04, 1.1), CFrame.new(0, -0.11, -0.55), Color3.fromRGB(80, 220, 255), Enum.Material.Neon)
	add("Hand", Vector3.new(0.34, 0.34, 0.5), CFrame.new(0, 0, 0.35), Color3.fromRGB(240, 200, 170), Enum.Material.SmoothPlastic)
	model.Parent = workspace.CurrentCamera
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
	if degrees <= 0 then
		return look
	end
	local r = math.rad(degrees) * math.sqrt(math.random())
	local theta = math.random() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(0, 0, theta) * CFrame.Angles(r, 0, 0)).LookVector
end

local function pushHud()
	HudController.SetAmmo(mag, reserve, reloading, stats.DisplayName, stats.MagSize, upgraded)
end

-- Adopt the server's view of the current weapon. Rebuilds the viewmodel if the weapon changed.
local function syncFromServer()
	local id = player:GetAttribute("WeaponId") or weaponId
	local up = player:GetAttribute("WeaponUpgraded") == true
	if id ~= weaponId or up ~= upgraded then
		weaponId, upgraded = id, up
		stats = WeaponConfig.Get(id, up) or stats
		reloading = false
		switchStartedAt = os.clock()
		switchUntil = switchStartedAt + WeaponConfig.SwitchTime
		buildViewmodel()
		SoundController.Play("WeaponSwitch")
	end
	mag = player:GetAttribute("Ammo") or mag
	reserve = player:GetAttribute("Reserve") or reserve
	pushHud()
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

local function tryReload()
	if reloading or mag >= stats.MagSize or reserve <= 0 or os.clock() < switchUntil then
		return
	end
	if not getHumanoid() then
		return
	end
	reloading = true
	reloadStartedAt = os.clock()
	reloadDuration = stats.ReloadTime * PerkConfig.ReloadMultiplier(player)
	reloadRemote:FireServer()
	SoundController.Play("Reload")
	pushHud()
end

local function trySwitch(slot: number)
	if (player:GetAttribute("Slot" .. slot) or "") == "" or player:GetAttribute("CurrentSlot") == slot then
		return
	end
	if not getHumanoid() then
		return
	end
	triggerHeld = triggerHeld and stats.FireMode == "Auto"
	switchRemote:FireServer(slot)
end

local function fire(hum, char)
	if reloading or os.clock() < switchUntil then
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
	nextShotAt = now + 60 / (stats.RPM * PerkConfig.RpmMultiplier(player))
	lastShotAt = now
	mag -= 1

	local cam = workspace.CurrentCamera
	local origin = cam.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, viewmodel, EffectsController.GetFolder() }
	local enemies = workspace:FindFirstChild("Enemies")

	local directions, claims = {}, {}
	local spread = currentSpread(hum)
	for i = 1, stats.Pellets do
		local direction = spreadDirection(cam.CFrame.LookVector, spread)
		local result = workspace:Raycast(origin, direction * stats.Range, params)
		local endPos = result and result.Position or (origin + direction * stats.Range)
		local claimed = false
		if result and enemies and result.Instance:IsDescendantOf(enemies) then
			claimed = result.Instance
		end
		directions[i] = direction
		claims[i] = claimed
		-- Feedback (purely cosmetic)
		EffectsController.Tracer(muzzle.Position, endPos, stats.TracerColor)
		if result then
			EffectsController.Impact(result.Position, result.Normal, claimed ~= false)
		end
	end
	fireRemote:FireServer(origin, directions, claims)

	SoundController.Play(stats.ShotSound, 1, stats.ShotPitch)
	if SoundController.ThumpEnabled then
		SoundController.Play("ShotThump", stats.Pellets > 1 and 1.6 or 1, 0.6 * stats.ShotPitch)
	end
	CameraController.Shake(0.25 + stats.RecoilKick * 0.15)
	flash.Transparency = 0.1
	flash.Size = Vector3.one * (0.4 + math.random() * 0.35) * (stats.Pellets > 1 and 1.6 or 1)
	flashLight.Brightness = 4
	kickBack = math.min(kickBack + 0.1 + stats.RecoilKick * 0.06, 0.45)
	kickPitch = math.min(kickPitch + 2 + stats.RecoilKick, 12)
	local adsScale = adsAlpha > 0.6 and 0.55 or 1
	CameraController.Kick(stats.RecoilKick * adsScale, (math.random() - 0.5) * 2 * stats.RecoilSide * adsScale)
	HudController.PulseCrosshair()
	pushHud()

	if mag <= 0 then
		task.delay(0.15, tryReload)
	end
end

-- Knife: lunge toward a close enemy, swing, let the server decide the hit.
local function melee()
	local now = os.clock()
	if now < nextMeleeAt then
		return
	end
	local hum, char = getHumanoid()
	if not hum then
		return
	end
	local cfg = GameConfig.Melee
	nextMeleeAt = now + cfg.Cooldown
	meleeStartedAt = now
	nextShotAt = math.max(nextShotAt, now + KNIFE_TIME + 0.1)
	if reloading then
		reloading = false -- server cancels the reload too
	end
	triggerHeld = false

	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local root = char.HumanoidRootPart
	-- Find the closest enemy roughly in front for lunge + claim
	local best, bestDist = nil, cfg.LungeRange
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		for _, m in enemies:GetChildren() do
			local r = m.PrimaryPart
			if r and r.CanQuery then
				local to = r.Position - cam.CFrame.Position
				local d = to.Magnitude
				if d < bestDist and (d < 2.5 or to.Unit:Dot(look) > 0.4) then
					best, bestDist = r, d
				end
			end
		end
	end
	if best and bestDist > cfg.Range * 0.6 then
		local flat = Vector3.new(best.Position.X - root.Position.X, 0, best.Position.Z - root.Position.Z)
		if flat.Magnitude > 0.1 then
			root.AssemblyLinearVelocity = flat.Unit * cfg.LungeSpeed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end
	end
	SoundController.Play("KnifeSwing")
	CameraController.Kick(-1.5, 2.5)
	-- Send slightly after the lunge so the server sees us closer
	task.delay(0.08, function()
		meleeRemote:FireServer(look, best)
	end)
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
	if reloading and os.clock() - reloadStartedAt > reloadDuration + 1 then
		reloading = false
		syncFromServer()
	end

	-- Movement (sprint cancelled by ADS, firing, reloading). SwiftStep perk scales both speeds.
	-- Sprint costs stamina; once empty you must recover to MinToRestart before sprinting again.
	local sc = GameConfig.Stamina
	local speedMult = PerkConfig.SpeedMultiplier(player)
	local wantsSprint = sprintHeld and isMoving(hum) and not adsHeld and not triggerHeld and not reloading and not exhausted and stamina > 0
	if wantsSprint then
		local drain = sc.DrainPerSecond * (player:GetAttribute("Perk_SwiftStep") and sc.SwiftStepDrainMult or 1)
		stamina = math.max(0, stamina - drain * dt)
		lastSprintAt = os.clock()
		if stamina <= 0 then
			exhausted = true
		end
	elseif os.clock() - lastSprintAt > sc.RegenDelay then
		stamina = math.min(sc.Max, stamina + sc.RegenPerSecond * dt)
	end
	if exhausted and stamina >= sc.MinToRestart then
		exhausted = false
	end
	HudController.SetStamina(stamina / sc.Max, exhausted)
	hum.WalkSpeed = (wantsSprint and GameConfig.Player.SprintSpeed or GameConfig.Player.WalkSpeed) * speedMult
	CameraController.SetSprinting(wantsSprint)

	-- ADS
	local wantsAds = adsHeld and not reloading and os.clock() >= switchUntil
	CameraController.SetAds(wantsAds and stats.AdsFov or nil)
	HudController.SetAds(wantsAds, stats.View.Scope == true)
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
		local t = math.clamp((os.clock() - reloadStartedAt) / reloadDuration, 0, 1)
		local s = math.sin(t * math.pi)
		reloadPose = CFrame.new(0, -0.35 * s, 0) * CFrame.Angles(math.rad(-25) * s, 0, math.rad(35) * s)
	end
	local switchPose = CFrame.new()
	if os.clock() < switchUntil then
		local t = 1 - math.clamp((os.clock() - switchStartedAt) / WeaponConfig.SwitchTime, 0, 1)
		switchPose = CFrame.new(0, -0.8 * t, 0.3 * t) * CFrame.Angles(math.rad(-40) * t, 0, 0)
	end

	local base = HIP_OFFSET:Lerp(adsOffset, adsAlpha)
	local sprintPose = CFrame.new(-0.2 * sprintAlpha, -0.15 * sprintAlpha, 0) * CFrame.Angles(math.rad(-15) * sprintAlpha, math.rad(40) * sprintAlpha, math.rad(10) * sprintAlpha)
	local sway = CFrame.Angles(swayY * (1 - adsAlpha * 0.7), swayX * (1 - adsAlpha * 0.7), swayX * 0.5)
	local kick = CFrame.new(0, 0, kickBack) * CFrame.Angles(math.rad(kickPitch), 0, 0)

	-- Knife swing: gun dips out of the way while the knife slashes right-to-left.
	local meleeT = (os.clock() - meleeStartedAt) / KNIFE_TIME
	local meleePose = CFrame.new()
	if meleeT < 1 then
		local s = math.sin(meleeT * math.pi)
		meleePose = CFrame.new(0.3 * s, -0.9 * s, 0.4 * s) * CFrame.Angles(math.rad(-30) * s, 0, math.rad(-20) * s)
		local camCf = workspace.CurrentCamera.CFrame
		local x = 1.1 - 2.0 * meleeT
		local knifeCf = camCf * CFrame.new(x, -0.45 + 0.25 * s, -1.7) * CFrame.Angles(math.rad(-10), math.rad(70 - 140 * meleeT), math.rad(-80))
		for _, entry in knifeParts do
			entry[1].CFrame = knifeCf * entry[2]
			entry[1].LocalTransparencyModifier = 0
		end
	else
		for _, entry in knifeParts do
			entry[1].LocalTransparencyModifier = 1
		end
	end

	local rootCf = workspace.CurrentCamera.CFrame * base * sprintPose * bob * sway * switchPose * reloadPose * meleePose * kick
	-- Hide the gun while looking through a scope.
	local scoped = stats.View.Scope and adsAlpha > 0.85
	for _, entry in vmParts do
		entry[1].CFrame = rootCf * entry[2]
		if scoped and entry[1] ~= flash then
			entry[1].LocalTransparencyModifier = 1
		end
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function WeaponController.Init()
	fireRemote = Remotes.Get("Fire")
	reloadRemote = Remotes.Get("Reload")
	switchRemote = Remotes.Get("SwitchWeapon")
	meleeRemote = Remotes.Get("Melee")
	buildViewmodel()
	buildKnife()
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
		elseif input.KeyCode == Enum.KeyCode.One then
			trySwitch(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			trySwitch(2)
		elseif input.KeyCode == Enum.KeyCode.V then
			melee()
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
	UserInputService.InputChanged:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			local currentSlot = player:GetAttribute("CurrentSlot") or 1
			trySwitch(currentSlot == 1 and 2 or 1)
		end
	end)

	-- Server is authoritative; adopt its state whenever we're not mid-burst.
	player:GetAttributeChangedSignal("Ammo"):Connect(function()
		-- Always adopt right after a switch/purchase (attributes may arrive after WeaponId).
		if os.clock() < switchUntil + 0.5 or (not reloading and os.clock() - lastShotAt > 0.4) then
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
	player:GetAttributeChangedSignal("WeaponId"):Connect(syncFromServer)
	player:GetAttributeChangedSignal("WeaponUpgraded"):Connect(syncFromServer)
	player.CharacterAdded:Connect(function()
		reloading = false
		task.defer(syncFromServer)
	end)

	Remotes.Get("HitConfirm").OnClientEvent:Connect(function(isHeadshot, isKill, _total, hits, isMelee)
		isHeadshot, isKill = isHeadshot == true, isKill == true
		HudController.ShowHitmarker(isHeadshot, isKill)
		-- Layered hit sound: tick + flesh, ding for headshots, ping + punch for kills
		SoundController.Play("Hitmarker", 1, isHeadshot and 1.25 or 1.6)
		SoundController.Play(isMelee and "KnifeHit" or "HitFlesh")
		if isHeadshot then
			SoundController.Play("HeadshotDing", 1, 1.8)
		end
		if isKill then
			SoundController.Play("KillConfirm", 1, 1.1)
			CameraController.Punch(isHeadshot and 2.5 or 1.5)
		end
		if isMelee then
			CameraController.Shake(1.2)
		end
		if typeof(hits) == "table" then
			for _, h in hits do
				if typeof(h) == "table" and typeof(h[2]) == "Vector3" then
					EffectsController.FlashEnemy(h[1])
					EffectsController.HitBurst(h[2], h[4] == true)
					EffectsController.DamageNumber(h[2], tonumber(h[3]) or 0, h[4] == true, h[5] == true)
				end
			end
		end
	end)

	-- After the camera (and CameraController's recoil at Camera+1), so the gun never lags a frame.
	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 2, update)
	syncFromServer()
end

return WeaponController
