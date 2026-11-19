--!nonstrict
-- Enemy spawning, a single throttled AI loop for all enemies, damage and death.
-- Models are PLACEHOLDER block zombies built in code (no rig/animations yet).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")

local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local WaveConfig = require(game.ReplicatedStorage.Shared.Config.WaveConfig)
local Signal = require(game.ReplicatedStorage.Shared.Util.Signal)
local MapService = require(script.Parent.MapService)
local PlayerService = require(script.Parent.PlayerService)

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
	local head = weldedPart(model, root, "Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 1.65, 0), skin)
	weldedPart(model, root, "LeftArm", Vector3.new(0.6, 0.6, 1.9), CFrame.new(-1.3, 0.6, -0.8), skin)
	weldedPart(model, root, "RightArm", Vector3.new(0.6, 0.6, 1.9), CFrame.new(1.3, 0.6, -0.8), skin)
	weldedPart(model, root, "LeftLeg", Vector3.new(0.8, 2, 0.8), CFrame.new(-0.5, -2, 0), cloth)
	weldedPart(model, root, "RightLeg", Vector3.new(0.8, 2, 0.8), CFrame.new(0.5, -2, 0), cloth)
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

function EnemyService.Spawn(enemyId: string, wave: number)
	local stats = EnemyConfig.Enemies[enemyId]
	assert(stats, "Unknown enemy " .. tostring(enemyId))

	local model = buildModel(stats, MapService.GetEnemySpawnPosition())
	local humanoid = model.Humanoid
	local maxHealth = math.floor(stats.BaseHealth * WaveConfig.HealthMultiplier(wave))
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	local isRunner = math.random() < WaveConfig.RunnerChance(wave)
	humanoid.WalkSpeed = isRunner and stats.RunSpeed or stats.WalkSpeed

	model.Parent = enemiesFolder
	model.PrimaryPart:SetNetworkOwner(nil) -- server-owned physics: no client control, no ownership jitter
	CollectionService:AddTag(model, "Enemy")

	enemies[model] = {
		model = model,
		humanoid = humanoid,
		root = model.PrimaryPart,
		stats = stats,
		damage = stats.Damage * WaveConfig.DamageMultiplier(wave),
		dead = false,
		lastAttack = 0,
		nextGroan = os.clock() + math.random() * 3,
		isRunner = isRunner,
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

local function despawn(data)
	local model = data.model
	data.root.Anchored = true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			if d ~= data.root then
				TweenService:Create(d, TweenInfo.new(0.45), { Transparency = 1 }):Play()
			end
		end
	end
	task.delay(0.5, function()
		model:Destroy()
	end)
end

-- Returns true if this hit killed the enemy.
function EnemyService.Damage(data, amount: number, attacker: Player?, isHeadshot: boolean): boolean
	if data.dead then
		return false
	end
	local hum = data.humanoid
	hum.Health = math.max(0, hum.Health - amount)
	if hum.Health > 0 then
		return false
	end
	data.dead = true
	enemies[data.model] = nil
	aliveCount -= 1
	despawn(data)
	EnemyService.EnemyDied:Fire(data, attacker, isHeadshot)
	return true
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
		local root, hum = data.root, data.humanoid
		local target, dist = nearestTarget(root.Position, characters)

		if not target then
			hum:MoveTo(root.Position)
			continue
		end

		local targetRoot = target.HumanoidRootPart
		local targetPos = targetRoot.Position

		-- Periodic groans so players can hear where the horde is (runners are noisier).
		if now >= data.nextGroan then
			playSound(data, "ZombieGroan")
			data.nextGroan = now + (data.isRunner and 2 or 3.5) + math.random() * 3
		end

		-- Attack
		if dist <= data.stats.AttackRange then
			hum:MoveTo(targetPos)
			if now - data.lastAttack >= data.stats.AttackCooldown then
				data.lastAttack = now
				local targetHum = target:FindFirstChildOfClass("Humanoid")
				if targetHum and targetHum.Health > 0 then
					targetHum:TakeDamage(data.damage)
					playSound(data, "ZombieAttack")
				end
			end
			continue
		end

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
				hum.Jump = true
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
