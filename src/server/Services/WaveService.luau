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

local WaveService = {}

local gameState: Folder
local notify: RemoteEvent
local wave = 0
local gameOver = false
local killsThisWave = 0
local totalThisWave = 0

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

local function runWave()
	wave += 1
	gameState:SetAttribute("Wave", wave)
	PlayerService.SpawnAllDead()

	totalThisWave = WaveConfig.EnemyCount(wave, #Players:GetPlayers())
	killsThisWave = 0
	updateRemaining()
	setState("Wave")
	notify:FireAllClients("WaveStart", { wave = wave })

	local spawned = 0
	local interval = WaveConfig.SpawnInterval(wave)
	while spawned < totalThisWave and not gameOver do
		if EnemyService.AliveCount() < EnemyConfig.MaxAlive then
			if EnemyService.Spawn("Shambler", wave) then
				spawned += 1
				task.wait(interval)
			else
				task.wait(0.5) -- no valid spawn right now; try again shortly
			end
		else
			task.wait(0.25)
		end
	end
	while EnemyService.AliveCount() > 0 and not gameOver do
		task.wait(0.25)
	end
end

local function waveReward()
	local bonus = math.min(GameConfig.Points.WaveCompleteBase * wave, GameConfig.Points.WaveCompleteCap)
	for _, p in Players:GetPlayers() do
		CurrencyService.Add(p, bonus, "Wave survived")
	end
	if GameConfig.RefillAmmoOnWaveEnd then
		WeaponService.RefillAll()
	end
	notify:FireAllClients("WaveComplete", { wave = wave, bonus = bonus })
end

local function resetMatch()
	EnemyService.ClearAll()
	MapService.Reset() -- relock doors
	MysteryBoxService.Reset()
	PowerUpService.Reset()
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

		while not gameOver do
			runWave()
			if gameOver then
				break
			end
			waveReward()
			intermission(GameConfig.Intermission)
		end

		setState("GameOver")
		gameState:SetAttribute("FinalWave", wave)
		gameState:SetAttribute("RestartAt", workspace:GetServerTimeNow() + GameConfig.GameOverDuration)
		notify:FireAllClients("GameOver", { wave = wave })
		task.wait(GameConfig.GameOverDuration)
	end
end

function WaveService.GetWave(): number
	return wave
end

function WaveService.Init()
	gameState = Remotes.GameState()
	notify = Remotes.Get("Notify")
	gameState:SetAttribute("State", "Waiting")
	gameState:SetAttribute("Wave", 0)
	gameState:SetAttribute("EnemiesRemaining", 0)
end

function WaveService.Start()
	EnemyService.EnemyDied:Connect(function()
		killsThisWave += 1
		updateRemaining()
	end)
	PlayerService.AllPlayersDead:Connect(function()
		if gameState:GetAttribute("State") == "Wave" then
			gameOver = true
		end
	end)
	task.spawn(mainLoop)
end

return WaveService
