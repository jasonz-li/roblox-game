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
		-- Claw up out of the ground: start below, rise, then hand over to physics.
		local finalCf = root.CFrame
		root.Anchored = true
		-- PivotTo moves every part. Setting only root.CFrame before parenting left the
		-- welded torso/head 6 studs above the root: those were the floating zombies.
		model:PivotTo(finalCf - Vector3.new(0, 6, 0))
		model.Parent = enemiesFolder
		TweenService:Create(root, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = finalCf }):Play()
		busyUntil = os.clock() + 1.15
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
		burst.Position = finalCf.Position - Vector3.new(0, HIP_HEIGHT + 1, 0)
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

-- Death: the block body comes apart and is knocked away from the shot, then fades.
-- Parts move to the "Corpses" collision group so they never block players or enemies.
local function despawn(data, hitDir: Vector3?, isHeadshot: boolean?)
	local model = data.model
	local push = (hitDir and hitDir.Magnitude > 0) and Vector3.new(hitDir.X, 0, hitDir.Z).Unit or Vector3.zero
	if data.humanoid.Parent then
		data.humanoid:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		end
	end
	local collider = model:FindFirstChild("Collider")
	if collider then
		collider:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
			if d == data.root then
				d.Anchored = true
				continue
			end
			d.CollisionGroup = "Corpses"
			d.CanCollide = true
			d.Massless = false
			local isHead = d.Name == "Head" or d.Name == "Eye"
			local speed = (isHead and isHeadshot) and 55 or 22
			local spread = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 14
			d.AssemblyLinearVelocity = push * speed + spread + Vector3.new(0, (isHead and isHeadshot) and 30 or 14, 0)
			d.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
			TweenService:Create(d, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 1.4), { Transparency = 1 }):Play()
		end
	end
	task.delay(2.1, function()
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
	if hum.Health > 0 then
		flinch(data, isHeadshot)
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
function EnemyService.KillAll()
	local list = {}
	for _, data in enemies do
		table.insert(list, data)
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
			AgentRadius = 2,
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
	if flat.Magnitude < 3 then
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
					if now - data.lastTear >= GameConfigRef.Barrier.TearInterval then
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
					targetHum:TakeDamage(data.damage)
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
			end
		else
			data.stuckTime = 0
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
end

function EnemyService.Start()
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
