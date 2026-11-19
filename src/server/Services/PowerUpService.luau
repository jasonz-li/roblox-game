--!nonstrict
-- Power-up drops from player kills: Max Ammo, Double Points, Insta-Kill, Nuke.
-- Timed effects are stored as GameState attributes (<Id>Until = server time) so
-- the HUD can show countdowns and WeaponService/CurrencyService can read them.

local Players = game:GetService("Players")

local PowerUpConfig = require(game.ReplicatedStorage.Shared.Config.PowerUpConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local EnemyService = require(script.Parent.EnemyService)
local WeaponService = require(script.Parent.WeaponService)
local CurrencyService = require(script.Parent.CurrencyService)
local PlayerService = require(script.Parent.PlayerService)

local PowerUpService = {}

local folder: Folder
local gameState: Folder
local notify: RemoteEvent
local dropsThisWave, dropWave, lastDropAt = 0, -1, 0

local function pickId(): string
	local total = 0
	for _, p in PowerUpConfig.PowerUps do
		total += p.Weight
	end
	local r = math.random() * total
	for id, p in PowerUpConfig.PowerUps do
		r -= p.Weight
		if r <= 0 then
			return id
		end
	end
	return "MaxAmmo"
end

local function apply(id: string, picker: Player)
	local def = PowerUpConfig.PowerUps[id]
	if id == "MaxAmmo" then
		WeaponService.RefillAll()
	elseif id == "DoublePoints" or id == "InstaKill" then
		gameState:SetAttribute(id .. "Until", workspace:GetServerTimeNow() + def.Duration)
	elseif id == "Nuke" then
		EnemyService.KillAll()
		for _, p in Players:GetPlayers() do
			CurrencyService.Add(p, PowerUpConfig.NukePoints, "Nuke")
		end
	end
	notify:FireAllClients("PowerUp", { id = id, name = def.DisplayName, by = picker.DisplayName })
end

local function spawnDrop(id: string, position: Vector3)
	local def = PowerUpConfig.PowerUps[id]
	local p = Instance.new("Part")
	p.Name = "PowerUp_" .. id
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 2
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = def.Color
	p.Position = Vector3.new(position.X, 2.2, position.Z)
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = p
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 34)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 20
	label.TextColor3 = def.Color
	label.TextStrokeTransparency = 0.3
	label.Text = def.DisplayName
	label.Parent = bb
	p.Parent = folder

	local taken = false
	p.Touched:Connect(function(hit)
		if taken then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and PlayerService.IsAlive(player) then
			taken = true
			p:Destroy()
			apply(id, player)
		end
	end)

	-- Blink during the last 5 seconds, then vanish.
	task.delay(PowerUpConfig.Lifetime - 5, function()
		for i = 1, 20 do
			if taken or not p.Parent then
				return
			end
			p.Transparency = (i % 2 == 0) and 0 or 0.8
			task.wait(0.25)
		end
		if not taken and p.Parent then
			p:Destroy()
		end
	end)
end

local function onEnemyDied(data, killer)
	if not killer then
		return -- nukes etc. don't chain drops
	end
	local wave = gameState:GetAttribute("Wave") or 0
	if wave ~= dropWave then
		dropWave, dropsThisWave = wave, 0
	end
	local now = os.clock()
	if dropsThisWave >= PowerUpConfig.MaxDropsPerWave or now - lastDropAt < PowerUpConfig.MinSecondsBetweenDrops then
		return
	end
	if math.random() > PowerUpConfig.DropChance then
		return
	end
	dropsThisWave += 1
	lastDropAt = now
	spawnDrop(pickId(), data.root.Position)
end

-- For testing / admin: force a drop at a position.
function PowerUpService.ForceDrop(id: string, position: Vector3)
	spawnDrop(id, position)
end

function PowerUpService.Reset()
	folder:ClearAllChildren()
	gameState:SetAttribute("DoublePointsUntil", 0)
	gameState:SetAttribute("InstaKillUntil", 0)
	dropsThisWave, dropWave = 0, -1
end

function PowerUpService.Init()
	gameState = Remotes.GameState()
	notify = Remotes.Get("Notify")
	folder = Instance.new("Folder")
	folder.Name = "PowerUps"
	folder.Parent = workspace
	gameState:SetAttribute("DoublePointsUntil", 0)
	gameState:SetAttribute("InstaKillUntil", 0)
end

function PowerUpService.Start()
	EnemyService.EnemyDied:Connect(onEnemyDied)
end

return PowerUpService
