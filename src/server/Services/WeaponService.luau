--!nonstrict
-- Server-authoritative weapons: ammo, reload, fire-rate limits, hit validation, damage.
-- See docs/TECHNICAL_ARCHITECTURE.md §3 for the hit-registration model.

local Players = game:GetService("Players")

local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local CurrencyService = require(script.Parent.CurrencyService)
local MapService = require(script.Parent.MapService)

local WeaponService = {}

local MAX_ORIGIN_OFFSET = 10 -- studs between claimed origin and server-side head
local HIT_TOLERANCE = 6 -- studs a claimed hit may be off the ray (latency allowance)

local states = {} -- [Player] = state
local hitConfirm: RemoteEvent
local shotFx: RemoteEvent

local function isFiniteVector(v)
	return typeof(v) == "Vector3"
		and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function syncAttributes(player, state)
	player:SetAttribute("WeaponId", state.stats.Id)
	player:SetAttribute("Ammo", state.mag)
	player:SetAttribute("Reserve", state.reserve)
	player:SetAttribute("Reloading", state.reloading)
end

local function giveWeapon(player: Player, weaponId: string)
	local stats = WeaponConfig.Get(weaponId)
	local prev = states[player]
	local state = {
		stats = stats,
		mag = stats.MagSize,
		reserve = stats.ReserveAmmo,
		reloading = false,
		reloadToken = 0,
		lastShot = 0,
		recentShots = {},
		generation = (prev and prev.generation or 0) + 1,
	}
	states[player] = state
	syncAttributes(player, state)
end

-- Fire-rate budget: tolerate network bunching, reject speed hacks.
local function passesRateLimit(state, now): boolean
	local interval = 60 / state.stats.RPM
	if now - state.lastShot < interval * 0.5 then
		return false
	end
	local shots = state.recentShots
	local i = 1
	while i <= #shots do
		if now - shots[i] > 1 then
			table.remove(shots, i)
		else
			i += 1
		end
	end
	local maxPerSecond = math.ceil((state.stats.RPM / 60) * 1.25) + 1
	if #shots >= maxPerSecond then
		return false
	end
	table.insert(shots, now)
	state.lastShot = now
	return true
end

local function characterExcludeList()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function resolveHit(origin, direction, range, claimedPart)
	-- 1) Server's own ray (excluding all player characters)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterExcludeList()
	local result = workspace:Raycast(origin, direction * range, params)
	local hitPart = result and result.Instance
	local endPos = result and result.Position or (origin + direction * range)

	if hitPart and EnemyService.GetEnemyFromPart(hitPart) then
		return hitPart, endPos
	end

	-- 2) Validate the client's claim (favor the shooter, within tolerance)
	if typeof(claimedPart) == "Instance" and claimedPart:IsA("BasePart") then
		local enemy = EnemyService.GetEnemyFromPart(claimedPart)
		if enemy then
			local toPart = claimedPart.Position - origin
			local along = toPart:Dot(direction)
			if along > 0 and along <= range then
				local offRay = (toPart - direction * along).Magnitude
				if offRay <= HIT_TOLERANCE then
					local mapParams = RaycastParams.new()
					mapParams.FilterType = Enum.RaycastFilterType.Include
					mapParams.FilterDescendantsInstances = { MapService.GetMapFolder() }
					local wall = workspace:Raycast(origin, direction * along, mapParams)
					if not wall then
						return claimedPart, origin + direction * along
					end
				end
			end
		end
	end

	return hitPart, endPos
end

local function onFire(player: Player, origin, direction, claimedPart)
	if not isFiniteVector(origin) or not isFiniteVector(direction) then
		return
	end
	local mag = direction.Magnitude
	if mag < 0.9 or mag > 1.1 then
		return
	end
	direction = direction.Unit

	local state = states[player]
	if not state or state.reloading or state.mag <= 0 then
		return
	end
	if not PlayerService.IsAlive(player) then
		return
	end
	local head = player.Character:FindFirstChild("Head")
	if not head or (head.Position - origin).Magnitude > MAX_ORIGIN_OFFSET then
		return
	end
	if not passesRateLimit(state, os.clock()) then
		return
	end

	state.mag -= 1
	player:SetAttribute("Ammo", state.mag)

	local stats = state.stats
	local hitPart, endPos = resolveHit(origin, direction, stats.Range, claimedPart)

	for _, other in Players:GetPlayers() do
		if other ~= player then
			shotFx:FireClient(other, player, origin, endPos)
		end
	end

	local enemy = hitPart and EnemyService.GetEnemyFromPart(hitPart)
	if not enemy then
		return
	end
	local isHeadshot = hitPart.Name == "Head"
	local damage = stats.Damage * (isHeadshot and stats.HeadshotMultiplier or 1)
	local killed = EnemyService.Damage(enemy, damage, player, isHeadshot)

	CurrencyService.Add(player, GameConfig.Points.Hit)
	if killed then
		CurrencyService.AddKill(player)
		CurrencyService.Add(player, isHeadshot and GameConfig.Points.HeadshotKill or GameConfig.Points.Kill, isHeadshot and "Headshot" or "Kill")
	end
	hitConfirm:FireClient(player, isHeadshot, killed, damage)
end

local function onReload(player: Player)
	local state = states[player]
	if not state or state.reloading or not PlayerService.IsAlive(player) then
		return
	end
	if state.mag >= state.stats.MagSize or state.reserve <= 0 then
		return
	end
	state.reloading = true
	state.reloadToken += 1
	local token, generation = state.reloadToken, state.generation
	player:SetAttribute("Reloading", true)

	task.delay(state.stats.ReloadTime, function()
		local current = states[player]
		if current ~= state or state.generation ~= generation or state.reloadToken ~= token then
			return
		end
		if PlayerService.IsAlive(player) then
			local take = math.min(state.stats.MagSize - state.mag, state.reserve)
			state.mag += take
			state.reserve -= take
		end
		state.reloading = false
		syncAttributes(player, state)
	end)
end

-- PLACEHOLDER "max ammo" until ammo purchases/power-ups exist (Milestone 2).
function WeaponService.RefillAll()
	for player, state in states do
		state.reserve = state.stats.ReserveAmmo
		syncAttributes(player, state)
	end
end

function WeaponService.Init()
	hitConfirm = Remotes.Get("HitConfirm")
	shotFx = Remotes.Get("ShotFx")
end

function WeaponService.Start()
	Remotes.Get("Fire").OnServerEvent:Connect(onFire)
	Remotes.Get("Reload").OnServerEvent:Connect(onReload)

	-- Fresh loadout every time a character spawns.
	PlayerService.CharacterSpawned:Connect(function(player)
		giveWeapon(player, WeaponConfig.Default)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return WeaponService
