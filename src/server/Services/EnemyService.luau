--!nonstrict
-- Enemy spawning, a single throttled AI loop for all enemies, damage and death.
-- Models are PLACEHOLDER block zombies built in code (no rig/animations yet).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")

local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local WaveConfig = require(game.ReplicatedStorage.Shared.Config.WaveConfig)
local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)
local Signal = require(game.ReplicatedStorage.Shared.Util.Signal)
local MapService = require(script.Parent.MapService)
local PlayerService = require(script.Parent.PlayerService)
local BarrierService = require(script.Parent.BarrierService)
local GameConfigRef = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local EnemyService = {}
EnemyService.EnemyDied = Signal.new() -- (enemyData, killer: Player?, wasHeadshot: boolean)

local HIP_HEIGHT = 2
local enemiesFolder: Folder
local enemies = {} -- [Model] = data
local aliveCount = 0

local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local gameState: Folder
local notify: RemoteEvent

local mapRayParams = RaycastParams.new()
mapRayParams.FilterType = Enum.RaycastFilterType.Include

----------------------------------------------------------------------
-- Model construction (PLACEHOLDER visuals)
----------------------------------------------------------------------

local function weldedPart(model, root, name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

-- Limbs hang on Motor6Ds (pivot = shoulder/hip) so clients can swing them while the
-- zombie walks (EffectsController sets Motor6D.Transform locally; nothing replicates).
local function jointedPart(model, root, name, size, pivot: CFrame, partFromPivot: CFrame, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * pivot * partFromPivot
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local m = Instance.new("Motor6D")
	m.Name = name .. "Joint"
	m.Part0 = root
	m.Part1 = p
	m.C0 = pivot
	m.C1 = partFromPivot:Inverse()
	m.Parent = root
	p.Parent = model
	return p
end

local function buildModel(stats, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = stats.DisplayName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(position + Vector3.new(0, HIP_HEIGHT + 1, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	root.Parent = model
	model.PrimaryPart = root

	local skin = stats.BodyColor
	local cloth = Color3.fromRGB(60, 52, 70)
	weldedPart(model, root, "Torso", Vector3.new(2, 2, 1), CFrame.new(), cloth)
	-- Invisible body collider (y 1.6..5.4 above the ground): zombies shove each other
	-- into a crowd instead of overlapping, and it's too tall to step up onto.
	-- CanQuery off so bullets/knife still hit the visible parts.
	local collider = weldedPart(model, root, "Collider", Vector3.new(2.2, 3.8, 1.6), CFrame.new(0, 0.5, 0), cloth)
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanQuery = false
	collider.CanTouch = false
	collider.CastShadow = false
	local head = weldedPart(model, root, "Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 1.65, 0), skin)
	-- arms reach forward from the shoulder; legs hang from the hip
	jointedPart(model, root, "LeftArm", Vector3.new(0.6, 0.6, 1.9), CFrame.new(-1.3, 0.6, 0.15), CFrame.new(0, 0, -0.95), skin)
	jointedPart(model, root, "RightArm", Vector3.new(0.6, 0.6, 1.9), CFrame.new(1.3, 0.6, 0.15), CFrame.new(0, 0, -0.95), skin)
	jointedPart(model, root, "LeftLeg", Vector3.new(0.8, 2, 0.8), CFrame.new(-0.5, -1, 0), CFrame.new(0, -1, 0), cloth)
	jointedPart(model, root, "RightLeg", Vector3.new(0.8, 2, 0.8), CFrame.new(0.5, -1, 0), CFrame.new(0, -1, 0), cloth)
	-- Glowing eyes (child of head so they count as head hits)
	for _, x in { -0.3, 0.3 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.25, 0.18, 0.05)
		eye.CFrame = head.CFrame * CFrame.new(x, 0.15, -0.66)
		eye.Color = Color3.fromRGB(255, 40, 60)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.CanQuery = false
		eye.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = eye
		w.Parent = eye
		eye.Parent = model
	end

	-- 3D positional sounds (server-played, replicated to every client)
	for _, name in { "ZombieGroan", "ZombieAttack" } do
		local def = SoundConfig[name]
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.Ids[math.random(1, #def.Ids)]
		s.Volume = def.Volume
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 6
		s.RollOffMaxDistance = 90
		s.Parent = root
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = HIP_HEIGHT
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.AutoJumpEnabled = true
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model

	return model
end

----------------------------------------------------------------------
-- Spawning / lookup
----------------------------------------------------------------------

-- Claw up out of the ground at finalCf: start below, rise, then hand over to physics.
-- Used for ground spawns and for relocating lost zombies. Returns busy-until time.
local function emergeAt(model: Model, finalCf: CFrame, scale: number): number
	local root = model.PrimaryPart
	root.Anchored = true
	-- PivotTo moves every part. Setting only root.CFrame before parenting left the
	-- welded torso/head 6 studs above the root: those were the floating zombies.
	model:PivotTo(finalCf - Vector3.new(0, 6 * scale, 0))
	model.Parent = enemiesFolder
	TweenService:Create(root, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = finalCf }):Play()
	task.delay(1.15, function()
		if root.Parent then
			root.Anchored = false
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	end)
	-- dirt burst
	local burst = Instance.new("Part")
	burst.Anchored, burst.CanCollide, burst.CanQuery, burst.CanTouch = true, false, false, false
	burst.Transparency = 1
	burst.Position = finalCf.Position - Vector3.new(0, (HIP_HEIGHT + 1) * scale, 0)
	burst.Name = "SpawnDirt"
	burst.Parent = workspace -- NOT the Enemies folder: everything in there must be an enemy Model
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(110, 90, 70))
	e.Size = NumberSequence.new(1.5, 4)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Lifetime = NumberRange.new(0.8, 1.2)
	e.Speed = NumberRange.new(6, 10)
	e.SpreadAngle = Vector2.new(50, 50)
	e.Rate = 0
	e.Parent = burst
	e:Emit(18)
	task.delay(2, function()
		burst:Destroy()
	end)
	return os.clock() + 1.15
end

-- Elite look: bigger, scorched red body, burning yellow eyes, ember aura.
local function makeElite(model: Model, spawnPos: Vector3)
	local e = ProgressionConfig.Elite
	model:ScaleTo(e.Scale)
	model.Humanoid.HipHeight = HIP_HEIGHT * e.Scale
	model:PivotTo(CFrame.new(spawnPos + Vector3.new(0, (HIP_HEIGHT + 1) * e.Scale, 0)) * model:GetPivot().Rotation)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "Eye" then
				d.Color = Color3.fromRGB(255, 220, 60)
			elseif d.Name == "Torso" or d.Name:find("Leg") then
				d.Color = Color3.fromRGB(90, 20, 24)
			elseif d.Name ~= "HumanoidRootPart" and d.Name ~= "Collider" then
				d.Color = d.Color:Lerp(Color3.fromRGB(160, 40, 40), 0.5)
			end
		end
	end
	local torso = model:FindFirstChild("Torso")
	if torso then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 120, 40)
		glow.Range = 12
		glow.Brightness = 1.5
		glow.Parent = torso
		local embers = Instance.new("ParticleEmitter")
		embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 60, 30))
		embers.LightEmission = 1
		embers.Size = NumberSequence.new(0.35, 0)
		embers.Lifetime = NumberRange.new(0.6, 1.1)
		embers.Rate = 14
		embers.Speed = NumberRange.new(1, 3)
		embers.SpreadAngle = Vector2.new(180, 180)
		embers.Acceleration = Vector3.new(0, 5, 0)
		embers.Parent = torso
	end
	model:SetAttribute("Elite", true)
	model.Name = "Elite " .. model.Name
end

-- Boss: the Dust Titan (wave 10 finale). Scaled-up zombie, stone + ember look.
-- Its health is published on GameState (BossName / BossHealth / BossMax) for the HUD bar.
function EnemyService.SpawnBoss(wave: number, playerCount: number, pos: Vector3)
	local b = EnemyConfig.Boss
	local look = { DisplayName = b.DisplayName, BodyColor = Color3.fromRGB(120, 105, 92) }
	local model = buildModel(look, pos)
	model:ScaleTo(b.Scale)
	model.Humanoid.HipHeight = HIP_HEIGHT * b.Scale
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "Eye" then
				d.Color = Color3.fromRGB(255, 140, 40)
			elseif d.Name == "Torso" then
				d.Color = Color3.fromRGB(70, 58, 50)
				d.Material = Enum.Material.Slate
			elseif d.Name ~= "HumanoidRootPart" and d.Name ~= "Collider" then
				d.Material = Enum.Material.Rock
			end
		end
	end
	local torso = model:FindFirstChild("Torso")
	if torso then
		-- glowing ember cracks
		for i = -1, 1 do
			local crack = Instance.new("Part")
			crack.Name = "EmberCrack"
			crack.Size = Vector3.new(0.15 * b.Scale, 1.4 * b.Scale, 0.05)
			crack.Color = Color3.fromRGB(255, 120, 30)
			crack.Material = Enum.Material.Neon
			crack.CanCollide, crack.CanQuery, crack.Massless = false, false, true
			crack.CFrame = torso.CFrame * CFrame.new(i * 0.5 * b.Scale, 0, -torso.Size.Z / 2 - 0.03) * CFrame.Angles(0, 0, math.rad(i * 25))
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = torso, crack
			w.Parent = crack
			crack.Parent = model
		end
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 130, 50)
		glow.Range = 24
		glow.Brightness = 2
		glow.Parent = torso
	end
	model:SetAttribute("Boss", true)
	local humanoid = model.Humanoid
	local maxHealth = math.floor(b.Health * (b.PlayerHealthMult[math.clamp(playerCount, 1, 4)] or 1))
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = b.WalkSpeed
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies"
		end
	end
	local finalCf = CFrame.new(pos + Vector3.new(0, (HIP_HEIGHT + 1) * b.Scale, 0))
	local busyUntil = emergeAt(model, finalCf, b.Scale) + 0.8
	CollectionService:AddTag(model, "Enemy")
	local stats = {
		Id = b.Id, DisplayName = b.DisplayName, BaseHealth = maxHealth,
		WalkSpeed = b.WalkSpeed, RunSpeed = b.WalkSpeed, Damage = b.Damage,
		AttackRange = b.AttackRange, AttackCooldown = b.AttackCooldown, AttackWindup = 0.5,
	}
	enemies[model] = {
		busyUntil = busyUntil, lastTear = os.clock(), model = model, humanoid = humanoid,
		root = model.PrimaryPart, stats = stats, damage = b.Damage, isBoss = true,
		scale = b.Scale, dead = false, lastAttack = 0, nextGroan = 0, isRunner = false,
		baseSpeed = b.WalkSpeed, waypoints = nil, waypointIndex = 0, lastPathTime = 0,
		computingPath = false, lastPos = finalCf.Position, stuckTime = 0,
		nextSlam = os.clock() + 4,
	}
	aliveCount += 1
	gameState:SetAttribute("BossName", b.DisplayName)
	gameState:SetAttribute("BossMax", maxHealth)
	gameState:SetAttribute("BossHealth", maxHealth)
	notify:FireAllClients("Message", { text = "The " .. b.DisplayName .. " rises", tone = "bad" })
	return enemies[model]
end

function EnemyService.Spawn(enemyId: string, wave: number, opts)
	local stats = EnemyConfig.Enemies[enemyId]
	assert(stats, "Unknown enemy " .. tostring(enemyId))
	local isElite = opts and opts.elite == true

	local spawnInfo = MapService.GetEnemySpawn()
	if not spawnInfo then
		return nil
	end
	local model = buildModel(stats, spawnInfo.pos)
	if isElite then
		makeElite(model, spawnInfo.pos)
	end
	local humanoid = model.Humanoid
	local maxHealth = math.floor(stats.BaseHealth * WaveConfig.HealthMultiplier(wave) * (isElite and ProgressionConfig.Elite.HealthMult or 1))
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	local isRunner = isElite or math.random() < WaveConfig.RunnerChance(wave)
	humanoid.WalkSpeed = isRunner and stats.RunSpeed * (isElite and 0.9 or 1) or stats.WalkSpeed
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies"
		end
	end

	local root = model.PrimaryPart
	local busyUntil = 0
	if spawnInfo.emerge then
		busyUntil = emergeAt(model, root.CFrame, isElite and ProgressionConfig.Elite.Scale or 1)
	else
		model.Parent = enemiesFolder
		root:SetNetworkOwner(nil) -- server-owned physics: no client control, no ownership jitter
		if spawnInfo.barrier then
			-- face the window
			local inside = spawnInfo.barrier:GetAttribute("Inside")
			model:PivotTo(CFrame.lookAt(root.Position, Vector3.new(inside.X, root.Position.Y, inside.Z)))
		end
	end
	CollectionService:AddTag(model, "Enemy")

	enemies[model] = {
		busyUntil = busyUntil,
		barrier = spawnInfo.barrier, -- set while outside a boarded window
		lastTear = os.clock(),
		model = model,
		humanoid = humanoid,
		root = model.PrimaryPart,
		stats = stats,
		damage = stats.Damage * WaveConfig.DamageMultiplier(wave) * (isElite and ProgressionConfig.Elite.DamageMult or 1),
		isElite = isElite,
		dead = false,
		lastAttack = 0,
		nextGroan = os.clock() + math.random() * 3,
		isRunner = isRunner,
		baseSpeed = humanoid.WalkSpeed,
		-- pathing
		waypoints = nil,
		waypointIndex = 0,
		lastPathTime = 0,
		computingPath = false,
		-- stuck detection
		lastPos = model.PrimaryPart.Position,
		stuckTime = 0,
	}
	aliveCount += 1
	return model
end

-- Resolve any descendant part (e.g. the Head that was shot) to its enemy record.
function EnemyService.GetEnemyFromPart(part: Instance)
	if typeof(part) ~= "Instance" or not part:IsDescendantOf(enemiesFolder) then
		return nil
	end
	local node = part
	while node and node.Parent ~= enemiesFolder do
		node = node.Parent
	end
	local data = node and enemies[node]
	if data and not data.dead then
		return data
	end
	return nil
end

function EnemyService.GetFolder(): Folder
	return enemiesFolder
end

function EnemyService.AliveCount(): number
	return aliveCount
end

----------------------------------------------------------------------
-- Damage & death
----------------------------------------------------------------------

-- Death: a ragdoll. The body stays in one piece (limb motors become ball sockets),
-- is thrown back along the hit and crumples; headshots pop the head off. After a
-- beat it dissolves into embers and ash. Corpses only collide with the world, and
-- they're gone in ~2s so nothing piles up underfoot.
local DISSOLVE_AT = 1.2
local DISSOLVE_TIME = 0.55

local function socket(part0: BasePart, part1: BasePart, at0: CFrame, at1: CFrame, upper: number)
	local a0 = Instance.new("Attachment")
	a0.CFrame = at0
	a0.Parent = part0
	local a1 = Instance.new("Attachment")
	a1.CFrame = at1
	a1.Parent = part1
	local s = Instance.new("BallSocketConstraint")
	s.Attachment0, s.Attachment1 = a0, a1
	s.LimitsEnabled = true
	s.UpperAngle = upper
	s.TwistLimitsEnabled = true
	s.TwistLowerAngle, s.TwistUpperAngle = -30, 30
	s.Parent = part0
end

local function despawn(data, hitDir: Vector3?, isHeadshot: boolean?)
	local model = data.model
	local root = data.root
	local scale = data.scale or 1
	local flat = (hitDir and Vector3.new(hitDir.X, 0, hitDir.Z).Magnitude > 0.05) and Vector3.new(hitDir.X, 0, hitDir.Z).Unit or -root.CFrame.LookVector
	local lift = hitDir and math.max(0, hitDir.Y) or 0 -- explosions add an upward kick
	if data.humanoid.Parent then
		data.humanoid:Destroy()
	end
	local collider = model:FindFirstChild("Collider")
	if collider then
		collider:Destroy()
	end

	-- limbs: Motor6D -> ball socket at the same shoulder/hip pivot
	for _, m in root:GetChildren() do
		if m:IsA("Motor6D") and m.Part1 then
			socket(root, m.Part1, m.C0, m.C1, 75)
			m:Destroy()
		end
	end
	-- head: welded to the root; becomes a neck socket, or pops off on a headshot
	local head = model:FindFirstChild("Head")
	if head then
		for _, w in head:GetChildren() do
			if w:IsA("WeldConstraint") then
				w:Destroy()
			end
		end
		if not isHeadshot then
			local neck = root.CFrame:ToObjectSpace(head.CFrame) * CFrame.new(0, -head.Size.Y / 2, 0)
			socket(root, head, neck, CFrame.new(0, -head.Size.Y / 2, 0), 45)
		end
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
			d.CollisionGroup = "Corpses"
			d.CanCollide = d.Name ~= "Eye" and d.Name ~= "EmberCrack"
			if d.Name ~= "Eye" and d.Name ~= "EmberCrack" then
				d.Massless = false
			end
		end
	end
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- thrown back along the hit, toppling over backwards
	local power = (isHeadshot and 30 or 22) + lift * 40
	root.AssemblyLinearVelocity = flat * power + Vector3.new(0, 12 + lift * 35, 0)
	root.AssemblyAngularVelocity = flat:Cross(Vector3.yAxis) * -(7 + math.random() * 4)

	if isHeadshot and head then
		pcall(function()
			head:SetNetworkOwner(nil)
		end)
		head.AssemblyLinearVelocity = flat * 26 + Vector3.new((math.random() - 0.5) * 10, 38, (math.random() - 0.5) * 10)
		head.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		-- spray from the neck
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(150, 10, 20))
		spray.Size = NumberSequence.new(0.6 * scale, 0)
		spray.Lifetime = NumberRange.new(0.3, 0.6)
		spray.Speed = NumberRange.new(10, 18)
		spray.SpreadAngle = Vector2.new(25, 25)
		spray.Acceleration = Vector3.new(0, -40, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Rate = 0
		spray.Parent = model:FindFirstChild("Torso") or root
		spray:Emit(24)
	end

	-- dissolve: embers + ash rise as the body shrinks away
	task.delay(DISSOLVE_AT, function()
		if not model.Parent then
			return
		end
		local torso = model:FindFirstChild("Torso")
		if torso then
			local ash = Instance.new("ParticleEmitter")
			ash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			ash.Color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(80, 70, 60))
			ash.LightEmission = 0.8
			ash.Size = NumberSequence.new(0.5 * scale, 0)
			ash.Lifetime = NumberRange.new(0.6, 1.1)
			ash.Speed = NumberRange.new(2, 5)
			ash.SpreadAngle = Vector2.new(180, 180)
			ash.Acceleration = Vector3.new(0, 8, 0)
			ash.Rate = 0
			ash.Parent = torso
			ash:Emit(26)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				TweenService:Create(d, TweenInfo.new(DISSOLVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = d.Size * 0.35 }):Play()
			end
		end
	end)
	task.delay(DISSOLVE_AT + DISSOLVE_TIME + 0.6, function()
		model:Destroy()
	end)
end

-- Current normal speed (base, reduced while slowed by an ability)
local function normalSpeed(data): number
	if data.slowUntil and os.clock() < data.slowUntil then
		return data.baseSpeed * data.slowMult
	end
	return data.baseSpeed
end

-- Brief stagger on non-lethal hits (bigger on headshots) so hits feel like they land.
local function flinch(data, isHeadshot: boolean?)
	local hum = data.humanoid
	data.flinchToken = (data.flinchToken or 0) + 1
	local token = data.flinchToken
	hum.WalkSpeed = normalSpeed(data) * (isHeadshot and 0.15 or 0.4)
	task.delay(isHeadshot and 0.3 or 0.15, function()
		if not data.dead and data.flinchToken == token then
			hum.WalkSpeed = normalSpeed(data)
		end
	end)
end

-- Slow an enemy to `mult` of its speed for `duration` seconds (frost abilities).
function EnemyService.Slow(data, mult: number, duration: number)
	if data.dead then
		return
	end
	data.slowMult = math.min(mult, (data.slowUntil and os.clock() < data.slowUntil) and data.slowMult or 1)
	data.slowUntil = math.max(data.slowUntil or 0, os.clock() + duration)
	data.humanoid.WalkSpeed = normalSpeed(data)
	local token = data.slowUntil
	task.delay(duration + 0.05, function()
		if not data.dead and data.slowUntil == token then
			data.slowUntil = nil
			data.humanoid.WalkSpeed = data.baseSpeed
		end
	end)
end

-- Area blast (upgrade picks, perks). Damage falls off to half at the edge. Kills are
-- tagged "blast" (Chain Reaction checks this) and reported through onKill(data).
function EnemyService.Explode(pos: Vector3, radius: number, damage: number, attacker: Player?, onKill, color: Color3?)
	for _, data in EnemyService.InRadius(pos, radius) do
		local d = (data.root.Position - pos).Magnitude
		local dmg = damage * (1 - 0.5 * math.clamp(d / radius, 0, 1))
		local away = data.root.Position - pos
		data.lastHitTag = "blast"
		local killed = EnemyService.Damage(data, dmg, attacker, false, (away.Magnitude > 0.1 and away.Unit or Vector3.yAxis) + Vector3.new(0, 0.8, 0))
		if not killed then
			data.lastHitTag = nil
		elseif onKill then
			onKill(data)
		end
	end
	notify:FireAllClients("AbilityFx", { kind = "Explosion", pos = pos, radius = radius, color = color })
end

-- Set an enemy on fire: `dps` for `duration` seconds (refreshes, doesn't stack).
-- onKill(data) is called if the fire finishes it, so the shooter gets the credit.
function EnemyService.Burn(data, dps: number, duration: number, attacker: Player?, onKill)
	if data.dead then
		return
	end
	data.burnDps = math.max(data.burnDps or 0, dps)
	local already = data.burnUntil and os.clock() < data.burnUntil
	data.burnUntil = os.clock() + duration
	if already then
		return
	end
	local torso = data.model:FindFirstChild("Torso")
	local fire
	if torso then
		fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 120, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
		fire.Parent = torso
	end
	task.spawn(function()
		while not data.dead and os.clock() < data.burnUntil do
			task.wait(0.5)
			if data.dead then
				break
			end
			if EnemyService.Damage(data, data.burnDps * 0.5, attacker, false, nil) and onKill then
				onKill(data)
			end
		end
		data.burnDps = nil
		if fire then
			fire:Destroy()
		end
	end)
end

-- Live enemies whose root is within `radius` of `pos` (optionally only on the XZ plane).
function EnemyService.InRadius(pos: Vector3, radius: number, flat: boolean?): { any }
	local list = {}
	for _, data in enemies do
		if not data.dead and data.root.Parent then
			local d = data.root.Position - pos
			if flat then
				d = Vector3.new(d.X, d.Y * 0.35, d.Z)
			end
			if d.Magnitude <= radius then
				table.insert(list, data)
			end
		end
	end
	return list
end

-- Returns true if this hit killed the enemy. hitDir (optional) = direction of the shot, for knockback.
function EnemyService.Damage(data, amount: number, attacker: Player?, isHeadshot: boolean, hitDir: Vector3?): boolean
	if data.dead then
		return false
	end
	local hum = data.humanoid
	hum.Health = math.max(0, hum.Health - amount)
	if data.isBoss then
		gameState:SetAttribute("BossHealth", hum.Health)
	end
	if hum.Health > 0 then
		if not data.isBoss then -- the Titan doesn't flinch
			flinch(data, isHeadshot)
		end
		return false
	end
	data.dead = true
	enemies[data.model] = nil
	aliveCount -= 1
	local deathPos = data.root.Position
	data.deathPosition = deathPos
	despawn(data, hitDir, isHeadshot)
	EnemyService.EnemyDied:Fire(data, attacker, isHeadshot)
	return true
end

-- Nuke: kill every live enemy with no killer (no per-kill points or drops).
-- The Titan survives a Nuke unless includeBoss is set (dev testing).
function EnemyService.KillAll(includeBoss: boolean?)
	local list = {}
	for _, data in enemies do
		if includeBoss or not data.isBoss then
			table.insert(list, data)
		end
	end
	for _, data in list do
		EnemyService.Damage(data, math.huge, nil, false, Vector3.new(math.random() - 0.5, 0, math.random() - 0.5))
	end
end

function EnemyService.ClearAll()
	for model, data in enemies do
		data.dead = true
		model:Destroy()
	end
	table.clear(enemies)
	aliveCount = 0
end

----------------------------------------------------------------------
-- AI
----------------------------------------------------------------------

local function nearestTarget(pos: Vector3, characters)
	local best, bestDist = nil, math.huge
	for _, char in characters do
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist = char, d
			end
		end
	end
	return best, bestDist
end

local function requestPath(data, targetPos: Vector3)
	data.computingPath = true
	data.lastPathTime = os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 3, -- wider than the body: paths keep clear of wall corners
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 6,
		})
		local ok = pcall(function()
			path:ComputeAsync(data.root.Position, targetPos)
		end)
		data.computingPath = false
		if data.dead then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			data.waypoints = path:GetWaypoints()
			data.waypointIndex = math.min(2, #data.waypoints)
		else
			data.waypoints = nil
		end
	end)
end

local function followPath(data): boolean
	local wps = data.waypoints
	if not wps or data.waypointIndex > #wps then
		return false
	end
	local wp = wps[data.waypointIndex]
	local flat = Vector3.new(wp.Position.X - data.root.Position.X, 0, wp.Position.Z - data.root.Position.Z)
	if flat.Magnitude < 2 then -- (was 3: switching early made zombies cut into corners)
		data.waypointIndex += 1
		if data.waypointIndex > #wps then
			return false
		end
		wp = wps[data.waypointIndex]
	end
	if wp.Action == Enum.PathWaypointAction.Jump then
		data.humanoid.Jump = true
	end
	data.humanoid:MoveTo(wp.Position)
	return true
end

local function playSound(data, name: string)
	local s = data.root:FindFirstChild(name)
	if not s then
		return
	end
	local def = SoundConfig[name]
	s.SoundId = def.Ids[math.random(1, #def.Ids)]
	s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * (def.PitchVariance or 0)
	s:Play()
end

-- Hunt mode (set by WaveService when the last few zombies of a wave remain):
-- they all run and get relocated sooner, so you never search for the last one.
local hunting = false

function EnemyService.SetHunting(on: boolean)
	if on == hunting then
		return
	end
	hunting = on
	if on then
		for _, data in enemies do
			if not data.dead then
				data.baseSpeed = math.max(data.baseSpeed, data.stats.RunSpeed)
				data.humanoid.WalkSpeed = data.baseSpeed
				data.isRunner = true
				data.checkAt = nil
			end
		end
	end
end

-- Move a lost/stuck zombie: it sinks away and claws up at a ground spawn near the players.
local function relocate(data)
	local info = MapService.GetEnemySpawn(true)
	if not info or data.dead then
		data.checkAt = nil
		return
	end
	local scale = data.scale or (data.isElite and ProgressionConfig.Elite.Scale or 1)
	data.barrier = nil
	data.waypoints = nil
	data.checkAt = nil
	data.stuckTime = 0
	local finalCf = CFrame.new(info.pos + Vector3.new(0, (HIP_HEIGHT + 1) * scale, 0))
	data.busyUntil = emergeAt(data.model, finalCf, scale)
	data.lastPos = finalCf.Position
end

local function aiTick(dt: number)
	local characters = PlayerService.GetAliveCharacters()
	local pathBudget = EnemyConfig.PathBudgetPerTick
	local now = os.clock()
	mapRayParams.FilterDescendantsInstances = { MapService.GetMapFolder() }

	for _, data in enemies do
		if data.dead or not data.root.Parent then
			continue
		end
		if now < (data.busyUntil or 0) then
			continue -- emerging from the ground or vaulting through a window
		end
		local root, hum = data.root, data.humanoid

		-- Outside a boarded window: walk to it, tear boards off, then vault in.
		if data.barrier then
			local barrier = data.barrier
			if not barrier.Parent then
				data.barrier = nil -- map was rebuilt
			else
				local outside = barrier:GetAttribute("Outside")
				local flat = Vector3.new(outside.X - root.Position.X, 0, outside.Z - root.Position.Z)
				if flat.Magnitude > 2.5 then
					hum:MoveTo(Vector3.new(outside.X, root.Position.Y, outside.Z))
				elseif (barrier:GetAttribute("Boards") or 0) > 0 then
					hum:MoveTo(root.Position)
					-- Slow, defendable tearing only where a player is near; at windows nobody is
				-- watching they rip through, so far-off windows don't just stall the wave.
				local bcfg = GameConfigRef.Barrier
				local watched = false
				local inside = barrier:GetAttribute("Inside")
				for _, char in characters do
					local r = char:FindFirstChild("HumanoidRootPart")
					if r and inside and (r.Position - inside).Magnitude <= (bcfg.UnwatchedRange or 35) then
						watched = true
						break
					end
				end
				local tearEvery = watched and bcfg.TearInterval or (bcfg.TearIntervalUnwatched or bcfg.TearInterval)
				if now - data.lastTear >= tearEvery then
						data.lastTear = now
						BarrierService.TearBoard(barrier)
						if now >= data.nextGroan then
							playSound(data, "ZombieAttack")
						end
					end
				else
					-- Vault: tween through the opening to the inside point
					local inside = barrier:GetAttribute("Inside")
					local vaultTime = GameConfigRef.Barrier.VaultTime
					data.barrier = nil
					data.busyUntil = now + vaultTime + 0.05
					root.Anchored = true
					local look = CFrame.lookAt(inside, inside + (inside - outside).Unit)
					local mid = (root.Position + inside) / 2 + Vector3.new(0, 2.5, 0)
					local t1 = TweenService:Create(root, TweenInfo.new(vaultTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = look.Rotation + mid })
					local t2 = TweenService:Create(root, TweenInfo.new(vaultTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = look })
					t1.Completed:Connect(function()
						t2:Play()
					end)
					t2.Completed:Connect(function()
						if root.Parent and not data.dead then
							root.Anchored = false
							pcall(function()
								root:SetNetworkOwner(nil)
							end)
						end
					end)
					t1:Play()
				end
				continue
			end
		end

		local target, dist = nearestTarget(root.Position, characters)

		if not target then
			hum:MoveTo(root.Position)
			continue
		end

		local targetRoot = target.HumanoidRootPart
		local targetPos = targetRoot.Position

		-- No jumping in a crowd around a player: jumps there land zombies on heads
		-- (the "floating" zombies). Path jumps far away still work.
		local near = dist < 12
		if near ~= data.noJump then
			data.noJump = near
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, not near)
		end
		-- Somehow on top of a player anyway: shove it off sideways.
		local flatOff = Vector3.new(root.Position.X - targetPos.X, 0, root.Position.Z - targetPos.Z)
		if root.Position.Y - targetPos.Y > 2.5 and flatOff.Magnitude < 3 then
			local away = flatOff.Magnitude > 0.1 and flatOff.Unit or Vector3.new(1, 0, 0)
			root.AssemblyLinearVelocity = away * 22 + Vector3.new(0, -8, 0)
		end

		-- Titan ground slam: telegraphed ring, then damage + knockback inside it.
		if data.isBoss and now >= (data.nextSlam or 0) and dist <= EnemyConfig.Boss.Slam.TriggerRange then
			local s = EnemyConfig.Boss.Slam
			data.nextSlam = now + s.Every
			data.busyUntil = now + s.Windup + 0.4
			hum:MoveTo(root.Position)
			local center = root.Position - Vector3.new(0, (HIP_HEIGHT + 1) * (data.scale or 1), 0)
			notify:FireAllClients("AbilityFx", { kind = "BossSlamWarn", pos = center, radius = s.Radius, delay = s.Windup })
			task.delay(s.Windup, function()
				if data.dead then
					return
				end
				for _, char in PlayerService.GetAliveCharacters() do
					local r = char:FindFirstChild("HumanoidRootPart")
					local h = char:FindFirstChildOfClass("Humanoid")
					if r and h then
						local off = Vector3.new(r.Position.X - center.X, 0, r.Position.Z - center.Z)
						if off.Magnitude <= s.Radius and math.abs(r.Position.Y - center.Y) < 10 then
							PlayerService.Damage(char, s.Damage * WaveConfig.DamageMultiplier(1))
							local p = game.Players:GetPlayerFromCharacter(char)
							if p then
								local away = off.Magnitude > 0.1 and off.Unit or Vector3.xAxis
								notify:FireClient(p, "Knockback", { vel = away * s.Knockback + Vector3.new(0, 30, 0) })
							end
						end
					end
				end
				notify:FireAllClients("AbilityFx", { kind = "BossSlam", pos = center, radius = s.Radius })
			end)
			continue
		end

		-- Periodic groans so players can hear where the horde is (runners are noisier).
		if now >= data.nextGroan then
			playSound(data, "ZombieGroan")
			data.nextGroan = now + (data.isRunner and 2 or 3.5) + math.random() * 3
		end

		-- Attack
		if dist <= data.stats.AttackRange then
			hum:MoveTo(targetPos)
			-- Wind-up: the first swing comes a beat after reaching you, so you can react
			data.inReachSince = data.inReachSince or now
			local ready = now - data.inReachSince >= (data.stats.AttackWindup or 0)
			if ready and now - data.lastAttack >= data.stats.AttackCooldown then
				data.lastAttack = now
				local targetHum = target:FindFirstChildOfClass("Humanoid")
				if targetHum and targetHum.Health > 0 then
					PlayerService.Damage(target, data.damage)
					playSound(data, "ZombieAttack")
				end
			end
			continue
		end

		data.inReachSince = nil -- out of reach: the next approach winds up again

		-- Movement: straight line if clear, otherwise pathfind around cover.
		local toTarget = targetPos - root.Position
		local blocked = workspace:Raycast(root.Position, toTarget, mapRayParams) ~= nil
		if not blocked then
			data.waypoints = nil
			hum:MoveTo(targetPos)
		else
			local stale = now - data.lastPathTime > EnemyConfig.PathRecomputeInterval
			if (not data.waypoints or stale) and not data.computingPath and pathBudget > 0 then
				pathBudget -= 1
				requestPath(data, targetPos)
			end
			if not followPath(data) then
				hum:MoveTo(targetPos)
			end
		end

		-- Lost or stuck: every few seconds, check the zombie actually got closer.
		-- If not (and it's not already near you), it re-emerges from the ground near
		-- the players, zombies-style. During the hunt (last few zombies) it's quicker.
		local check = hunting and 4 or 8
		if not data.checkAt then
			data.checkAt, data.checkDist = now + check, dist
		elseif now >= data.checkAt then
			if dist > (hunting and 25 or 35) and dist > data.checkDist - 6 then
				relocate(data)
				continue
			end
			data.checkAt, data.checkDist = now + check, dist
		end

		-- Stuck detection: barely moved while it should be walking.
		local moved = (root.Position - data.lastPos).Magnitude
		data.lastPos = root.Position
		if moved < hum.WalkSpeed * dt * 0.2 then
			data.stuckTime += dt
			if data.stuckTime > 1.2 then
				-- pressed against the player's crowd isn't "stuck": never jump there
				hum.Jump = not near
				data.waypoints = nil
				data.lastPathTime = 0
				data.stuckTime = 0
				-- snagged twice in a row while far from you: relocate instead of grinding a wall
				data.snags = (data.snags or 0) + 1
				if data.snags >= 2 and dist > 20 and not data.isBoss then
					data.snags = 0
					relocate(data)
				end
			end
		else
			data.stuckTime = 0
			if moved > 2 then
				data.snags = 0
			end
		end
	end
end

function EnemyService.Init()
	-- Collision groups: corpses only collide with the world.
	local PhysicsService = game:GetService("PhysicsService")
	for _, g in { "Players", "Enemies", "Corpses" } do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("Corpses", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Corpses", "Enemies", false)
	PhysicsService:CollisionGroupSetCollidable("Corpses", "Corpses", false)
	-- Zombies collide with each other (a crowd, not overlapping bodies); the tall
	-- body collider stops them stepping onto each other's heads.
	PhysicsService:CollisionGroupSetCollidable("Enemies", "Enemies", true)
	-- Player-only blocking volumes (stop players climbing over walls/roofs to skip doors)
	if not PhysicsService:IsCollisionGroupRegistered("PlayerClip") then
		PhysicsService:RegisterCollisionGroup("PlayerClip")
	end
	for _, g in { "Enemies", "Corpses", "Default" } do
		PhysicsService:CollisionGroupSetCollidable("PlayerClip", g, false)
	end
	PhysicsService:CollisionGroupSetCollidable("PlayerClip", "Players", true)

	local existing = workspace:FindFirstChild("Enemies")
	if existing then
		existing:Destroy()
	end
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace

	gameState = Remotes.GameState()
	notify = Remotes.Get("Notify")
	gameState:SetAttribute("BossMax", 0)
	gameState:SetAttribute("BossHealth", 0)
end

function EnemyService.Start()
	-- Zombies still outside a window (tearing boards) count toward its queue limit
	MapService.SetWindowOccupancy(function(barrier)
		local n = 0
		for _, data in enemies do
			if data.barrier == barrier and not data.dead then
				n += 1
			end
		end
		return n
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(EnemyConfig.AiTickRate)
			local now = os.clock()
			local ok, err = pcall(aiTick, now - last)
			last = now
			if not ok then
				warn("[EnemyService] AI tick error:", err)
			end
		end
	end)
end

return EnemyService
