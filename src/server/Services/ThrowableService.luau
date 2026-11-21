--!nonstrict
-- Throwables (ThrowableConfig): the Ember Frag (G) and the Maneki Lure (T).
-- The client only asks to throw (Throw remote: kind + aim). The server owns the count,
-- spawns a physical projectile, and handles the blast / lure.
--   Frag: bounces, then blows after the fuse. Kills pay like gun kills. Hurts the
--         thrower a little if they're inside the blast (no friendly fire otherwise).
--   Lure: settles where it lands, then every zombie within PullRadius goes for it
--         instead of you (EnemyService lures) for Duration seconds, then it bursts.

local Players = game:GetService("Players")

local ThrowableConfig = require(game.ReplicatedStorage.Shared.Config.ThrowableConfig)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local WaveConfig = require(game.ReplicatedStorage.Shared.Config.WaveConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local RemoteGuard = require(script.Parent.Parent.Util.RemoteGuard)
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local CurrencyService = require(script.Parent.CurrencyService)
local ProgressionService = require(script.Parent.ProgressionService)

local ThrowableService = {}

local notify: RemoteEvent
local gameState: Folder
local lastThrow = {} -- [Player] = os.clock()
local live = {} -- projectiles in flight / lures on the ground (cleared on reset)

local function wave(): number
	return math.max(1, gameState:GetAttribute("Wave") or 1)
end

-- Damage at the center of a blast: a multiple of a regular zombie's health this wave
local function blastDamage(cfg): number
	return cfg.DamageMult * EnemyConfig.Enemies.Shambler.BaseHealth * WaveConfig.HealthMultiplier(math.min(wave(), 9))
end

local function blast(player: Player, pos: Vector3, cfg, label: string)
	local center = blastDamage(cfg)
	for _, data in EnemyService.InRadius(pos, cfg.Radius) do
		local away = data.root.Position - pos
		local falloff = 1 - 0.5 * math.clamp(away.Magnitude / cfg.Radius, 0, 1)
		data.lastHitTag = "blast"
		local dir = (away.Magnitude > 0.1 and away.Unit or Vector3.yAxis) + Vector3.new(0, 0.8, 0)
		if EnemyService.Damage(data, center * falloff, player, false, dir) then
			if player.Parent then
				CurrencyService.AddKill(player)
				local mult = ProgressionService.OnKill(player, false)
				CurrencyService.Add(player, math.floor(GameConfig.Points.Kill * mult), label, true)
			end
		else
			data.lastHitTag = nil
		end
	end
	-- the thrower only (no friendly fire)
	if cfg.SelfDamage and player.Character then
		local r = player.Character:FindFirstChild("HumanoidRootPart")
		if r and PlayerService.IsAlive(player) then
			local d = (r.Position - pos).Magnitude
			if d <= cfg.Radius then
				PlayerService.Damage(player.Character, cfg.SelfDamage * (1 - 0.5 * d / cfg.Radius))
			end
		end
	end
	notify:FireAllClients("AbilityFx", { kind = "Explosion", pos = pos, radius = cfg.Radius, color = cfg.Color })
end

----------------------------------------------------------------------
-- Projectiles
----------------------------------------------------------------------

local function projectile(kind: string, from: Vector3, vel: Vector3): BasePart
	local cfg = ThrowableConfig[kind]
	local p = Instance.new("Part")
	p.Name = kind
	p.CollisionGroup = "Corpses" -- bounces off the world only, not zombies or players
	p.CanQuery, p.CanTouch = false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if kind == "Frag" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 0.8
		p.Color = Color3.fromRGB(45, 40, 38)
		p.Material = Enum.Material.Metal
		p.CustomPhysicalProperties = PhysicalProperties.new(2, 1, 0.25, 1, 1) -- a short bounce, then it bites
		-- ember core you can see blinking
		local core = Instance.new("Part")
		core.Name = "Core"
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.one * 0.45
		core.Material = Enum.Material.Neon
		core.Color = cfg.Color
		core.CanCollide, core.CanQuery, core.CanTouch, core.Massless = false, false, false, true
		core.CFrame = CFrame.new(from) * CFrame.new(0, 0.25, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = p, core
		w.Parent = core
		core.Parent = p
		local light = Instance.new("PointLight")
		light.Color = cfg.Color
		light.Range = 6
		light.Brightness = 1.5
		light.Parent = core
	else
		-- Maneki Lure: a little white beckoning cat charm with a gold collar and a raised paw
		p.Size = Vector3.new(0.9, 1.1, 0.8)
		p.Color = Color3.fromRGB(245, 240, 230)
		p.Material = Enum.Material.SmoothPlastic
		p.CustomPhysicalProperties = PhysicalProperties.new(1.5, 0.9, 0.05)
		local function bit(name, size, offset, color, mat, shape)
			local b = Instance.new("Part")
			b.Name = name
			b.Size = size
			b.Color = color
			b.Material = mat or Enum.Material.SmoothPlastic
			if shape then
				b.Shape = shape
			end
			b.CanCollide, b.CanQuery, b.CanTouch, b.Massless = false, false, false, true
			b.CFrame = CFrame.new(from) * offset
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = p, b
			w.Parent = b
			b.Parent = p
			return b
		end
		local white = Color3.fromRGB(245, 240, 230)
		bit("Head", Vector3.one * 0.85, CFrame.new(0, 0.85, 0), white, nil, Enum.PartType.Ball)
		bit("EarL", Vector3.new(0.22, 0.3, 0.12), CFrame.new(-0.25, 1.3, 0), white)
		bit("EarR", Vector3.new(0.22, 0.3, 0.12), CFrame.new(0.25, 1.3, 0), white)
		bit("Paw", Vector3.new(0.25, 0.55, 0.25), CFrame.new(0.5, 0.95, -0.1), white)
		local collar = bit("Collar", Vector3.new(0.95, 0.14, 0.85), CFrame.new(0, 0.48, 0), Color3.fromRGB(220, 40, 50), Enum.Material.SmoothPlastic)
		local bell = bit("Bell", Vector3.one * 0.25, CFrame.new(0, 0.42, -0.45), cfg.Color, Enum.Material.Neon, Enum.PartType.Ball)
		local light = Instance.new("PointLight")
		light.Name = "LureGlow"
		light.Color = cfg.Color
		light.Range = 8
		light.Brightness = 1.2
		light.Parent = bell
		local _ = collar
	end
	p.CFrame = CFrame.new(from)
	p.AssemblyLinearVelocity = vel
	p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (kind == "Frag" and 12 or 3)
	p.Parent = workspace
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
	table.insert(live, p)
	return p
end

local function throwFrag(player: Player, from: Vector3, vel: Vector3)
	local cfg = ThrowableConfig.Frag
	local p = projectile("Frag", from, vel)
	local core = p:FindFirstChild("Core")
	-- blink faster as the fuse runs out
	task.spawn(function()
		local t0 = os.clock()
		while p.Parent and os.clock() - t0 < cfg.Fuse do
			local left = cfg.Fuse - (os.clock() - t0)
			if core then
				core.Transparency = core.Transparency == 0 and 0.8 or 0
			end
			task.wait(math.clamp(left * 0.18, 0.05, 0.25))
		end
		if not p.Parent then
			return
		end
		local pos = p.Position
		p:Destroy()
		blast(player, pos, cfg, "Frag")
	end)
end

local function throwLure(player: Player, from: Vector3, vel: Vector3)
	local cfg = ThrowableConfig.Lure
	local p = projectile("Lure", from, vel)
	task.spawn(function()
		-- let it land and settle (or give up after 2s)
		local t0 = os.clock()
		task.wait(0.4)
		while p.Parent and os.clock() - t0 < 2 and p.AssemblyLinearVelocity.Magnitude > 1.5 do
			task.wait(0.1)
		end
		if not p.Parent then
			return
		end
		p.Anchored = true
		-- stand it upright facing the way it was thrown
		local look = Vector3.new(vel.X, 0, vel.Z)
		look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
		p.CFrame = CFrame.lookAt(p.Position, p.Position - look) + Vector3.new(0, 0.1, 0)
		local pos = p.Position
		local untilT = os.clock() + cfg.Duration
		EnemyService.AddLure(pos, cfg.PullRadius, untilT)

		local chime = Instance.new("Sound")
		chime.SoundId = SoundConfig.BoxJingle.Ids[1]
		chime.Volume = 0.6
		chime.Looped = true
		chime.RollOffMode = Enum.RollOffMode.InverseTapered
		chime.RollOffMaxDistance = 120
		chime.Parent = p
		chime:Play()
		local glow = p:FindFirstChild("LureGlow", true)
		local paw = p:FindFirstChild("Paw")
		local pawBase = paw and p.CFrame:ToObjectSpace(paw.CFrame)
		if paw then
			-- animate the paw on its own (moving a welded part would drag the whole charm)
			local w = paw:FindFirstChildOfClass("WeldConstraint")
			if w then
				w:Destroy()
			end
			paw.Anchored = true
		end
		-- beckon: the paw waves, the glow pulses
		while p.Parent and os.clock() < untilT do
			local t = os.clock()
			if paw and pawBase then
				paw.CFrame = p.CFrame * pawBase * CFrame.new(0, 0, 0.12 * math.sin(t * 9))
			end
			if glow then
				glow.Brightness = 1.5 + math.sin(t * 6) * 0.8
				glow.Range = 10 + math.sin(t * 6) * 3
			end
			task.wait(0.05)
		end
		if not p.Parent then
			return
		end
		p:Destroy()
		blast(player, pos, cfg, "Lure")
	end)
end

----------------------------------------------------------------------
-- Counts and input
----------------------------------------------------------------------

local function isFiniteVector(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude > 0.5 and v.Magnitude < 1.5
end

local function onThrow(player: Player, kind, aim)
	local cfg = typeof(kind) == "string" and ThrowableConfig[kind]
	if not cfg or not isFiniteVector(aim) then
		return
	end
	if not PlayerService.IsAlive(player) then
		return -- not while downed
	end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < cfg.Cooldown then
		return
	end
	local count = player:GetAttribute(cfg.Attribute) or 0
	if count <= 0 then
		notify:FireClient(player, "Sound", { name = "Denied" })
		return
	end
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	lastThrow[player] = now
	player:SetAttribute(cfg.Attribute, count - 1)
	local dir = aim.Unit
	local from = head.Position + dir * 1.5 + Vector3.new(0, -0.3, 0)
	local vel = dir * cfg.Speed + Vector3.new(0, cfg.Lift, 0)
	if kind == "Frag" then
		throwFrag(player, from, vel)
	else
		throwLure(player, from, vel)
	end
end

-- Lure Shrine purchase (InteractionService). Returns ok, message.
function ThrowableService.BuyLure(player: Player): (boolean, string?)
	local cfg = ThrowableConfig.Lure
	local have = player:GetAttribute(cfg.Attribute) or 0
	if have >= cfg.Max then
		return false, "You can carry " .. cfg.Max .. " lures"
	end
	if not CurrencyService.TrySpend(player, cfg.Cost) then
		return false, "Not enough points (" .. cfg.Cost .. ")"
	end
	player:SetAttribute(cfg.Attribute, have + 1)
	return true, "Maneki Lure (" .. (have + 1) .. "/" .. cfg.Max .. ")  •  press " .. cfg.Key .. " to throw"
end

-- Wave survived: everyone gets more frags (WaveService)
function ThrowableService.WaveComplete()
	local cfg = ThrowableConfig.Frag
	for _, p in Players:GetPlayers() do
		p:SetAttribute(cfg.Attribute, math.min(cfg.Max, (p:GetAttribute(cfg.Attribute) or 0) + cfg.PerWave))
	end
end

local function setStart(player: Player)
	for _, cfg in ThrowableConfig do
		player:SetAttribute(cfg.Attribute, cfg.Start)
	end
end

function ThrowableService.Reset()
	for _, p in live do
		if p.Parent then
			p:Destroy()
		end
	end
	table.clear(live)
	EnemyService.ClearLures()
	for _, p in Players:GetPlayers() do
		setStart(p)
	end
end

function ThrowableService.Init()
	notify = Remotes.Get("Notify")
	gameState = Remotes.GameState()
end

function ThrowableService.Start()
	RemoteGuard.Connect(Remotes.Get("Throw"), { rate = 3, burst = 2 }, onThrow)
	Players.PlayerAdded:Connect(setStart)
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Frags") == nil then
			setStart(p)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		lastThrow[p] = nil
	end)
	-- drop finished projectiles from the list now and then
	task.spawn(function()
		while true do
			task.wait(10)
			for i = #live, 1, -1 do
				if not live[i].Parent then
					table.remove(live, i)
				end
			end
		end
	end)
end

return ThrowableService
