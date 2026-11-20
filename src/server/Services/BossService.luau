--!nonstrict
-- The Titan Encounter (wave 10): a raid-style boss fight in the Hollow.
-- Everything up to wave 9 is zombies; this fight is about mechanics and teamwork:
--   Phase 1 (100-66%): threat/tanking, slam, fireball rings, Meteor Brand (stack)
--   Phase 2 (66-33%):  shield + Ember Totems (kill them all within the window),
--                      then rings + Scatter Embers (spread)
--   Phase 3 (33-0%):   Cataclysm channel (break the core or the party eats it),
--                      lava shrinks the floor, everything faster; enrage at 5 min
-- Each phase change gives everyone a boon pick. Clients draw everything from
-- AbilityFx notifies + GameState attributes (BossPhase, LavaRadius, Core...).

local Players = game:GetService("Players")

local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local MapService = require(script.Parent.MapService)
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local ProgressionService = require(script.Parent.ProgressionService)

local BossService = {}

local CFG = {
	BaseHealth = 26000, -- solo, before party power
	PlayerMult = { 1, 1.7, 2.4, 3.1 },
	WalkSpeed = 15,
	MeleeDamage = 55,
	Phase2At = 0.66,
	Phase3At = 0.33,
	Ring = { Count = 24, Gaps = 3, GapWidth = 2, Speed = 26, Life = 4.6, Damage = 28, HitRadius = 3.2 },
	RingEvery = { 8, 6.5, 4.5 },
	-- total = TotalBase + TotalPerPlayer x players, split among everyone standing in it
	-- (solo 45; four players 165, so a lone player in a 4-stack's brand nearly dies)
	Brand = { Every = { 14, 13, 11 }, Delay = 4, Radius = 9, TotalBase = 5, TotalPerPlayer = 40 },
	Scatter = { Every = 15, Delay = 3, Radius = 7, Damage = 30 },
	Totems = { Health = 1600, Window = 10, Count = { 2, 3, 4, 4 } },
	Channel = { Duration = 6, ThresholdFrac = 0.05, FailDamage = 85, StaggerTime = 5, Every = 40 },
	Lava = { From = 64, To = 34, Over = 75, Dps = 20 },
	Enrage = { At = 300, DamageMult = 3, RingEvery = 2 },
}

local notify: RemoteEvent
local gameState: Folder

local function standingPlayers()
	local list = {}
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and PlayerService.IsAlive(p) then
			table.insert(list, { player = p, root = r, char = p.Character })
		end
	end
	return list
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

----------------------------------------------------------------------
-- Projectiles (fireball rings): simulated on the server for hits; the client
-- simulates the same motion for visuals from the BossRing notify.
----------------------------------------------------------------------

local projectiles = {}
local mapParams = RaycastParams.new()
mapParams.FilterType = Enum.RaycastFilterType.Include

local function fireRing(origin: Vector3)
	local r = CFG.Ring
	local skip = {}
	for _ = 1, r.Gaps do
		local start = math.random(1, r.Count)
		for k = 0, r.GapWidth - 1 do
			skip[(start + k - 1) % r.Count + 1] = true
		end
	end
	local dirs = {}
	local spin = math.random() * math.pi * 2
	for i = 1, r.Count do
		if not skip[i] then
			local a = spin + (i / r.Count) * math.pi * 2
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			table.insert(dirs, d)
			table.insert(projectiles, { pos = origin, vel = d * r.Speed, born = os.clock() })
		end
	end
	notify:FireAllClients("AbilityFx", { kind = "BossRing", origin = origin, dirs = dirs, speed = r.Speed, life = r.Life })
end

local function stepProjectiles(dt: number)
	local r = CFG.Ring
	local players = standingPlayers()
	local now = os.clock()
	for i = #projectiles, 1, -1 do
		local pr = projectiles[i]
		local nextPos = pr.pos + pr.vel * dt
		local blocked = workspace:Raycast(pr.pos, nextPos - pr.pos, mapParams) -- pillars stop it
		local dead = blocked ~= nil or now - pr.born > r.Life
		if not dead then
			for _, pl in players do
				local d = pl.root.Position - nextPos
				-- flat distance; jumping clears it (it flies at chest height)
				if Vector3.new(d.X, 0, d.Z).Magnitude <= r.HitRadius and math.abs(d.Y) < 3 then
					PlayerService.Damage(pl.char, r.Damage)
					dead = true
					break
				end
			end
		end
		if dead then
			table.remove(projectiles, i)
		else
			pr.pos = nextPos
		end
	end
end

----------------------------------------------------------------------
-- Marks: Meteor Brand (stack to split) and Scatter Embers (spread out)
----------------------------------------------------------------------

local function meteorBrand()
	local players = standingPlayers()
	if #players == 0 then
		return
	end
	local target = players[math.random(1, #players)]
	local b = CFG.Brand
	notify:FireAllClients("AbilityFx", { kind = "BossMark", mark = "Brand", target = target.player, radius = b.Radius, delay = b.Delay })
	task.delay(b.Delay, function()
		local r = target.player.Character and target.player.Character:FindFirstChild("HumanoidRootPart")
		if not r then
			return
		end
		local center = r.Position
		local inside = {}
		for _, pl in standingPlayers() do
			if flat(pl.root.Position - center).Magnitude <= b.Radius then
				table.insert(inside, pl)
			end
		end
		local total = b.TotalBase + b.TotalPerPlayer * #Players:GetPlayers()
		local share = total / math.max(1, #inside)
		for _, pl in inside do
			PlayerService.Damage(pl.char, share)
		end
		notify:FireAllClients("AbilityFx", { kind = "BossBoom", pos = center, radius = b.Radius, color = Color3.fromRGB(255, 120, 40) })
	end)
end

local function scatterEmbers()
	local s = CFG.Scatter
	local marked = standingPlayers()
	for _, pl in marked do
		notify:FireAllClients("AbilityFx", { kind = "BossMark", mark = "Scatter", target = pl.player, radius = s.Radius, delay = s.Delay })
	end
	task.delay(s.Delay, function()
		for _, m in marked do
			local r = m.player.Character and m.player.Character:FindFirstChild("HumanoidRootPart")
			if r then
				local center = r.Position
				for _, pl in standingPlayers() do
					local d = flat(pl.root.Position - center).Magnitude
					if pl.player == m.player then
						PlayerService.Damage(pl.char, s.Damage * 0.5) -- you always take a little
					elseif d <= s.Radius then
						PlayerService.Damage(pl.char, s.Damage) -- standing too close to a teammate
					end
				end
				notify:FireAllClients("AbilityFx", { kind = "BossBoom", pos = center, radius = s.Radius, color = Color3.fromRGB(190, 90, 255) })
			end
		end
	end)
end

----------------------------------------------------------------------
-- Threat: the Titan chases whoever has hurt it most; War Cry overrides.
----------------------------------------------------------------------

local function pickTarget(boss)
	local now = workspace:GetServerTimeNow()
	local best, bestScore = nil, -1
	for _, pl in standingPlayers() do
		local score = (boss.threat and boss.threat[pl.player]) or 0
		if (pl.player:GetAttribute("TauntUntil") or 0) > now then
			score += 1e9 -- taunted
		end
		if boss.forcedTarget == pl.char then
			score *= 1.1 -- a little stickiness so it doesn't flip-flop
		end
		if score > bestScore then
			best, bestScore = pl.char, score
		end
	end
	boss.forcedTarget = best
	-- threat slowly fades so the tank has to keep earning it
	if boss.threat then
		for p, v in boss.threat do
			boss.threat[p] = v * 0.985
		end
	end
end

----------------------------------------------------------------------
-- Shield + totems (phase 2)
----------------------------------------------------------------------

local function setShield(boss, on: boolean)
	boss.immune = on
	local torso = boss.model:FindFirstChild("Torso")
	local orb = boss.model:FindFirstChild("ShieldOrb")
	if on and torso and not orb then
		orb = Instance.new("Part")
		orb.Name = "ShieldOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.one * 18
		orb.Material = Enum.Material.ForceField
		orb.Color = Color3.fromRGB(255, 140, 50)
		orb.CanCollide, orb.CanQuery, orb.CanTouch, orb.Massless = false, false, false, true
		orb.CFrame = torso.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, orb
		w.Parent = orb
		orb.Parent = boss.model
	elseif not on and orb then
		orb:Destroy()
	end
	gameState:SetAttribute("BossShield", on)
end

----------------------------------------------------------------------
-- The encounter
----------------------------------------------------------------------

-- Runs the whole fight. Returns when the Titan dies or isOver() says the party wiped.
function BossService.Run(wave: number, power: number, isOver)
	local layout = MapService.GetLayout()
	local H = layout.Hollow
	mapParams.FilterDescendantsInstances = { MapService.GetMapFolder() }
	table.clear(projectiles)

	-- 1. The drop
	notify:FireAllClients("AbilityFx", { kind = "BossIntro" })
	EnemyService.ClearAll()
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Downed") then
			PlayerService.Revive(p, nil)
		end
	end
	PlayerService.SpawnAllDead()
	task.wait(2.2)
	local i = 0
	for _, p in Players:GetPlayers() do
		i += 1
		local char = p.Character or p.CharacterAdded:Wait()
		local spot = H.PlayerSpawns[(i - 1) % #H.PlayerSpawns + 1]
		char:PivotTo(CFrame.lookAt(spot + Vector3.new(0, 3, 0), H.Center + Vector3.new(0, 3, 0)))
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
	end
	gameState:SetAttribute("InHollow", true)
	gameState:SetAttribute("LavaRadius", H.Radius)
	gameState:SetAttribute("HollowCenter", H.Center)

	-- 2. The Titan
	local n = math.clamp(#Players:GetPlayers(), 1, 4)
	local boss = EnemyService.SpawnBoss(wave, n, H.Center - Vector3.new(0, 0, 20), 1)
	local maxHp = math.floor(CFG.BaseHealth * CFG.PlayerMult[n] * (power or 1))
	boss.humanoid.MaxHealth = maxHp
	boss.humanoid.Health = maxHp
	boss.humanoid.WalkSpeed = CFG.WalkSpeed
	boss.baseSpeed = CFG.WalkSpeed
	boss.damage = CFG.MeleeDamage
	boss.threat = {}
	gameState:SetAttribute("BossMax", maxHp)
	gameState:SetAttribute("BossHealth", maxHp)
	gameState:SetAttribute("BossPhase", 1)

	local started = os.clock()
	local phase = 1
	local nextRing, nextBrand, nextScatter = started + 5, started + 9, math.huge
	local nextTarget = 0
	local totems, firstTotemDeath = {}, nil
	local nextChannel, channelEnd, coreThreshold = math.huge, nil, 0
	local lavaStart = nil
	local enraged = false

	local function spawnTotems()
		local count = CFG.Totems.Count[n]
		local hp = CFG.Totems.Health * CFG.PlayerMult[n] * (power or 1) * 0.5
		table.clear(totems)
		for k = 1, count do
			local spot = H.TotemSpots[(k - 1) % #H.TotemSpots + 1]
			table.insert(totems, { spot = spot, data = EnemyService.SpawnTotem(spot, hp), hp = hp })
		end
		firstTotemDeath = nil
		notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "EMBER TOTEMS", sub = "Destroy them ALL within " .. CFG.Totems.Window .. "s of each other, or they reform" })
	end

	local last = os.clock()
	while not boss.dead and not isOver() do
		task.wait(0.05)
		local now = os.clock()
		local dt = now - last
		last = now
		stepProjectiles(dt)

		local frac = boss.humanoid.Health / maxHp
		local elapsed = now - started

		-- threat / target
		if now >= nextTarget then
			nextTarget = now + 0.5
			pickTarget(boss)
		end

		-- phase changes
		if phase == 1 and frac <= CFG.Phase2At then
			phase = 2
			gameState:SetAttribute("BossPhase", 2)
			setShield(boss, true)
			boss.busyUntil = math.huge -- stands and channels the siege
			boss.root.CFrame = CFrame.new(H.Center + Vector3.new(0, boss.root.Position.Y - H.Center.Y, 0))
			spawnTotems()
			ProgressionService.OfferUpgrades(wave)
			nextRing = now + 3
		elseif phase == 2 and frac <= CFG.Phase3At then
			phase = 3
			gameState:SetAttribute("BossPhase", 3)
			ProgressionService.OfferUpgrades(wave)
			notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "COLLAPSE", sub = "The Hollow is caving in. Break its core when it channels!" })
			lavaStart = now
			nextChannel = now + 3
		end

		-- phase 2: totem window
		if phase == 2 and boss.immune then
			local alive = 0
			for _, t in totems do
				if t.data and not t.data.dead then
					alive += 1
				elseif not firstTotemDeath then
					firstTotemDeath = now
				end
			end
			if alive == 0 then
				setShield(boss, false)
				boss.busyUntil = 0
				nextScatter = now + 6
				notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "SHIELD BROKEN", sub = "Spread out when you're marked" })
			elseif firstTotemDeath and now - firstTotemDeath > CFG.Totems.Window then
				-- too slow: the dead ones reform at full health
				for _, t in totems do
					if not t.data or t.data.dead then
						t.data = EnemyService.SpawnTotem(t.spot, t.hp)
					end
				end
				firstTotemDeath = nil
				notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "TOTEMS REFORMED", sub = "Kill them closer together" })
			end
		end

		-- phase 3: Cataclysm channel (break the core)
		if phase == 3 then
			if not channelEnd and now >= nextChannel then
				channelEnd = now + CFG.Channel.Duration
				coreThreshold = maxHp * CFG.Channel.ThresholdFrac
				boss.recentDamage = 0
				boss.busyUntil = channelEnd
				gameState:SetAttribute("CoreThreshold", coreThreshold)
				gameState:SetAttribute("CoreDamage", 0)
				gameState:SetAttribute("CoreUntil", workspace:GetServerTimeNow() + CFG.Channel.Duration)
				notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "CATACLYSM", sub = "Pour damage into it to break its core!" })
			end
			if channelEnd then
				gameState:SetAttribute("CoreDamage", boss.recentDamage or 0)
				if now >= channelEnd then
					local broke = (boss.recentDamage or 0) >= coreThreshold
					channelEnd = nil
					nextChannel = now + CFG.Channel.Every
					gameState:SetAttribute("CoreUntil", 0)
					if broke then
						boss.vulnerableUntil = now + CFG.Channel.StaggerTime
						boss.busyUntil = now + CFG.Channel.StaggerTime
						notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "STAGGERED", sub = "It takes +50% damage. Unload!" })
					else
						for _, pl in standingPlayers() do
							PlayerService.Damage(pl.char, CFG.Channel.FailDamage)
						end
						notify:FireAllClients("AbilityFx", { kind = "BossBoom", pos = boss.root.Position, radius = 70, color = Color3.fromRGB(255, 60, 30) })
					end
				end
			end
			-- lava creeps in
			local t = math.clamp((now - lavaStart) / CFG.Lava.Over, 0, 1)
			local radius = CFG.Lava.From + (CFG.Lava.To - CFG.Lava.From) * t
			gameState:SetAttribute("LavaRadius", radius)
			for _, pl in standingPlayers() do
				if flat(pl.root.Position - H.Center).Magnitude > radius then
					PlayerService.Damage(pl.char, CFG.Lava.Dps * dt)
				end
			end
		end

		-- enrage
		if not enraged and elapsed > CFG.Enrage.At then
			enraged = true
			boss.damage *= CFG.Enrage.DamageMult
			notify:FireAllClients("AbilityFx", { kind = "BossCallout", text = "ENRAGED", sub = "Finish it NOW" })
		end

		-- attacks
		local ringEvery = enraged and CFG.Enrage.RingEvery or CFG.RingEvery[phase]
		if now >= nextRing then
			nextRing = now + ringEvery
			fireRing(boss.root.Position + Vector3.new(0, -boss.root.Size.Y * 0.2, 0))
		end
		if now >= nextBrand and not boss.immune then
			nextBrand = now + CFG.Brand.Every[phase]
			meteorBrand()
		end
		if now >= nextScatter and phase >= 2 and not boss.immune then
			nextScatter = now + CFG.Scatter.Every
			scatterEmbers()
		end
	end

	-- cleanup
	table.clear(projectiles)
	for _, t in totems do
		if t.data and not t.data.dead then
			EnemyService.Damage(t.data, math.huge, nil, false, nil)
		end
	end
	gameState:SetAttribute("BossPhase", 0)
	gameState:SetAttribute("LavaRadius", 0)
	gameState:SetAttribute("CoreUntil", 0)
	gameState:SetAttribute("BossShield", false)
	return boss.dead
end

function BossService.Reset()
	if gameState then
		gameState:SetAttribute("InHollow", false)
		gameState:SetAttribute("BossPhase", 0)
		gameState:SetAttribute("LavaRadius", 0)
	end
end

function BossService.Init()
	notify = Remotes.Get("Notify")
	gameState = Remotes.GameState()
end

return BossService
