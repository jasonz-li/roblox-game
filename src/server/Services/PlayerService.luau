--!nonstrict
-- Manual character spawning and alive tracking.
-- Dead players stay dead until the next wave starts (zombies-style), and
-- AllPlayersDead fires when nobody in the server is alive.

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)
local Signal = require(game.ReplicatedStorage.Shared.Util.Signal)
local MapService = require(script.Parent.MapService)

local PlayerService = {}
PlayerService.CharacterSpawned = Signal.new() -- (player, character)
PlayerService.PlayerDied = Signal.new() -- (player)
PlayerService.AllPlayersDead = Signal.new()

-- Lethal guards: functions(player, humanoid) -> true if they saved the player from a
-- killing blow (Second Chance pick, Phoenix perk). They run in order; first one wins.
PlayerService.LethalGuards = {}

-- All enemy damage to players goes through here (so guards can intercept death).
function PlayerService.Damage(character: Model, amount: number)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	if hum.Health - amount <= 0 then
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			for _, guard in PlayerService.LethalGuards do
				if guard(player, hum) then
					return
				end
			end
		end
	end
	hum:TakeDamage(amount)
end

function PlayerService.IsAlive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil
end

function PlayerService.GetAliveCharacters(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if PlayerService.IsAlive(p) then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function checkAllDead()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	for _, p in players do
		if PlayerService.IsAlive(p) then
			return
		end
	end
	PlayerService.AllPlayersDead:Fire()
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	humanoid.MaxHealth = GameConfig.Player.MaxHealth
	humanoid.Health = GameConfig.Player.MaxHealth
	humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	humanoid.BreakJointsOnDeath = false

	-- Collision group so enemy corpses pass through players.
	local function setGroup(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)

	task.defer(function()
		if root.Parent then
			character:PivotTo(MapService.GetPlayerSpawnCFrame())
		end
	end)

	-- Health regen (zombies-style): no healing for RegenDelay after a hit, then fast.
	-- Replaces Roblox's default slow "Health" script.
	local defaultRegen = character:FindFirstChild("Health")
	if defaultRegen and defaultRegen:IsA("Script") then
		defaultRegen:Destroy()
	end
	local cfg = GameConfig.Player
	local lastHealth, lastHit = humanoid.Health, 0
	humanoid.HealthChanged:Connect(function(h)
		if h < lastHealth - 0.01 then
			lastHit = os.clock()
		end
		lastHealth = h
	end)
	task.spawn(function()
		while humanoid.Parent and humanoid.Health > 0 do
			local dt = task.wait(0.1)
			if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and os.clock() - lastHit >= cfg.RegenDelay * ProgressionConfig.RegenDelayMult(player) then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + cfg.RegenPerSecond * dt)
				lastHealth = humanoid.Health
			end
		end
	end)

	humanoid.Died:Connect(function()
		PlayerService.PlayerDied:Fire(player)
		task.defer(checkAllDead)
	end)

	PlayerService.CharacterSpawned:Fire(player, character)
end

function PlayerService.Spawn(player: Player)
	if player.Parent then
		player:LoadCharacter()
	end
end

function PlayerService.SpawnAllDead()
	for _, p in Players:GetPlayers() do
		if not PlayerService.IsAlive(p) then
			task.spawn(PlayerService.Spawn, p)
		end
	end
end

function PlayerService.RespawnAll()
	for _, p in Players:GetPlayers() do
		task.spawn(PlayerService.Spawn, p)
	end
end

function PlayerService.Init()
	Players.CharacterAutoLoads = false
end

function PlayerService.Start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacterAdded(player, char)
		end)
		PlayerService.Spawn(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function()
		task.defer(checkAllDead)
	end)
end

return PlayerService
