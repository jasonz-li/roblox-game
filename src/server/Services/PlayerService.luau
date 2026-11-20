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
PlayerService.PlayerDowned = Signal.new() -- (player)
PlayerService.PlayerRevived = Signal.new() -- (player, by)

-- Lethal guards: functions(player, humanoid) -> true if they saved the player from a
-- killing blow (Second Chance pick, Phoenix perk). They run in order; first one wins.
PlayerService.LethalGuards = {}
-- Damage-taken multipliers: functions(player) -> number (Kaida's passive, War Cry)
PlayerService.DamageMultipliers = {}

-- All enemy damage to players goes through here (so guards can intercept death).
function PlayerService.Damage(character: Model, amount: number)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		for _, fn in PlayerService.DamageMultipliers do
			amount *= fn(player)
		end
	end
	if player and player:GetAttribute("Downed") then
		return -- downed players are out of the fight; they bleed out on a timer
	end
	if hum.Health - amount <= 0 then
		if player then
			for _, guard in PlayerService.LethalGuards do
				if guard(player, hum) then
					return
				end
			end
			-- Co-op: with a teammate still standing, you go DOWN instead of dying
			if PlayerService.CanGoDown(player) then
				PlayerService.Down(player)
				return
			end
		end
	end
	hum:TakeDamage(amount)
end

----------------------------------------------------------------------
-- Downed & revive (co-op). Downed players crawl, zombies ignore them, and they
-- bleed out after BLEED_OUT seconds unless a teammate holds E next to them for
-- REVIVE_TIME. Solo (or the last one standing) there is no downed state: you die.
----------------------------------------------------------------------

local BLEED_OUT = 30
local REVIVE_TIME = 3
local REVIVE_RANGE = 7

local function standing(p: Player): boolean
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not p:GetAttribute("Downed")
end

function PlayerService.CanGoDown(player: Player): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player and standing(other) then
			return true
		end
	end
	return false
end

function PlayerService.Down(player: Player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.Health = 1
	player:SetAttribute("Downed", true)
	player:SetAttribute("DownedUntil", workspace:GetServerTimeNow() + BLEED_OUT)
	player:SetAttribute("ReviveProgress", 0)
	PlayerService.PlayerDowned:Fire(player)
	local token = {}
	player:SetAttribute("DownToken", tostring(token))
	local tokenStr = tostring(token)
	task.delay(BLEED_OUT, function()
		if player:GetAttribute("Downed") and player:GetAttribute("DownToken") == tokenStr then
			player:SetAttribute("Downed", false)
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h then
				h.Health = 0 -- bled out
			end
		end
	end)
	task.defer(function()
		-- everyone else may be down too: that's a wipe
		local any = false
		for _, p in Players:GetPlayers() do
			if standing(p) then
				any = true
			end
		end
		if not any then
			PlayerService.AllPlayersDead:Fire()
		end
	end)
end

function PlayerService.Revive(player: Player, by: Player?)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or not player:GetAttribute("Downed") then
		return
	end
	player:SetAttribute("Downed", false)
	player:SetAttribute("ReviveProgress", 0)
	hum.Health = hum.MaxHealth * 0.5
	PlayerService.PlayerRevived:Fire(player, by)
end

-- Alive or downed (last stand): downed players can still shoot, with limited ammo.
function PlayerService.CanShoot(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil
end

-- Standing AND not downed: zombies ignore downed players; no knife/abilities while down.
function PlayerService.IsAlive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil and not player:GetAttribute("Downed")
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
			if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and not player:GetAttribute("Downed") and os.clock() - lastHit >= cfg.RegenDelay * ProgressionConfig.RegenDelayMult(player) then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + cfg.RegenPerSecond * dt)
				lastHealth = humanoid.Health
			end
		end
	end)

	humanoid.Died:Connect(function()
		player:SetAttribute("Downed", false)
		PlayerService.PlayerDied:Fire(player)
		task.defer(checkAllDead)
	end)

	player:SetAttribute("Downed", false)
	player:SetAttribute("ReviveProgress", 0)
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

	-- Revive: the same "hold E" input as window repair (RepairHold remote). While a
	-- standing player holds E within range of a downed teammate, progress fills.
	local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
	local holding = {} -- [Player] = true
	Remotes.Get("RepairHold").OnServerEvent:Connect(function(p, h)
		holding[p] = h == true or nil
	end)
	Players.PlayerRemoving:Connect(function(p)
		holding[p] = nil
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(0.1)
			local beingRevived = {}
			for reviver in holding do
				local r = reviver.Character and reviver.Character:FindFirstChild("HumanoidRootPart")
				if r and standing(reviver) then
					local best, bd = nil, REVIVE_RANGE
					for _, p in Players:GetPlayers() do
						local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
						if p ~= reviver and p:GetAttribute("Downed") and pr then
							local d = (pr.Position - r.Position).Magnitude
							if d <= bd then
								best, bd = p, d
							end
						end
					end
					if best then
						beingRevived[best] = reviver
					end
				end
			end
			for _, p in Players:GetPlayers() do
				if p:GetAttribute("Downed") then
					local by = beingRevived[p]
					if by then
						local prog = (p:GetAttribute("ReviveProgress") or 0) + dt / REVIVE_TIME
						if prog >= 1 then
							PlayerService.Revive(p, by)
						else
							p:SetAttribute("ReviveProgress", prog)
						end
					elseif (p:GetAttribute("ReviveProgress") or 0) > 0 then
						p:SetAttribute("ReviveProgress", 0) -- let go: start over
					end
				end
			end
		end
	end)
end

return PlayerService
