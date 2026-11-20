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
-- PowerUpService requires WeaponService, which requires this module: load it in Start
-- (after every module has finished loading) to avoid a require cycle.
local PowerUpService

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
	st.count += isHeadshot and cfg.HeadshotPoints or 1
	local window = ProgressionConfig.StreakWindow(player)
	st.expires = now + window
	setStreakAttrs(player, st.count, math.min(cfg.MaxMult, 1 + cfg.PerKill * st.count), workspace:GetServerTimeNow() + window)

	-- Bloodthirst heal
	local heal = ProgressionConfig.HealPerKill(player)
	local hum = heal > 0 and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + heal)
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
	if id == "Vitality" then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.MaxHealth = maxHealthFor(player)
			hum.Health = math.min(hum.MaxHealth, hum.Health + 25)
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

local function rollOptions(player): { string }
	local pool = {}
	for id, def in ProgressionConfig.Upgrades do
		if ProgressionConfig.Count(player, id) < def.Max then
			table.insert(pool, id)
		end
	end
	local picks = {}
	for _ = 1, math.min(ProgressionConfig.Offer.Choices, #pool) do
		table.insert(picks, table.remove(pool, math.random(1, #pool)))
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
		local options = rollOptions(player)
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
	end
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

local function onEnemyDied(data, killer: Player?)
	if not data.isElite then
		return
	end
	local e = ProgressionConfig.Elite
	if killer and killer.Parent then
		CurrencyService.Add(killer, e.Points, "Elite", true)
		notify:FireAllClients("Message", { text = killer.DisplayName .. " slew an Elite", tone = "good" })
	end
	if e.DropPowerUp and data.root then
		local ids = powerUpIds()
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
		if bonus > 0 then
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
