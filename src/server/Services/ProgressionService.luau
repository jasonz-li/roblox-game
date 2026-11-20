--!nonstrict
-- In-run progression (server-authoritative):
--   * Kill streaks: chained kills raise a points multiplier; a zombie hit ends it.
--   * Upgrade picks: every few waves each player picks 1 of 3 run upgrades.
--   * Elite rewards: bonus points + a power-up for killing an elite.
-- Replicated player attributes:
--   StreakCount, StreakMult, StreakEnds (server time)  — streak HUD
--   Upg_<Id> = stacks                                   — owned upgrades
--   UpgradeOffer = "Id,Id,Id" ("" = none), UpgradeOfferEnds (server time)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)
local PowerUpConfig = require(game.ReplicatedStorage.Shared.Config.PowerUpConfig)
local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local RemoteGuard = require(script.Parent.Parent.Util.RemoteGuard)
local PlayerService = require(script.Parent.PlayerService)
local CurrencyService = require(script.Parent.CurrencyService)
local EnemyService = require(script.Parent.EnemyService)
local DataService = require(script.Parent.DataService)
-- PowerUpService requires WeaponService, which requires this module: load it in Start
-- (after every module has finished loading) to avoid a require cycle.
local PowerUpService
local WeaponService -- same reason (WeaponService requires this module)

local ProgressionService = {}

local notify: RemoteEvent
local streaks = {} -- [Player] = { count, expires (os.clock) }
local offers = {} -- [Player] = { options = {ids}, token }

----------------------------------------------------------------------
-- Streaks
----------------------------------------------------------------------

local function setStreakAttrs(player, count, mult, endsAt)
	player:SetAttribute("StreakCount", count)
	player:SetAttribute("StreakMult", mult)
	player:SetAttribute("StreakEnds", endsAt)
end

function ProgressionService.BreakStreak(player: Player)
	if streaks[player] and streaks[player].count > 0 then
		streaks[player] = nil
		setStreakAttrs(player, 0, 1, 0)
	end
end

-- Call on every kill BEFORE awarding points. Returns the multiplier for this kill
-- (streak x upgrade), so the first kill of a streak is x1.
function ProgressionService.OnKill(player: Player, isHeadshot: boolean): number
	local cfg = ProgressionConfig.Streak
	local now = os.clock()
	local st = streaks[player]
	if not st or now > st.expires then
		st = { count = 0, expires = 0 }
		streaks[player] = st
	end
	local mult = math.min(cfg.MaxMult, 1 + cfg.PerKill * st.count)
	local before = st.count
	st.count += isHeadshot and cfg.HeadshotPoints or 1
	local window = ProgressionConfig.StreakWindow(player)
	st.expires = now + window
	setStreakAttrs(player, st.count, math.min(cfg.MaxMult, 1 + cfg.PerKill * st.count), workspace:GetServerTimeNow() + window)

	DataService.AddKill(player)
	if st.count > (player:GetAttribute("RunBestStreak") or 0) then
		player:SetAttribute("RunBestStreak", st.count)
	end
	local record = DataService.RecordStreak(player, st.count)

	-- Milestones crossed by this kill (headshots add 2, so check the range)
	local last = cfg.Milestones[#cfg.Milestones]
	for _, m in cfg.Milestones do
		if before < m.At and st.count >= m.At then
			DataService.AddShards(player, m.Shards, "Streak " .. m.At)
			if m.Uav then
				local untilT = math.max(player:GetAttribute("UavUntil") or 0, workspace:GetServerTimeNow()) + m.Uav
				player:SetAttribute("UavUntil", untilT)
			end
			notify:FireClient(player, "StreakMilestone", { at = m.At, label = m.Label, shards = m.Shards, uav = m.Uav, record = record })
		end
	end
	if st.count > last.At then
		local steps = math.floor((st.count - last.At) / cfg.RepeatEvery)
		local prevSteps = before > last.At and math.floor((before - last.At) / cfg.RepeatEvery) or 0
		if steps > prevSteps then
			local at = last.At + steps * cfg.RepeatEvery
			DataService.AddShards(player, cfg.RepeatShards, "Streak " .. at)
			notify:FireClient(player, "StreakMilestone", { at = at, label = "GODLIKE", shards = cfg.RepeatShards, record = record })
		end
	end

	-- Bloodthirst heal
	local heal = ProgressionConfig.HealPerKill(player)
	local hum = heal > 0 and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + heal)
	end
	-- Adrenaline: speed burst (the client applies it from this attribute)
	if ProgressionConfig.Count(player, "Adrenaline") > 0 then
		player:SetAttribute("AdrenalineUntil", workspace:GetServerTimeNow() + 3)
	end
	-- Scavenger: chance to load rounds straight into the magazine
	local scav = ProgressionConfig.Count(player, "Scavenger")
	if scav > 0 and WeaponService and math.random() < 0.15 * (scav + 1) then
		WeaponService.AddMag(player, 3)
	end

	return mult * ProgressionConfig.PointsMult(player)
end

local function streakSweep()
	local now = os.clock()
	for player, st in streaks do
		if now > st.expires then
			streaks[player] = nil
			if player.Parent then
				setStreakAttrs(player, 0, 1, 0)
			end
		end
	end
end

----------------------------------------------------------------------
-- Upgrades
----------------------------------------------------------------------

local function maxHealthFor(player)
	local base = player:GetAttribute(PerkConfig.AttributeName("IronBody")) and PerkConfig.IronBodyHealth or GameConfig.Player.MaxHealth
	return base + ProgressionConfig.BonusHealth(player)
end

local function apply(player: Player, id: string)
	local def = ProgressionConfig.Upgrades[id]
	player:SetAttribute("Upg_" .. id, ProgressionConfig.Count(player, id) + 1)
	if id == "Vitality" or id == "GlassCannon" then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.MaxHealth = maxHealthFor(player)
			hum.Health = math.min(hum.MaxHealth, hum.Health + (id == "Vitality" and 25 or 0))
		end
	end
	notify:FireClient(player, "UpgradeChosen", { id = id, name = def.Name, stacks = ProgressionConfig.Count(player, id) })
	notify:FireClient(player, "Sound", { name = "PerkDrink" })
end

local function clearOffer(player)
	offers[player] = nil
	player:SetAttribute("UpgradeOffer", "")
	player:SetAttribute("UpgradeOfferEnds", 0)
end

-- Each card rolls a rarity first (legendaries get likelier every wave), then a
-- not-yet-maxed upgrade of that rarity; falls back to any rarity if that pool is empty.
local RARITY_ORDER = { "Legendary", "Cursed", "Rare", "Common" }
local function rollRarity(wave: number): string
	local r = ProgressionConfig.Rarity
	local w = table.clone(r.Weights)
	w.Legendary += r.LegendaryPerWave * math.max(0, wave - 1)
	local total = 0
	for _, v in w do
		total += v
	end
	local x = math.random() * total
	for _, name in RARITY_ORDER do
		x -= w[name]
		if x <= 0 then
			return name
		end
	end
	return "Common"
end

local function rollOptions(player, wave: number): { string }
	local byRarity, all = {}, {}
	for id, def in ProgressionConfig.Upgrades do
		if ProgressionConfig.Count(player, id) < def.Max then
			byRarity[def.Rarity] = byRarity[def.Rarity] or {}
			table.insert(byRarity[def.Rarity], id)
			table.insert(all, id)
		end
	end
	local picks, used = {}, {}
	for _ = 1, ProgressionConfig.Offer.Choices do
		local pool = {}
		for _, id in byRarity[rollRarity(wave)] or {} do
			if not used[id] then
				table.insert(pool, id)
			end
		end
		if #pool == 0 then
			for _, id in all do
				if not used[id] then
					table.insert(pool, id)
				end
			end
		end
		if #pool == 0 then
			break
		end
		local id = pool[math.random(1, #pool)]
		used[id] = true
		table.insert(picks, id)
	end
	return picks
end

local function choose(player: Player, index: number)
	local offer = offers[player]
	if not offer then
		return
	end
	local id = offer.options[index]
	if not id then
		return
	end
	clearOffer(player)
	apply(player, id)
end

-- Called by WaveService after a wave is cleared. Returns true if picks were offered.
function ProgressionService.OfferUpgrades(wave: number): boolean
	if wave <= 0 or wave % ProgressionConfig.Offer.EveryWaves ~= 0 then
		return false
	end
	local seconds = ProgressionConfig.Offer.Seconds
	local offered = false
	for _, player in Players:GetPlayers() do
		local options = rollOptions(player, wave)
		if #options > 0 then
			offered = true
			local token = {}
			offers[player] = { options = options, token = token }
			player:SetAttribute("UpgradeOffer", table.concat(options, ","))
			player:SetAttribute("UpgradeOfferEnds", workspace:GetServerTimeNow() + seconds)
			notify:FireClient(player, "Sound", { name = "BoxJingle" })
			task.delay(seconds, function()
				local o = offers[player]
				if o and o.token == token then
					choose(player, math.random(1, #o.options)) -- didn't pick: random
				end
			end)
		end
	end
	return offered
end

function ProgressionService.Reset()
	for _, player in Players:GetPlayers() do
		clearOffer(player)
		for id in ProgressionConfig.Upgrades do
			player:SetAttribute("Upg_" .. id, nil)
		end
		streaks[player] = nil
		setStreakAttrs(player, 0, 1, 0)
		player:SetAttribute("RunBestStreak", 0)
		player:SetAttribute("UavUntil", 0)
	end
	DataService.StartRun()
end

----------------------------------------------------------------------
-- Elite rewards
----------------------------------------------------------------------

local function powerUpIds()
	local ids = {}
	for id in PowerUpConfig.PowerUps do
		table.insert(ids, id)
	end
	return ids
end

-- Volatile Rounds: the killer's kills explode. Blast kills only chain with Chain Reaction.
local function volatile(data, killer: Player?)
	if not killer or not killer.Parent then
		return
	end
	local n = ProgressionConfig.Count(killer, "Volatile")
	if n == 0 or not data.deathPosition then
		return
	end
	if data.lastHitTag == "blast" and ProgressionConfig.Count(killer, "ChainReaction") == 0 then
		return
	end
	local wave = Remotes.GameState():GetAttribute("Wave") or 1
	local radius = (6 + 2 * n) * ProgressionConfig.BlastRadiusMult(killer)
	local damage = (60 + 25 * wave) * n
	task.defer(function()
		EnemyService.Explode(data.deathPosition, radius, damage, killer, function()
			CurrencyService.AddKill(killer)
			local mult = ProgressionService.OnKill(killer, false)
			CurrencyService.Add(killer, math.floor(GameConfig.Points.Kill * mult), "Chain blast", true)
		end, Color3.fromRGB(255, 140, 40))
	end)
end

local function onEnemyDied(data, killer: Player?)
	volatile(data, killer)
	if not data.isElite then
		return
	end
	local e = ProgressionConfig.Elite
	if killer and killer.Parent then
		CurrencyService.Add(killer, e.Points, "Elite", true)
		DataService.AddShards(killer, ProgressionConfig.Rewards.ShardsPerElite, "Elite kill")
		notify:FireAllClients("Message", { text = killer.DisplayName .. " slew an Elite", tone = "good" })
	end
	if e.DropPowerUp and data.root and math.random() < (e.DropChance or 1) then
		local ids = e.DropPool or powerUpIds()
		PowerUpService.ForceDrop(ids[math.random(1, #ids)], data.root.Position)
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function ProgressionService.Init()
	notify = Remotes.Get("Notify")
end

function ProgressionService.Start()
	PowerUpService = require(script.Parent.PowerUpService)
	WeaponService = require(script.Parent.WeaponService)
	RemoteGuard.Connect(Remotes.Get("ChooseUpgrade"), { rate = 4, burst = 2 }, function(player, index)
		if typeof(index) == "number" and index == math.floor(index) then
			choose(player, index)
		end
	end)

	-- Upgrades survive going down: re-apply bonus health on respawn; hits end the streak.
	PlayerService.CharacterSpawned:Connect(function(player, character)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		local bonus = ProgressionConfig.BonusHealth(player)
		if bonus ~= 0 then -- (Glass Cannon makes it negative)
			hum.MaxHealth = maxHealthFor(player)
			hum.Health = hum.MaxHealth
		end
		local last = hum.Health
		hum.HealthChanged:Connect(function(h)
			if h < last - 0.5 and ProgressionConfig.Streak.BreakOnHit then
				ProgressionService.BreakStreak(player)
			end
			last = h
		end)
	end)
	PlayerService.PlayerDied:Connect(ProgressionService.BreakStreak)

	-- Second Chance (legendary pick): once per wave, a lethal hit heals you to 60%
	-- and blasts everything around you.
	table.insert(PlayerService.LethalGuards, function(player, hum)
		if ProgressionConfig.Count(player, "SecondChance") == 0 then
			return false
		end
		local wave = Remotes.GameState():GetAttribute("Wave") or 0
		if player:GetAttribute("SecondChanceWave") == wave then
			return false
		end
		player:SetAttribute("SecondChanceWave", wave)
		hum.Health = hum.MaxHealth * 0.6
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			EnemyService.Explode(root.Position, 18, 400 + 120 * wave, player, nil, Color3.fromRGB(255, 230, 120))
		end
		notify:FireClient(player, "Message", { text = "SECOND CHANCE", tone = "good" })
		notify:FireClient(player, "Impact", { tier = "heavy" })
		return true
	end)

	EnemyService.EnemyDied:Connect(onEnemyDied)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			streakSweep()
		end
	end)

	Players.PlayerAdded:Connect(function(p)
		setStreakAttrs(p, 0, 1, 0)
		p:SetAttribute("UpgradeOffer", "")
	end)
	Players.PlayerRemoving:Connect(function(p)
		streaks[p] = nil
		offers[p] = nil
	end)
end

return ProgressionService
