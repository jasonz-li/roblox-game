--!nonstrict
-- Round state machine:
--   Waiting (no players) -> Intermission -> Wave N -> Intermission -> ... -> GameOver -> reset

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local EnemyConfig = require(game.ReplicatedStorage.Shared.Config.EnemyConfig)
local WaveConfig = require(game.ReplicatedStorage.Shared.Config.WaveConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local CurrencyService = require(script.Parent.CurrencyService)
local WeaponService = require(script.Parent.WeaponService)
local MapService = require(script.Parent.MapService)
local MysteryBoxService = require(script.Parent.MysteryBoxService)
local PowerUpService = require(script.Parent.PowerUpService)
local ProgressionService = require(script.Parent.ProgressionService)
local DataService = require(script.Parent.DataService)
local AbilityService = require(script.Parent.AbilityService)
local BossService = require(script.Parent.BossService)
local ThrowableService = require(script.Parent.ThrowableService)
local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)

local WaveService = {}

local gameState: Folder
local notify: RemoteEvent
local wave = 0
local gameOver = false
local killsThisWave = 0
local totalThisWave = 0
local bossDown = false

local function setState(state: string)
	gameState:SetAttribute("State", state)
end

local function updateRemaining()
	gameState:SetAttribute("EnemiesRemaining", math.max(0, totalThisWave - killsThisWave))
end

local function intermission(duration: number)
	setState("Intermission")
	gameState:SetAttribute("IntermissionEndsAt", workspace:GetServerTimeNow() + duration)
	task.wait(duration)
end

-- How strong the party's builds are (1 = fresh, up to 3). The Titan's health scales
-- with it so a fully forged, fully picked build still gets a real boss fight.
--   per player: 1 + 0.35 x best Forge level + 0.06 x upgrade picks + 0.05 x perks
local function partyPower(): number
	local total, n = 0, 0
	for _, p in Players:GetPlayers() do
		local forge = 0
		for i = 1, 3 do
			forge = math.max(forge, p:GetAttribute("Slot" .. i .. "Lvl") or 0)
		end
		local picks = 0
		for name, v in p:GetAttributes() do
			if name:sub(1, 4) == "Upg_" and typeof(v) == "number" then
				picks += v
			end
		end
		local perks = 0
		for _, id in string.split(p:GetAttribute("PerkOrder") or "", ",") do
			if id ~= "" then
				perks += 1
			end
		end
		total += 1 + 0.35 * forge + 0.06 * picks + 0.05 * perks
		n += 1
	end
	return n > 0 and math.clamp(total / n, 1, 3) or 1
end

local function runWave()
	wave += 1
	gameState:SetAttribute("Wave", wave)
	PlayerService.SpawnAllDead()

	local isBossWave = wave == GameConfig.Run.BossWave
	local escorts = WaveConfig.EnemyCount(wave, #Players:GetPlayers())
	totalThisWave = escorts + (isBossWave and 1 or 0)
	killsThisWave = 0
	bossDown = false
	updateRemaining()
	setState("Wave")
	notify:FireAllClients("WaveStart", {
		wave = wave,
		of = GameConfig.Run.Waves,
		elite = ProgressionConfig.IsEliteWave(wave),
		boss = isBossWave and EnemyConfig.Boss.DisplayName or nil,
	})

	-- First appearance of each special zombie: a one-line warning with how to beat it
	local intro = ({
		[3] = "Crawlers incoming: low and fast, aim down",
		[4] = "Brutes incoming: armored, go for the head",
		[5] = "Spitters incoming: kill them before the acid lands",
		[6] = "Exploders incoming: pop them inside the horde, not next to you",
	})[wave]
	if intro then
		task.delay(1.5, function()
			notify:FireAllClients("Message", { text = intro, tone = "bad" })
		end)
	end

	if isBossWave then
		-- The raid: the party drops into the Hollow and fights the Titan (BossService).
		-- No zombie escort; the fight is the mechanics.
		totalThisWave = 1
		updateRemaining()
		BossService.Run(wave, partyPower(), function()
			return gameOver
		end)
		while EnemyService.AliveCount() > 0 and not gameOver do
			task.wait(0.25)
		end
		return
	end

	local spawned = 0
	local interval = WaveConfig.SpawnInterval(wave)
	local eliteChance = ProgressionConfig.EliteChance(wave)
	local cap = math.min(EnemyConfig.MaxAlive, WaveConfig.AliveCap(escorts) + (isBossWave and 1 or 0))
	EnemyService.SetHunting(false)
	task.wait(WaveConfig.WaveStartDelay)
	while spawned < escorts and not gameOver do
		if EnemyService.AliveCount() < cap then
			local kind = WaveConfig.PickEnemy(wave, EnemyService.AliveOfType)
			if EnemyService.Spawn(kind, wave, { elite = kind == "Shambler" and math.random() < eliteChance }) then
				spawned += 1
				task.wait(interval * (0.75 + math.random() * 0.5)) -- ±25% jitter
			else
				task.wait(0.5) -- no valid spawn right now; try again shortly
			end
		else
			task.wait(0.25)
		end
	end
	-- Everything spawned: the last few zombies hunt you down instead of getting lost.
	while EnemyService.AliveCount() > 0 and not gameOver do
		if EnemyService.AliveCount() <= WaveConfig.HuntWhenRemaining then
			EnemyService.SetHunting(true)
		end
		task.wait(0.25)
	end
	EnemyService.SetHunting(false)
end

local function waveReward()
	local bonus = math.min(GameConfig.Points.WaveCompleteBase * wave, GameConfig.Points.WaveCompleteCap)
	for _, p in Players:GetPlayers() do
		CurrencyService.Add(p, bonus, "Wave survived")
	end
	if GameConfig.RefillAmmoOnWaveEnd then
		WeaponService.RefillAll()
	end
	ThrowableService.WaveComplete()
	notify:FireAllClients("WaveComplete", { wave = wave, bonus = bonus })
end

local function resetMatch()
	EnemyService.ClearAll()
	MapService.Reset() -- relock doors
	MysteryBoxService.Reset()
	PowerUpService.Reset()
	ProgressionService.Reset()
	AbilityService.Reset()
	BossService.Reset()
	ThrowableService.Reset()
	CurrencyService.ResetAll()
	wave = 0
	gameOver = false
	totalThisWave, killsThisWave = 0, 0
	gameState:SetAttribute("Wave", 0)
	updateRemaining()
	PlayerService.RespawnAll()
end

local function mainLoop()
	while true do
		resetMatch()
		while #Players:GetPlayers() == 0 do
			setState("Waiting")
			task.wait(1)
		end
		intermission(GameConfig.FirstIntermission)

		local victory = false
		while not gameOver do
			runWave()
			if gameOver then
				break
			end
			if wave >= GameConfig.Run.Waves then
				victory = true
				break
			end
			waveReward()
			local offered = ProgressionService.OfferUpgrades(wave)
			intermission(GameConfig.Intermission + (offered and ProgressionConfig.Offer.ExtraIntermission or 0))
		end

		gameState:SetAttribute("FinalWave", wave)
		gameState:SetAttribute("BossMax", 0)
		gameState:SetAttribute("RestartAt", workspace:GetServerTimeNow() + GameConfig.GameOverDuration)
		if victory then
			setState("Victory")
			for _, p in Players:GetPlayers() do
				DataService.AddShards(p, GameConfig.Run.VictoryShards, "Dustwater cleared")
			end
			-- wave + 1 so every wave counts as survived
			DataService.EndRun(wave + 1, ProgressionConfig.Rewards.ShardsPerWaveSurvived, true)
			notify:FireAllClients("Victory", { wave = wave })
		else
			setState("GameOver")
			DataService.EndRun(wave, ProgressionConfig.Rewards.ShardsPerWaveSurvived, false)
			notify:FireAllClients("GameOver", { wave = wave })
		end
		task.wait(GameConfig.GameOverDuration)
	end
end

function WaveService.GetWave(): number
	return wave
end

-- Studio testing only (DevService): the next wave to start will be `n`.
function WaveService.DevSetWave(n: number)
	wave = math.max(0, n - 1)
	gameState:SetAttribute("Wave", wave)
	return "next wave = " .. n
end

function WaveService.Init()
	gameState = Remotes.GameState()
	notify = Remotes.Get("Notify")
	gameState:SetAttribute("State", "Waiting")
	gameState:SetAttribute("Wave", 0)
	gameState:SetAttribute("EnemiesRemaining", 0)
end

function WaveService.Start()
	EnemyService.EnemyDied:Connect(function(data, killer)
		killsThisWave += 1
		updateRemaining()
		-- special zombies pay a bounty on top of the normal kill points
		local bonus = data.stats and data.stats.BonusPoints
		if bonus and killer and killer.Parent then
			CurrencyService.Add(killer, bonus, data.stats.DisplayName, true)
		end
		if data.isBoss then
			-- Titan down: every player is paid. The wave is NOT over: the rest of the
			-- escort still has to be cleared (it no longer crumbles with the Titan).
			bossDown = true
			gameState:SetAttribute("BossHealth", 0)
			for _, p in Players:GetPlayers() do
				CurrencyService.Add(p, EnemyConfig.Boss.Points, EnemyConfig.Boss.DisplayName .. " slain")
			end
			notify:FireAllClients("AbilityFx", { kind = "BossDown", pos = data.root.Position })
			notify:FireAllClients("Message", { text = "The Titan has fallen!", tone = "good" })
		end
	end)
	PlayerService.AllPlayersDead:Connect(function()
		if gameState:GetAttribute("State") == "Wave" then
			gameOver = true
		end
	end)
	task.spawn(mainLoop)
end

return WaveService
