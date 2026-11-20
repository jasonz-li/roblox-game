--!nonstrict
-- Hero abilities (server-authoritative). The client asks to cast (UseAbility) and
-- plays its own effects; the server checks hero, cooldown/charge and aliveness,
-- picks targets from the REAL character position, deals damage, and broadcasts
-- an AbilityFx notify so every client draws the effect.
--
-- Replicated player attributes:
--   Hero (id), AbilityReadyAt (server time), UltCharge (0..Max), UltActive (bool)

local Players = game:GetService("Players")

local HeroConfig = require(game.ReplicatedStorage.Shared.Config.HeroConfig)
local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local RemoteGuard = require(script.Parent.Parent.Util.RemoteGuard)
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local CurrencyService = require(script.Parent.CurrencyService)
local MapService = require(script.Parent.MapService)
local ProgressionService = require(script.Parent.ProgressionService)

local AbilityService = {}

local notify: RemoteEvent
local gameState: Folder
local readyAt = {} -- [Player] = os.clock() when the ability is ready again

local function wave(): number
	return gameState:GetAttribute("Wave") or 1
end

local function isFiniteVector(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude > 0.5 and v.Magnitude < 1.5
end

local function setUlt(player, value)
	player:SetAttribute("UltCharge", math.clamp(value, 0, HeroConfig.Ult.Max))
end

-- Damage one enemy from an ability; kills pay normal kill points and feed the streak.
local function hit(player: Player, data, damage: number, dir: Vector3?)
	local killed = EnemyService.Damage(data, damage, player, false, dir)
	if killed then
		CurrencyService.AddKill(player)
		local mult = ProgressionService.OnKill(player, false)
		CurrencyService.Add(player, math.floor(GameConfig.Points.Kill * mult), "Ability", true)
	end
	return killed
end

local function mapParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { MapService.GetMapFolder() }
	return p
end

----------------------------------------------------------------------
-- Abilities (Q)
----------------------------------------------------------------------

local cast = {}

function cast.Swordsman(player, hero, root, aim)
	local a = hero.Ability
	local dir = Vector3.new(aim.X, 0, aim.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector
	local from = root.Position
	-- stop at walls (same check the client uses for the dash itself)
	local block = workspace:Raycast(from, dir * a.Range, mapParams())
	local length = block and math.max(0, (block.Position - from).Magnitude - 2) or a.Range
	local to = from + dir * length
	local dmg = HeroConfig.Damage(a.Damage, wave())
	local kills = 0
	for _, data in EnemyService.InRadius(from + dir * (length / 2), length / 2 + a.Width) do
		-- distance from the dash segment
		local rel = data.root.Position - from
		local t = math.clamp(rel:Dot(dir), 0, length)
		local closest = from + dir * t
		if (Vector3.new(data.root.Position.X, 0, data.root.Position.Z) - Vector3.new(closest.X, 0, closest.Z)).Magnitude <= a.Width and math.abs(rel.Y) < 8 then
			if hit(player, data, dmg, dir) then
				kills += 1
			end
		end
	end
	notify:FireAllClients("AbilityFx", { kind = "GaleStep", by = player, from = from, to = to, kills = kills })
	return true
end

function cast.Mage(player, hero, root, _aim)
	local a = hero.Ability
	local center = root.Position
	local dmg = HeroConfig.Damage(a.Damage, wave())
	for _, data in EnemyService.InRadius(center, a.Radius, true) do
		local away = data.root.Position - center
		local killed = hit(player, data, dmg, away.Magnitude > 0 and away.Unit or nil)
		if not killed then
			EnemyService.Slow(data, a.Slow, a.SlowTime)
		end
	end
	notify:FireAllClients("AbilityFx", { kind = "FrostNova", by = player, pos = center, radius = a.Radius })
	return true
end

----------------------------------------------------------------------
-- Ultimates (F)
----------------------------------------------------------------------

local ult = {}

function ult.Swordsman(player, hero, root, _aim)
	local u = hero.Ultimate
	player:SetAttribute("UltActive", true)
	task.spawn(function()
		for i = 1, u.Pulses do
			if not PlayerService.IsAlive(player) then
				break
			end
			local center = player.Character.HumanoidRootPart.Position
			local dmg = HeroConfig.Damage(u.Damage, wave())
			for _, data in EnemyService.InRadius(center, u.Radius, true) do
				local away = data.root.Position - center
				hit(player, data, dmg, away.Magnitude > 0 and away.Unit or nil)
			end
			notify:FireAllClients("AbilityFx", { kind = "Tempest", by = player, pos = center, radius = u.Radius, pulse = i })
			task.wait(u.Interval)
		end
		player:SetAttribute("UltActive", false)
	end)
	return true
end

function ult.Mage(player, hero, root, aim)
	local u = hero.Ultimate
	local head = player.Character:FindFirstChild("Head") or root
	-- aim point: first thing the look ray hits (map or ground), else max range
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { EnemyService.GetFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(head.Position, aim.Unit * u.Range, params)
	local target = result and result.Position or (head.Position + aim.Unit * u.Range)
	-- drop onto the ground under that point
	local ground = workspace:Raycast(target + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), mapParams())
	if ground then
		target = ground.Position
	end
	notify:FireAllClients("AbilityFx", { kind = "StarfallMark", by = player, pos = target, radius = u.Radius, delay = u.Delay })
	player:SetAttribute("UltActive", true)
	task.delay(u.Delay, function()
		local dmg = HeroConfig.Damage(u.Damage, wave())
		for _, data in EnemyService.InRadius(target, u.Radius, true) do
			local away = data.root.Position - target
			hit(player, data, dmg, (away.Magnitude > 0 and away.Unit or Vector3.yAxis) + Vector3.new(0, 0.6, 0))
		end
		notify:FireAllClients("AbilityFx", { kind = "Starfall", by = player, pos = target, radius = u.Radius })
		if player.Parent then
			player:SetAttribute("UltActive", false)
		end
	end)
	return true
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------

local function onUse(player: Player, slot, aim)
	if (slot ~= "Ability" and slot ~= "Ultimate") or not isFiniteVector(aim) then
		return
	end
	if not PlayerService.IsAlive(player) then
		return
	end
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local hero = HeroConfig.Get(player:GetAttribute("Hero"))
	if slot == "Ability" then
		local now = os.clock()
		if now < (readyAt[player] or 0) then
			return
		end
		if cast[hero.Id](player, hero, root, aim) then
			local cd = hero.Ability.Cooldown * ProgressionConfig.CooldownMult(player) -- Overclock
			readyAt[player] = now + cd
			player:SetAttribute("AbilityReadyAt", workspace:GetServerTimeNow() + cd)
		end
	else
		if (player:GetAttribute("UltCharge") or 0) < HeroConfig.Ult.Max or player:GetAttribute("UltActive") then
			return
		end
		if ult[hero.Id](player, hero, root, aim) then
			setUlt(player, 0)
		end
	end
end

local function onSelect(player: Player, id)
	if typeof(id) ~= "string" or not HeroConfig.Heroes[id] then
		return
	end
	if gameState:GetAttribute("State") == "Wave" then
		notify:FireClient(player, "Message", { text = "Switch heroes between waves", tone = "bad" })
		return
	end
	if player:GetAttribute("Hero") == id then
		return
	end
	player:SetAttribute("Hero", id)
	-- fresh cooldown so swapping can't be used to reset it
	readyAt[player] = os.clock() + 2
	player:SetAttribute("AbilityReadyAt", workspace:GetServerTimeNow() + 2)
	local h = HeroConfig.Heroes[id]
	notify:FireClient(player, "Message", { text = h.Name .. ", " .. h.Title .. "  ·  " .. h.Passive, tone = "good" })
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function AbilityService.Reset()
	for _, p in Players:GetPlayers() do
		setUlt(p, 0)
		p:SetAttribute("UltActive", false)
		readyAt[p] = 0
		p:SetAttribute("AbilityReadyAt", 0)
	end
end

-- Take `seconds` off the current ability cooldown (Vampiric Edge)
function AbilityService.Refund(player: Player, seconds: number)
	if not readyAt[player] then
		return
	end
	readyAt[player] -= seconds
	local at = (player:GetAttribute("AbilityReadyAt") or 0) - seconds
	player:SetAttribute("AbilityReadyAt", math.max(0, at))
end

function AbilityService.KnifeMult(player: Player): number
	return HeroConfig.Get(player:GetAttribute("Hero")).KnifeMult or 1
end

function AbilityService.Init()
	notify = Remotes.Get("Notify")
	gameState = Remotes.GameState()
end

function AbilityService.Start()
	RemoteGuard.Connect(Remotes.Get("UseAbility"), { rate = 4, burst = 3 }, onUse)
	RemoteGuard.Connect(Remotes.Get("SelectHero"), { rate = 2, burst = 2 }, onSelect)

	-- Ultimate charge from kills (not from kills made by an active ultimate)
	EnemyService.EnemyDied:Connect(function(data, killer, headshot)
		if not killer or not killer.Parent or killer:GetAttribute("UltActive") then
			return
		end
		local c = HeroConfig.Ult
		local gain = data.isElite and c.EliteKillCharge or (headshot and c.HeadshotKillCharge or c.KillCharge)
		gain *= HeroConfig.Get(killer:GetAttribute("Hero")).UltChargeMult or 1
		gain *= ProgressionConfig.UltChargeMult(killer) -- Overclock
		setUlt(killer, (killer:GetAttribute("UltCharge") or 0) + gain)
	end)

	local function setup(p)
		if not p:GetAttribute("Hero") then
			p:SetAttribute("Hero", HeroConfig.Default)
		end
		setUlt(p, 0)
		p:SetAttribute("AbilityReadyAt", 0)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		readyAt[p] = nil
	end)
end

return AbilityService
